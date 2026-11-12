import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uuid/uuid.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';

/// 浙大智云课堂（Zhiyun Classroom）单节录播回放或课程房间详情
class ZhiyunReplayInfo {
  final String? courseId;
  final String? subId;
  final String courseName;
  final String lessonTitle;
  final DateTime? lessonDate;
  final bool hasReplay;
  final bool isLive;
  final bool isLessonSpecific;
  final String livingroomUrl;

  const ZhiyunReplayInfo({
    this.courseId,
    this.subId,
    required this.courseName,
    required this.lessonTitle,
    this.lessonDate,
    this.hasReplay = true,
    this.isLive = false,
    this.isLessonSpecific = false,
    required this.livingroomUrl,
  });
}

/// 课程所处的学年/学期/半学期（秋/冬/春/夏）提示，用于多学期同名课程精准分流
class ZhiyunSemesterHint {
  final int? academicYearStart;
  final int? semesterTerm;
  final String? halfTag;
  final String? exactYearMonth;
  final Set<String> preferredYearMonths;

  const ZhiyunSemesterHint({
    this.academicYearStart,
    this.semesterTerm,
    this.halfTag,
    this.exactYearMonth,
    this.preferredYearMonths = const {},
  });

  String? get scopeKey {
    if (academicYearStart != null && halfTag != null) {
      return '${academicYearStart}_$halfTag';
    }
    if (academicYearStart != null && semesterTerm != null) {
      return '${academicYearStart}_t$semesterTerm';
    }
    if (halfTag != null) return halfTag;
    return exactYearMonth;
  }
}

/// 浙大智云课堂（Zhiyun Classroom）全自动动态同步与回放直达服务
/// 遵循“千人千面、全动态在线发现、绝不死板硬编码”设计原则
class ZhiyunService {
  ZhiyunService._();

  static const String _kZhiyunBaseUrl = 'https://classroom.zju.edu.cn';
  static const String _kTenantCode = '112';

  /// 用户运行时发现与绑定的课程映射表（内存缓存，如 "微积分": "86957"）
  static final Map<String, String> _userCourseIds = {};

  /// 课节回放 sub_id 映射表（"${courseId}_${YYYY-MM-DD}" -> sub_id）
  static final Map<String, String> _knownSubIds = {};

  /// 智云课程目录缓存 (course_id -> 课节列表)
  static final Map<String, List<Map<String, dynamic>>> _catalogueCache = {};
  static final Map<String, DateTime> _catalogueCacheTime = {};

  /// 智云课程元数据缓存 (course_id -> publish/show/term_name/is_off_shelf 等)
  static final Map<String, Map<String, dynamic>> _courseDetailMetaCache = {};

  /// 单节课流媒体存在性短时缓存 ("courseId_subId" -> ({bool isLive, bool hasReplay, DateTime cachedAt}))
  static final Map<String, ({bool isLive, bool hasReplay, DateTime cachedAt})>
      _lessonAvailabilityCache = {};

  static const int _kCacheSchemaVersion = 2;

  /// 智云认证 Token 与用户信息内存缓存
  static String? _cachedZhiyunToken;
  static String? _cachedZhiyunAccount;
  static String? _cachedZhiyunUserId;
  static String? _cachedZhiyunTenantId;
  static Future<int>? _syncFuture;

  /// 创建专用于浙大智云课堂的 HttpClient
  /// 自动直连绕过代理（Clash/VPN），防止内网接口在 SSL 握手时被重置
  static HttpClient createHttpClient(
      {Duration timeout = const Duration(seconds: 12)}) {
    final client = HttpClient()..connectionTimeout = timeout;
    applyZjuNetworkDefense(client, connectionTimeout: timeout);
    return client;
  }

  /// 获取有效的智云 Token（优先内存，其次 Hive）
  static String? getCachedZhiyunToken() {
    if (_cachedZhiyunToken != null && _cachedZhiyunToken!.isNotEmpty) {
      return _cachedZhiyunToken;
    }
    final box = _getHiveBox();
    final saved = box?.get('zhiyun_token')?.toString();
    if (saved != null && saved.isNotEmpty) {
      _cachedZhiyunToken = saved;
      return saved;
    }
    return null;
  }

  /// 获取缓存的用户智云学号/账号
  static String? _getCachedAccount() {
    if (_cachedZhiyunAccount != null && _cachedZhiyunAccount!.isNotEmpty) {
      return _cachedZhiyunAccount;
    }
    final box = _getHiveBox();
    final saved = box?.get('zhiyun_account')?.toString();
    if (saved != null && saved.isNotEmpty) {
      _cachedZhiyunAccount = saved;
      return saved;
    }
    return null;
  }

  /// 获取缓存的用户智云平台用户数字 ID
  static String? _getCachedUserId() {
    if (_cachedZhiyunUserId != null && _cachedZhiyunUserId!.isNotEmpty) {
      return _cachedZhiyunUserId;
    }
    final box = _getHiveBox();
    final saved = box?.get('zhiyun_user_id')?.toString();
    if (saved != null && saved.isNotEmpty) {
      _cachedZhiyunUserId = saved;
      return saved;
    }
    return null;
  }

  /// 构建智云前端 getToken() 所需的 PHP 序列化格式 _token Cookie 值
  /// 智云前端正则：`/{i:\d+;s:\d+:"_token";i:\d+;s:\d+:"(.+?)";}/`
  static String buildPhpSerializedTokenCookie(String token) {
    final trimmed = token.trim();
    final raw =
        'a:2:{i:0;s:6:"_token";i:1;s:${trimmed.length}:"$trimmed";}';
    return Uri.encodeComponent(raw);
  }

  /// 为智云课堂网页 URL 附加 token 与 tenant_code 参数，确保 WebView 首屏加载即完成鉴权
  static String appendTokenToUrl(String url, String? token) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return trimmedUrl;
    final tk = (token ?? getCachedZhiyunToken())?.trim() ?? '';
    if (tk.isEmpty || !trimmedUrl.contains('zju.edu.cn')) return trimmedUrl;
    try {
      final uri = Uri.parse(trimmedUrl);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['token'] = tk;
      qp.putIfAbsent('tenant_code', () => _kTenantCode);
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      final sep = trimmedUrl.contains('?') ? '&' : '?';
      return '$trimmedUrl${sep}token=${Uri.encodeQueryComponent(tk)}';
    }
  }

  /// 按照智云课堂前端 1P4N / concatUUID 规范对流媒体地址附加 clientUUID 与播放鉴权签名 t
  static String signPlayUrl(String rawUrl, {bool isLive = false}) {
    var url = rawUrl.trim();
    if (url.isEmpty) return url;
    try {
      var uri = Uri.parse(url);
      final qp = Map<String, String>.from(uri.queryParameters);
      if (!qp.containsKey('clientUUID')) {
        qp['clientUUID'] = const Uuid().v4();
      }
      final hasOpenSign = qp.containsKey('pt') && qp.containsKey('sig');
      if (!isLive && !hasOpenSign && !qp.containsKey('t')) {
        final userId = _getCachedUserId();
        final tenantId = _cachedZhiyunTenantId ?? _kTenantCode;
        if (userId != null && userId.isNotEmpty) {
          final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final path = uri.path;
          final sig = md5
              .convert(utf8.encode('$path$userId$tenantId$epoch'))
              .toString();
          qp['t'] = '$userId-$epoch-$sig';
        }
      }
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return url;
    }
  }

  /// 确保智云 Token 有效（若缺失或过期则自动通过 ZJUAM 重新握手刷新）
  static Future<String?> ensureValidToken({bool forceRefresh = false}) async {
    var token = forceRefresh ? null : getCachedZhiyunToken();
    final client = createHttpClient();
    try {
      if (token != null && token.isNotEmpty) {
        try {
          final infoUri = Uri.parse('$_kZhiyunBaseUrl/userapi/v1/infosimple');
          final req = await client.getUrl(infoUri);
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.set(
              'Cookie', '_token=${buildPhpSerializedTokenCookie(token)}; token=$token');
          req.headers.set('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
          final resp = await req.close().timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map &&
                (json['code'] == 200 || json['code'] == '200') &&
                json['params'] is Map) {
              final params = json['params'] as Map;
              final uid = params['id']?.toString();
              final acc = params['account']?.toString();
              final tid = params['tenant_id']?.toString();
              if (uid != null && uid.isNotEmpty) {
                _cachedZhiyunUserId = uid;
                _cachedZhiyunAccount = acc ?? _cachedZhiyunAccount;
                _cachedZhiyunTenantId = tid ?? _cachedZhiyunTenantId ?? _kTenantCode;
                final box = _getHiveBox();
                box?.put('zhiyun_user_id', uid);
                if (acc != null && acc.isNotEmpty) {
                  box?.put('zhiyun_account', acc);
                }
                return token;
              }
            }
          } else {
            await resp.drain();
          }
        } catch (_) {}
      }

      // Token 无效或过期，使用学号密码重新执行 CAS 认证握手
      String? u;
      String? p;
      try {
        if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
          final db = Get.find<DatabaseHelper>(tag: 'db');
          final scholar = await db.getScholar();
          u = scholar.username;
          p = scholar.password;
        }
      } catch (_) {}
      if (u != null && u.isNotEmpty && p != null && p.isNotEmpty) {
        final ssoCookie = await ZjuAm.getSsoCookie(client, u, p);
        if (ssoCookie != null) {
          final refreshed = await _loginZhiyunCas(client, ssoCookie);
          if (refreshed != null && refreshed.isNotEmpty) {
            return refreshed;
          }
        }
      }
      return token;
    } catch (_) {
      return token;
    } finally {
      client.close(force: true);
    }
  }

  static dynamic _rawStartAt(Map? item) {
    if (item == null) return null;
    return item['start_at'] ??
        item['class_begin'] ??
        item['course_begin'] ??
        item['begin'];
  }

  static dynamic _rawEndAt(Map? item) {
    if (item == null) return null;
    return item['end_at'] ??
        item['class_over'] ??
        item['course_over'] ??
        item['over'];
  }

  static Map<String, dynamic> _normalizeCatalogueItem(Map raw) {
    final item = Map<String, dynamic>.from(raw);
    final startRaw = _rawStartAt(item);
    final endRaw = _rawEndAt(item);
    if (item['start_at'] == null && startRaw != null) {
      item['start_at'] = startRaw;
    }
    if (item['end_at'] == null && endRaw != null) {
      item['end_at'] = endRaw;
    }
    final subId = item['sub_id']?.toString() ?? item['id']?.toString();
    if (subId != null && subId.isNotEmpty) {
      item['sub_id'] ??= subId;
    }
    final title = item['title']?.toString() ??
        item['sub_title']?.toString() ??
        item['course_title']?.toString();
    if (title != null && title.isNotEmpty) {
      item['title'] ??= title;
    }
    return item;
  }

  static final _semesterTagRegex = RegExp(
    r'[\(\[（【]\s*(\d{4}[-~]\d{4})?\s*(秋冬|春夏|秋学期|冬学期|春学期|夏学期|前半学期|后半学期|秋|冬|春|夏|前半|后半)\s*[\)\]）】]',
    caseSensitive: false,
  );
  static final _academicYearTagRegex = RegExp(
    r'[\(\[（【]?\b\d{4}[-~]\d{4}(秋冬|春夏|秋|冬|春|夏)?\b[\)\]）】]?',
    caseSensitive: false,
  );

  /// 提取纯净课程名称（去除末尾教学班编号、学期修饰、括号编号等，提高智云课堂检索命中率）
  static String cleanCourseName(String courseName) {
    var cleaned = courseName.trim();
    // 替换中文全角括号为半角便于统一处理
    cleaned = cleaned.replaceAll('（', '(').replaceAll('）', ')');
    cleaned = cleaned.replaceAll('【', '[').replaceAll('】', ']');
    // 去除秋冬/春夏学期及学年标签（解决冬学期换学期导致的匹配失败）
    cleaned = cleaned.replaceAll(_semesterTagRegex, '');
    cleaned = cleaned.replaceAll(_academicYearTagRegex, '');
    // 去除末尾诸如 (01), (02), (01班), [01], [01班] 的班级编号（保留单数字如 (3) 的课程序号）
    cleaned = cleaned.replaceAll(
        RegExp(r'[\(\[]\s*(0\d+|\d{2,}|\d+班)\s*[\)\]]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'-\d+$'), '');
    return cleaned.trim();
  }

  /// 提取核心课程名称（去除荣誉 (H) 标记、班级号、学期标记以及 (网络)/(线上)/(双语)/(全英文)/(MOOC)/(慕课) 等模式标签）
  static String extractCoreCourseName(String name) {
    var s = stripHonorsTag(name).trim();
    s = s.replaceAll('（', '(').replaceAll('）', ')');
    s = s.replaceAll('【', '[').replaceAll('】', ']');
    // 移除学期与学年修饰
    s = s.replaceAll(_semesterTagRegex, '');
    s = s.replaceAll(_academicYearTagRegex, '');
    // 移除常见教学修饰标签
    s = s.replaceAll(
        RegExp(
            r'[\(\[]\s*(网络|线上|线下|双语|全英文|英文|mooc|MOOC|慕课|研讨|实验|翻转|翻转课堂|理论|通识|通识核心|选修|必修)\s*[\)\]]',
            caseSensitive: false),
        '');
    // 移除班级号如 (01), (01班)（保留 (3) 单数字序号）
    s = s.replaceAll(RegExp(r'[\(\[]\s*(0\d+|\d{2,}|\d+班)\s*[\)\]]'), '');
    s = s.replaceAll(RegExp(r'-\d+$'), '');
    return s.trim();
  }

  /// 判断课程是否为荣誉课程（带 (H)、（H）、[H]、荣誉等标记）
  static bool isHonorsCourse(String name) {
    final lower = name.toLowerCase();
    return lower.contains('(h)') ||
        lower.contains('（h）') ||
        lower.contains('[h]') ||
        lower.contains('【h】') ||
        lower.contains('(荣誉)') ||
        lower.contains('（荣誉）') ||
        lower.contains('荣誉课程') ||
        RegExp(r'[\(（\[【]\s*h\s*[\)）\]】]', caseSensitive: false)
            .hasMatch(name) ||
        RegExp(r'\bh\b', caseSensitive: false).hasMatch(name) ||
        RegExp(r'[\u4e00-\u9fa5]h$', caseSensitive: false)
            .hasMatch(name.trim());
  }

  /// 移除课程名称中的荣誉课程 (H) 标记（用于在两者均为荣誉课程时进一步比对核心名称）
  static String stripHonorsTag(String name) {
    return name
        .replaceAll(
            RegExp(r'[\(（\[【]\s*h\s*[\)）\]】]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(（\[【]\s*荣誉\s*[\)）\]】]'), '')
        .replaceAll('荣誉课程', '')
        .replaceAll('荣誉', '')
        .replaceAll(RegExp(r'\bh\b', caseSensitive: false), '')
        .trim();
  }

  /// 提取课程等级（甲、乙、丙、丁），若无则返回 null
  static String? extractCourseTier(String name) {
    final m = RegExp(r'[\(（]([甲乙丙丁])[\)）]').firstMatch(name);
    if (m != null) return m.group(1);
    final m2 = RegExp(r'([甲乙丙丁])(?=[ⅠⅡⅢⅣ1-4一二三四\s\(\)（）]|$)').firstMatch(name);
    return m2?.group(1);
  }

  /// 提取课程序号（1, 2, 3, 4 或 Ⅰ, Ⅱ, Ⅲ, Ⅳ），若无则返回 null
  static String? extractCourseSequence(String name) {
    if (name.contains(RegExp(r'[Ⅰⅰ]'))) return '1';
    if (name.contains(RegExp(r'[Ⅱⅱ]'))) return '2';
    if (name.contains(RegExp(r'[Ⅲⅲ]'))) return '3';
    if (name.contains(RegExp(r'[Ⅳⅳ]'))) return '4';
    final m = RegExp(r'[\(（\s]([1-4一二三四])[\)）\s]?$').firstMatch(name);
    if (m != null) {
      final s = m.group(1)!;
      if (s == '1' || s == '一') return '1';
      if (s == '2' || s == '二') return '2';
      if (s == '3' || s == '三') return '3';
      if (s == '4' || s == '四') return '4';
    }
    return null;
  }

  /// 安全解析智云可能为秒级或毫秒级的时间戳
  static DateTime? parseZhiyunTimestamp(dynamic value) {
    if (value == null) return null;
    final numVal = int.tryParse(value.toString());
    if (numVal == null || numVal <= 0) return null;
    if (numVal > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numVal);
    } else {
      return DateTime.fromMillisecondsSinceEpoch(numVal * 1000);
    }
  }

  /// 对课程名进行多维度归一化处理（用于智能模糊匹配教务网课程与智云“我的课程”）
  static String normalizeCourseName(String name) {
    var s = stripHonorsTag(name).trim().toLowerCase();
    // 替换中文全角括号为半角
    s = s.replaceAll('（', '(').replaceAll('）', ')');
    s = s.replaceAll('【', '[').replaceAll('】', ']');
    // 移除学期标签与学年标签
    s = s.replaceAll(_semesterTagRegex, '');
    s = s.replaceAll(_academicYearTagRegex, '');
    // 去除末尾诸如 (01), (02), (1班) 的教学班编号（绝不去除 (3) 单数字序号）
    s = s.replaceAll(RegExp(r'\((0\d+|\d{2,}|\d+班)\)$'), '');
    // 统一罗马数字为阿拉伯数字
    s = s
        .replaceAll('ⅰ', '1')
        .replaceAll('Ⅰ', '1')
        .replaceAll('ⅱ', '2')
        .replaceAll('Ⅱ', '2')
        .replaceAll('ⅲ', '3')
        .replaceAll('Ⅲ', '3')
        .replaceAll('ⅳ', '4')
        .replaceAll('Ⅳ', '4');
    // 统一中文数字
    s = s
        .replaceAll('一', '1')
        .replaceAll('二', '2')
        .replaceAll('三', '3')
        .replaceAll('四', '4');
    // 去除所有空白
    s = s.replaceAll(RegExp(r'\s+'), '');
    // 去除括号
    s = s.replaceAll('(', '').replaceAll(')', '');
    return s;
  }

  /// 智能判断教务网课程名称与智云课堂课程名称是否匹配
  static bool matchesCourseName(String scheduleName, String zhiyunName) {
    // 1. 荣誉课程 (H) 严格互斥：一带 (H) 另一不带 (H) 坚决不匹配，绝不混淆
    if (isHonorsCourse(scheduleName) != isHonorsCourse(zhiyunName)) {
      return false;
    }

    // 2. 课程等级（甲/乙/丙/丁）严格互斥：等级不同坚决不匹配
    final tier1 = extractCourseTier(scheduleName);
    final tier2 = extractCourseTier(zhiyunName);
    if (tier1 != null && tier2 != null && tier1 != tier2) {
      return false;
    }

    // 3. 课程序号（Ⅰ/Ⅱ/Ⅲ/Ⅳ 或 1/2/3/4）严格互斥：序号不同坚决不匹配
    final seq1 = extractCourseSequence(scheduleName);
    final seq2 = extractCourseSequence(zhiyunName);
    if (seq1 != null && seq2 != null && seq1 != seq2) {
      return false;
    }

    final s1 = normalizeCourseName(scheduleName);
    final s2 = normalizeCourseName(zhiyunName);

    // 4. 归一化完全一致
    if (s1 == s2) return true;

    // 4.1 核心课程名称一致（去除 (网络)、(慕课)、(全英文)、班级号等修饰后）
    final core1 = normalizeCourseName(extractCoreCourseName(scheduleName));
    final core2 = normalizeCourseName(extractCoreCourseName(zhiyunName));
    if (core1.isNotEmpty && core1 == core2) return true;

    // 5. Python 课程识别（如 面向对象程序设计(Python)、程序设计基础(Python)、Python程序设计）
    if (s1.contains('python') && s2.contains('python')) {
      return true;
    }

    // 6. 大学英语 / 英语课程（分级匹配 1/2/3/4 或通用大学英语/学术英语等）
    if ((s1.contains('英语') || s1.contains('english')) &&
        (s2.contains('英语') || s2.contains('english'))) {
      for (final level in ['1', '2', '3', '4']) {
        if (s1.contains(level) && s2.contains(level)) {
          return true;
        }
      }
      if (!s1.contains(RegExp(r'[1-4]')) && !s2.contains(RegExp(r'[1-4]'))) {
        return true;
      }
      return false;
    }

    // 7. 线性代数、微积分与各专业课包含关系（要求长度 >= 3，如“电工学”、“运筹学”等，且等级序号已排除冲突）
    if (s1.length >= 3 && s2.contains(s1)) return true;
    if (s2.length >= 3 && s1.contains(s2)) return true;
    if (core1.length >= 3 && s2.contains(core1)) return true;
    if (core2.length >= 3 && s1.contains(core2)) return true;

    return false;
  }

  /// 获取本地持久化缓存的“我的课程”列表
  static List<Map<String, dynamic>> getMySyncedCourses() {
    try {
      final box = _getHiveBox();
      final raw = box?.get('zhiyun_my_courses');
      if (raw != null && raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 读取已同步课程列表失败: $e');
    }
    return const [];
  }

  /// 获取本地持久化缓存的“我的课程”具体排课节次列表（包含上课时间、直播与回放映射）
  static List<Map<String, dynamic>> getMySyncedSessions() {
    try {
      final box = _getHiveBox();
      final raw = box?.get('zhiyun_my_sessions');
      if (raw != null && raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 读取已同步排课节次失败: $e');
    }
    return const [];
  }

  /// 判断该课程是否属于非录播课程（例如身体素质课、体育课、体测等显然不可能有智云回放的课程）
  static bool isRecordableCourse(String courseName, {String? courseCode}) {
    // 1. 若本地已知/已绑定 courseId，或智云已同步存在该课程，则必定为可录播课程，绝不拦截
    if (getKnownCourseId(courseName, courseCode: courseCode) != null) {
      return true;
    }

    final name = cleanCourseName(courseName);

    // 明确属于录播/理论类课程，绝不误拦截（军事理论必定属于课堂理论讲授录播）
    if (name.contains('军事理论') ||
        name.contains('理论') ||
        name.contains('概论') ||
        name.contains('研讨') ||
        name.contains('素养') ||
        name.contains('思修') ||
        name.contains('马原') ||
        name.contains('毛概') ||
        name.contains('史纲')) {
      return true;
    }

    const nonRecordableKeywords = [
      '体育',
      '身体素质',
      '体质健康',
      '体测',
      '体能',
      '专项',
      '太极',
      '游泳',
      '篮球',
      '足球',
      '排球',
      '乒乓球',
      '羽毛球',
      '网球',
      '健美操',
      '武术',
      '轮滑',
      '定向越野',
      '散打',
      '跆拳道',
      '击剑',
      '龙舟',
      '皮划艇',
      '瑜伽',
      '形策',
      '形式与政策',
      '形势与政策',
      '军训',
      '军事技能',
      '生产实习',
      '认知实习',
      '金工实习',
      '毕业设计',
      '毕业论文',
      '创新实践',
      '社会实践',
      '劳动实践',
    ];

    for (final kw in nonRecordableKeywords) {
      if (name.contains(kw)) {
        return false;
      }
    }
    return true;
  }

  /// 获取 Hive optionsBox 引用
  static Box? _getHiveBox() {
    try {
      if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
        final db = Get.find<DatabaseHelper>(tag: 'db');
        return db.optionsBox;
      }
    } catch (_) {}
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        return Hive.box('dbOptions');
      }
    } catch (_) {}
    return null;
  }

  /// 判断用户是否对该课程执行过显式解绑
  static bool isExplicitlyUnbound(String courseName, {String? courseCode}) {
    final box = _getHiveBox();
    if (box == null) return false;
    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    final coreNormalized = normalizeCourseName(core);
    return box.get('zhiyun_unbind_$cleaned') == true ||
        box.get('zhiyun_unbind_$courseName') == true ||
        box.get('zhiyun_unbind_$normalized') == true ||
        (core.isNotEmpty && box.get('zhiyun_unbind_$core') == true) ||
        (coreNormalized.isNotEmpty &&
            box.get('zhiyun_unbind_$coreNormalized') == true) ||
        (courseCode != null &&
            courseCode.isNotEmpty &&
            box.get('zhiyun_unbind_$courseCode') == true);
  }

  static String _normalizeYearMonth(String raw) {
    final trimmed = raw.trim();
    final m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(trimmed);
    if (m != null) {
      return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}';
    }
    return trimmed;
  }

  static String? _extractHalfTagFromText(String text, {int? defaultTerm}) {
    if (text.isEmpty) return null;
    final sanitized = text
        .replaceAll('秋冬', ' ')
        .replaceAll('春夏', ' ')
        .replaceAll('冬春', ' ')
        .replaceAll('夏秋', ' ')
        .replaceAll('春秋', ' ');
    if (RegExp(r'(秋学期|[（(\[【\s]秋[）)\]】\s]?|秋$)')
        .hasMatch(sanitized)) {
      return 'autumn';
    }
    if (RegExp(r'(冬学期|[（(\[【\s]冬[）)\]】\s]?|冬$)')
        .hasMatch(sanitized)) {
      return 'winter';
    }
    if (RegExp(r'(春学期|[（(\[【\s]春[）)\]】\s]?|春$)').hasMatch(sanitized)) {
      return 'spring';
    }
    if (RegExp(r'(夏学期|[（(\[【\s]夏[）)\]】\s]?|夏$)').hasMatch(sanitized)) {
      return 'summer';
    }
    if (RegExp(r'(前半学期|[（(\[【]前半[）)\]】]|^前半$)').hasMatch(sanitized)) {
      return defaultTerm == 2 ? 'spring' : 'autumn';
    }
    if (RegExp(r'(后半学期|[（(\[【]后半[）)\]】]|^后半$)').hasMatch(sanitized)) {
      return defaultTerm == 2 ? 'summer' : 'winter';
    }
    return null;
  }

  static ({int? yearStart, int? term}) _parseYearAndTerm(String text) {
    if (text.isEmpty) return (yearStart: null, term: null);
    final codeMatch = RegExp(r'(\d{4})-(\d{4})-([12])').firstMatch(text);
    if (codeMatch != null) {
      return (
        yearStart: int.tryParse(codeMatch.group(1)!),
        term: int.tryParse(codeMatch.group(3)!),
      );
    }
    final nameMatch =
        RegExp(r'(\d{4})[-~](\d{4})\s*(?:学年)?\s*(秋冬|春夏|秋|冬|春|夏)?')
            .firstMatch(text);
    if (nameMatch != null) {
      final tag = nameMatch.group(3) ?? '';
      int? term;
      if (tag.contains('秋') || tag.contains('冬')) {
        term = 1;
      } else if (tag.contains('春') || tag.contains('夏')) {
        term = 2;
      }
      return (
        yearStart: int.tryParse(nameMatch.group(1)!),
        term: term,
      );
    }
    return (yearStart: null, term: null);
  }

  static String? _inferHalfFromMonths(
    Iterable<String> months, {
    int? defaultTerm,
    String termText = '',
  }) {
    final monthNums = <int>[];
    for (final ym in months) {
      final norm = _normalizeYearMonth(ym);
      final m = int.tryParse(norm.split('-').last);
      if (m != null) monthNums.add(m);
    }
    if (monthNums.isEmpty) return null;

    final hasSpringOrSummerHint =
        termText.contains('春') || termText.contains('夏') || defaultTerm == 2;
    final hasAutumnOrWinterHint =
        termText.contains('秋') || termText.contains('冬') || defaultTerm == 1;

    if (monthNums.every((m) => m == 8 || m == 9 || m == 10)) {
      if (monthNums.every((m) => m == 8) && hasSpringOrSummerHint) {
        return 'summer';
      }
      return 'autumn';
    }
    if (monthNums.every((m) => m == 11 || m == 12 || m == 1 || m == 2)) {
      if (monthNums.every((m) => m == 2) && hasSpringOrSummerHint) {
        return 'spring';
      }
      return 'winter';
    }
    if (monthNums.every((m) => m == 2 || m == 3 || m == 4)) {
      if (monthNums.every((m) => m == 2) && hasAutumnOrWinterHint) {
        return 'winter';
      }
      return 'spring';
    }
    if (monthNums.every((m) => m == 5 || m == 6 || m == 7)) {
      return 'summer';
    }
    return null;
  }

  /// 根据课程对象、选课代码、所在学期与目标上课日期推断所属学年/学期/半学期（秋/冬/春/夏）
  static ZhiyunSemesterHint inferSemesterHint({
    Course? course,
    String? courseCode,
    String? courseName,
    String? semesterName,
    String? preferredHalfTag,
    DateTime? targetDate,
  }) {
    int? yearStart;
    int? term;
    final codeSources = <String>[
      if (courseCode != null && courseCode.isNotEmpty) courseCode,
      if (course?.id != null && course!.id!.isNotEmpty) course.id!,
      if (course != null)
        for (final s in course.sessions)
          if (s.id != null && s.id!.isNotEmpty) s.id!,
      if (semesterName != null && semesterName.isNotEmpty) semesterName,
    ];
    for (final src in codeSources) {
      final parsed = _parseYearAndTerm(src);
      yearStart ??= parsed.yearStart;
      term ??= parsed.term;
      if (yearStart != null && term != null) break;
    }

    final rawName = courseName ?? course?.name ?? '';
    if ((yearStart == null || term == null) && rawName.isNotEmpty) {
      final parsed = _parseYearAndTerm(rawName);
      yearStart ??= parsed.yearStart;
      term ??= parsed.term;
    }

    String? halfTag;
    if (course != null && course.sessions.isNotEmpty) {
      final hasFirst = course.sessions.any((s) => s.firstHalf);
      final hasSecond = course.sessions.any((s) => s.secondHalf);
      if (hasFirst && !hasSecond) {
        halfTag = (term == 2) ? 'spring' : 'autumn';
      } else if (hasSecond && !hasFirst) {
        halfTag = (term == 2) ? 'summer' : 'winter';
      }
    }

    String? exactYearMonth;
    if (targetDate != null) {
      final y = targetDate.year;
      final m = targetDate.month;
      exactYearMonth = '$y-${m.toString().padLeft(2, '0')}';
      if (m == 8) {
        if (term == 2) {
          halfTag ??= 'summer';
          yearStart ??= y - 1;
        } else {
          halfTag ??= 'autumn';
          yearStart ??= y;
          term ??= 1;
        }
      } else if (m == 9 || m == 10) {
        halfTag ??= 'autumn';
        yearStart ??= y;
        term ??= 1;
      } else if (m == 11 || m == 12) {
        halfTag ??= 'winter';
        yearStart ??= y;
        term ??= 1;
      } else if (m == 1) {
        halfTag ??= 'winter';
        yearStart ??= y - 1;
        term ??= 1;
      } else if (m == 2) {
        yearStart ??= y - 1;
        if (term == 2 || (term == null && targetDate.day >= 20)) {
          halfTag ??= 'spring';
          term ??= 2;
        } else {
          halfTag ??= 'winter';
          term ??= 1;
        }
      } else if (m == 3 || m == 4) {
        halfTag ??= 'spring';
        yearStart ??= y - 1;
        term ??= 2;
      } else {
        halfTag ??= 'summer';
        yearStart ??= y - 1;
        term ??= 2;
      }
    } else {
      if (preferredHalfTag != null && preferredHalfTag.isNotEmpty) {
        halfTag ??= preferredHalfTag;
      }
      halfTag ??= _extractHalfTagFromText(rawName, defaultTerm: term);
      if (halfTag == 'autumn' || halfTag == 'winter') {
        term ??= 1;
      } else if (halfTag == 'spring' || halfTag == 'summer') {
        term ??= 2;
      }
    }

    final preferred = <String>{};
    if (yearStart != null) {
      if (halfTag == 'autumn') {
        preferred.addAll([
          '$yearStart-08',
          '$yearStart-09',
          '$yearStart-10',
        ]);
      } else if (halfTag == 'winter') {
        preferred.addAll([
          '$yearStart-11',
          '$yearStart-12',
          '${yearStart + 1}-01',
          '${yearStart + 1}-02',
        ]);
      } else if (halfTag == 'spring') {
        preferred.addAll([
          '${yearStart + 1}-02',
          '${yearStart + 1}-03',
          '${yearStart + 1}-04',
        ]);
      } else if (halfTag == 'summer') {
        preferred.addAll([
          '${yearStart + 1}-05',
          '${yearStart + 1}-06',
          '${yearStart + 1}-07',
        ]);
      } else if (term == 1) {
        preferred.addAll([
          '$yearStart-08',
          '$yearStart-09',
          '$yearStart-10',
          '$yearStart-11',
          '$yearStart-12',
          '${yearStart + 1}-01',
          '${yearStart + 1}-02',
        ]);
      } else if (term == 2) {
        preferred.addAll([
          '${yearStart + 1}-02',
          '${yearStart + 1}-03',
          '${yearStart + 1}-04',
          '${yearStart + 1}-05',
          '${yearStart + 1}-06',
          '${yearStart + 1}-07',
        ]);
      }
    }
    if (exactYearMonth != null) {
      preferred.add(exactYearMonth);
    }

    return ZhiyunSemesterHint(
      academicYearStart: yearStart,
      semesterTerm: term,
      halfTag: halfTag,
      exactYearMonth: exactYearMonth,
      preferredYearMonths: preferred,
    );
  }

  static bool isCourseOffShelfMeta(Map? data) {
    if (data == null) return false;
    if (data['is_off_shelf'] == true) return true;
    final publish = data['publish']?.toString().trim();
    final show = data['show']?.toString().trim().toLowerCase();
    return publish == '2' || show == 'no';
  }

  static int scoreSemesterMatch(
    ZhiyunSemesterHint hint, {
    String title = '',
    String? termName,
    Iterable<dynamic>? activeMonths,
    List<DateTime>? lessonDates,
    Map? meta,
    DateTime? nowForTiebreak,
  }) {
    if (isCourseOffShelfMeta(meta)) return -1000;

    int score = 0;
    final combined = '${termName ?? ''} $title'.trim();

    final ymMatch = RegExp(r'(\d{4})[-~](\d{4})').firstMatch(combined);
    if (ymMatch != null && hint.academicYearStart != null) {
      final candStart = int.tryParse(ymMatch.group(1)!);
      if (candStart == hint.academicYearStart) {
        score += 100;
      } else if (candStart != null) {
        score -= 150;
      }
    }

    final candHalf =
        _extractHalfTagFromText(combined, defaultTerm: hint.semesterTerm);
    final isFullAutumnWinter = combined.contains('秋冬');
    final isFullSpringSummer = combined.contains('春夏');
    if (hint.halfTag != null) {
      if (candHalf == hint.halfTag) {
        score += 60;
      } else if (candHalf != null) {
        score -= 120;
      } else if ((hint.halfTag == 'autumn' || hint.halfTag == 'winter') &&
          isFullAutumnWinter) {
        score += 20;
      } else if ((hint.halfTag == 'spring' || hint.halfTag == 'summer') &&
          isFullSpringSummer) {
        score += 20;
      }
    }

    final normMonths = <String>{};
    if (activeMonths != null) {
      for (final m in activeMonths) {
        final s = _normalizeYearMonth(m.toString());
        if (s.isNotEmpty) normMonths.add(s);
      }
    }
    if (normMonths.isNotEmpty) {
      if (hint.exactYearMonth != null &&
          normMonths.contains(hint.exactYearMonth)) {
        score += 90;
      } else if (hint.preferredYearMonths.isNotEmpty) {
        final overlap = normMonths.intersection(hint.preferredYearMonths).length;
        if (overlap > 0) {
          score += 50;
        } else {
          score -= 80;
        }
      }
    }

    if (lessonDates != null && lessonDates.isNotEmpty) {
      int exactCount = 0;
      int prefCount = 0;
      int yearCount = 0;
      for (final dt in lessonDates) {
        final ym = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        if (hint.exactYearMonth != null && ym == hint.exactYearMonth) {
          exactCount++;
        }
        if (hint.preferredYearMonths.contains(ym)) {
          prefCount++;
        }
        if (hint.academicYearStart != null) {
          final start = DateTime(hint.academicYearStart!, 8, 1);
          final end = DateTime(hint.academicYearStart! + 1, 8, 1);
          if (!dt.isBefore(start) && dt.isBefore(end)) {
            yearCount++;
          }
        }
      }
      if (exactCount > 0) score += 90;
      if (hint.preferredYearMonths.isNotEmpty) {
        if (prefCount > 0) {
          score += 20 + (prefCount * 60) ~/ lessonDates.length;
        } else if (hint.academicYearStart != null) {
          if (yearCount == 0) {
            score -= 150;
          } else {
            score -= 80;
          }
        }
      }
    }

    if (hint.halfTag == null && hint.exactYearMonth == null) {
      final ref = nowForTiebreak ?? DateTime.now();
      final curYm = '${ref.year}-${ref.month.toString().padLeft(2, '0')}';
      if (normMonths.contains(curYm)) {
        score += 15;
      }
    }
    return score;
  }

  static bool isCatalogueMismatchedWithHint(
    List<Map<String, dynamic>> catalogue,
    ZhiyunSemesterHint hint, {
    Map<String, dynamic>? meta,
  }) {
    if (isCourseOffShelfMeta(meta)) return true;
    if (hint.halfTag == null && hint.academicYearStart == null) return false;
    final lessonDates = <DateTime>[];
    for (final item in catalogue) {
      final dt = parseZhiyunTimestamp(_rawStartAt(item));
      if (dt != null) lessonDates.add(dt);
    }
    final title = meta?['title']?.toString() ?? '';
    final termName = meta?['term_name']?.toString();
    if (lessonDates.isEmpty && (termName == null || termName.isEmpty)) {
      return false;
    }
    return scoreSemesterMatch(
          hint,
          title: title,
          termName: termName,
          lessonDates: lessonDates,
          meta: meta,
        ) <
        0;
  }

  static List<String> _buildScopedCidKeys({
    required String cleaned,
    required String courseName,
    required String normalized,
    required String core,
    required String coreNormalized,
    String? courseCode,
    String? scopeKey,
  }) {
    final keys = <String>[];
    if (courseCode != null && courseCode.isNotEmpty) {
      if (scopeKey != null && scopeKey.isNotEmpty) {
        keys.add('${courseCode}__$scopeKey');
      }
      keys.add(courseCode);
    }
    if (scopeKey != null && scopeKey.isNotEmpty) {
      keys.add('${cleaned}__$scopeKey');
      if (core.isNotEmpty && core != cleaned) {
        keys.add('${core}__$scopeKey');
      }
    }
    keys.addAll([
      cleaned,
      courseName,
      normalized,
      if (core.isNotEmpty) core,
      if (coreNormalized.isNotEmpty) coreNormalized,
    ]);
    return keys;
  }

  static void _cacheResolvedCourseId(
    String courseId, {
    required String cleaned,
    required String courseName,
    required String normalized,
    required String core,
    required String coreNormalized,
    String? courseCode,
    String? scopeKey,
    bool persistToBox = false,
  }) {
    final box = persistToBox ? _getHiveBox() : null;
    if (courseCode != null && courseCode.isNotEmpty) {
      if (scopeKey != null && scopeKey.isNotEmpty) {
        final k = '${courseCode}__$scopeKey';
        _userCourseIds[k] = courseId;
        box?.put('zhiyun_cid_$k', courseId);
      }
      _userCourseIds[courseCode] = courseId;
      box?.put('zhiyun_cid_$courseCode', courseId);
    }
    if (scopeKey != null && scopeKey.isNotEmpty) {
      final scKey = '${cleaned}__$scopeKey';
      _userCourseIds[scKey] = courseId;
      box?.put('zhiyun_cid_$scKey', courseId);
      if (core.isNotEmpty && core != cleaned) {
        final coreKey = '${core}__$scopeKey';
        _userCourseIds[coreKey] = courseId;
        box?.put('zhiyun_cid_$coreKey', courseId);
      }
    } else {
      _userCourseIds[cleaned] = courseId;
      _userCourseIds[courseName] = courseId;
      _userCourseIds[normalized] = courseId;
      if (core.isNotEmpty) _userCourseIds[core] = courseId;
      if (coreNormalized.isNotEmpty) _userCourseIds[coreNormalized] = courseId;
      box?.put('zhiyun_cid_$cleaned', courseId);
      box?.put('zhiyun_cid_$courseName', courseId);
      box?.put('zhiyun_cid_$normalized', courseId);
      if (core.isNotEmpty) box?.put('zhiyun_cid_$core', courseId);
    }
  }

  static bool _isManuallyPinned(
    String courseName, {
    String? courseCode,
    ZhiyunSemesterHint? hint,
  }) {
    final box = _getHiveBox();
    if (box == null) return false;
    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    final keys = _buildScopedCidKeys(
      cleaned: cleaned,
      courseName: courseName,
      normalized: normalized,
      core: core,
      coreNormalized: normalizeCourseName(core),
      courseCode: courseCode,
      scopeKey: hint?.scopeKey,
    );
    return keys.any((k) {
      final v = box.get('zhiyun_manual_cid_$k');
      return v != null && v.toString().isNotEmpty;
    });
  }

  static void _ensureCacheSchemaUpgraded() {
    final box = _getHiveBox();
    if (box == null) return;
    if (box.get('zhiyun_cache_schema_v') == _kCacheSchemaVersion) return;

    final hasLegacySync = box.containsKey('zhiyun_my_courses_time') ||
        box.keys.any((k) => k is String && k.startsWith('zhiyun_cid_'));
    if (hasLegacySync) {
      final staleKeys = <dynamic>[];
      for (final key in box.keys) {
        if (key is String &&
            (key.startsWith('zhiyun_cid_') ||
                key.startsWith('zhiyun_last_played_') ||
                key == 'zhiyun_my_courses' ||
                key == 'zhiyun_my_courses_time' ||
                key == 'zhiyun_my_sessions')) {
          staleKeys.add(key);
        }
      }
      for (final key in staleKeys) {
        box.delete(key);
      }
      _userCourseIds.clear();
      _knownSubIds.clear();
    }
    box.put('zhiyun_cache_schema_v', _kCacheSchemaVersion);
  }

  /// 查询指定课程的智云 course_id
  /// 优先级：1. 用户显式手动绑定 > 2. 动态匹配用户“我的课程”（按目标学期/半学期智能分流） > 3. 内存运行时缓存 > 4. 历史缓存
  static String? getKnownCourseId(
    String courseName, {
    String? courseCode,
    String? teacher,
    List<String>? candidateTeachers,
    Course? course,
    String? semesterName,
    String? preferredHalfTag,
    DateTime? targetDate,
  }) {
    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    final coreNormalized = normalizeCourseName(core);
    final effectiveCode = courseCode ?? course?.id;
    final hint = inferSemesterHint(
      course: course,
      courseCode: effectiveCode,
      courseName: courseName,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );

    // 0. 特殊历史脏数据清洗：如果是思想文化素养/素质类课程，清除错误绑定的 86975
    if (cleaned.contains('思想文化素养') || cleaned.contains('思想素质')) {
      final box = _getHiveBox();
      final savedCid = box?.get('zhiyun_cid_$cleaned')?.toString() ??
          box?.get('zhiyun_cid_$courseName')?.toString() ??
          box?.get('zhiyun_cid_$normalized')?.toString() ??
          box?.get('zhiyun_cid_$core')?.toString() ??
          box?.get('zhiyun_cid_$coreNormalized')?.toString();
      if (savedCid == '86975') {
        box?.delete('zhiyun_cid_$cleaned');
        box?.delete('zhiyun_cid_$courseName');
        box?.delete('zhiyun_cid_$normalized');
        box?.delete('zhiyun_cid_$core');
        box?.delete('zhiyun_cid_$coreNormalized');
        box?.put('zhiyun_unbind_$cleaned', true);
        box?.put('zhiyun_unbind_$courseName', true);
        box?.put('zhiyun_unbind_$normalized', true);
        _userCourseIds.remove(cleaned);
        _userCourseIds.remove(courseName);
        _userCourseIds.remove(normalized);
        _userCourseIds.remove(core);
        _userCourseIds.remove(coreNormalized);
        return null;
      }
    }

    // 1. 若用户主动解绑过该课程，且未显式重新绑定，坚决返回 null
    if (isExplicitlyUnbound(courseName, courseCode: effectiveCode)) {
      return null;
    }

    final box = _getHiveBox();
    final scopedKeys = _buildScopedCidKeys(
      cleaned: cleaned,
      courseName: courseName,
      normalized: normalized,
      core: core,
      coreNormalized: coreNormalized,
      courseCode: effectiveCode,
      scopeKey: hint.scopeKey,
    );

    // 2. 检查用户显式手动绑定 (例如在弹窗中手动输入的 ID)
    if (box != null) {
      for (final k in scopedKeys) {
        final manualCid = box.get('zhiyun_manual_cid_$k');
        if (manualCid != null && manualCid.toString().isNotEmpty) {
          return manualCid.toString();
        }
      }
    }

    // 整合所有教师候选
    final allTeachers = <String>{};
    if (teacher != null && teacher.trim().isNotEmpty) {
      allTeachers.add(teacher.trim());
    }
    if (candidateTeachers != null) {
      for (final t in candidateTeachers) {
        if (t.trim().isNotEmpty) allTeachers.add(t.trim());
      }
    }

    // 3. 核心：从用户专属“我的课程”列表中按目标学年与秋/冬/春/夏半学期动态智能匹配
    final myCourses = getMySyncedCourses();
    final myCourseById = <String, Map<String, dynamic>>{};
    for (final item in myCourses) {
      final cid = item['course_id']?.toString() ?? '';
      if (cid.isNotEmpty) myCourseById[cid] = item;
    }

    if (myCourses.isNotEmpty) {
      final matchingCourses = <Map<String, dynamic>>[];
      for (final item in myCourses) {
        final tTitle = item['course_title']?.toString() ?? '';
        final tCid = item['course_id']?.toString() ?? '';
        if (tCid.isNotEmpty && matchesCourseName(courseName, tTitle)) {
          if (isCourseOffShelfMeta(item) ||
              isCourseOffShelfMeta(_courseDetailMetaCache[tCid])) {
            continue;
          }
          matchingCourses.add(item);
        }
      }

      if (matchingCourses.isNotEmpty) {
        Map<String, dynamic>? bestItem;
        int bestScore = -1;

        for (final item in matchingCourses) {
          int score = 10;
          final tCid = item['course_id']?.toString() ?? '';
          final tTitle = item['course_title']?.toString() ?? '';
          final tTeacher = item['teacher']?.toString() ?? '';
          final tTerm = item['term_name']?.toString() ??
              _courseDetailMetaCache[tCid]?['term_name']?.toString();

          if (allTeachers.isNotEmpty && tTeacher.isNotEmpty) {
            for (final t in allTeachers) {
              if (tTeacher.contains(t) || t.contains(tTeacher)) {
                score += 50;
                break;
              }
            }
          }

          score += scoreSemesterMatch(
            hint,
            title: tTitle,
            termName: tTerm,
            activeMonths: item['active_months'] as List?,
            meta: _courseDetailMetaCache[tCid] ?? item,
          );

          if (score > bestScore) {
            bestScore = score;
            bestItem = item;
          }
        }

        if (bestItem != null && bestScore >= 0) {
          final bestCid = bestItem['course_id']?.toString() ?? '';
          if (bestCid.isNotEmpty) {
            _cacheResolvedCourseId(
              bestCid,
              cleaned: cleaned,
              courseName: courseName,
              normalized: normalized,
              core: core,
              coreNormalized: coreNormalized,
              courseCode: effectiveCode,
              scopeKey: hint.scopeKey,
            );
            return bestCid;
          }
        }
      }
    }

    bool isCompatibleCachedCid(String cidStr, {required bool isScoped}) {
      if (isCourseOffShelfMeta(_courseDetailMetaCache[cidStr])) return false;
      if (isScoped) return true;
      final item = myCourseById[cidStr];
      if (item == null) return true;
      if (isCourseOffShelfMeta(item)) return false;
      final s = scoreSemesterMatch(
        hint,
        title: item['course_title']?.toString() ?? '',
        termName: item['term_name']?.toString(),
        activeMonths: item['active_months'] as List?,
        meta: item,
      );
      return s >= 0;
    }

    // 4. 检查内存缓存（优先精确作用域 Key，兼容旧裸 Key 时校验学期不冲突）
    for (final k in scopedKeys) {
      final cachedCid = _userCourseIds[k];
      if (cachedCid != null && cachedCid.isNotEmpty) {
        final isScoped = k.contains('__') ||
            (effectiveCode != null && k == effectiveCode);
        if (isCompatibleCachedCid(cachedCid, isScoped: isScoped)) {
          return cachedCid;
        }
      }
    }

    // 5. 兜底检查持久化存储
    if (box != null) {
      for (final k in scopedKeys) {
        final savedCid = box.get('zhiyun_cid_$k');
        if (savedCid != null && savedCid.toString().isNotEmpty) {
          final cidStr = savedCid.toString();
          final isScoped = k.contains('__') ||
              (effectiveCode != null && k == effectiveCode);
          if (isCompatibleCachedCid(cidStr, isScoped: isScoped)) {
            _userCourseIds[k] = cidStr;
            return cidStr;
          }
        }
      }
    }

    return null;
  }

  /// 通过智云课堂检索接口在线精准搜索匹配课程 ID，并校验课程下架状态与学年/半学期
  static Future<String?> searchCourseOnline({
    required String courseName,
    String? teacher,
    HttpClient? httpClient,
    Course? course,
    String? courseCode,
    String? semesterName,
    String? preferredHalfTag,
    DateTime? targetDate,
  }) async {
    final effectiveCode = courseCode ?? course?.id;
    // 若已被显式解绑，跳过在线检索
    if (isExplicitlyUnbound(courseName, courseCode: effectiveCode)) return null;

    final token = getCachedZhiyunToken();
    if (token == null || token.isEmpty) return null;

    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final coreName = extractCoreCourseName(courseName);
    final coreNormalized = normalizeCourseName(coreName);
    final hint = inferSemesterHint(
      course: course,
      courseCode: effectiveCode,
      courseName: courseName,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );

    final client = httpClient ?? createHttpClient();
    try {
      final account = _getCachedAccount();
      final userId = _getCachedUserId();

      // 候选标题：先查 cleanCourseName，若不同再查 extractCoreCourseName（例如 军事理论(网络) -> 军事理论）
      final titleCandidates = <String>[cleaned];
      if (coreName.isNotEmpty && coreName != cleaned) {
        titleCandidates.add(coreName);
      }

      // 提取主讲教师名（智云 realname 参数不支持多个教师拼接，如 '张三,李四' 会导致 0 结果）
      String? singleTeacher;
      if (teacher != null && teacher.trim().isNotEmpty) {
        final parts = teacher
            .trim()
            .split(RegExp(r'[,，/、\s+]'))
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          singleTeacher = parts.first;
        }
      }

      final seenCids = <String>{};
      final rawCandidates = <Map<String, dynamic>>[];

      for (final titleKeyword in titleCandidates) {
        final teacherCandidates = <String?>[];
        if (singleTeacher != null && singleTeacher.isNotEmpty) {
          teacherCandidates.add(singleTeacher);
        }
        teacherCandidates.add(null);

        for (final t in teacherCandidates) {
          final uri = Uri.parse(
            '$_kZhiyunBaseUrl/pptnote/v1/searchlist?tenant_id=$_kTenantCode'
            '&user_id=${userId ?? ''}'
            '&user_name=${account ?? ''}'
            '&page=1&per_page=30'
            '&title=${Uri.encodeComponent(titleKeyword)}'
            '${t != null && t.isNotEmpty ? '&realname=${Uri.encodeComponent(t)}' : ''}'
            '&trans=&tenant_code=$_kTenantCode'
            '&randomKey=${DateTime.now().millisecondsSinceEpoch}',
          );

          final req = await client.getUrl(uri);
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.set(
            'Cookie',
            '_token=${buildPhpSerializedTokenCookie(token)}; token=$token',
          );
          req.headers.set('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');

          final resp = await req.close().timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map && (json['code'] == 0 || json['code'] == '0')) {
              final total = json['total'];
              final list = total is Map ? total['list'] : null;
              if (list is List && list.isNotEmpty) {
                for (final item in list) {
                  if (item is! Map) continue;
                  final cid =
                      item['course_id']?.toString() ?? item['id']?.toString();
                  final title = item['title']?.toString() ?? '';
                  if (cid == null || cid.isEmpty || !seenCids.add(cid)) {
                    continue;
                  }
                  if (!matchesCourseName(courseName, title)) continue;
                  if (isCourseOffShelfMeta(item)) continue;

                  int preScore = 10;
                  final itemTeacher = item['realname']?.toString() ?? '';
                  if (teacher != null &&
                      teacher.trim().isNotEmpty &&
                      itemTeacher.isNotEmpty &&
                      (itemTeacher.contains(teacher.trim()) ||
                          teacher.trim().contains(itemTeacher) ||
                          (singleTeacher != null &&
                              itemTeacher.contains(singleTeacher)))) {
                    preScore += 50;
                  }
                  preScore += scoreSemesterMatch(
                    hint,
                    title: title,
                    termName: item['term_name']?.toString(),
                    meta: item,
                  );
                  rawCandidates.add({
                    'cid': cid,
                    'title': title,
                    'teacher': itemTeacher,
                    'term_name': item['term_name']?.toString(),
                    'preScore': preScore,
                  });
                }
              }
            }
          }
        }
      }

      if (rawCandidates.isEmpty) return null;

      rawCandidates.sort((a, b) {
        final sCmp = (b['preScore'] as int).compareTo(a['preScore'] as int);
        if (sCmp != 0) return sCmp;
        final idA = int.tryParse(a['cid'] as String) ?? 0;
        final idB = int.tryParse(b['cid'] as String) ?? 0;
        return idB.compareTo(idA);
      });

      String? bestCid;
      int bestScore = -1;
      for (final cand in rawCandidates.take(8)) {
        final cid = cand['cid'] as String;
        final catalogue = await fetchCourseCatalogue(cid);
        final meta = _courseDetailMetaCache[cid];
        if (isCourseOffShelfMeta(meta)) continue;

        final lessonDates = <DateTime>[];
        for (final item in catalogue) {
          final dt = parseZhiyunTimestamp(_rawStartAt(item));
          if (dt != null) lessonDates.add(dt);
        }

        final teacherHit = cand['teacher']?.toString().isNotEmpty == true &&
            teacher != null &&
            teacher.trim().isNotEmpty &&
            ((cand['teacher'] as String).contains(teacher.trim()) ||
                teacher.trim().contains(cand['teacher'] as String) ||
                (singleTeacher != null &&
                    (cand['teacher'] as String).contains(singleTeacher)));
        int finalScore = 10 +
            (teacherHit ? 50 : 0) +
            scoreSemesterMatch(
              hint,
              title: meta?['title']?.toString().isNotEmpty == true
                  ? meta!['title'].toString()
                  : cand['title'].toString(),
              termName: meta?['term_name']?.toString() ??
                  cand['term_name']?.toString(),
              lessonDates: lessonDates,
              meta: meta,
            );
        if (catalogue.isNotEmpty) finalScore += 5;

        if (finalScore > bestScore) {
          bestScore = finalScore;
          bestCid = cid;
        }
      }

      if (bestCid != null && bestScore >= 0) {
        _cacheResolvedCourseId(
          bestCid,
          cleaned: cleaned,
          courseName: courseName,
          normalized: normalized,
          core: coreName,
          coreNormalized: coreNormalized,
          courseCode: effectiveCode,
          scopeKey: hint.scopeKey,
          persistToBox: true,
        );
        return bestCid;
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 在线检索课程失败 ($courseName): $e');
    } finally {
      if (httpClient == null) {
        client.close(force: true);
      }
    }
    return null;
  }

  /// 保存课程的最近观看/播放记录（断点记忆，支持按 courseCode/scopeKey 隔离秋冬同门课程）
  static Future<void> saveLastWatchedReplay({
    required String courseName,
    required String lessonTitle,
    required String livingroomUrl,
    String? courseId,
    String? subId,
    String? courseCode,
    String? scopeKey,
  }) async {
    try {
      final box = _getHiveBox();
      final record = {
        'courseName': courseName,
        'lessonTitle': lessonTitle,
        'livingroomUrl': livingroomUrl,
        'courseId': courseId,
        'subId': subId,
        'courseCode': courseCode,
        'timestamp': DateTime.now().toIso8601String(),
      };
      final cleaned = cleanCourseName(courseName);
      final jsonStr = jsonEncode(record);
      if (courseCode != null && courseCode.isNotEmpty) {
        await box?.put('zhiyun_last_played_code_$courseCode', jsonStr);
      }
      if (scopeKey != null && scopeKey.isNotEmpty) {
        await box?.put('zhiyun_last_played_${cleaned}__$scopeKey', jsonStr);
      } else {
        await box?.put('zhiyun_last_played_$cleaned', jsonStr);
      }
      if (courseId != null && courseId.isNotEmpty) {
        await box?.put('zhiyun_last_played_cid_$courseId', jsonStr);
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 保存播放进度异常: $e');
    }
  }

  /// 获取课程的最近观看记录
  static Map<String, dynamic>? getLastWatchedReplay({
    required String courseName,
    String? courseId,
    String? courseCode,
    String? scopeKey,
  }) {
    try {
      final box = _getHiveBox();
      final cleaned = cleanCourseName(courseName);
      String? raw;
      if (courseId != null && courseId.isNotEmpty) {
        raw ??= box?.get('zhiyun_last_played_cid_$courseId')?.toString();
      }
      if (courseCode != null && courseCode.isNotEmpty) {
        raw ??= box?.get('zhiyun_last_played_code_$courseCode')?.toString();
      }
      if (scopeKey != null && scopeKey.isNotEmpty) {
        raw ??=
            box?.get('zhiyun_last_played_${cleaned}__$scopeKey')?.toString();
      }
      raw ??= box?.get('zhiyun_last_played_$cleaned')?.toString();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final map = decoded is Map<String, dynamic>
            ? decoded
            : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);
        if (map != null) {
          final recCid = map['courseId']?.toString();
          if (courseId != null &&
              courseId.isNotEmpty &&
              recCid != null &&
              recCid.isNotEmpty &&
              recCid != courseId) {
            return null;
          }
          return map;
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 读取播放进度异常: $e');
    }
    return null;
  }

  /// 获取指定课程的课节回放目录（优先内存缓存，其次本地 Hive 离线缓存，网络失败时优雅降级）
  static Future<List<Map<String, dynamic>>> fetchCourseCatalogue(
    String courseId, {
    bool forceRefresh = false,
  }) async {
    final cached = _catalogueCache[courseId];
    final cacheTime = _catalogueCacheTime[courseId];
    if (!forceRefresh &&
        cached != null &&
        cacheTime != null &&
        DateTime.now().difference(cacheTime) < const Duration(minutes: 15)) {
      return cached;
    }

    // 检查本地 Hive 离线持久化缓存
    final box = _getHiveBox();
    List<Map<String, dynamic>>? hiveCached;
    if (box != null) {
      final rawMeta = box.get('zhiyun_meta_$courseId')?.toString();
      if (rawMeta != null && rawMeta.isNotEmpty) {
        try {
          final decodedMeta = jsonDecode(rawMeta);
          if (decodedMeta is Map) {
            _courseDetailMetaCache[courseId] =
                Map<String, dynamic>.from(decodedMeta);
          }
        } catch (_) {}
      }
      final raw = box.get('zhiyun_cat_$courseId')?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            hiveCached = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            if (hiveCached.isNotEmpty) {
              _catalogueCache[courseId] = hiveCached;
              _registerSubIdsFromList(courseId, hiveCached);
            }
          }
        } catch (_) {}
      }
    }

    final client = createHttpClient();
    try {
      final token = getCachedZhiyunToken();
      final account = _getCachedAccount();

      // 1. 优先尝试 get-course-detail 接口 (包含完整的课节结构 sub_list)
      final detailBases = <String>[
        'https://yjapi.cmc.zju.edu.cn',
        _kZhiyunBaseUrl,
      ];
      for (final base in detailBases) {
        try {
          final detailUri = Uri.parse(
            '$base/courseapi/v3/multi-search/get-course-detail?course_id=$courseId${account != null ? '&student=$account' : ''}',
          );
          final req = await client.getUrl(detailUri);
          req.headers.set('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
          req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
          if (token != null && token.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $token');
            req.headers.set(
              'Cookie',
              '_token=${buildPhpSerializedTokenCookie(token)}; token=$token',
            );
          }
          final resp = await req.close().timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map &&
                (json['code'] == 0 ||
                    json['code'] == '0' ||
                    json['success'] == true)) {
              final data = json['data'] ?? json['result'];
              if (data is Map) {
                final publishVal = data['publish']?.toString().trim();
                final showVal = data['show']?.toString().trim();
                final isOffShelf = publishVal == '2' ||
                    showVal?.toLowerCase() == 'no';
                final metaMap = <String, dynamic>{
                  'course_id': courseId,
                  'title':
                      (data['title'] ?? data['course_name'] ?? '').toString(),
                  'teacher': (data['realname'] ??
                          data['teacher_name'] ??
                          data['teacher'] ??
                          '')
                      .toString(),
                  'term_name':
                      (data['term_name'] ?? data['semester_name'] ?? '')
                          .toString(),
                  if (publishVal != null) 'publish': publishVal,
                  if (showVal != null) 'show': showVal,
                  'is_off_shelf': isOffShelf,
                };
                _courseDetailMetaCache[courseId] = metaMap;
                box?.put('zhiyun_meta_$courseId', jsonEncode(metaMap));
              }
              final subListMap = data is Map ? data['sub_list'] : null;
              final list = <Map<String, dynamic>>[];

              if (subListMap is Map) {
                _extractSubList(subListMap, list);
              } else if (data is Map && data['list'] is List) {
                for (final item in data['list']) {
                  if (item is Map) list.add(_normalizeCatalogueItem(item));
                }
              }

              if (list.isNotEmpty) {
                _catalogueCache[courseId] = list;
                _catalogueCacheTime[courseId] = DateTime.now();
                _registerSubIdsFromList(courseId, list);
                if (box != null) {
                  box.put('zhiyun_cat_$courseId', jsonEncode(list));
                  box.put('zhiyun_cat_time_$courseId',
                      DateTime.now().toIso8601String());
                }
                return list;
              }
            }
          } else {
            await resp.drain();
          }
        } catch (_) {}
      }

      // 2. 备用尝试 /courseapi/v2/course/catalogue
      final catUri = Uri.parse(
          '$_kZhiyunBaseUrl/courseapi/v2/course/catalogue?course_id=$courseId');
      final req2 = await client.getUrl(catUri);
      req2.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      if (token != null && token.isNotEmpty) {
        req2.headers.set('Authorization', 'Bearer $token');
        req2.headers.set(
          'Cookie',
          '_token=${buildPhpSerializedTokenCookie(token)}; token=$token',
        );
      }
      final resp2 = await req2.close().timeout(const Duration(seconds: 8));
      if (resp2.statusCode == 200) {
        final body2 = await resp2.transform(utf8.decoder).join();
        final json2 = jsonDecode(body2);
        if (json2 is Map) {
          final rawData =
              json2['result']?['data'] ?? json2['data'] ?? json2['list'];
          if (rawData is List) {
            final list = <Map<String, dynamic>>[];
            for (final item in rawData) {
              if (item is Map) list.add(_normalizeCatalogueItem(item));
            }
            if (list.isNotEmpty) {
              _catalogueCache[courseId] = list;
              _catalogueCacheTime[courseId] = DateTime.now();
              _registerSubIdsFromList(courseId, list);
              if (box != null) {
                box.put('zhiyun_cat_$courseId', jsonEncode(list));
                box.put('zhiyun_cat_time_$courseId',
                    DateTime.now().toIso8601String());
              }
              return list;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 获取课程目录异常 (courseId=$courseId): $e，尝试降级到离线缓存');
    } finally {
      client.close(force: true);
    }

    // 弱网或请求失败时，优先返回离线缓存，确保课程课次依然可见
    return cached ?? hiveCached ?? const [];
  }

  /// 递归解析 sub_list 结构 (year -> month -> week -> list of subs)
  static void _extractSubList(
      Map subListMap, List<Map<String, dynamic>> target) {
    for (final yearVal in subListMap.values) {
      if (yearVal is Map) {
        for (final monthVal in yearVal.values) {
          if (monthVal is Map) {
            for (final weekVal in monthVal.values) {
              if (weekVal is List) {
                for (final sub in weekVal) {
                  if (sub is Map) {
                    target.add(_normalizeCatalogueItem(sub));
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// 从任意接口响应（嵌套 sub_list 字典、course/sub_list 或扁平列表）提取并归一化课节列表
  static List<Map<String, dynamic>> _extractSubItemsFromResponse(
          dynamic decoded) =>
      extractSubItemsFromResponse(decoded);

  /// 公开测试/调用入口：从任意接口响应提取并归一化课节列表
  static List<Map<String, dynamic>> extractSubItemsFromResponse(
      dynamic decoded) {
    final items = <Map<String, dynamic>>[];

    void addNormalized(Map raw, String inheritedCid) {
      final norm = _normalizeCatalogueItem(raw);
      if ((norm['course_id']?.toString() ?? '').isEmpty &&
          inheritedCid.isNotEmpty) {
        norm['course_id'] = inheritedCid;
      }
      items.add(norm);
    }

    void walk(dynamic node, String inheritedCid) {
      if (node is List) {
        for (final el in node) {
          walk(el, inheritedCid);
        }
        return;
      }
      if (node is! Map) return;

      // get-my-course-day 根级条目以 id 表示 course_id、sub_id 表示课节 id（两者不同且无父 course_id）
      final hasDistinctCourseAndSubId = node['sub_id'] != null &&
          node['id'] != null &&
          node['id'].toString().isNotEmpty &&
          node['id'].toString() != node['sub_id'].toString();
      final nodeCid = (node['course_id'] ??
                  ((inheritedCid.isEmpty && hasDistinctCourseAndSubId) ||
                          (node['sub_id'] == null &&
                              node['save_playback'] == null &&
                              node['mpc'] == null &&
                              node['pgc'] == null)
                      ? node['id']
                      : null))
              ?.toString() ??
          '';
      final nextCid = inheritedCid.isNotEmpty ? inheritedCid : nodeCid;

      final looksLikeLesson = node['sub_id'] != null ||
          node['save_playback'] != null ||
          node['mpc'] != null ||
          node['pgc'] != null ||
          node['relation_data'] != null ||
          node['class_begin'] != null ||
          node['course_begin'] != null ||
          node['start_at'] != null;
      if (looksLikeLesson) {
        addNormalized(node, nextCid);
      }

      if (node['sub_list'] is Map) {
        final subTarget = <Map<String, dynamic>>[];
        _extractSubList(node['sub_list'] as Map, subTarget);
        for (final norm in subTarget) {
          if ((norm['course_id']?.toString() ?? '').isEmpty &&
              nextCid.isNotEmpty) {
            norm['course_id'] = nextCid;
          }
          items.add(norm);
        }
      } else if (node['sub_list'] is List) {
        walk(node['sub_list'], nextCid);
      }

      for (final key in const [
        'list',
        'subs',
        'course',
        'courses',
        'data',
        'result',
      ]) {
        if (node[key] != null) {
          walk(node[key], nextCid);
        }
      }
    }

    walk(decoded, '');
    return items;
  }

  /// 从课节列表中解析并自动记录日期到 sub_id 的映射
  static void _registerSubIdsFromList(
      String courseId, List<Map<String, dynamic>> list) {
    for (final item in list) {
      final subId = item['sub_id']?.toString() ?? item['id']?.toString();
      final startAt = int.tryParse(_rawStartAt(item)?.toString() ?? '');
      if (subId != null && subId.isNotEmpty) {
        if (startAt != null && startAt > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
          final dKey =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          _knownSubIds['${courseId}_$dKey'] = subId;
          _knownSubIds['${courseId}_${dKey}_${dt.hour}'] = subId;
          _knownSubIds['${courseId}_${dKey}_${dt.hour}_${dt.minute}'] = subId;
        } else if (item['date'] != null) {
          final dateStr = item['date'].toString().split(' ').first;
          if (dateStr.isNotEmpty) {
            _knownSubIds['${courseId}_$dateStr'] = subId;
          }
        }
      }
    }
  }

  /// 构建智云课堂单节课回放直达 livingroom URL
  static String buildLivingroomUrl(String courseId, String subId) {
    return '$_kZhiyunBaseUrl/livingroom?course_id=$courseId&sub_id=$subId&tenant_code=$_kTenantCode';
  }

  /// 构建智云课堂整门课程详情页直达 URL（无 sub_id 时必须使用 /coursedetail，避免 /livingroom 缺参提示“课程已下架”）
  static String buildCourseDetailUrl(String courseId) {
    return '$_kZhiyunBaseUrl/coursedetail?course_id=$courseId&tenant_code=$_kTenantCode';
  }

  /// 构建智云课堂整门课程专属房间直达 URL（传入 subId 时进入直播/回放间，否则进入课程详情页）
  static String buildCourseLivingroomUrl(String courseId, {String? subId}) {
    if (subId != null && subId.isNotEmpty) {
      return buildLivingroomUrl(courseId, subId);
    }
    return buildCourseDetailUrl(courseId);
  }

  /// 构建智云课堂“我的课程”主页 URL
  static String buildMyCoursesUrl() {
    return '$_kZhiyunBaseUrl/?tenant_code=$_kTenantCode';
  }

  /// 构建智云课堂站内检索直达 URL
  static String buildSearchContentUrl(String courseName) {
    final keyword = cleanCourseName(courseName);
    return '$_kZhiyunBaseUrl/#/searchContent?title=${Uri.encodeComponent(keyword)}&tenant_code=$_kTenantCode';
  }

  /// 别名兼容
  static String buildSearchUrl(String courseName) =>
      buildSearchContentUrl(courseName);

  /// 智云课堂首页门户 URL
  static String buildPortalUrl() {
    return _kZhiyunBaseUrl;
  }

  /// 智云课堂 SSO 统一身份认证直达 URL
  static String buildSsoLoginUrl() {
    return 'https://zjuam.zju.edu.cn/cas/login?service=${Uri.encodeComponent(_kZhiyunBaseUrl)}';
  }

  /// 从用户输入的文本或直达链接中智能提取课程 course_id
  static String? extractCourseId(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;

    // 1. 如果是完整 URL，尝试解析 URL 中的 course_id 参数
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.queryParameters.containsKey('course_id')) {
        final cid = uri.queryParameters['course_id'];
        if (cid != null && RegExp(r'^\d+$').hasMatch(cid)) {
          return cid;
        }
      }
    } catch (_) {}

    // 2. 正则查找形如 course_id=12345
    final paramMatch =
        RegExp(r'course_id=(\d+)', caseSensitive: false).firstMatch(raw);
    if (paramMatch != null) {
      return paramMatch.group(1);
    }

    // 3. 正则查找纯数字 ID
    final digitMatch = RegExp(r'^\d+$').firstMatch(raw);
    if (digitMatch != null) {
      return digitMatch.group(0);
    }

    final embeddedDigits = RegExp(r'\b(\d{4,8})\b').firstMatch(raw);
    if (embeddedDigits != null) {
      return embeddedDigits.group(1);
    }

    return null;
  }

  /// 用户显式保存/手动绑定课程智云 ID
  static Future<void> saveCourseId(
    String courseName,
    String courseId, {
    String? courseCode,
    Course? course,
    String? semesterName,
    String? preferredHalfTag,
    DateTime? targetDate,
  }) async {
    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    final coreNormalized = normalizeCourseName(core);
    final effectiveCode = courseCode ?? course?.id;
    final hint = inferSemesterHint(
      course: course,
      courseCode: effectiveCode,
      courseName: courseName,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );
    final scopeKey = hint.scopeKey;

    if (effectiveCode != null && effectiveCode.isNotEmpty) {
      if (scopeKey != null && scopeKey.isNotEmpty) {
        _userCourseIds['${effectiveCode}__$scopeKey'] = courseId;
      }
      _userCourseIds[effectiveCode] = courseId;
    }
    if (scopeKey != null && scopeKey.isNotEmpty) {
      _userCourseIds['${cleaned}__$scopeKey'] = courseId;
      if (core.isNotEmpty && core != cleaned) {
        _userCourseIds['${core}__$scopeKey'] = courseId;
      }
    } else {
      _userCourseIds[cleaned] = courseId;
      _userCourseIds[courseName] = courseId;
      _userCourseIds[normalized] = courseId;
      if (core.isNotEmpty) _userCourseIds[core] = courseId;
      if (coreNormalized.isNotEmpty) _userCourseIds[coreNormalized] = courseId;
    }

    final box = _getHiveBox();
    if (box != null) {
      // 重新绑定时清除主动解绑标记
      await box.delete('zhiyun_unbind_$cleaned');
      await box.delete('zhiyun_unbind_$courseName');
      await box.delete('zhiyun_unbind_$normalized');
      if (core.isNotEmpty) await box.delete('zhiyun_unbind_$core');
      if (coreNormalized.isNotEmpty) {
        await box.delete('zhiyun_unbind_$coreNormalized');
      }
      if (effectiveCode != null && effectiveCode.isNotEmpty) {
        await box.delete('zhiyun_unbind_$effectiveCode');
      }

      if (effectiveCode != null && effectiveCode.isNotEmpty) {
        if (scopeKey != null && scopeKey.isNotEmpty) {
          await box.put(
              'zhiyun_manual_cid_${effectiveCode}__$scopeKey', courseId);
          await box.put('zhiyun_cid_${effectiveCode}__$scopeKey', courseId);
        }
        await box.put('zhiyun_manual_cid_$effectiveCode', courseId);
        await box.put('zhiyun_cid_$effectiveCode', courseId);
      }
      if (scopeKey != null && scopeKey.isNotEmpty) {
        await box.put('zhiyun_manual_cid_${cleaned}__$scopeKey', courseId);
        await box.put('zhiyun_cid_${cleaned}__$scopeKey', courseId);
        if (core.isNotEmpty && core != cleaned) {
          await box.put('zhiyun_manual_cid_${core}__$scopeKey', courseId);
          await box.put('zhiyun_cid_${core}__$scopeKey', courseId);
        }
      } else {
        await box.put('zhiyun_manual_cid_$cleaned', courseId);
        await box.put('zhiyun_manual_cid_$courseName', courseId);
        await box.put('zhiyun_manual_cid_$normalized', courseId);
        if (core.isNotEmpty) {
          await box.put('zhiyun_manual_cid_$core', courseId);
        }

        await box.put('zhiyun_cid_$cleaned', courseId);
        await box.put('zhiyun_cid_$courseName', courseId);
        await box.put('zhiyun_cid_$normalized', courseId);
        if (core.isNotEmpty) await box.put('zhiyun_cid_$core', courseId);
        if (coreNormalized.isNotEmpty) {
          await box.put('zhiyun_cid_$coreNormalized', courseId);
        }
      }
    }
  }

  /// 用户显式解绑课程智云 ID
  static Future<void> deleteCourseId(
    String courseName, {
    String? courseCode,
    String? courseId,
    Course? course,
    String? semesterName,
    String? preferredHalfTag,
    DateTime? targetDate,
  }) async {
    final cleaned = cleanCourseName(courseName);
    final normalized = normalizeCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    final coreNormalized = normalizeCourseName(core);
    final effectiveCode = courseCode ?? course?.id;
    final hint = inferSemesterHint(
      course: course,
      courseCode: effectiveCode,
      courseName: courseName,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );
    final scopeKey = hint.scopeKey;
    final cid = courseId ??
        (effectiveCode != null ? _userCourseIds[effectiveCode] : null) ??
        _userCourseIds[cleaned] ??
        _userCourseIds[courseName] ??
        _userCourseIds[normalized] ??
        _userCourseIds[core] ??
        _userCourseIds[coreNormalized];
    if (cid != null) {
      _catalogueCache.remove(cid);
      _catalogueCacheTime.remove(cid);
      _courseDetailMetaCache.remove(cid);
    }

    final keysToRemove = _buildScopedCidKeys(
      cleaned: cleaned,
      courseName: courseName,
      normalized: normalized,
      core: core,
      coreNormalized: coreNormalized,
      courseCode: effectiveCode,
      scopeKey: scopeKey,
    );
    for (final k in keysToRemove) {
      _userCourseIds.remove(k);
    }

    final box = _getHiveBox();
    if (box != null) {
      for (final k in keysToRemove) {
        await box.delete('zhiyun_manual_cid_$k');
        await box.delete('zhiyun_cid_$k');
      }

      // 持久化记录用户显式解绑标记，防止后续自动搜索或后台同步再次错误关联
      if (effectiveCode != null && effectiveCode.isNotEmpty) {
        await box.put('zhiyun_unbind_$effectiveCode', true);
      } else {
        await box.put('zhiyun_unbind_$cleaned', true);
        await box.put('zhiyun_unbind_$courseName', true);
        await box.put('zhiyun_unbind_$normalized', true);
        if (core.isNotEmpty) await box.put('zhiyun_unbind_$core', true);
        if (coreNormalized.isNotEmpty) {
          await box.put('zhiyun_unbind_$coreNormalized', true);
        }
      }
    }
  }

  /// 清空智云课堂所有内存与持久化缓存（用于切换账号或注销时彻底隔离多用户数据）
  static Future<void> clearCache() async {
    _userCourseIds.clear();
    _knownSubIds.clear();
    _catalogueCache.clear();
    _catalogueCacheTime.clear();
    _courseDetailMetaCache.clear();
    _lessonAvailabilityCache.clear();
    _cachedZhiyunToken = null;
    _cachedZhiyunAccount = null;
    _cachedZhiyunUserId = null;
    _syncFuture = null;

    final box = _getHiveBox();
    if (box != null) {
      final keysToDelete = <dynamic>[];
      for (final key in box.keys) {
        if (key is String && key.startsWith('zhiyun_')) {
          keysToDelete.add(key);
        }
      }
      for (final key in keysToDelete) {
        await box.delete(key);
      }
    }
    debugPrint('[ZhiyunService] 已成功清理智云课堂所有账号缓存');
  }

  /// 同步清空智云课堂内存缓存
  static void clearCacheSync() {
    _userCourseIds.clear();
    _knownSubIds.clear();
    _catalogueCache.clear();
    _catalogueCacheTime.clear();
    _courseDetailMetaCache.clear();
    _lessonAvailabilityCache.clear();
    _cachedZhiyunToken = null;
    _cachedZhiyunAccount = null;
    _cachedZhiyunUserId = null;
    _syncFuture = null;
  }

  /// 校验当前登录账号与智云缓存账号是否一致，若账号发生变化则自动触发重置
  static Future<void> ensureAccountScope(String? currentUsername) async {
    if (currentUsername == null || currentUsername.isEmpty) return;
    final cachedAccount = _getCachedAccount();
    if (cachedAccount != null &&
        cachedAccount.isNotEmpty &&
        cachedAccount.toLowerCase() != currentUsername.toLowerCase()) {
      debugPrint(
          '[ZhiyunService] 检测到当前账号 ($currentUsername) 与智云缓存账号 ($cachedAccount) 不一致，正在执行数据重置隔离...');
      await clearCache();
    }
  }

  /// 注册/更新课程的 Zhiyun course_id 映射
  static void registerCourseMapping(String courseName, String courseId) {
    final cleaned = cleanCourseName(courseName);
    final core = extractCoreCourseName(courseName);
    _userCourseIds[cleaned] = courseId;
    _userCourseIds[courseName] = courseId;
    if (core.isNotEmpty) _userCourseIds[core] = courseId;
    final box = _getHiveBox();
    box?.put('zhiyun_cid_$cleaned', courseId);
    box?.put('zhiyun_cid_$courseName', courseId);
    if (core.isNotEmpty) box?.put('zhiyun_cid_$core', courseId);
  }

  /// 注册/更新课节的 Zhiyun sub_id 映射
  static void registerSubIdMapping(
      String courseId, String dateStr, String subId,
      {int? hour, int? minute}) {
    _knownSubIds['${courseId}_$dateStr'] = subId;
    if (hour != null) {
      _knownSubIds['${courseId}_${dateStr}_$hour'] = subId;
      if (minute != null) {
        _knownSubIds['${courseId}_${dateStr}_${hour}_$minute'] = subId;
      }
    }
  }

  /// 智能检测课程或特定课节当前是否正在智云课堂直播
  static bool checkIsLive({
    Map<String, dynamic>? item,
    DateTime? targetDate,
    Period? period,
  }) {
    final now = DateTime.now();

    // 0. 时间合理性硬防线：防止历史缓存/普通课节(如 status='1')被误判成“正在直播”
    if (period != null) {
      if (now.isBefore(period.startTime.subtract(const Duration(minutes: 20))) ||
          now.isAfter(period.endTime.add(const Duration(minutes: 25)))) {
        return false;
      }
    }

    final sDt = parseZhiyunTimestamp(_rawStartAt(item));
    final eDt = parseZhiyunTimestamp(_rawEndAt(item));
    if (eDt != null && now.isAfter(eDt.add(const Duration(minutes: 30)))) {
      return false;
    }
    if (sDt != null && now.isBefore(sDt.subtract(const Duration(minutes: 20)))) {
      return false;
    }
    if (sDt != null &&
        eDt == null &&
        now.isAfter(sDt.add(const Duration(hours: 3)))) {
      return false;
    }
    if (period == null && sDt == null && targetDate != null) {
      // 目标日期若与今天不是同一天，绝不可能是直播
      if (targetDate.year != now.year ||
          targetDate.month != now.month ||
          targetDate.day != now.day) {
        return false;
      }
    }

    // 1. 排除明确已结束/未开始/仅回放状态
    final statusLabel = item?['status_label']?.toString() ?? '';
    final status = item?['status']?.toString() ?? '';
    final subStatus = item?['sub_status']?.toString() ?? '';
    if (status == '3' ||
        status == '4' ||
        subStatus == '3' ||
        subStatus == '5' ||
        subStatus == '6' ||
        statusLabel.contains('回放') ||
        statusLabel.contains('录播') ||
        statusLabel.contains('已结束') ||
        statusLabel == '未开始') {
      return false;
    }

    // 2. 服务端明确的实时直播信号（注意：智云目录 status=='1' 为普通发布态，而 sub_status=='1'/'2' 表示直播中）
    if (item != null) {
      if (subStatus == '1' || subStatus == '2') {
        return true;
      }
      if (statusLabel == '直播' ||
          statusLabel.contains('直播') ||
          statusLabel.toLowerCase() == 'live') {
        return true;
      }
      final isLiveField = item['is_live'];
      if (isLiveField == true ||
          isLiveField == 1 ||
          isLiveField == '1' ||
          isLiveField == 'true') {
        return true;
      }
      if (status == '2') {
        return true;
      }
      final liveType = item['live_type']?.toString();
      if (liveType == 'live') {
        return true;
      }
    }

    // 3. 仅当接口明确返回直播流地址（且尚未转为回放）时才判定为直播，
    // 禁止仅凭课表时间段“偷懒猜直播”（并非每门课/每节课都开启智云直播）。
    final hasReplayMedia = item != null &&
        ((item['playback'] != null &&
                item['playback'] != false &&
                item['playback'] != 'false' &&
                item['playback'].toString().isNotEmpty) ||
            ((item['video_url'] ??
                        item['play_url'] ??
                        item['m3u8'] ??
                        item['replay_url'])
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true));
    if (hasReplayMedia || item == null) {
      return false;
    }

    final liveUrl = (item['live_url'] ??
            item['stream_url'] ??
            item['hls_url'] ??
            item['rtmp_url'])
        ?.toString()
        .trim();
    if (liveUrl != null && liveUrl.isNotEmpty) {
      if (period != null) {
        return now.isAfter(
                period.startTime.subtract(const Duration(minutes: 15))) &&
            now.isBefore(period.endTime.add(const Duration(minutes: 30)));
      }
      if (sDt != null) {
        final effectiveEnd = eDt ?? sDt.add(const Duration(minutes: 120));
        return now.isAfter(sDt.subtract(const Duration(minutes: 15))) &&
            now.isBefore(effectiveEnd.add(const Duration(minutes: 30)));
      }
      return true;
    }

    return false;
  }

  /// 智能检测课程或特定课节是否已在智云课堂生成录播回放
  static bool checkHasReplay({
    Map<String, dynamic>? item,
    DateTime? targetDate,
    Period? period,
  }) {
    if (item == null) return false;

    // 1. 检查 item 中的明确回放/录播标记
    final statusLabel = item['status_label']?.toString() ?? '';
    if (statusLabel == '回放' ||
        statusLabel.contains('回放') ||
        statusLabel.contains('录播')) {
      return true;
    }
    final status = item['status']?.toString();
    final subStatus = item['sub_status']?.toString();
    if (status == '4' || status == '3' || subStatus == '6') {
      return true;
    }
    final playback = item['playback'];
    if (playback != null &&
        playback != false &&
        playback != 'false' &&
        playback.toString().trim().isNotEmpty) {
      return true;
    }
    final videoUrl = item['video_url'] ??
        item['play_url'] ??
        item['m3u8'] ??
        item['replay_url'];
    if (videoUrl != null && videoUrl.toString().trim().isNotEmpty) {
      return true;
    }
    final explicitReplay = item['has_replay'] ?? item['is_replay'];
    if (explicitReplay == true || explicitReplay?.toString() == '1') {
      return true;
    }

    // 2. 时间维度：如果是未来的课节，绝无回放
    final now = DateTime.now();
    final lessonDate = targetDate ?? parseZhiyunTimestamp(_rawStartAt(item));
    if (lessonDate != null && lessonDate.isAfter(now)) {
      return false;
    }

    // 3. 若未给出任何回放标识/媒体链接，不凭“开课超过 30 分钟”假设有回放：
    // 同一门课的不同课节不一定都有回放，需由目录字段或流媒体探测实际证实。
    return false;
  }

  /// 从课程目录项中提取时间
  static DateTime? _extractCatalogueItemDateTime(
      Map<String, dynamic> item, DateTime fallbackDate) {
    final parsed = parseZhiyunTimestamp(_rawStartAt(item));
    if (parsed != null) {
      return parsed;
    }
    final dateVal = item['date']?.toString();
    if (dateVal != null && dateVal.isNotEmpty) {
      final p = DateTime.tryParse(dateVal);
      if (p != null && (p.hour != 0 || p.minute != 0)) {
        return p;
      }
    }
    final title =
        item['title']?.toString() ?? item['sub_title']?.toString() ?? '';
    final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(title);
    if (timeMatch != null) {
      final h = int.parse(timeMatch.group(1)!);
      final m = int.parse(timeMatch.group(2)!);
      return DateTime(
          fallbackDate.year, fallbackDate.month, fallbackDate.day, h, m);
    }
    return null;
  }

  /// 从智云课程目录中精准匹配目标日期及节次的单堂课记录
  ///
  /// 当一门课在同一天有多堂（如上午一堂、下午一堂）时：
  /// 1. 优先在正在上课的时间窗口内校准正在直播中的节次；
  /// 2. 优先通过上课时间（Period.startTime 与 item.start_at）的最小时间差精确匹配；
  /// 3. 辅助结合节次安排（如第1-2节 vs 第6-7节）；
  /// 4. 若时间信息缺失，结合课程当天排课次序与智云课表先后顺序对齐。
  static Map<String, dynamic>? findBestMatchingCatalogueItem({
    required List<Map<String, dynamic>> catalogue,
    required DateTime targetDate,
    Course? course,
    Period? period,
  }) {
    if (catalogue.isEmpty) return null;

    final dateKey =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
    final shortDateKey = '${targetDate.month}月${targetDate.day}日';

    // 1. 筛选出属于目标日期的所有候选课节
    final sameDateItems = <Map<String, dynamic>>[];
    for (final item in catalogue) {
      DateTime? itemDate = parseZhiyunTimestamp(_rawStartAt(item));
      if (itemDate == null && item['date'] != null) {
        itemDate = DateTime.tryParse(item['date'].toString());
      }

      final title =
          item['title']?.toString() ?? item['sub_title']?.toString() ?? '';

      final isSameDay = itemDate != null &&
          itemDate.year == targetDate.year &&
          itemDate.month == targetDate.month &&
          itemDate.day == targetDate.day;

      final containsDate =
          title.contains(dateKey) || title.contains(shortDateKey);

      if (isSameDay || containsDate) {
        sameDateItems.add(item);
      }
    }

    if (sameDateItems.isEmpty) return null;
    if (sameDateItems.length == 1) return sameDateItems.first;

    // 当同一天存在多节课时，按多维度智能判定最优匹配：
    final now = DateTime.now();

    // 策略 A（实时直播优先）：若当前正处于该节课的上课时间窗口内，优先匹配正在直播状态的节次
    if (period != null) {
      final isCurrentPeriodActive =
          now.isAfter(period.startTime.subtract(const Duration(minutes: 15))) &&
              now.isBefore(period.endTime.add(const Duration(minutes: 15)));
      if (isCurrentPeriodActive) {
        for (final item in sameDateItems) {
          if (checkIsLive(item: item, period: period)) {
            return item;
          }
        }
      }
    }

    // 策略 B（绝对时间距离最接近匹配）：对比 Period.startTime 与 item.start_at / 标题中时间
    if (period != null) {
      Map<String, dynamic>? closestItem;
      int minDiffMs = 1 << 62;

      for (final item in sameDateItems) {
        final itemStart = _extractCatalogueItemDateTime(item, targetDate);
        if (itemStart != null) {
          final dayItemTime = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            itemStart.hour,
            itemStart.minute,
          );
          final diff =
              (dayItemTime.difference(period.startTime)).abs().inMilliseconds;
          if (diff < minDiffMs) {
            minDiffMs = diff;
            closestItem = item;
          }
        }
      }

      // 如果最接近的一项时间差在合理范围内（2小时内，通常同一天不同课节间隔至少2~3小时以上）
      if (closestItem != null && minDiffMs <= 2 * 3600 * 1000) {
        return closestItem;
      }
    }

    // 策略 C（节次序号匹配）：从 Period 的描述中提取节次数字与智云标题对比
    if (period != null) {
      final periodSectionMatch =
          RegExp(r'第?\s*(\d+)').firstMatch(period.description);
      if (periodSectionMatch != null) {
        final secNum = periodSectionMatch.group(1);
        if (secNum != null) {
          for (final item in sameDateItems) {
            final title = item['title']?.toString() ??
                item['sub_title']?.toString() ??
                '';
            if (title.contains('第$secNum') ||
                title.contains('第 $secNum') ||
                title.contains('$secNum节')) {
              return item;
            }
          }
        }
      }
    }

    // 策略 D（当天节次排序对齐）：
    // 若当天同一门课有多个 Period，按 startTime 排序，并与按时间排序后的智云 catalogue 对应
    if (period != null) {
      try {
        if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
          final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
          final todayPeriods = scholar.periods
              .where((p) =>
                  p.type == PeriodType.classes &&
                  (p.fromUid == period.fromUid ||
                      p.summary == period.summary ||
                      (course != null &&
                          (p.fromUid == course.id ||
                              p.summary == course.name))) &&
                  p.startTime.year == targetDate.year &&
                  p.startTime.month == targetDate.month &&
                  p.startTime.day == targetDate.day)
              .toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          final rank = todayPeriods.indexWhere(
              (p) => p.startTime.isAtSameMomentAs(period.startTime));

          if (rank >= 0) {
            final sortedItems = List<Map<String, dynamic>>.from(sameDateItems);
            sortedItems.sort((a, b) {
              final aStart = int.tryParse(a['start_at']?.toString() ?? '') ?? 0;
              final bStart = int.tryParse(b['start_at']?.toString() ?? '') ?? 0;
              if (aStart != bStart) return aStart.compareTo(bStart);
              final aId = int.tryParse(
                      a['sub_id']?.toString() ?? a['id']?.toString() ?? '') ??
                  0;
              final bId = int.tryParse(
                      b['sub_id']?.toString() ?? b['id']?.toString() ?? '') ??
                  0;
              return aId.compareTo(bId);
            });

            if (rank < sortedItems.length) {
              return sortedItems[rank];
            }
          }
        }
      } catch (_) {}
    }

    // 兜底返回第一个候选
    return sameDateItems.first;
  }

  /// 按智云课堂真实流媒体结果核验单节课是否确有直播或录播回放，避免仅靠排课时间段误判
  static Future<ZhiyunReplayInfo> _resolveVerifiedLessonReplayInfo({
    required String courseId,
    required String subId,
    required String courseName,
    required Map<String, dynamic>? matchedItem,
    required String shortDateKey,
    DateTime? targetDate,
    Period? period,
  }) async {
    var isLive = checkIsLive(
      item: matchedItem,
      targetDate: targetDate,
      period: period,
    );
    var hasReplay = checkHasReplay(
      item: matchedItem,
      targetDate: targetDate,
      period: period,
    );

    final now = DateTime.now();
    final effectiveStart = period?.startTime ??
        targetDate ??
        (matchedItem != null
            ? parseZhiyunTimestamp(_rawStartAt(matchedItem))
            : null);
    final effectiveEnd = period?.endTime ??
        (matchedItem != null
            ? parseZhiyunTimestamp(_rawEndAt(matchedItem))
            : null) ??
        effectiveStart?.add(const Duration(minutes: 120));

    final isFutureLesson = effectiveStart != null &&
        effectiveStart.isAfter(now.add(const Duration(minutes: 15)));
    final isInLiveWindow = effectiveStart == null ||
        (now.isAfter(effectiveStart.subtract(const Duration(minutes: 20))) &&
            now.isBefore(
                (effectiveEnd ?? effectiveStart.add(const Duration(minutes: 120)))
                    .add(const Duration(minutes: 30))));

    // 若目录/日程摘要未给出明确状态，主动探测该节真实音视频流
    if (!isLive && !hasReplay && !isFutureLesson) {
      final cacheKey = '${courseId}_$subId';
      final cached = _lessonAvailabilityCache[cacheKey];
      if (cached != null &&
          now.difference(cached.cachedAt) < const Duration(minutes: 2)) {
        isLive = cached.isLive && isInLiveWindow;
        hasReplay = cached.hasReplay;
      } else {
        final streams = await fetchLessonStreams(
          courseId: courseId,
          subId: subId,
          preferLive: isInLiveWindow,
        );
        if (streams.any((s) => !s.isLive)) {
          hasReplay = true;
          isLive = false;
        } else if (streams.any((s) => s.isLive) && isInLiveWindow) {
          isLive = true;
        }
        _lessonAvailabilityCache[cacheKey] = (
          isLive: isLive,
          hasReplay: hasReplay,
          cachedAt: now,
        );
      }
    }

    final rawTitle = (matchedItem?['title'] ?? matchedItem?['sub_title'])
        ?.toString()
        .trim();
    final lessonTitle = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : (isLive
            ? '$shortDateKey 课堂直播'
            : hasReplay
                ? '$shortDateKey 课堂录播'
                : '$shortDateKey 智云课程');

    return ZhiyunReplayInfo(
      courseId: courseId,
      subId: subId,
      courseName: courseName,
      lessonTitle: lessonTitle,
      lessonDate: targetDate,
      hasReplay: hasReplay,
      isLive: isLive,
      isLessonSpecific: true,
      livingroomUrl: buildLivingroomUrl(courseId, subId),
    );
  }

  /// 解析指定课程/节次的回放或直播信息。若为体育/素质课等非录播课程，返回 null（自动隐藏入口）
  static Future<ZhiyunReplayInfo?> getLessonReplay({
    required Course course,
    Period? period,
    DateTime? lessonDate,
    String? semesterName,
    String? preferredHalfTag,
  }) async {
    // 1. 若为体育、身体素质、实践等非录播课程，坚决不展示回放入口（自动隐藏）
    if (!isRecordableCourse(course.name, courseCode: course.id)) {
      return null;
    }

    // 确定目标节次日期
    final targetDate = period?.startTime ?? lessonDate;

    // 自动升级/清理跨版本的旧版智云污染缓存（仅执行一次，保留手动绑定与解绑记录）
    _ensureCacheSchemaUpgraded();
    final hint = inferSemesterHint(
      course: course,
      courseCode: course.id,
      courseName: course.name,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );

    // 若用户显式解绑过该课程，不进行静默自动同步或在线匹配，保持未绑定状态
    if (isExplicitlyUnbound(course.name, courseCode: course.id)) {
      return ZhiyunReplayInfo(
        courseId: null,
        subId: null,
        courseName: course.name,
        lessonTitle: '${course.name} 智云课堂',
        lessonDate: targetDate,
        hasReplay: false,
        isLive: false,
        isLessonSpecific: false,
        livingroomUrl: buildSearchContentUrl(course.name),
      );
    }

    // 收集所有候选教师（秋冬/春夏不同学期教学班可能分配不同教师）
    final candidateTeachers = <String>{};
    if (course.teacher != null && course.teacher!.trim().isNotEmpty) {
      candidateTeachers.add(course.teacher!.trim());
    }
    for (final s in course.sessions) {
      if (s.teacher.trim().isNotEmpty) {
        candidateTeachers.add(s.teacher.trim());
      }
    }

    // 自动检查同步时效：若尚未同步或缓存已超过 12 小时（跨学期过渡期），自动触发后台更新
    final box = _getHiveBox();
    final lastSyncStr = box?.get('zhiyun_my_courses_time')?.toString();
    final lastSync =
        lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;
    final isStale = lastSync == null ||
        DateTime.now().difference(lastSync) > const Duration(hours: 12);
    if (getMySyncedCourses().isEmpty || isStale) {
      await syncFromMyCourses();
    }

    // 2. 优先策略：从用户专属“我的排课节次”中动态精准查找目标日期的直播/回放节次
    if (targetDate != null) {
      final dateKey =
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      final shortDateKey = '${targetDate.month}月${targetDate.day}日';

      final matchingTodaySessions = getMySyncedSessions().where((s) {
        if (s['date'] != dateKey) return false;
        final t =
            s['course_title']?.toString() ?? s['title']?.toString() ?? '';
        return matchesCourseName(course.name, t);
      }).toList();

      if (matchingTodaySessions.isNotEmpty) {
        Map<String, dynamic>? bestSession;
        if (period != null) {
          // 优先匹配当前正在直播的节次
          for (final s in matchingTodaySessions) {
            if (checkIsLive(item: s, targetDate: targetDate, period: period)) {
              bestSession = s;
              break;
            }
          }
          // 其次匹配上课时间最接近的节次
          if (bestSession == null) {
            int minDiff = 1 << 62;
            for (final s in matchingTodaySessions) {
              final sDt = parseZhiyunTimestamp(s['start_at']);
              if (sDt != null) {
                final diff =
                    (sDt.difference(period.startTime)).abs().inMilliseconds;
                if (diff < minDiff) {
                  minDiff = diff;
                  bestSession = s;
                }
              }
            }
          }
        }
        bestSession ??= matchingTodaySessions.first;

        final sCid = bestSession['course_id']?.toString();
        final sSubId = bestSession['sub_id']?.toString();
        if (sCid != null &&
            sCid.isNotEmpty &&
            sSubId != null &&
            sSubId.isNotEmpty &&
            !isCourseOffShelfMeta(_courseDetailMetaCache[sCid])) {
          return _resolveVerifiedLessonReplayInfo(
            courseId: sCid,
            subId: sSubId,
            courseName: course.name,
            matchedItem: bestSession,
            shortDateKey: shortDateKey,
            targetDate: targetDate,
            period: period,
          );
        }
      }
    }

    // 3. 解析 course_id（结合课程学年、所在学期与秋/冬/春/夏半学期智能分流）
    var courseId = getKnownCourseId(
      course.name,
      courseCode: course.id,
      teacher: course.teacher,
      candidateTeachers: candidateTeachers.toList(),
      course: course,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );

    // 如果未找到，尝试强制同步
    if (courseId == null) {
      final synced = await syncFromMyCourses();
      if (synced > 0) {
        courseId = getKnownCourseId(
          course.name,
          courseCode: course.id,
          teacher: course.teacher,
          candidateTeachers: candidateTeachers.toList(),
          course: course,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
          targetDate: targetDate,
        );
      }
    }

    // 若依然未找到，尝试直接通过智云搜索接口在线精准检索（校验下架状态与学年半学期）
    courseId ??= await searchCourseOnline(
      courseName: course.name,
      teacher: course.teacher,
      course: course,
      courseCode: course.id,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
      targetDate: targetDate,
    );

    // 4. 如果成功匹配到 course_id
    if (courseId != null) {
      // 尝试拉取智云课程目录
      var catalogue = await fetchCourseCatalogue(courseId);
      var detailMeta = _courseDetailMetaCache[courseId];

      // 校验是否属于已下架课程或与目标学年/半学期（秋/冬/春/夏）冲突
      // 绝不使用“>45天”一刀切判定失效，确保跨学期仍可正常观看上一学期/前半学期回放
      final isPinnedManually = _isManuallyPinned(
        course.name,
        courseCode: course.id,
        hint: hint,
      );
      final isInvalidOrMismatched = !isPinnedManually &&
          (isCourseOffShelfMeta(detailMeta) ||
              isCatalogueMismatchedWithHint(
                catalogue,
                hint,
                meta: detailMeta,
              ));

      if (isInvalidOrMismatched) {
        final cleaned = cleanCourseName(course.name);
        final staleKeys = _buildScopedCidKeys(
          cleaned: cleaned,
          courseName: course.name,
          normalized: normalizeCourseName(course.name),
          core: extractCoreCourseName(course.name),
          coreNormalized:
              normalizeCourseName(extractCoreCourseName(course.name)),
          courseCode: course.id,
          scopeKey: hint.scopeKey,
        );
        for (final k in staleKeys) {
          _userCourseIds.remove(k);
          box?.delete('zhiyun_cid_$k');
        }

        await syncFromMyCourses();
        var refreshedId = getKnownCourseId(
          course.name,
          courseCode: course.id,
          teacher: course.teacher,
          candidateTeachers: candidateTeachers.toList(),
          course: course,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
          targetDate: targetDate,
        );
        refreshedId ??= await searchCourseOnline(
          courseName: course.name,
          teacher: course.teacher,
          course: course,
          courseCode: course.id,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
          targetDate: targetDate,
        );
        if (refreshedId != null && refreshedId != courseId) {
          courseId = refreshedId;
          catalogue = await fetchCourseCatalogue(courseId);
          detailMeta = _courseDetailMetaCache[courseId];
        } else if (isCourseOffShelfMeta(detailMeta)) {
          courseId = null;
        }
      }

      if (courseId != null) {

      if (targetDate != null) {
        final dateKey =
            '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
        final shortDateKey = '${targetDate.month}月${targetDate.day}日';

        // 尝试从目录精准匹配具体节次（支持同一天多堂课智能区分）
        final matchedItem = findBestMatchingCatalogueItem(
          catalogue: catalogue,
          targetDate: targetDate,
          course: course,
          period: period,
        );

        String? subId = matchedItem?['sub_id']?.toString() ??
            matchedItem?['id']?.toString();

        if (subId == null || subId.isEmpty) {
          if (period != null) {
            final h = period.startTime.hour;
            final m = period.startTime.minute;
            subId = _knownSubIds['${courseId}_${dateKey}_${h}_$m'] ??
                _knownSubIds['${courseId}_${dateKey}_$h'] ??
                _knownSubIds['${courseId}_$dateKey'];
          } else {
            subId = _knownSubIds['${courseId}_$dateKey'];
          }
        }

        if (subId == null || subId.isEmpty) {
          subId = await fetchActiveSubIdForDate(
            courseId,
            targetDate,
            period: period,
          );
        }

        if (subId != null && subId.isNotEmpty) {
          if (period != null) {
            registerSubIdMapping(
              courseId,
              dateKey,
              subId,
              hour: period.startTime.hour,
              minute: period.startTime.minute,
            );
          }
          return _resolveVerifiedLessonReplayInfo(
            courseId: courseId,
            subId: subId,
            courseName: course.name,
            matchedItem: matchedItem,
            shortDateKey: shortDateKey,
            targetDate: targetDate,
            period: period,
          );
        } else if (checkIsLive(
          item: matchedItem,
          targetDate: targetDate,
          period: period,
        )) {
          // 当前时段正在直播，但未拿到特定 subId，直达整门课程房间
          return ZhiyunReplayInfo(
            courseId: courseId,
            subId: null,
            courseName: course.name,
            lessonTitle: '$shortDateKey 课堂直播',
            lessonDate: targetDate,
            hasReplay: false,
            isLive: true,
            isLessonSpecific: true,
            livingroomUrl: buildCourseLivingroomUrl(courseId),
          );
        } else if (period != null || lessonDate != null) {
          // 明确选定课节，未找到录播回放
          return ZhiyunReplayInfo(
            courseId: courseId,
            subId: null,
            courseName: course.name,
            lessonTitle: '$shortDateKey 智云课程',
            lessonDate: targetDate,
            hasReplay: false,
            isLive: false,
            isLessonSpecific: true,
            livingroomUrl: buildCourseLivingroomUrl(courseId),
          );
        }
      }

      // 如果节次未匹配上或尚未生成，返回整门课程专属房间直达
      // 检查整门课是否有任何正在直播的节次
      bool courseHasLive = false;
      String? liveSubId;
      for (final item in catalogue) {
        if (checkIsLive(item: item)) {
          courseHasLive = true;
          liveSubId = item['sub_id']?.toString() ?? item['id']?.toString();
          break;
        }
      }

      // 检查整门课是否有任何已生成的回放
      final courseHasAnyReplay =
          catalogue.any((item) => checkHasReplay(item: item));

      return ZhiyunReplayInfo(
        courseId: courseId,
        subId: liveSubId,
        courseName: course.name,
        lessonTitle:
            courseHasLive ? '${course.name} 课堂直播' : '${course.name} 智云课程房间',
        lessonDate: targetDate,
        hasReplay: courseHasAnyReplay,
        isLive: courseHasLive,
        isLessonSpecific: false,
        livingroomUrl: liveSubId != null
            ? buildLivingroomUrl(courseId, liveSubId)
            : buildCourseLivingroomUrl(courseId),
      );
      }
    }

    // 5. 未找到智云课程：返回智云搜索与手动绑定入口
    return ZhiyunReplayInfo(
      courseId: null,
      subId: null,
      courseName: course.name,
      lessonTitle: '${course.name} 智云课堂',
      lessonDate: targetDate,
      hasReplay: false,
      isLive: false,
      isLessonSpecific: false,
      livingroomUrl: buildSearchContentUrl(course.name),
    );
  }

  /// 按日期实时查询某门课当日/指定日期的课节 sub_id（用于正在直播但目录尚未归档的课节）
  static Future<String?> fetchActiveSubIdForDate(
    String courseId,
    DateTime targetDate, {
    Period? period,
  }) async {
    final dateKey =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
    if (period != null) {
      final cached = _knownSubIds[
              '${courseId}_${dateKey}_${period.startTime.hour}_${period.startTime.minute}'] ??
          _knownSubIds['${courseId}_${dateKey}_${period.startTime.hour}'] ??
          _knownSubIds['${courseId}_$dateKey'];
      if (cached != null && cached.isNotEmpty) return cached;
    } else {
      final cached = _knownSubIds['${courseId}_$dateKey'];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final client = createHttpClient();
    try {
      final token = await ensureValidToken();
      final candidateItems = <Map<String, dynamic>>[];

      final dateUnpadded =
          '${targetDate.year}-${targetDate.month}-${targetDate.day}';
      final uris = <Uri>[
        Uri.parse(
          '$_kZhiyunBaseUrl/courseapi/v2/course-live/get-my-course-day?day=$dateKey&tenant_code=$_kTenantCode',
        ),
        if (dateUnpadded != dateKey)
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/v2/course-live/get-my-course-day?day=$dateUnpadded&tenant_code=$_kTenantCode',
          ),
        Uri.parse(
          '$_kZhiyunBaseUrl/courseapi/v2/course-live/search-live-course-list?all=1&course_id=$courseId&with_sub_data=1&with_room_data=1&show_all=1&show_delete=2',
        ),
      ];

      for (final uri in uris) {
        try {
          final req = await client.getUrl(uri);
          if (token != null && token.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $token');
            req.headers.set(
              'Cookie',
              '_token=${buildPhpSerializedTokenCookie(token)}; token=$token',
            );
          }
          req.headers.set('Origin', 'https://classroom.zju.edu.cn');
          req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
          req.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          );
          final resp = await req.close().timeout(const Duration(seconds: 6));
          if (resp.statusCode != 200) continue;
          final body = await resp.transform(utf8.decoder).join();
          final decoded = jsonDecode(body);
          for (final item in _extractSubItemsFromResponse(decoded)) {
            final itemCid = item['course_id']?.toString() ?? '';
            if (itemCid.isEmpty || itemCid == courseId) {
              candidateItems.add(item);
            }
          }
        } catch (_) {}
      }

      if (candidateItems.isNotEmpty) {
        _registerSubIdsFromList(courseId, candidateItems);
        final matched = findBestMatchingCatalogueItem(
          catalogue: candidateItems,
          targetDate: targetDate,
          period: period,
        );
        final matchedSubId =
            matched?['sub_id']?.toString() ?? matched?['id']?.toString();
        if (matchedSubId != null && matchedSubId.isNotEmpty) {
          return matchedSubId;
        }
        for (final item in candidateItems) {
          if (checkIsLive(item: item, targetDate: targetDate, period: period)) {
            final sid = item['sub_id']?.toString() ?? item['id']?.toString();
            if (sid != null && sid.isNotEmpty) return sid;
          }
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return _knownSubIds['${courseId}_$dateKey'];
  }

  /// 通过统一身份认证登录智云课堂并动态同步“我的课程”所有课程及课节回放映射
  static Future<int> syncFromMyCourses({
    HttpClient? httpClient,
    Cookie? ssoCookie,
    String? username,
    String? password,
  }) async {
    final pending = _syncFuture;
    if (pending != null) {
      return await pending;
    }
    final future = _doSyncFromMyCourses(
      httpClient: httpClient,
      ssoCookie: ssoCookie,
      username: username,
      password: password,
    );
    _syncFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_syncFuture, future)) {
        _syncFuture = null;
      }
    }
  }

  static Future<int> _doSyncFromMyCourses({
    HttpClient? httpClient,
    Cookie? ssoCookie,
    String? username,
    String? password,
  }) async {
    // 始终使用专用的 DIRECT 直连客户端，绕过系统代理，防止校园网内网握手失败
    final client = createHttpClient();

    try {
      String? u = username;
      String? p = password;
      if (u == null || p == null) {
        try {
          if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
            final db = Get.find<DatabaseHelper>(tag: 'db');
            final scholar = await db.getScholar();
            u = scholar.username;
            p = scholar.password;
          }
        } catch (_) {}
      }

      if (u != null && u.isNotEmpty) {
        await ensureAccountScope(u);
      }

      Cookie? cookie = ssoCookie;
      if (cookie == null) {
        if (u != null && u.isNotEmpty && p != null && p.isNotEmpty) {
          cookie = await ZjuAm.getSsoCookie(client, u, p);
        }
      }

      var token = cookie != null ? await _loginZhiyunCas(client, cookie) : null;
      token ??= getCachedZhiyunToken();
      if (token == null || token.isEmpty) {
        debugPrint('[ZhiyunService] 暂无有效智云 Token，跳过课程自动同步');
        return 0;
      }
      final authToken = token;

      _ensureCacheSchemaUpgraded();

      final now = DateTime.now();
      // 动态生成覆盖“当月 + 上一学期 + 当前完整学年（含春夏/秋冬/短学期）”的滑窗月份列表
      final curMonthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final prevMonthDt = DateTime(now.year, now.month - 1, 1);
      final nextMonthDt = DateTime(now.year, now.month + 1, 1);
      final prevMonthStr =
          '${prevMonthDt.year}-${prevMonthDt.month.toString().padLeft(2, '0')}';
      final nextMonthStr =
          '${nextMonthDt.year}-${nextMonthDt.month.toString().padLeft(2, '0')}';

      final orderedMonths = <String>[curMonthStr, prevMonthStr, nextMonthStr];
      // 滑窗：覆盖过去 9 个月至未来 6 个月（无论处在春夏或秋冬，都能兼顾上一学期与本学期全阶段）
      for (int offset = 0; offset >= -9; offset--) {
        final d = DateTime(now.year, now.month + offset, 1);
        final s = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (!orderedMonths.contains(s)) orderedMonths.add(s);
      }
      for (int offset = 2; offset <= 6; offset++) {
        final d = DateTime(now.year, now.month + offset, 1);
        final s = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (!orderedMonths.contains(s)) orderedMonths.add(s);
      }
      final academicStartYear = now.month >= 8 ? now.year : now.year - 1;
      final academicEndYear = academicStartYear + 1;
      if (!orderedMonths.contains('$academicStartYear-08')) {
        orderedMonths.add('$academicStartYear-08');
      }
      for (int m = 9; m <= 12; m++) {
        final s = '$academicStartYear-${m.toString().padLeft(2, '0')}';
        if (!orderedMonths.contains(s)) orderedMonths.add(s);
      }
      for (int m = 1; m <= 7; m++) {
        final s = '$academicEndYear-${m.toString().padLeft(2, '0')}';
        if (!orderedMonths.contains(s)) orderedMonths.add(s);
      }

      final foundCoursesMap = <String, Map<String, dynamic>>{};
      final foundSessions = <Map<String, dynamic>>[];

      Future<void> fetchOneMonth(String m) async {
        final unpadded = m.replaceFirstMapped(
          RegExp(r'^(\d{4})-0(\d)$'),
          (match) => '${match.group(1)}-${match.group(2)}',
        );
        final queryCandidates = unpadded != m ? [unpadded, m] : [m];

        for (final qMonth in queryCandidates) {
          try {
            final uri = Uri.parse(
                '$_kZhiyunBaseUrl/courseapi/v2/course-live/get-my-course-month?month=$qMonth&tenant_code=$_kTenantCode');
            final req = await client.getUrl(uri);
            req.headers.set('Authorization', 'Bearer $authToken');
            req.headers.set(
              'Cookie',
              '_token=${buildPhpSerializedTokenCookie(authToken)}; token=$authToken',
            );
            req.headers.set('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
            final resp = await req.close().timeout(const Duration(seconds: 8));
            if (resp.statusCode != 200) {
              await resp.drain();
              continue;
            }
            final body = await resp.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is! Map) continue;

            final rawList = json['list'] ??
                (json['data'] is Map ? json['data']['list'] : null);
            Iterable? dayItems;
            if (rawList is List) {
              dayItems = rawList;
            } else if (rawList is Map) {
              dayItems = rawList.values;
            }
            if (dayItems == null) continue;

            final normMonth = _normalizeYearMonth(m);
            for (final dayItem in dayItems) {
              if (dayItem is! Map) continue;
              final rawCourses = dayItem['course'] ?? dayItem['courses'];
              Iterable? coursesList;
              if (rawCourses is List) {
                coursesList = rawCourses;
              } else if (rawCourses is Map) {
                coursesList = rawCourses.values;
              }
              if (coursesList == null) continue;

              for (final c in coursesList) {
                if (c is! Map) continue;
                if (isCourseOffShelfMeta(c)) continue;

                final cid = c['course_id']?.toString() ?? c['id']?.toString();
                final title =
                    c['title']?.toString() ?? c['course_title']?.toString();
                final subId = (c['sub_id'] ?? c['id'])?.toString();
                final startAt = int.tryParse(_rawStartAt(c)?.toString() ?? '');
                final endAt = int.tryParse(_rawEndAt(c)?.toString() ?? '');
                final teacher = c['realname']?.toString() ??
                    c['teacher']?.toString() ??
                    c['lecturer_name']?.toString();
                final termName =
                    (c['term_name'] ?? c['semester_name'] ?? '').toString();

                if (cid != null &&
                    cid.isNotEmpty &&
                    title != null &&
                    title.isNotEmpty) {
                  final existing = foundCoursesMap.putIfAbsent(
                    cid,
                    () => {
                      'course_id': cid,
                      'course_title': title,
                      if (teacher != null && teacher.isNotEmpty)
                        'teacher': teacher,
                      if (termName.isNotEmpty) 'term_name': termName,
                      'active_months': <String>[],
                    },
                  );
                  if (termName.isNotEmpty &&
                      (existing['term_name']?.toString().isEmpty ?? true)) {
                    existing['term_name'] = termName;
                  }
                  final activeMonths = existing['active_months'] as List;
                  if (!activeMonths.contains(normMonth)) {
                    activeMonths.add(normMonth);
                  }

                  final dt = parseZhiyunTimestamp(startAt);
                  if (dt != null && subId != null && subId.isNotEmpty) {
                    final dKey =
                        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                    _knownSubIds['${cid}_$dKey'] = subId;
                    _knownSubIds['${cid}_${dKey}_${dt.hour}'] = subId;
                    _knownSubIds['${cid}_${dKey}_${dt.hour}_${dt.minute}'] =
                        subId;

                    foundSessions.add({
                      'course_id': cid,
                      'course_title': title,
                      'sub_id': subId,
                      if (teacher != null && teacher.isNotEmpty)
                        'teacher': teacher,
                      'start_at': startAt,
                      'end_at': endAt,
                      'date': dKey,
                      if (c['status'] != null) 'status': c['status'].toString(),
                      if (c['sub_status'] != null)
                        'sub_status': c['sub_status'].toString(),
                      if (c['is_live'] != null) 'is_live': c['is_live'],
                      if (c['playback'] != null) 'playback': c['playback'],
                      if (c['video_url'] != null) 'video_url': c['video_url'],
                      if (c['play_url'] != null) 'play_url': c['play_url'],
                      if (c['m3u8'] != null) 'm3u8': c['m3u8'],
                      if (c['replay_url'] != null)
                        'replay_url': c['replay_url'],
                      if (c['live_url'] != null) 'live_url': c['live_url'],
                      if (c['has_replay'] != null)
                        'has_replay': c['has_replay'],
                      if (c['is_replay'] != null) 'is_replay': c['is_replay'],
                      'status_label': c['status_label']?.toString() ?? '',
                      'month': normMonth,
                    });
                  }
                }
              }
            }
            // 成功解析出 list 结构，无需再用补零月份重复请求
            break;
          } catch (e) {
            debugPrint('[ZhiyunService] 查询月份课程失败 ($qMonth): $e');
          }
        }
      }

      // 并发分批拉取全部月份（确保 9 月秋学期课程不会被串行超时丢弃）
      for (int i = 0; i < orderedMonths.length; i += 4) {
        final batch = orderedMonths.sublist(
          i,
          i + 4 > orderedMonths.length ? orderedMonths.length : i + 4,
        );
        await Future.wait(batch.map(fetchOneMonth));
      }

      // 额外尝试调用用户主页选课接口 (vlabpassportapi，需携带 PHP 序列化 _token Cookie 并兼容 code=1000/params)
      try {
        final profileUri = Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/vlabpassportapi/v1/account-profile/course?tenant_code=$_kTenantCode');
        final pReq = await client.getUrl(profileUri);
        pReq.headers.set('Authorization', 'Bearer $token');
        pReq.headers.set(
          'Cookie',
          '_token=${buildPhpSerializedTokenCookie(token)}; token=$token',
        );
        pReq.headers.set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
        final pResp = await pReq.close().timeout(const Duration(seconds: 8));
        if (pResp.statusCode == 200) {
          final pBody = await pResp.transform(utf8.decoder).join();
          final pJson = jsonDecode(pBody);
          final pCode = pJson is Map ? pJson['code']?.toString() : null;
          if (pJson is Map &&
              (pCode == '1000' ||
                  pCode == '200' ||
                  pCode == '0' ||
                  pJson['success'] == true)) {
            final pData =
                pJson['params'] ?? pJson['data'] ?? pJson['result'];
            final pList = pData is List
                ? pData
                : (pData is Map
                    ? (pData['list'] ?? pData['models'] ?? pData['rows'])
                    : null);
            if (pList is List) {
              for (final item in pList) {
                if (item is Map) {
                  if (isCourseOffShelfMeta(item)) continue;
                  final cid =
                      item['course_id']?.toString() ?? item['id']?.toString();
                  final title = item['course_name']?.toString() ??
                      item['course_title']?.toString() ??
                      item['title']?.toString();
                  final teacher = item['teacher']?.toString() ??
                      item['realname']?.toString();
                  final termName =
                      (item['term_name'] ?? item['semester_name'] ?? '')
                          .toString();
                  if (cid != null &&
                      cid.isNotEmpty &&
                      title != null &&
                      title.isNotEmpty) {
                    final existing = foundCoursesMap.putIfAbsent(
                      cid,
                      () => {
                        'course_id': cid,
                        'course_title': title,
                        if (teacher != null && teacher.isNotEmpty)
                          'teacher': teacher,
                        if (termName.isNotEmpty) 'term_name': termName,
                        'active_months': <String>[],
                      },
                    );
                    if (termName.isNotEmpty &&
                        (existing['term_name']?.toString().isEmpty ?? true)) {
                      existing['term_name'] = termName;
                    }
                    if (teacher != null &&
                        teacher.isNotEmpty &&
                        (existing['teacher']?.toString().isEmpty ?? true)) {
                      existing['teacher'] = teacher;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ZhiyunService] 查询个人课程列表失败: $e');
      }

      final box = _getHiveBox();
      int count = 0;
      final assignedCleaned = <String>{};

      // 排序：当前学期/当月课程高优写入裸 Key，同时按半学期作用域分别缓存，防止秋/冬同名课程相互覆盖
      final sortedCourses = foundCoursesMap.values.toList()
        ..sort((a, b) {
          final aActive =
              (a['active_months'] as List?)?.contains(curMonthStr) == true
                  ? 1
                  : 0;
          final bActive =
              (b['active_months'] as List?)?.contains(curMonthStr) == true
                  ? 1
                  : 0;
          return bActive.compareTo(aActive);
        });

      for (final entry in sortedCourses) {
        final cid = entry['course_id'] as String;
        final title = entry['course_title'] as String;
        final cleaned = cleanCourseName(title);
        final normalized = normalizeCourseName(title);
        final core = extractCoreCourseName(title);
        final coreNormalized = normalizeCourseName(core);

        if (isExplicitlyUnbound(title) ||
            isExplicitlyUnbound(cleaned) ||
            isExplicitlyUnbound(normalized) ||
            (core.isNotEmpty && isExplicitlyUnbound(core)) ||
            (coreNormalized.isNotEmpty &&
                isExplicitlyUnbound(coreNormalized))) {
          continue;
        }

        // 推导该课程所属的学年半学期作用域并持久化，避免春/夏/秋/冬同名课程相互覆盖
        final termStr = entry['term_name']?.toString() ?? '';
        final parsedTerm = _parseYearAndTerm(termStr);
        final months = (entry['active_months'] as List?)
                ?.map((e) => _normalizeYearMonth(e.toString()))
                .toList() ??
            const <String>[];
        final entryHalf = _extractHalfTagFromText('$title $termStr',
                defaultTerm: parsedTerm.term) ??
            _inferHalfFromMonths(
              months,
              defaultTerm: parsedTerm.term,
              termText: termStr,
            );
        int entryYearStart = parsedTerm.yearStart ?? academicStartYear;
        if (parsedTerm.yearStart == null && months.isNotEmpty) {
          final ymParts = months.first.split('-');
          final y = int.tryParse(ymParts.first);
          final m = ymParts.length > 1 ? int.tryParse(ymParts[1]) : null;
          if (y != null && m != null) {
            entryYearStart = m >= 8 ? y : y - 1;
          }
        }
        if (entryHalf != null) {
          final scopedKey = '${cleaned}__${entryYearStart}_$entryHalf';
          _userCourseIds[scopedKey] = cid;
          if (box != null) {
            await box.put('zhiyun_cid_$scopedKey', cid);
          }
        }

        // 高优当季课程优先写入默认裸 Key，已绑定的当季课程不被后续旧课覆盖
        if (assignedCleaned.add(cleaned)) {
          _userCourseIds[cleaned] = cid;
          _userCourseIds[title] = cid;
          _userCourseIds[normalized] = cid;
          if (core.isNotEmpty) _userCourseIds[core] = cid;
          if (coreNormalized.isNotEmpty) _userCourseIds[coreNormalized] = cid;

          if (box != null) {
            await box.put('zhiyun_cid_$cleaned', cid);
            await box.put('zhiyun_cid_$title', cid);
            await box.put('zhiyun_cid_$normalized', cid);
            if (core.isNotEmpty) await box.put('zhiyun_cid_$core', cid);
            if (coreNormalized.isNotEmpty) {
              await box.put('zhiyun_cid_$coreNormalized', cid);
            }
          }
          count++;
        }
      }

      if (box != null) {
        if (foundCoursesMap.isNotEmpty) {
          await box.put(
              'zhiyun_my_courses', jsonEncode(foundCoursesMap.values.toList()));
        }
        if (foundSessions.isNotEmpty) {
          await box.put('zhiyun_my_sessions', jsonEncode(foundSessions));
        }
        await box.put(
            'zhiyun_my_courses_time', DateTime.now().toIso8601String());
      }

      debugPrint('[ZhiyunService] 从“我的课程”成功同步 $count 门专属课程 ID');
      return count;
    } catch (e, stack) {
      debugPrint('[ZhiyunService] 同步“我的课程”发生异常: $e\n$stack');
      return 0;
    } finally {
      client.close(force: true);
    }
  }

  /// 执行智云 CAS 认证握手并提取 Authorization Token
  static Future<String?> _loginZhiyunCas(
      HttpClient httpClient, Cookie ssoCookie) async {
    try {
      final cookieJar = <String, Cookie>{};

      void storeCookie(Cookie c, Uri source) {
        final domain = c.domain ?? source.host;
        cookieJar['${c.name}|$domain'] = c;
      }

      List<Cookie> cookiesFor(Uri uri) {
        final host = uri.host.toLowerCase();
        return cookieJar.values.where((c) {
          final d =
              (c.domain ?? '').toLowerCase().replaceFirst(RegExp(r'^\.'), '');
          return d.isEmpty || host == d || host.endsWith('.$d');
        }).toList();
      }

      final trustedSso = Cookie(ssoCookie.name, ssoCookie.value)
        ..domain = 'zju.edu.cn'
        ..path = '/';
      storeCookie(trustedSso, Uri.parse('https://zjuam.zju.edu.cn/'));

      // 使用带 auType=cmc 的标准智云 CAS 入口
      var current = Uri.parse(
        'https://tgmedia.cmc.zju.edu.cn/index.php?r=auth/login&auType=cmc&tenant_code=112&forward=https%3A%2F%2Fclassroom.zju.edu.cn%2F',
      );

      String? token;

      for (var hop = 0; hop < 12; hop++) {
        final outgoing = cookiesFor(current);
        final req = await httpClient
            .getUrl(current)
            .timeout(const Duration(seconds: 8));
        req.followRedirects = false;
        req.cookies.addAll(outgoing);

        final resp = await req.close().timeout(const Duration(seconds: 8));
        for (final c in resp.cookies) {
          storeCookie(c, current);
          final raw = c.value;
          final decoded = Uri.decodeComponent(raw);

          // 1. PHP 序列化形式：{i:...;s:...:"_token";...s:...:"<token>";}
          final match =
              RegExp(r'\{i:\d+;s:\d+:"_token";i:\d+;s:\d+:"([^"]+)";\}')
                  .firstMatch(decoded);
          if (match != null) {
            token = match.group(1);
          }

          // 2. 直接以 _token 或 token 命名的 Cookie
          if (token == null && (c.name == '_token' || c.name == 'token')) {
            if (decoded.contains('_token')) {
              final m = RegExp(r'"([^"]{20,})"').firstMatch(decoded);
              token = m?.group(1) ?? c.value;
            } else {
              token = c.value;
            }
          }
        }

        if (current.queryParameters.containsKey('token')) {
          token = current.queryParameters['token'];
        }
        if (current.queryParameters.containsKey('_token')) {
          token = current.queryParameters['_token'];
        }

        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (resp.isRedirect && loc != null && loc.isNotEmpty) {
          current = current.resolve(loc);
          if (current.queryParameters.containsKey('token')) {
            token = current.queryParameters['token'];
          }
          if (current.queryParameters.containsKey('_token')) {
            token = current.queryParameters['_token'];
          }
        } else {
          break;
        }
      }

      // 若已抓取到 Token，向 infosimple 发起校验并拉取真实账号信息
      if (token != null && token.isNotEmpty) {
        try {
          final infoUri = Uri.parse('$_kZhiyunBaseUrl/userapi/v1/infosimple');
          final infoReq = await httpClient.getUrl(infoUri);
          infoReq.headers.set('Authorization', 'Bearer $token');
          infoReq.headers.set('Cookie', '_token=$token; token=$token');
          infoReq.headers.set('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
          final infoResp =
              await infoReq.close().timeout(const Duration(seconds: 5));
          if (infoResp.statusCode == 200) {
            final infoBody = await infoResp.transform(utf8.decoder).join();
            final infoJson = jsonDecode(infoBody);
            if (infoJson is Map && infoJson['params'] is Map) {
              final params = infoJson['params'];
              _cachedZhiyunAccount = params['account']?.toString();
              _cachedZhiyunUserId = params['id']?.toString();
              final box = _getHiveBox();
              if (_cachedZhiyunAccount != null) {
                box?.put('zhiyun_account', _cachedZhiyunAccount!);
              }
              if (_cachedZhiyunUserId != null) {
                box?.put('zhiyun_user_id', _cachedZhiyunUserId!);
              }
            }
          }
        } catch (e) {
          debugPrint('[ZhiyunService] 验证智云 Token 异常: $e');
        }

        _cachedZhiyunToken = token;
        final box = _getHiveBox();
        box?.put('zhiyun_token', token);
      }
      return token;
    } catch (e) {
      debugPrint('[ZhiyunService] CAS 认证握手异常: $e');
      return null;
    }
  }

  /// 调起外部浏览器打开指定直达链接
  static Future<bool> openUrl(String url) async {
    try {
      return await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('打开智云课堂链接失败: $e');
      return false;
    }
  }

  /// 调起外部浏览器打开指定课程的智云课堂页面
  static Future<bool> openCourse(String courseName) async {
    final cleaned = cleanCourseName(courseName);
    final courseId = getKnownCourseId(cleaned);
    final url = courseId != null
        ? buildCourseLivingroomUrl(courseId)
        : buildSearchContentUrl(courseName);
    return await openUrl(url);
  }

  /// 复制课程直达链接到剪贴板
  static Future<void> copyCourseLink(
      BuildContext context, String courseName) async {
    final cleaned = cleanCourseName(courseName);
    final courseId = getKnownCourseId(cleaned);
    final url = courseId != null
        ? buildCourseLivingroomUrl(courseId)
        : buildSearchContentUrl(courseName);
    await Clipboard.setData(ClipboardData(text: url));
  }

  static String? _normalizeStreamUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var url = rawUrl.trim();
    if (url.isEmpty) return null;
    if (url.startsWith('//')) url = 'https:$url';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return null;
    }
    return url;
  }

  static int _streamPriority(ZhiyunStreamOption option) {
    final u = option.url.toLowerCase();
    var score = 0;
    if (u.startsWith('https://')) score += 100;
    if (u.contains('.m3u8')) {
      score += 50;
    } else if (u.contains('.mp4')) {
      score += 40;
    } else if (u.contains('.flv')) {
      score += 10;
    }
    return score;
  }

  /// 获取智云课堂单节课的直播/回放流媒体地址（MP4 / HLS m3u8）
  ///
  /// 参考开源项目：
  /// - Anchorite-no/zju-skill-public (`courseapi/v3/portal-home-setting/get-sub-info`)
  /// - PeiPei233/zju-learning-assistant (`courseapi/index.php/v2/meta/getscreenstream`)
  /// - Lucent-Snow/zju-scholar
  static Future<List<ZhiyunStreamOption>> fetchLessonStreams({
    required String courseId,
    required String subId,
    bool preferLive = false,
  }) async {
    final client = createHttpClient();
    final replayStreams = <ZhiyunStreamOption>[];
    final liveStreams = <ZhiyunStreamOption>[];
    final seenUrls = <String>{};

    void addStream(String label, String? rawUrl, {bool isLive = false}) {
      final normalized = _normalizeStreamUrl(rawUrl);
      if (normalized == null) return;
      final signedUrl = signPlayUrl(normalized, isLive: isLive);
      if (seenUrls.add(signedUrl)) {
        final option = ZhiyunStreamOption(
          label: label,
          url: signedUrl,
          isLive: isLive,
        );
        if (isLive) {
          liveStreams.add(option);
        } else {
          replayStreams.add(option);
        }
      }
      // 若直播流返回的是 HTTP-FLV (.flv)，同时派生同路径 .m3u8 HLS 候选，提升移动端原生播放器兼容性
      if (isLive &&
          RegExp(r'\.flv(\?|$)', caseSensitive: false).hasMatch(normalized)) {
        final hlsCandidate = normalized.replaceFirst(
          RegExp(r'\.flv(\?|$)', caseSensitive: false),
          r'.m3u8$1',
        );
        final signedHls = signPlayUrl(hlsCandidate, isLive: true);
        if (seenUrls.add(signedHls)) {
          final hlsLabel = label.contains('(FLV)')
              ? label.replaceAll('(FLV)', '(HLS)')
              : '$label (HLS)';
          liveStreams.add(
            ZhiyunStreamOption(
              label: hlsLabel,
              url: signedHls,
              isLive: true,
            ),
          );
        }
      }
    }

    dynamic decodeMultiRateOrJson(String raw) {
      var trimmed = raw.trim();
      final prefixMatch = RegExp(
        r'^mu(?:tl|lt)i-rate:\s*',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (prefixMatch != null) {
        trimmed = trimmed.substring(prefixMatch.end).trim();
      }
      if ((trimmed.startsWith('[') && trimmed.endsWith(']')) ||
          (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
        try {
          return jsonDecode(trimmed);
        } catch (_) {}
      }
      return null;
    }

    void extractDynamicUrls(
      String label,
      dynamic node, {
      required bool isLive,
      int depth = 0,
    }) {
      if (node == null || depth > 5) return;
      if (node is String) {
        final decoded = decodeMultiRateOrJson(node);
        if (decoded != null) {
          extractDynamicUrls(label, decoded, isLive: isLive, depth: depth + 1);
          return;
        }
        addStream(label, node, isLive: isLive);
        return;
      }
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          final item = node[i];
          if (item is Map) {
            final itemTitle = item['title']?.toString() ??
                item['name']?.toString() ??
                item['rate']?.toString() ??
                (node.length > 1 ? '$label ${i + 1}' : label);
            final direct = item['m3u8']?.toString() ??
                item['hls_url']?.toString() ??
                item['hls']?.toString() ??
                item['url']?.toString() ??
                item['play_url']?.toString() ??
                item['video_url']?.toString() ??
                item['preview_url']?.toString() ??
                item['file_url']?.toString() ??
                item['flv']?.toString() ??
                item['file_name']?.toString();
            if (direct != null && direct.trim().isNotEmpty) {
              extractDynamicUrls(
                itemTitle,
                direct,
                isLive: isLive,
                depth: depth + 1,
              );
            } else {
              extractDynamicUrls(
                itemTitle,
                item,
                isLive: isLive,
                depth: depth + 1,
              );
            }
          } else {
            extractDynamicUrls(
              node.length > 1 ? '$label ${i + 1}' : label,
              item,
              isLive: isLive,
              depth: depth + 1,
            );
          }
        }
        return;
      }
      if (node is Map) {
        for (final key in [
          'm3u8',
          'hls_url',
          'hls',
          'stream_m3u8',
          'stream_url',
          'pull_url',
          'url',
          'play_url',
          'video_url',
          'preview_url',
          'file_url',
          'path',
          'mp4',
          'flv',
          'stream_flv',
          'play_addres_arr',
          'contents',
        ]) {
          if (!node.containsKey(key)) continue;
          final v = node[key];
          if (v == null) continue;
          var subLabel = label;
          if (key.contains('flv') && !subLabel.contains('FLV')) {
            subLabel = '$subLabel (FLV)';
          } else if ((key.contains('m3u8') || key.contains('hls')) &&
              !subLabel.contains('HLS')) {
            subLabel = '$subLabel (HLS)';
          }
          extractDynamicUrls(
            subLabel,
            v,
            isLive: isLive,
            depth: depth + 1,
          );
        }
      }
    }

    void extractLiveNode(String label, dynamic node) {
      if (node == null) return;
      if (node is Map) {
        if (node.containsKey('output')) {
          extractDynamicUrls('$label (教师画面)', node['output'], isLive: true);
        }
        if (node.containsKey('output_student')) {
          extractDynamicUrls(
              '$label (学生画面)', node['output_student'], isLive: true);
        }
        if (node.containsKey('output_ppt')) {
          extractDynamicUrls('$label (课件投屏)', node['output_ppt'], isLive: true);
        }
        if (node.containsKey('teacher')) {
          extractDynamicUrls('$label (教师视角)', node['teacher'], isLive: true);
        }
        if (node.containsKey('student')) {
          extractDynamicUrls('$label (学生视角)', node['student'], isLive: true);
        }
        if (node.containsKey('ppt')) {
          extractDynamicUrls('$label (课件画面)', node['ppt'], isLive: true);
        }
      }
      extractDynamicUrls(label, node, isLive: true);
    }

    void extractFromMap(Map? container, {String prefix = ''}) {
      if (container == null) return;

      extractDynamicUrls(
        '${prefix}课堂回放',
        container['playurl'],
        isLive: false,
      );
      extractDynamicUrls(
        '${prefix}回放视频',
        container['play_url'],
        isLive: false,
      );
      extractDynamicUrls(
        '${prefix}视频流',
        container['video_url'],
        isLive: false,
      );
      extractDynamicUrls(
        '${prefix}视频列表',
        container['video_list'],
        isLive: false,
      );
      extractDynamicUrls(
        '${prefix}点播列表',
        container['vod_list'],
        isLive: false,
      );

      final savePlayback = container['save_playback'];
      if (savePlayback is Map) {
        final isMpc = savePlayback['is_mpc']?.toString() == '1';
        if (isMpc && savePlayback['mpc'] != null) {
          extractDynamicUrls(
            '${prefix}多视角回放',
            savePlayback['mpc'],
            isLive: false,
          );
        }
        if (savePlayback['pgc'] != null) {
          extractDynamicUrls(
            '${prefix}导播回放',
            savePlayback['pgc'],
            isLive: false,
          );
        }
        extractDynamicUrls(
          '${prefix}标准回放',
          savePlayback['play_addres_arr'] ?? savePlayback['contents'],
          isLive: false,
        );
      } else if (savePlayback != null) {
        extractDynamicUrls('${prefix}标准回放', savePlayback, isLive: false);
      }

      final relationData = container['relation_data'];
      if (relationData is Map) {
        extractDynamicUrls(
          '${prefix}关联回放',
          relationData['path'] ?? relationData['url'],
          isLive: false,
        );
      }

      final playback = container['playback'];
      if (playback != null) {
        extractDynamicUrls('${prefix}课堂回放主视角', playback, isLive: false);
      }

      final fileList = container['file_list'];
      if (fileList != null) {
        extractDynamicUrls('${prefix}回放视角', fileList, isLive: false);
      }
    }

    try {
      var token = await ensureValidToken();

      Future<HttpClientResponse> getWithHeaders(Uri uri, String? tk) async {
        final req = await client.getUrl(uri);
        if (tk != null && tk.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $tk');
          req.headers.set(
            'Cookie',
            '_token=${buildPhpSerializedTokenCookie(tk)}; token=$tk',
          );
        }
        req.headers.set('Origin', 'https://classroom.zju.edu.cn');
        req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
        req.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        );
        return req.close().timeout(const Duration(seconds: 7));
      }

      var resolvedSubId = subId.trim();
      if (resolvedSubId.isEmpty || preferLive) {
        final todayActive = await fetchActiveSubIdForDate(
          courseId,
          DateTime.now(),
        );
        if (resolvedSubId.isEmpty &&
            todayActive != null &&
            todayActive.isNotEmpty) {
          resolvedSubId = todayActive;
        }
      }

      bool subIsLive = false;
      bool subIsEndedOrReplay = false;

      void inspectSubItemMap(Map<String, dynamic> data, {String prefix = ''}) {
        if (checkIsLive(item: data)) {
          subIsLive = true;
        }
        final statusStr =
            (data['sub_status'] ?? data['status'])?.toString() ?? '';
        final statusLabel = data['status_label']?.toString() ?? '';
        if (statusStr == '3' ||
            statusStr == '4' ||
            statusStr == '6' ||
            statusLabel.contains('回放') ||
            statusLabel.contains('已结束')) {
          subIsEndedOrReplay = true;
        }

        extractFromMap(data, prefix: prefix);

        for (final contentField in ['content', 'sub_content', 'room_data']) {
          final rawContent = data[contentField];
          Map? contentMap;
          if (rawContent is String && rawContent.trim().startsWith('{')) {
            try {
              contentMap = jsonDecode(rawContent) as Map?;
            } catch (_) {}
          } else if (rawContent is Map) {
            contentMap = rawContent;
          }
          if (contentMap != null) {
            extractFromMap(contentMap, prefix: prefix);
            extractLiveNode('${prefix}直播流', contentMap['live_url']);
          }
        }

        extractLiveNode('${prefix}实时直播', data['live_url']);
        extractLiveNode('${prefix}直播流', data['stream_url']);
        extractLiveNode('${prefix}HLS 直播流', data['hls_url']);
      }

      // 1. 查询 v3/v2 get-sub-info 与 search-live-course-list（与智云 Web 端 livingroom 完全一致）
      if (resolvedSubId.isNotEmpty) {
        final subInfoUris = [
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/v3/portal-home-setting/get-sub-info?course_id=$courseId&sub_id=$resolvedSubId',
          ),
          Uri.parse(
            'https://yjapi.cmc.zju.edu.cn/courseapi/v3/portal-home-setting/get-sub-info?course_id=$courseId&sub_id=$resolvedSubId',
          ),
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/v2/course-live/search-live-course-list?all=1&course_id=$courseId&sub_id=$resolvedSubId&with_sub_data=1&with_room_data=1&show_all=1&show_delete=2',
          ),
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/v2/course-live/get-sub-info?course_id=$courseId&sub_id=$resolvedSubId',
          ),
        ];

        for (final subInfoUri in subInfoUris) {
          try {
            var resp = await getWithHeaders(subInfoUri, token);
            if (resp.statusCode == 401 || resp.statusCode == 403) {
              token = await ensureValidToken(forceRefresh: true);
              resp = await getWithHeaders(subInfoUri, token);
            }
            if (resp.statusCode != 200) continue;
            final body = await resp.transform(utf8.decoder).join();
            final decoded = jsonDecode(body);
            if (decoded is! Map) continue;

            final rawData = decoded['data'] ?? decoded['result'];
            if (rawData is Map) {
              if (rawData['data'] is Map) {
                inspectSubItemMap(
                  _normalizeCatalogueItem(rawData['data'] as Map),
                );
              } else {
                inspectSubItemMap(_normalizeCatalogueItem(rawData));
              }
            }
            for (final item in _extractSubItemsFromResponse(decoded)) {
              final sid =
                  item['sub_id']?.toString() ?? item['id']?.toString() ?? '';
              if (sid.isEmpty || sid == resolvedSubId) {
                inspectSubItemMap(item);
              }
            }

            if (preferLive || subIsLive) {
              if (liveStreams.isNotEmpty) break;
            } else if (replayStreams.isNotEmpty) {
              break;
            }
          } catch (_) {}
        }
      }

      // 2. 从课程目录缓存与 v3/v2 catalogue 补充提取该 sub_id 的视频直链
      final catList = await fetchCourseCatalogue(courseId);
      for (final item in catList) {
        final itemSubId =
            item['sub_id']?.toString() ?? item['id']?.toString() ?? '';
        if (resolvedSubId.isNotEmpty && itemSubId != resolvedSubId) continue;
        inspectSubItemMap(item, prefix: '目录');
      }

      // 3. 直播流接口 getscreenstream（在直播模式、正在直播，或尚无可用流时拉取，支持双域名与新旧路由）
      if (resolvedSubId.isNotEmpty &&
          (preferLive ||
              subIsLive ||
              (replayStreams.isEmpty && !subIsEndedOrReplay))) {
        final screenUris = [
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/index.php/v2/meta/getscreenstream?sub_id=$resolvedSubId',
          ),
          Uri.parse(
            'https://yjapi.cmc.zju.edu.cn/courseapi/index.php/v2/meta/getscreenstream?sub_id=$resolvedSubId',
          ),
          Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/v2/Room/getscreenstream?sub_id=$resolvedSubId',
          ),
          Uri.parse(
            'https://yjapi.cmc.zju.edu.cn/courseapi/v2/Room/getscreenstream?sub_id=$resolvedSubId',
          ),
        ];
        for (final screenUri in screenUris) {
          try {
            var screenResp = await getWithHeaders(screenUri, token);
            if (screenResp.statusCode == 401 || screenResp.statusCode == 403) {
              token = await ensureValidToken(forceRefresh: true);
              screenResp = await getWithHeaders(screenUri, token);
            }
            if (screenResp.statusCode != 200) continue;
            final screenBody = await screenResp.transform(utf8.decoder).join();
            final screenJson = jsonDecode(screenBody);
            if (screenJson is Map) {
              final dynamic dataList = (screenJson['result'] is Map
                      ? screenJson['result']['data']
                      : null) ??
                  (screenJson['data'] is Map
                      ? screenJson['data']['data'] ?? screenJson['data']['list']
                      : screenJson['data']) ??
                  screenJson['list'];
              if (dataList is List) {
                for (final item in dataList) {
                  if (item is Map) {
                    final type = item['type']?.toString() ?? '';
                    final label = type == '2'
                        ? '课件投屏直播'
                        : type == '3'
                            ? '教师摄像直播'
                            : '课堂实时直播';
                    extractLiveNode(label, item);
                  }
                }
              } else if (dataList is Map) {
                extractLiveNode('课堂实时直播', dataList);
              }
            }
            if (liveStreams.isNotEmpty) break;
          } catch (_) {}
        }
      }

      liveStreams
          .sort((a, b) => _streamPriority(b).compareTo(_streamPriority(a)));
      replayStreams
          .sort((a, b) => _streamPriority(b).compareTo(_streamPriority(a)));

      // 直播模式/正在直播时优先直播流；回放模式优先回放流
      if (preferLive || subIsLive) {
        return [...liveStreams, ...replayStreams];
      }
      if (replayStreams.isNotEmpty) {
        // 如果已明确生成回放或课已结束，不再把失效的直播 URL 放在可选列表里干扰播放
        return replayStreams;
      }
      return liveStreams;
    } catch (e) {
      debugPrint('[ZhiyunService] fetchLessonStreams error: $e');
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// 获取智云课堂单节课的 PPT 幻灯片截图列表（按时间轴排序）
  static Future<List<ZhiyunPptSlide>> fetchLessonPptSlides({
    required String courseId,
    required String subId,
  }) async {
    final client = createHttpClient();
    final slides = <ZhiyunPptSlide>[];
    final seenUrls = <String>{};

    try {
      final token = getCachedZhiyunToken();
      final uri = Uri.parse(
        '$_kZhiyunBaseUrl/pptnote/v1/schedule/search-ppt?course_id=$courseId&sub_id=$subId&page=1&per_page=100',
      );
      final req = await client.getUrl(uri);
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Cookie', '_token=$token; token=$token');
      }
      req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final list = decoded['list'] ??
              (decoded['data'] is Map ? decoded['data']['list'] : null);
          if (list is List) {
            for (final item in list) {
              if (item is! Map) continue;
              final sec =
                  int.tryParse(item['created_sec']?.toString() ?? '0') ?? 0;
              var imgUrl = item['pptimgurl']?.toString() ?? '';
              final contentRaw = item['content'];
              if (imgUrl.isEmpty && contentRaw is String) {
                try {
                  final cMap = jsonDecode(contentRaw);
                  if (cMap is Map) {
                    imgUrl = cMap['pptimgurl']?.toString() ?? '';
                  }
                } catch (_) {}
              } else if (imgUrl.isEmpty && contentRaw is Map) {
                imgUrl = contentRaw['pptimgurl']?.toString() ?? '';
              }
              if (imgUrl.isNotEmpty && seenUrls.add(imgUrl)) {
                slides.add(ZhiyunPptSlide(
                  imageUrl: imgUrl,
                  createdSec: sec,
                ));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] fetchLessonPptSlides error: $e');
    } finally {
      client.close(force: true);
    }

    return slides;
  }

  /// 获取智云课堂单节课的语音转写字幕列表
  static Future<List<ZhiyunTranscriptSegment>> fetchLessonTranscript({
    required String subId,
  }) async {
    final client = createHttpClient();
    final segments = <ZhiyunTranscriptSegment>[];

    try {
      final token = getCachedZhiyunToken();
      final uri = Uri.parse(
        'https://yjapi.cmc.zju.edu.cn/courseapi/v3/web-socket/search-trans-result?sub_id=$subId&format=json',
      );
      final req = await client.getUrl(uri);
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Cookie', '_token=$token; token=$token');
      }
      req.headers.set('Origin', 'https://classroom.zju.edu.cn');
      req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final list = decoded['list'];
          if (list is List && list.isNotEmpty) {
            final first = list.first;
            if (first is Map && first['all_content'] is List) {
              for (final seg in first['all_content'] as List) {
                if (seg is! Map) continue;
                final text = seg['Text']?.toString().trim() ?? '';
                if (text.isEmpty) continue;
                final begin =
                    int.tryParse(seg['BeginSec']?.toString() ?? '0') ?? 0;
                final end = int.tryParse(seg['EndSec']?.toString() ?? '0') ?? 0;
                segments.add(ZhiyunTranscriptSegment(
                  beginSec: begin,
                  endSec: end,
                  text: text,
                ));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] fetchLessonTranscript error: $e');
    } finally {
      client.close(force: true);
    }

    return segments;
  }

  /// 从智云课堂目录接口提取教师上传的共享课件直链列表
  static Future<List<Map<String, String>>> fetchZhiyunCourseware(
      String courseId) async {
    final client = createHttpClient();
    final files = <Map<String, String>>[];
    final seenUrls = <String>{};

    try {
      final token = getCachedZhiyunToken();
      final uri = Uri.parse(
        'https://yjapi.cmc.zju.edu.cn/courseapi/v2/course/catalogue?course_id=$courseId',
      );
      final req = await client.getUrl(uri);
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Cookie', '_token=$token; token=$token');
      }
      req.headers.set('Origin', 'https://classroom.zju.edu.cn');
      req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['result'] is Map) {
          final dataList = decoded['result']['data'];
          if (dataList is List) {
            for (final item in dataList) {
              if (item is! Map) continue;
              final lessonTitle = item['title']?.toString() ?? '智云课件';
              final rawContent = item['content'];
              Map? contentMap;
              if (rawContent is String && rawContent.trim().startsWith('{')) {
                try {
                  contentMap = jsonDecode(rawContent) as Map?;
                } catch (_) {}
              } else if (rawContent is Map) {
                contentMap = rawContent;
              }
              final downloadMap = contentMap?['download'];
              if (downloadMap is Map) {
                downloadMap.forEach((_, val) {
                  if (val is Map) {
                    final name = val['file_name']?.toString() ?? '';
                    final url = val['url']?.toString() ?? '';
                    if (name.isNotEmpty &&
                        url.startsWith('http') &&
                        seenUrls.add(url)) {
                      files.add({
                        'name': name,
                        'url': url,
                        'sectionTitle': lessonTitle,
                      });
                    }
                  }
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] fetchZhiyunCourseware error: $e');
    } finally {
      client.close(force: true);
    }

    return files;
  }
}

class ZhiyunStreamOption {
  final String label;
  final String url;
  final bool isLive;

  const ZhiyunStreamOption({
    required this.label,
    required this.url,
    this.isLive = false,
  });
}

class ZhiyunPptSlide {
  final String imageUrl;
  final int createdSec;

  const ZhiyunPptSlide({
    required this.imageUrl,
    required this.createdSec,
  });

  String get timeLabel {
    final m = (createdSec ~/ 60).toString().padLeft(2, '0');
    final s = (createdSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class ZhiyunTranscriptSegment {
  final int beginSec;
  final int endSec;
  final String text;

  const ZhiyunTranscriptSegment({
    required this.beginSec,
    required this.endSec,
    required this.text,
  });

  String get timeLabel {
    final m = (beginSec ~/ 60).toString().padLeft(2, '0');
    final s = (beginSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
