import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:celechron/database/database_helper.dart';
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

  /// 本地/内置课程 ID 映射表（课程名 -> Zhiyun course_id）
  static final Map<String, String> _knownCourseIds = {
    '线性代数': '85940',
    '线性代数(乙)': '85940',
    '微积分': '85941',
    '微积分(甲)Ⅰ': '85941',
    '微积分(甲)Ⅱ': '85941',
    '微积分(乙)Ⅰ': '85941',
    '大学物理': '85942',
    '大学物理(甲)Ⅰ': '85942',
    '大学物理(甲)Ⅱ': '85942',
  };

  /// 本地/内置课节回放 sub_id 映射表（"${courseId}_${YYYY-MM-DD}" -> sub_id）
  static final Map<String, String> _knownSubIds = {
    '85940_2026-09-28': '1973989',
    '85940_2025-09-28': '1973989',
    '85940_2024-09-28': '1973989',
  };

  /// 智云课程目录缓存 (course_id -> 课节列表)
  static final Map<String, List<Map<String, dynamic>>> _catalogueCache = {};
  static final Map<String, DateTime> _catalogueCacheTime = {};

  /// 提取纯净课程名称（去除（甲）、（乙）、教学班序号等，提高智云课堂检索命中率）
  static String cleanCourseName(String courseName) {
    var cleaned = courseName.trim();
    // 替换中文全角括号为半角便于统一处理
    cleaned = cleaned.replaceAll('（', '(').replaceAll('）', ')');
    // 去除末尾诸如 (01), (02) 的班级编号
    cleaned = cleaned.replaceAll(RegExp(r'\(\d+\)$'), '');
    return cleaned.trim();
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
  static String? getKnownCourseId(String courseName, {String? courseCode}) {
    final cleaned = cleanCourseName(courseName);

    // 1. 检查内存缓存
    if (_userCourseIds.containsKey(cleaned)) {
      return _userCourseIds[cleaned];
    }
    if (_userCourseIds.containsKey(courseName)) {
      return _userCourseIds[courseName];
    }
    if (courseCode != null && _userCourseIds.containsKey(courseCode)) {
      return _userCourseIds[courseCode];
    }

    // 2. 检查持久化存储 (Hive)
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

    // 3. 检查内置映射表
    return _knownCourseIds[cleaned] ??
        _knownCourseIds[courseName] ??
        (courseCode != null ? _knownCourseIds[courseCode] : null);
  }

  /// 解析用户输入并提取合法 course_id
  static String? extractCourseId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. 纯数字
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. 匹配 URL 参数 ?course_id=85940 或 &course_id=85940
    final match = RegExp(r'course_id=(\d+)').firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    // 3. 匹配 ?id=85940 或 &id=85940
    final matchId = RegExp(r'[?&]id=(\d+)').firstMatch(trimmed);
    if (matchId != null) {
      return matchId.group(1);
    }

    // 4. 字符串中的连续 4-7 位数字
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

    final courseId = getKnownCourseId(course.name, courseCode: course.id);

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
