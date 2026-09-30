import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';

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

  /// 智云认证 Token 与用户信息内存缓存
  static String? _cachedZhiyunToken;
  static String? _cachedZhiyunAccount;
  static String? _cachedZhiyunUserId;
  static Future<int>? _syncFuture;

  /// 创建专用于浙大智云课堂的 HttpClient
  /// 自动直连绕过代理（Clash/VPN），防止内网接口在 SSL 握手时被重置
  static HttpClient createHttpClient({Duration timeout = const Duration(seconds: 8)}) {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) => true;

    client.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      // 对所有浙大校内及智云域名强制直连（DIRECT），避免系统代理拦截或中断校园网 SSL 握手
      if (host.contains('zju.edu.cn') ||
          host.contains('cmc.zju.edu.cn') ||
          host.contains('classroom.zju.edu.cn')) {
        return 'DIRECT';
      }
      return HttpClient.findProxyFromEnvironment(uri);
    };
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

  /// 提取纯净课程名称（去除（甲）、（乙）、教学班序号等，提高智云课堂检索命中率）
  static String cleanCourseName(String courseName) {
    var cleaned = courseName.trim();
    // 替换中文全角括号为半角便于统一处理
    cleaned = cleaned.replaceAll('（', '(').replaceAll('）', ')');
    // 去除末尾诸如 (01), (02) 的班级编号
    cleaned = cleaned.replaceAll(RegExp(r'\(\d+\)$'), '');
    return cleaned.trim();
  }

  /// 对课程名进行多维度归一化处理（用于智能模糊匹配教务网课程与智云“我的课程”）
  static String normalizeCourseName(String name) {
    var s = name.trim().toLowerCase();
    // 替换中文全角括号为半角
    s = s.replaceAll('（', '(').replaceAll('）', ')');
    // 去除末尾诸如 (01), (02), (1) 的教学班编号
    s = s.replaceAll(RegExp(r'\(\d+\)$'), '');
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
    final s1 = normalizeCourseName(scheduleName);
    final s2 = normalizeCourseName(zhiyunName);

    // 1. 归一化完全一致
    if (s1 == s2) return true;

    // 2. Python 课程识别（如 面向对象程序设计(Python)、程序设计基础(Python)、Python程序设计）
    if (s1.contains('python') && s2.contains('python')) {
      return true;
    }

    // 3. 大学英语 / 英语课程（分级匹配 1/2/3/4 或通用大学英语/学术英语等）
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
    }

    // 4. 线性代数与微积分等基础课包含关系
    if (s1.length >= 3 && s2.contains(s1)) return true;
    if (s2.length >= 3 && s1.contains(s2)) return true;

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

  /// 判断该课程是否属于非录播课程（例如身体素质课、体育课、实践课等显然不可能有智云回放的课程）
  static bool isRecordableCourse(String courseName) {
    final name = cleanCourseName(courseName);
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
      '军事理论',
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
  static bool isExplicitlyUnbound(String courseName) {
    final box = _getHiveBox();
    if (box == null) return false;
    final cleaned = cleanCourseName(courseName);
    return box.get('zhiyun_unbind_$cleaned') == true ||
        box.get('zhiyun_unbind_$courseName') == true;
  }

  /// 查询指定课程的智云 course_id
  /// 优先级：1. 内存运行时缓存 > 2. 用户持久化手动绑定 > 3. 动态同步的“我的课程”
  /// 坚决不使用任何死板硬编码，完全按用户实际账号数据匹配
  static String? getKnownCourseId(
    String courseName, {
    String? courseCode,
    String? teacher,
  }) {
    final cleaned = cleanCourseName(courseName);

    // 0. 特殊历史脏数据清洗：如果是思想文化素养/素质类课程，清除错误绑定的 86975
    if (cleaned.contains('思想文化素养') || cleaned.contains('思想素质')) {
      final box = _getHiveBox();
      final savedCid = box?.get('zhiyun_cid_$cleaned')?.toString() ??
          box?.get('zhiyun_cid_$courseName')?.toString();
      if (savedCid == '86975') {
        box?.delete('zhiyun_cid_$cleaned');
        box?.delete('zhiyun_cid_$courseName');
        box?.put('zhiyun_unbind_$cleaned', true);
        _userCourseIds.remove(cleaned);
        _userCourseIds.remove(courseName);
        return null;
      }
    }

    // 1. 若用户主动解绑过该课程，且未显式重新绑定，坚决返回 null
    if (isExplicitlyUnbound(courseName)) {
      return null;
    }

    // 2. 检查内存缓存 (已成功解析或用户手动绑定)
    if (_userCourseIds.containsKey(cleaned)) {
      return _userCourseIds[cleaned];
    }
    if (_userCourseIds.containsKey(courseName)) {
      return _userCourseIds[courseName];
    }
    if (courseCode != null && _userCourseIds.containsKey(courseCode)) {
      return _userCourseIds[courseCode];
    }

    // 3. 检查持久化存储 (Hive 用户显式保存的 ID 或上次同步的 ID)
    final box = _getHiveBox();
    if (box != null) {
      final savedCid = box.get('zhiyun_cid_$cleaned') ??
          box.get('zhiyun_cid_$courseName') ??
          (courseCode != null ? box.get('zhiyun_cid_$courseCode') : null);
      if (savedCid != null && savedCid.toString().isNotEmpty) {
        final cidStr = savedCid.toString();
        _userCourseIds[cleaned] = cidStr;
        return cidStr;
      }
    }

    // 4. 核心：从用户专属“我的课程”列表中动态智能匹配（千人千面，不死板硬编码）
    final myCourses = getMySyncedCourses();
    if (myCourses.isNotEmpty) {
      // 优先：课程名匹配且教师匹配（精准匹配特定教师的教学班，区分如陈锦辉与谈之奕）
      if (teacher != null && teacher.trim().isNotEmpty) {
        final tTrimmed = teacher.trim();
        for (final item in myCourses) {
          final tTitle = item['course_title']?.toString() ?? '';
          final tTeacher = item['teacher']?.toString() ?? '';
          final tCid = item['course_id']?.toString() ?? '';
          if (tCid.isNotEmpty &&
              matchesCourseName(courseName, tTitle) &&
              (tTeacher.contains(tTrimmed) || tTrimmed.contains(tTeacher))) {
            _userCourseIds[cleaned] = tCid;
            _userCourseIds[courseName] = tCid;
            return tCid;
          }
        }
      }

      // 次优：课程名智能模糊匹配（如 Python程序设计、大学英语等）
      for (final item in myCourses) {
        final tTitle = item['course_title']?.toString() ?? '';
        final tCid = item['course_id']?.toString() ?? '';
        if (tCid.isNotEmpty && matchesCourseName(courseName, tTitle)) {
          _userCourseIds[cleaned] = tCid;
          _userCourseIds[courseName] = tCid;
          return tCid;
        }
      }
    }

    return null;
  }

  /// 通过智云课堂检索接口在线精准搜索匹配课程 ID（针对未在月排课表中出现的半学期/考查课程等）
  static Future<String?> searchCourseOnline({
    required String courseName,
    String? teacher,
    HttpClient? httpClient,
  }) async {
    // 若已被显式解绑，跳过在线检索
    if (isExplicitlyUnbound(courseName)) return null;

    final token = getCachedZhiyunToken();
    if (token == null || token.isEmpty) return null;

    final client = httpClient ?? createHttpClient();
    try {
      final account = _getCachedAccount();
      final userId = _getCachedUserId();
      final cleaned = cleanCourseName(courseName);

      final uri = Uri.parse(
        '$_kZhiyunBaseUrl/pptnote/v1/searchlist?tenant_id=$_kTenantCode'
        '&user_id=${userId ?? ''}'
        '&user_name=${account ?? ''}'
        '&page=1&per_page=16'
        '&title=${Uri.encodeComponent(cleaned)}'
        '${teacher != null && teacher.trim().isNotEmpty ? '&realname=${Uri.encodeComponent(teacher.trim())}' : ''}'
        '&trans=&tenant_code=$_kTenantCode'
        '&randomKey=${DateTime.now().millisecondsSinceEpoch}',
      );

      final req = await client.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Cookie', '_token=$token; token=$token');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json is Map && (json['code'] == 0 || json['code'] == '0')) {
          final total = json['total'];
          final list = total is Map ? total['list'] : null;
          if (list is List && list.isNotEmpty) {
            // 优先：课程名称严格/规范匹配，且教师一致
            for (final item in list) {
              if (item is Map) {
                final cid =
                    item['course_id']?.toString() ?? item['id']?.toString();
                final title = item['title']?.toString() ?? '';
                final itemTeacher = item['realname']?.toString() ?? '';

                if (cid != null && cid.isNotEmpty) {
                  if (matchesCourseName(courseName, title)) {
                    if (teacher != null &&
                        teacher.trim().isNotEmpty &&
                        itemTeacher.isNotEmpty &&
                        (itemTeacher.contains(teacher.trim()) ||
                            teacher.trim().contains(itemTeacher))) {
                      _userCourseIds[cleaned] = cid;
                      _userCourseIds[courseName] = cid;
                      _getHiveBox()?.put('zhiyun_cid_$cleaned', cid);
                      return cid;
                    }
                  }
                }
              }
            }

            // 次优：课程名称智能匹配（不盲目依赖第一项，杜绝误绑无关课程）
            for (final item in list) {
              if (item is Map) {
                final cid =
                    item['course_id']?.toString() ?? item['id']?.toString();
                final title = item['title']?.toString() ?? '';

                if (cid != null &&
                    cid.isNotEmpty &&
                    matchesCourseName(courseName, title)) {
                  _userCourseIds[cleaned] = cid;
                  _userCourseIds[courseName] = cid;
                  _getHiveBox()?.put('zhiyun_cid_$cleaned', cid);
                  return cid;
                }
              }
            }
          }
        }
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

  /// 获取指定课程的课节回放目录（优先内存缓存）
  static Future<List<Map<String, dynamic>>> fetchCourseCatalogue(
      String courseId) async {
    final cached = _catalogueCache[courseId];
    final cacheTime = _catalogueCacheTime[courseId];
    if (cached != null &&
        cacheTime != null &&
        DateTime.now().difference(cacheTime) < const Duration(hours: 1)) {
      return cached;
    }

    final client = createHttpClient();
    try {
      final token = getCachedZhiyunToken();
      final account = _getCachedAccount();

      // 1. 优先尝试 get-course-detail 接口 (包含完整的课节结构 sub_list)
      final detailUri = Uri.parse(
        '$_kZhiyunBaseUrl/courseapi/v3/multi-search/get-course-detail?course_id=$courseId${account != null ? '&student=$account' : ''}',
      );
      final req = await client.getUrl(detailUri);
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Cookie', '_token=$token; token=$token');
      }
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json is Map &&
            (json['code'] == 0 ||
                json['code'] == '0' ||
                json['success'] == true)) {
          final data = json['data'] ?? json['result'];
          final subListMap = data is Map ? data['sub_list'] : null;
          final list = <Map<String, dynamic>>[];

          if (subListMap is Map) {
            _extractSubList(subListMap, list);
          } else if (data is Map && data['list'] is List) {
            for (final item in data['list']) {
              if (item is Map) list.add(Map<String, dynamic>.from(item));
            }
          }

          if (list.isNotEmpty) {
            _catalogueCache[courseId] = list;
            _catalogueCacheTime[courseId] = DateTime.now();
            _registerSubIdsFromList(courseId, list);
            return list;
          }
        }
      }

      // 2. 备用尝试 /courseapi/v2/course/catalogue
      final catUri = Uri.parse(
          '$_kZhiyunBaseUrl/courseapi/v2/course/catalogue?course_id=$courseId');
      final req2 = await client.getUrl(catUri);
      req2.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      if (token != null && token.isNotEmpty) {
        req2.headers.set('Authorization', 'Bearer $token');
        req2.headers.set('Cookie', '_token=$token; token=$token');
      }
      final resp2 = await req2.close().timeout(const Duration(seconds: 5));
      if (resp2.statusCode == 200) {
        final body2 = await resp2.transform(utf8.decoder).join();
        final json2 = jsonDecode(body2);
        if (json2 is Map) {
          final rawData =
              json2['result']?['data'] ?? json2['data'] ?? json2['list'];
          if (rawData is List) {
            final list = <Map<String, dynamic>>[];
            for (final item in rawData) {
              if (item is Map) list.add(Map<String, dynamic>.from(item));
            }
            if (list.isNotEmpty) {
              _catalogueCache[courseId] = list;
              _catalogueCacheTime[courseId] = DateTime.now();
              _registerSubIdsFromList(courseId, list);
              return list;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ZhiyunService] 获取课程目录失败 (courseId=$courseId): $e');
    } finally {
      client.close(force: true);
    }

    return cached ?? const [];
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
                    target.add(Map<String, dynamic>.from(sub));
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// 从课节列表中解析并自动记录日期到 sub_id 的映射
  static void _registerSubIdsFromList(
      String courseId, List<Map<String, dynamic>> list) {
    for (final item in list) {
      final subId = item['sub_id']?.toString() ?? item['id']?.toString();
      final startAt = int.tryParse(item['start_at']?.toString() ?? '');
      if (subId != null && subId.isNotEmpty) {
        if (startAt != null && startAt > 0) {
          final dt = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
          final dKey =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          _knownSubIds['${courseId}_$dKey'] = subId;
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

  /// 构建智云课堂整门课程专属房间直达 URL
  static String buildCourseLivingroomUrl(String courseId) {
    return '$_kZhiyunBaseUrl/livingroom?course_id=$courseId&tenant_code=$_kTenantCode';
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
    final paramMatch = RegExp(r'course_id=(\d+)', caseSensitive: false).firstMatch(raw);
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
  }) async {
    final cleaned = cleanCourseName(courseName);
    _userCourseIds[cleaned] = courseId;
    _userCourseIds[courseName] = courseId;
    if (courseCode != null && courseCode.isNotEmpty) {
      _userCourseIds[courseCode] = courseId;
    }

    final box = _getHiveBox();
    if (box != null) {
      // 重新绑定时清除主动解绑标记
      await box.delete('zhiyun_unbind_$cleaned');
      await box.delete('zhiyun_unbind_$courseName');
      if (courseCode != null && courseCode.isNotEmpty) {
        await box.delete('zhiyun_unbind_$courseCode');
      }

      await box.put('zhiyun_cid_$cleaned', courseId);
      await box.put('zhiyun_cid_$courseName', courseId);
      if (courseCode != null && courseCode.isNotEmpty) {
        await box.put('zhiyun_cid_$courseCode', courseId);
      }
    }
  }

  /// 用户显式解绑课程智云 ID
  static Future<void> deleteCourseId(
    String courseName, {
    String? courseCode,
    String? courseId,
  }) async {
    final cleaned = cleanCourseName(courseName);
    final cid = courseId ?? _userCourseIds[cleaned] ?? _userCourseIds[courseName];
    if (cid != null) {
      _catalogueCache.remove(cid);
      _catalogueCacheTime.remove(cid);
    }
    _userCourseIds.remove(cleaned);
    _userCourseIds.remove(courseName);
    if (courseCode != null) {
      _userCourseIds.remove(courseCode);
    }

    final box = _getHiveBox();
    if (box != null) {
      await box.delete('zhiyun_cid_$cleaned');
      await box.delete('zhiyun_cid_$courseName');
      if (courseCode != null) {
        await box.delete('zhiyun_cid_$courseCode');
      }

      // 持久化记录用户显式解绑标记，防止后续自动搜索或后台同步再次错误关联
      await box.put('zhiyun_unbind_$cleaned', true);
      await box.put('zhiyun_unbind_$courseName', true);
      if (courseCode != null) {
        await box.put('zhiyun_unbind_$courseCode', true);
      }
    }
  }

  /// 注册/更新课程的 Zhiyun course_id 映射
  static void registerCourseMapping(String courseName, String courseId) {
    final cleaned = cleanCourseName(courseName);
    _userCourseIds[cleaned] = courseId;
    _userCourseIds[courseName] = courseId;
    final box = _getHiveBox();
    box?.put('zhiyun_cid_$cleaned', courseId);
    box?.put('zhiyun_cid_$courseName', courseId);
  }

  /// 注册/更新课节的 Zhiyun sub_id 映射
  static void registerSubIdMapping(
      String courseId, String dateStr, String subId) {
    _knownSubIds['${courseId}_$dateStr'] = subId;
  }

  /// 智能检测课程或特定课节当前是否正在智云课堂直播
  static bool checkIsLive({
    Map<String, dynamic>? item,
    DateTime? targetDate,
    Period? period,
  }) {
    // 1. 检查 item 中的状态标记
    if (item != null) {
      final statusLabel = item['status_label']?.toString() ?? '';
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
      final status = item['status']?.toString();
      // 智云状态码 2 表示直播中
      if (status == '2') {
        return true;
      }
      final liveType = item['live_type']?.toString();
      if (liveType == 'live') {
        return true;
      }
    }

    // 2. 时间维度辅助判断：如果当前正处于该节课的上课时间窗口内
    final now = DateTime.now();
    if (period != null) {
      final start = period.startTime;
      final end = period.endTime;
      // 节次开始前 10 分钟到结束后 10 分钟
      if (now.isAfter(start.subtract(const Duration(minutes: 10))) &&
          now.isBefore(end.add(const Duration(minutes: 10)))) {
        final statusLabel = item?['status_label']?.toString() ?? '';
        final status = item?['status']?.toString();
        // 若已生成回放或已明确结束，则不算直播
        if (statusLabel != '回放' && statusLabel != '已结束' && status != '4') {
          return true;
        }
      }
    } else if (targetDate != null) {
      if (targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day) {
        final startAt = int.tryParse(item?['start_at']?.toString() ?? '');
        final endAt = int.tryParse(item?['end_at']?.toString() ?? '');
        if (startAt != null && endAt != null && startAt > 0 && endAt > 0) {
          final sDt = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
          final eDt = DateTime.fromMillisecondsSinceEpoch(endAt * 1000);
          if (now.isAfter(sDt.subtract(const Duration(minutes: 10))) &&
              now.isBefore(eDt.add(const Duration(minutes: 10)))) {
            final statusLabel = item?['status_label']?.toString() ?? '';
            final status = item?['status']?.toString();
            if (statusLabel != '回放' && statusLabel != '已结束' && status != '4') {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// 智能检测课程或特定课节是否已在智云课堂生成录播回放
  static bool checkHasReplay({
    Map<String, dynamic>? item,
    DateTime? targetDate,
  }) {
    if (item == null) return false;

    // 1. 检查 item 中的状态标记
    final statusLabel = item['status_label']?.toString() ?? '';
    if (statusLabel == '回放' || statusLabel.contains('回放')) {
      return true;
    }
    final status = item['status']?.toString();
    if (status == '4' || status == '3') {
      return true;
    }
    final playback = item['playback'];
    if (playback != null &&
        playback != false &&
        playback != 'false' &&
        playback.toString().isNotEmpty) {
      return true;
    }
    final videoUrl = item['video_url'] ?? item['play_url'] ?? item['m3u8'];
    if (videoUrl != null && videoUrl.toString().isNotEmpty) {
      return true;
    }

    // 2. 时间维度：如果是未来的课节，绝无回放
    final now = DateTime.now();
    final lessonDate = targetDate ??
        (item['start_at'] != null && int.tryParse(item['start_at'].toString()) != null
            ? DateTime.fromMillisecondsSinceEpoch(int.parse(item['start_at'].toString()) * 1000)
            : null);
    if (lessonDate != null && lessonDate.isAfter(now)) {
      return false;
    }

    // 3. 如果状态为未开始或正在直播，无回放
    if (statusLabel == '未开始' || statusLabel.contains('直播') || status == '2' || status == '1') {
      return false;
    }

    // 4. 如果过去发生且有 sub_id，且距离开课已超过 1 小时
    final subId = item['sub_id']?.toString() ?? item['id']?.toString();
    if (subId != null && subId.isNotEmpty && lessonDate != null) {
      if (now.difference(lessonDate) > const Duration(hours: 1)) {
        return true;
      }
    }

    return false;
  }

  /// 解析指定课程/节次的回放或直播信息。若为体育/素质课等非录播课程，返回 null（自动隐藏入口）
  static Future<ZhiyunReplayInfo?> getLessonReplay({
    required Course course,
    Period? period,
    DateTime? lessonDate,
  }) async {
    // 1. 若为体育、身体素质、实践等非录播课程，坚决不展示回放入口（自动隐藏）
    if (!isRecordableCourse(course.name)) {
      return null;
    }

    // 确定目标节次日期
    final targetDate = period?.startTime ?? lessonDate;

    // 若用户显式解绑过该课程，不进行静默自动同步或在线匹配，保持未绑定状态
    if (isExplicitlyUnbound(course.name)) {
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

    // 2. 解析 course_id（从手动绑定、已同步课程动态匹配）
    var courseId = getKnownCourseId(
      course.name,
      courseCode: course.id,
      teacher: course.teacher,
    );

    // 如果未找到且尚未同步过“我的课程”，尝试静默自动同步
    if (courseId == null && getMySyncedCourses().isEmpty) {
      final synced = await syncFromMyCourses();
      if (synced > 0) {
        courseId = getKnownCourseId(
          course.name,
          courseCode: course.id,
          teacher: course.teacher,
        );
      }
    }

    // 若依然未找到，尝试直接通过智云搜索接口在线精准检索
    courseId ??= await searchCourseOnline(
      courseName: course.name,
      teacher: course.teacher,
    );

    // 3. 如果成功匹配到 course_id
    if (courseId != null) {
      // 尝试拉取智云课程目录
      final catalogue = await fetchCourseCatalogue(courseId);

      if (targetDate != null) {
        final dateKey =
            '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
        final shortDateKey = '${targetDate.month}月${targetDate.day}日';

        // 尝试从目录匹配具体节次
        Map<String, dynamic>? matchedItem;
        for (final item in catalogue) {
          final title = item['title']?.toString() ??
              item['sub_title']?.toString() ??
              '';
          final startAt = int.tryParse(item['start_at']?.toString() ?? '');
          DateTime? itemDate;
          if (startAt != null && startAt > 0) {
            itemDate = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
          } else if (item['date'] != null) {
            itemDate = DateTime.tryParse(item['date'].toString());
          }

          if (title.contains(dateKey) ||
              title.contains(shortDateKey) ||
              (itemDate != null &&
                  itemDate.year == targetDate.year &&
                  itemDate.month == targetDate.month &&
                  itemDate.day == targetDate.day)) {
            matchedItem = item;
            break;
          }
        }

        String? subId = matchedItem?['sub_id']?.toString() ??
            matchedItem?['id']?.toString() ??
            _knownSubIds['${courseId}_$dateKey'];

        final isLive = checkIsLive(
          item: matchedItem,
          targetDate: targetDate,
          period: period,
        );
        final hasReplay = checkHasReplay(
          item: matchedItem,
          targetDate: targetDate,
        );

        if (subId != null && subId.isNotEmpty) {
          return ZhiyunReplayInfo(
            courseId: courseId,
            subId: subId,
            courseName: course.name,
            lessonTitle: matchedItem?['title']?.toString() ??
                matchedItem?['sub_title']?.toString() ??
                (isLive ? '$shortDateKey 课堂直播' : '$shortDateKey 课堂录播'),
            lessonDate: targetDate,
            hasReplay: hasReplay,
            isLive: isLive,
            isLessonSpecific: true,
            livingroomUrl: buildLivingroomUrl(courseId, subId),
          );
        } else if (isLive) {
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
            lessonTitle: '$shortDateKey 课堂录播',
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
        lessonTitle: courseHasLive
            ? '${course.name} 课堂直播'
            : '${course.name} 智云课程房间',
        lessonDate: targetDate,
        hasReplay: courseHasAnyReplay,
        isLive: courseHasLive,
        isLessonSpecific: false,
        livingroomUrl: liveSubId != null
            ? buildLivingroomUrl(courseId, liveSubId)
            : buildCourseLivingroomUrl(courseId),
      );
    }

    // 4. 未找到智云课程：返回智云搜索与手动绑定入口
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
    final client = httpClient ?? createHttpClient();

    try {
      Cookie? cookie = ssoCookie;
      if (cookie == null) {
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

      final now = DateTime.now();
      // 查询当前学期所有相关月份（格式必须为带前导零的 YYYY-MM）
      final monthsToQuery = <String>{
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
        '${now.year}-${(now.month == 1 ? 12 : now.month - 1).toString().padLeft(2, '0')}',
        '${now.year}-${(now.month == 12 ? 1 : now.month + 1).toString().padLeft(2, '0')}',
        '${now.year}-09',
        '${now.year}-10',
        '${now.year}-11',
        '${now.year}-12',
        '${now.year + 1}-01',
        '${now.year}-02',
        '${now.year}-03',
        '${now.year}-04',
        '${now.year}-05',
        '${now.year}-06',
      };

      final foundCoursesMap = <String, Map<String, dynamic>>{};

      for (final m in monthsToQuery) {
        try {
          final uri = Uri.parse(
              '$_kZhiyunBaseUrl/courseapi/v2/course-live/get-my-course-month?month=$m&tenant_code=$_kTenantCode');
          final req = await client.getUrl(uri);
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.set('Cookie', '_token=$token; token=$token');
          req.headers.set('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
          final resp = await req.close().timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map) {
              // 兼容根级 list 与 data.list
              final list = json['list'] ??
                  (json['data'] is Map ? json['data']['list'] : null);
              if (list is List) {
                for (final dayItem in list) {
                  if (dayItem is Map) {
                    final courses = dayItem['course'] ?? dayItem['courses'];
                    if (courses is List) {
                      for (final c in courses) {
                        if (c is Map) {
                          final cid = c['id']?.toString() ??
                              c['course_id']?.toString();
                          final title = c['title']?.toString() ??
                              c['course_title']?.toString();
                          final subId = c['sub_id']?.toString();
                          final startAt =
                              int.tryParse(c['start_at']?.toString() ?? '');
                          final teacher = c['realname']?.toString() ??
                              c['teacher']?.toString() ??
                              c['lecturer_name']?.toString();

                          if (cid != null &&
                              cid.isNotEmpty &&
                              title != null &&
                              title.isNotEmpty) {
                            foundCoursesMap[cid] = {
                              'course_id': cid,
                              'course_title': title,
                              if (teacher != null && teacher.isNotEmpty)
                                'teacher': teacher,
                            };

                            if (subId != null &&
                                subId.isNotEmpty &&
                                startAt != null &&
                                startAt > 0) {
                              final dt = DateTime.fromMillisecondsSinceEpoch(
                                  startAt * 1000);
                              final dKey =
                                  '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                              _knownSubIds['${cid}_$dKey'] = subId;
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[ZhiyunService] 查询月份课程失败 ($m): $e');
        }
      }

      // 额外尝试调用用户主页选课接口 (vlabpassportapi)
      try {
        final profileUri = Uri.parse(
            '$_kZhiyunBaseUrl/courseapi/vlabpassportapi/v1/account-profile/course?tenant_code=$_kTenantCode');
        final pReq = await client.getUrl(profileUri);
        pReq.headers.set('Authorization', 'Bearer $token');
        pReq.headers.set('Cookie', '_token=$token; token=$token');
        pReq.headers.set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
        final pResp = await pReq.close().timeout(const Duration(seconds: 8));
        if (pResp.statusCode == 200) {
          final pBody = await pResp.transform(utf8.decoder).join();
          final pJson = jsonDecode(pBody);
          if (pJson is Map &&
              (pJson['code'] == 200 ||
                  pJson['code'] == 0 ||
                  pJson['success'] == true)) {
            final pData = pJson['data'] ?? pJson['result'];
            final pList = pData is List
                ? pData
                : (pData is Map ? (pData['list'] ?? pData['models']) : null);
            if (pList is List) {
              for (final item in pList) {
                if (item is Map) {
                  final cid = item['course_id']?.toString() ??
                      item['id']?.toString();
                  final title = item['course_name']?.toString() ??
                      item['course_title']?.toString() ??
                      item['title']?.toString();
                  final teacher = item['teacher']?.toString() ??
                      item['realname']?.toString();
                  if (cid != null &&
                      cid.isNotEmpty &&
                      title != null &&
                      title.isNotEmpty) {
                    foundCoursesMap[cid] = {
                      'course_id': cid,
                      'course_title': title,
                      if (teacher != null && teacher.isNotEmpty)
                        'teacher': teacher,
                    };
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
      for (final entry in foundCoursesMap.values) {
        final cid = entry['course_id'] as String;
        final title = entry['course_title'] as String;
        final cleaned = cleanCourseName(title);

        if (isExplicitlyUnbound(title) || isExplicitlyUnbound(cleaned)) {
          continue;
        }

        _userCourseIds[cleaned] = cid;
        _userCourseIds[title] = cid;

        if (box != null) {
          await box.put('zhiyun_cid_$cleaned', cid);
          await box.put('zhiyun_cid_$title', cid);
        }
        count++;
      }

      if (box != null && foundCoursesMap.isNotEmpty) {
        await box.put(
            'zhiyun_my_courses', jsonEncode(foundCoursesMap.values.toList()));
      }

      debugPrint('[ZhiyunService] 从“我的课程”成功同步 $count 门专属课程 ID');
      return count;
    } catch (e, stack) {
      debugPrint('[ZhiyunService] 同步“我的课程”发生异常: $e\n$stack');
      return 0;
    } finally {
      if (httpClient == null) {
        client.close(force: true);
      }
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
          final infoUri =
              Uri.parse('$_kZhiyunBaseUrl/userapi/v1/infosimple');
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
}
