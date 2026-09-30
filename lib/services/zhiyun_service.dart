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
  final bool isLessonSpecific;
  final String livingroomUrl;

  const ZhiyunReplayInfo({
    this.courseId,
    this.subId,
    required this.courseName,
    required this.lessonTitle,
    this.lessonDate,
    this.hasReplay = true,
    this.isLessonSpecific = false,
    required this.livingroomUrl,
  });
}

/// 浙大智云课堂（Zhiyun Classroom）精准直达与回放服务
class ZhiyunService {
  ZhiyunService._();

  static const String _kZhiyunBaseUrl = 'https://classroom.zju.edu.cn';
  static const String _kTenantCode = '112';

  /// 用户自定义/运行时发现的课程映射表（内存缓存）
  static final Map<String, String> _userCourseIds = {};

  /// 本地/内置课程 ID 备用映射表（仅作初次使用或离线兜底，切勿死板覆盖用户账号的专属课程）
  static final Map<String, String> _knownCourseIds = {
    '线性代数': '85940',
    '线性代数(乙)': '85940',
    '线性代数Ⅰ(H)': '85941',
    '微积分': '86957',
    '微积分(甲)Ⅰ': '86957',
    '微积分(甲)Ⅱ': '86957',
    '微积分(乙)Ⅰ': '86957',
    '微积分(乙)Ⅱ': '86957',
    '大学物理': '85942',
    '大学物理(甲)Ⅰ': '85942',
    '大学物理(甲)Ⅱ': '85942',
  };

  /// 本地/内置课节回放 sub_id 映射表（"${courseId}_${YYYY-MM-DD}" -> sub_id）
  static final Map<String, String> _knownSubIds = {
    '85940_2026-09-28': '1973989',
    '85940_2025-09-28': '1973989',
    '85940_2024-09-28': '1973989',
    '86957_2026-09-29': '1974698',
  };

  /// 智云课程目录缓存 (course_id -> 课节列表)
  static final Map<String, List<Map<String, dynamic>>> _catalogueCache = {};
  static final Map<String, DateTime> _catalogueCacheTime = {};

  /// 智云认证 Token 内存缓存与并发互斥 Future
  static String? _cachedZhiyunToken;
  static Future<int>? _syncFuture;

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

    // 4. 包含关系（例如 微积分 包含在 微积分甲1 中，或 线性代数 包含在 线性代数乙 中）
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

  /// 查询指定课程的智云 course_id
  /// 优先级：1. 用户手动绑定 > 2. 动态同步的“我的课程”（千人千面） > 3. 兜底内置映射
  static String? getKnownCourseId(
    String courseName, {
    String? courseCode,
    String? teacher,
  }) {
    final cleaned = cleanCourseName(courseName);

    // 1. 检查内存缓存 (已成功解析或用户手动绑定)
    if (_userCourseIds.containsKey(cleaned)) {
      return _userCourseIds[cleaned];
    }
    if (_userCourseIds.containsKey(courseName)) {
      return _userCourseIds[courseName];
    }
    if (courseCode != null && _userCourseIds.containsKey(courseCode)) {
      return _userCourseIds[courseCode];
    }

    // 2. 检查持久化存储 (Hive 用户显式保存的 ID)
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

    // 3. 核心：从用户专属“我的课程”列表中动态智能匹配（千人千面，不死板硬编码）
    final myCourses = getMySyncedCourses();
    if (myCourses.isNotEmpty) {
      // 优先：课程名匹配且教师匹配（精准匹配特定教师的教学班）
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
          return tCid;
        }
      }
    }

    // 4. 兜底内置映射（作为初次使用或未同步时的备用，绝不强制覆盖专属课程）
    return _knownCourseIds[cleaned] ??
        _knownCourseIds[courseName] ??
        (courseCode != null ? _knownCourseIds[courseCode] : null);
  }

  /// 解析用户输入并提取合法 course_id（支持纯数字、各类智云 URL 如 livingroom, coursedetail 等）
  static String? extractCourseId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. 纯数字
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. 匹配 URL 参数 ?course_id=85940 或 &course_id=85940
    final match = RegExp(r'[?&]course_id=(\d+)').firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    // 3. 匹配 ?id=85940 或 &id=85940 或 ?cid=85940
    final matchId = RegExp(r'[?&](?:id|cid)=(\d+)').firstMatch(trimmed);
    if (matchId != null) {
      return matchId.group(1);
    }

    // 4. 匹配 /coursedetail/85940 或 /livingroom/85940 或 /detail/85940
    final matchPath =
        RegExp(r'/(?:coursedetail|livingroom|detail)/(\d+)').firstMatch(trimmed);
    if (matchPath != null) {
      return matchPath.group(1);
    }

    // 5. 字符串中的连续 4-7 位数字
    final matchDigits = RegExp(r'\b\d{4,7}\b').firstMatch(trimmed);
    if (matchDigits != null) {
      return matchDigits.group(0);
    }

    return null;
  }

  /// 绑定/保存课程的 Zhiyun course_id
  static Future<void> saveCourseId(
    String courseName,
    String rawInput, {
    String? courseCode,
  }) async {
    final courseId = extractCourseId(rawInput);
    if (courseId == null || courseId.isEmpty) {
      return;
    }
    final cleaned = cleanCourseName(courseName);
    _userCourseIds[cleaned] = courseId;
    _userCourseIds[courseName] = courseId;
    if (courseCode != null) {
      _userCourseIds[courseCode] = courseId;
    }

    final box = _getHiveBox();
    if (box != null) {
      await box.put('zhiyun_cid_$cleaned', courseId);
      await box.put('zhiyun_cid_$courseName', courseId);
      if (courseCode != null) {
        await box.put('zhiyun_cid_$courseCode', courseId);
      }
    }

    // 保存后在后台异步预热拉取录播目录
    fetchCourseCatalogue(courseId);
  }

  /// 删除课程的 Zhiyun course_id 绑定
  static Future<void> deleteCourseId(
    String courseName, {
    String? courseCode,
  }) async {
    final cleaned = cleanCourseName(courseName);
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
    }
  }

  /// 请求智云官方公开接口获取该课程的全量录播目录
  static Future<List<Map<String, dynamic>>> fetchCourseCatalogue(
      String courseId) async {
    final cached = _catalogueCache[courseId];
    final cachedTime = _catalogueCacheTime[courseId];
    if (cached != null &&
        cachedTime != null &&
        DateTime.now().difference(cachedTime) < const Duration(minutes: 30)) {
      return cached;
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      client.badCertificateCallback = (cert, host, port) => true;
      final uri = Uri.parse(
          '$_kZhiyunBaseUrl/courseapi/v2/course/catalogue?course_id=$courseId');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      final token = getCachedZhiyunToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
        request.headers.set('Cookie', '_token=$token; token=$token');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (json is Map && json['success'] == true && json['result'] is Map) {
          final data = json['result']['data'];
          if (data is List) {
            final list = <Map<String, dynamic>>[];
            for (final item in data) {
              if (item is Map) {
                list.add(Map<String, dynamic>.from(item));
              }
            }
            _catalogueCache[courseId] = list;
            _catalogueCacheTime[courseId] = DateTime.now();

            // 自动注册已知 sub_ids
            for (final item in list) {
              final subId = item['sub_id']?.toString();
              final startAt = int.tryParse(item['start_at']?.toString() ?? '');
              if (subId != null && startAt != null && startAt > 0) {
                final dt = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
                final dKey =
                    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                _knownSubIds['${courseId}_$dKey'] = subId;
              }
            }

            return list;
          }
        }
      }
    } catch (e) {
      debugPrint('获取智云课程目录失败 (courseId=$courseId): $e');
    }

    return cached ?? const [];
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

  /// 构建智云课堂课程关键字检索直达 URL (兼容旧链接)
  static String buildSearchUrl(String courseName) {
    final keyword = cleanCourseName(courseName);
    return '$_kZhiyunBaseUrl/search?keywords=${Uri.encodeComponent(keyword)}';
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

  /// 注册/更新课程的 Zhiyun course_id 映射
  static void registerCourseMapping(String courseName, String courseId) {
    _knownCourseIds[cleanCourseName(courseName)] = courseId;
    _knownCourseIds[courseName] = courseId;
  }

  /// 注册/更新课节的 Zhiyun sub_id 映射
  static void registerSubIdMapping(
      String courseId, String dateStr, String subId) {
    _knownSubIds['${courseId}_$dateStr'] = subId;
  }

  /// 解析指定课程/节次的回放信息。若为体育/素质课等非录播课程，返回 null（自动隐藏入口）
  static Future<ZhiyunReplayInfo?> getLessonReplay({
    required Course course,
    Period? period,
    DateTime? lessonDate,
  }) async {
    // 1. 若为体育、身体素质、实践等非录播课程，坚决不展示回放入口（自动隐藏）
    if (!isRecordableCourse(course.name)) {
      return null;
    }

    var courseId = getKnownCourseId(
      course.name,
      courseCode: course.id,
      teacher: course.teacher,
    );

    // 如果未找到映射且尚未同步过“我的课程”，尝试触发一次静默自动同步
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

    // 2. 如果已知 course_id，尝试拉取该课程目录进行节次回放精准匹配
    if (courseId != null) {
      final catalogue = await fetchCourseCatalogue(courseId);

      // 确定目标节次日期
      final targetDate = period?.startTime ?? lessonDate;

      if (targetDate != null) {
        final dateKey =
            '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
        final shortDateKey = '${targetDate.month}月${targetDate.day}日';

        // 在目录中查找对应日期的录播课节
        Map<String, dynamic>? matchedItem;
        for (final item in catalogue) {
          final title = item['title']?.toString() ?? '';
          final startAt = int.tryParse(item['start_at']?.toString() ?? '');
          DateTime? itemDate;
          if (startAt != null && startAt > 0) {
            itemDate = DateTime.fromMillisecondsSinceEpoch(startAt * 1000);
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

        // 检查备用 sub_id 映射
        String? subId = matchedItem?['sub_id']?.toString() ??
            _knownSubIds['${courseId}_$dateKey'];

        if (matchedItem != null) {
          final status = matchedItem['status']?.toString();
          final hasPlayback = matchedItem['playback'] != null ||
              status == '6' ||
              status == '3' ||
              status == '4';

          // 确认已生成录播且处于可观看状态
          if (hasPlayback && subId != null && subId.isNotEmpty) {
            return ZhiyunReplayInfo(
              courseId: courseId,
              subId: subId,
              courseName: course.name,
              lessonTitle:
                  matchedItem['title']?.toString() ?? '$shortDateKey 课堂录播',
              lessonDate: targetDate,
              hasReplay: true,
              isLessonSpecific: true,
              livingroomUrl: buildLivingroomUrl(courseId, subId),
            );
          } else {
            // 未生成录播或转码未就绪（如 status == '2' 或正在上课中）
            // 按照需求：确认生成了再给出入口，没上课或者没生成回放的，回放入口应该自动隐藏
            return ZhiyunReplayInfo(
              courseId: courseId,
              subId: null,
              courseName: course.name,
              lessonTitle:
                  matchedItem['title']?.toString() ?? '$shortDateKey 课堂录播',
              lessonDate: targetDate,
              hasReplay: false,
              isLessonSpecific: true,
              livingroomUrl: buildCourseLivingroomUrl(courseId),
            );
          }
        } else if (subId != null && subId.isNotEmpty) {
          // 在已知 sub_id 映射中命中
          return ZhiyunReplayInfo(
            courseId: courseId,
            subId: subId,
            courseName: course.name,
            lessonTitle: '$shortDateKey 课堂录播',
            lessonDate: targetDate,
            hasReplay: true,
            isLessonSpecific: true,
            livingroomUrl: buildLivingroomUrl(courseId, subId),
          );
        }
      }

      // 针对整门课程（非指定课节，例如从课程列表进入）：提供课程录播房间直达
      return ZhiyunReplayInfo(
        courseId: courseId,
        subId: null,
        courseName: course.name,
        lessonTitle: '${course.name} 智云课程房间',
        lessonDate: targetDate,
        hasReplay: true,
        isLessonSpecific: false,
        livingroomUrl: buildCourseLivingroomUrl(courseId),
      );
    }

    // 3. 课程尚未绑定智云 ID：返回课程级检索与绑定入口，不再隐藏全部课程
    return ZhiyunReplayInfo(
      courseId: null,
      subId: null,
      courseName: course.name,
      lessonTitle: '${course.name} 智云课堂',
      lessonDate: period?.startTime ?? lessonDate,
      hasReplay: false,
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
    final client = httpClient ??
        (HttpClient()
          ..connectionTimeout = const Duration(seconds: 10)
          ..badCertificateCallback = (cert, host, port) => true);

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
      final monthsToQuery = <String>{
        '${now.year}-${now.month}',
        '${now.year}-${now.month == 1 ? 12 : now.month - 1}',
        '${now.year}-${now.month == 12 ? 1 : now.month + 1}',
        if (now.month >= 8) '${now.year}-9',
        if (now.month >= 8) '${now.year}-10',
        if (now.month >= 8) '${now.year}-11',
        if (now.month >= 8) '${now.year}-12',
        if (now.month <= 3) '${now.year}-1',
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
            if (json is Map && json['code'] == 0 && json['data'] is Map) {
              final list = json['data']['list'];
              if (list is List) {
                for (final dayItem in list) {
                  if (dayItem is Map && dayItem['course'] is List) {
                    for (final c in dayItem['course']) {
                      if (c is Map) {
                        final cid =
                            c['course_id']?.toString() ?? c['id']?.toString();
                        final title = c['course_title']?.toString() ??
                            c['title']?.toString();
                        final subId = c['sub_id']?.toString();
                        final startAt =
                            int.tryParse(c['start_at']?.toString() ?? '');
                        final teacher = c['teacher']?.toString() ??
                            c['lecturer_name']?.toString();

                        if (cid != null &&
                            cid.isNotEmpty &&
                            title != null &&
                            title.isNotEmpty) {
                          foundCoursesMap[cid] = {
                            'course_id': cid,
                            'course_title': title,
                            if (teacher != null) 'teacher': teacher,
                          };

                          if (subId != null &&
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
        } catch (e) {
          debugPrint('[ZhiyunService] 查询月份课程失败 ($m): $e');
        }
      }

      // 额外调用个人中心已选课程列表接口
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
                  final teacher = item['teacher']?.toString();
                  if (cid != null &&
                      cid.isNotEmpty &&
                      title != null &&
                      title.isNotEmpty) {
                    foundCoursesMap[cid] = {
                      'course_id': cid,
                      'course_title': title,
                      if (teacher != null) 'teacher': teacher,
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

      var current = Uri.parse(
        'https://tgmedia.cmc.zju.edu.cn/index.php?r=auth/login&tenant_code=112&forward=https%3A%2F%2Fclassroom.zju.edu.cn%2F%3Ftenant_code%3D112',
      );

      String? token;

      for (var hop = 0; hop < 12; hop++) {
        final outgoing = cookiesFor(current);
        final req = await httpClient
            .getUrl(current)
            .timeout(const Duration(seconds: 8));
        req.followRedirects = false;
        req.cookies.addAll(outgoing);

        final resp =
            await req.close().timeout(const Duration(seconds: 8));
        for (final c in resp.cookies) {
          storeCookie(c, current);
          if (c.name == '_token' || c.name == 'token') {
            final decoded = Uri.decodeComponent(c.value);
            final match =
                RegExp(r'\{i:\d+;s:\d+:"_token";i:\d+;s:\d+:"(.+?)";\}')
                    .firstMatch(decoded);
            token = match?.group(1) ?? c.value;
          }
        }

        if (current.queryParameters.containsKey('token')) {
          token = current.queryParameters['token'];
        }

        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (resp.isRedirect && loc != null && loc.isNotEmpty) {
          current = current.resolve(loc);
          if (current.queryParameters.containsKey('token')) {
            token = current.queryParameters['token'];
          }
        } else {
          break;
        }
      }

      if (token != null && token.isNotEmpty) {
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
