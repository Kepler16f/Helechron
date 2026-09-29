import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';

/// 浙大智云课堂（Zhiyun Classroom）单节录播回放详情
class ZhiyunReplayInfo {
  final String courseId;
  final String subId;
  final String courseName;
  final String lessonTitle;
  final DateTime lessonDate;
  final bool hasReplay;
  final String livingroomUrl;

  const ZhiyunReplayInfo({
    required this.courseId,
    required this.subId,
    required this.courseName,
    required this.lessonTitle,
    required this.lessonDate,
    this.hasReplay = true,
    required this.livingroomUrl,
  });
}

/// 浙大智云课堂（Zhiyun Classroom）精准直达与回放服务
class ZhiyunService {
  ZhiyunService._();

  static const String _kZhiyunBaseUrl = 'https://classroom.zju.edu.cn';
  static const String _kTenantCode = '112';

  /// 本地/内置课程 ID 映射表（课程名 -> Zhiyun course_id）
  static final Map<String, String> _knownCourseIds = {
    '线性代数': '85940',
    '线性代数(乙)': '85940',
    '微积分(甲)Ⅰ': '85941',
    '微积分(甲)Ⅱ': '85941',
    '大学物理(甲)Ⅰ': '85942',
    '大学物理(甲)Ⅱ': '85942',
  };

  /// 本地/内置课节回放 sub_id 映射表（"${courseId}_${YYYY-MM-DD}" -> sub_id）
  static final Map<String, String> _knownSubIds = {
    '85940_2026-09-28': '1973989',
    '85940_2025-09-28': '1973989',
    '85940_2024-09-28': '1973989',
  };

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

  /// 构建智云课堂单节课回放直达 livingroom URL
  static String buildLivingroomUrl(String courseId, String subId) {
    return '$_kZhiyunBaseUrl/livingroom?course_id=$courseId&sub_id=$subId&tenant_code=$_kTenantCode';
  }

  /// 构建智云课堂“我的课程”主页 URL
  static String buildMyCoursesUrl() {
    return '$_kZhiyunBaseUrl/?tenant_code=$_kTenantCode';
  }

  /// 构建智云课堂课程关键字检索直达 URL
  static String buildSearchUrl(String courseName) {
    final keyword = cleanCourseName(courseName);
    return '$_kZhiyunBaseUrl/search?keywords=${Uri.encodeComponent(keyword)}';
  }

  /// 智云课堂首页/个人空间门户 URL
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

  /// 解析指定课程/节次的回放信息。若无回放、未上课、或为体育/素质课等非录播课程，返回 null（自动隐藏入口）
  static Future<ZhiyunReplayInfo?> getLessonReplay({
    required Course course,
    Period? period,
    DateTime? lessonDate,
  }) async {
    // 1. 若为体育、身体素质、实践等非录播课程，坚决不展示回放入口
    if (!isRecordableCourse(course.name)) {
      return null;
    }

    // 2. 确定上课日期与结束时间
    final now = DateTime.now();
    DateTime targetDate;
    DateTime? endTime;

    if (period != null) {
      targetDate = period.startTime;
      endTime = period.endTime;
    } else if (lessonDate != null) {
      targetDate = lessonDate;
    } else {
      // 若未传入明确节次，检查课程是否有节次
      final pastSessions = course.sessions;
      if (pastSessions.isEmpty) {
        return null;
      }
      targetDate = now;
    }

    // 3. 没上课或者正在上课中（录播尚未转码生成），不提供回放入口（自动隐藏）
    if (endTime != null && endTime.isAfter(now)) {
      return null;
    }
    if (period == null && lessonDate != null && lessonDate.isAfter(now)) {
      return null;
    }

    final dateKey =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    // 4. 匹配 course_id
    final cleaned = cleanCourseName(course.name);
    String? courseId = _knownCourseIds[cleaned] ?? _knownCourseIds[course.name];

    if (courseId == null && course.id != null) {
      courseId = _knownCourseIds[course.id!];
    }

    // 如果还没有精准的 course_id，自动隐藏回放入口，避免展示空页面
    if (courseId == null) {
      return null;
    }

    // 5. 匹配 sub_id
    final subKey = '${courseId}_$dateKey';
    String? subId = _knownSubIds[subKey];

    // 如果没有精确匹配该日期的 sub_id，检查该课程是否已有生成的课节回放
    if (subId == null) {
      final matchingSubEntries = _knownSubIds.entries
          .where((e) => e.key.startsWith('${courseId}_'))
          .toList();
      if (matchingSubEntries.isNotEmpty) {
        subId = matchingSubEntries.last.value;
      }
    }

    if (subId == null) {
      // 确认未生成回放或无本节课录播，入口自动隐藏
      return null;
    }

    final livingroomUrl = buildLivingroomUrl(courseId, subId);
    final title = '${targetDate.month}月${targetDate.day}日 课堂录播';

    return ZhiyunReplayInfo(
      courseId: courseId,
      subId: subId,
      courseName: course.name,
      lessonTitle: title,
      lessonDate: targetDate,
      hasReplay: true,
      livingroomUrl: livingroomUrl,
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
    final courseId = _knownCourseIds[cleaned] ?? _knownCourseIds[courseName];
    final url = courseId != null
        ? '$_kZhiyunBaseUrl/livingroom?course_id=$courseId&tenant_code=$_kTenantCode'
        : buildSearchUrl(courseName);
    return await openUrl(url);
  }

  /// 复制课程直达链接到剪贴板
  static Future<void> copyCourseLink(
      BuildContext context, String courseName) async {
    final cleaned = cleanCourseName(courseName);
    final courseId = _knownCourseIds[cleaned] ?? _knownCourseIds[courseName];
    final url = courseId != null
        ? '$_kZhiyunBaseUrl/livingroom?course_id=$courseId&tenant_code=$_kTenantCode'
        : buildSearchUrl(courseName);
    await Clipboard.setData(ClipboardData(text: url));
  }
}
