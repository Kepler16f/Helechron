import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'package:celechron/utils/json_utils.dart';

/// 单个课程类别的学分与成绩聚合模型
class CourseCategoryGroup {
  final String name;
  final double earnedCredits;
  final double? targetCredits;
  final int courseCount;
  final List<Grade> courses;
  final double averageGpa;
  final double excellentRate; // 优秀率 (>= 4.5 比例)
  final RxBool isExpanded;

  CourseCategoryGroup({
    required this.name,
    required this.earnedCredits,
    this.targetCredits,
    required this.courseCount,
    required this.courses,
    required this.averageGpa,
    required this.excellentRate,
    bool initiallyExpanded = false,
  }) : isExpanded = initiallyExpanded.obs;

  double get completionRate {
    if (targetCredits == null || targetCredits! <= 0) return 1.0;
    return (earnedCredits / targetCredits!).clamp(0.0, 1.0);
  }
}

/// 培养方案与学分进度控制器
class CreditProgressController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  /// 目标毕业学分（默认浙大本科标准 160.0，支持自定义）
  final targetGraduationCredits = 160.0.obs;

  /// 用户主修专业名称（从教务网拉取或手动填写）
  final userMajor = ''.obs;

  /// 专业信息来源：'zdbk'（教务网自动拉取） | 'manual'（用户手动填写） | 'none'（未设置）
  final majorSource = 'none'.obs;

  /// 是否已配置或拉取到主修专业
  bool get hasMajor => userMajor.value.isNotEmpty;

  /// 正在从教务网同步专业中
  final isSyncingMajor = false.obs;

  /// 基于本学期课程智能推测的候选大类/专业名称
  final inferredMajor = ''.obs;

  /// 各分类目标学分要求（根据专业培养方案映射）
  final categoryTargetCredits = <String, double>{}.obs;

  static const String _kTargetCreditsKey = 'graduation_target_credits';
  static const String _kUserMajorKey = 'user_major';
  static const String _kMajorSourceKey = 'user_major_source';
  static const String _kZdbkMajorCacheKey = 'zdbk_user_major';

  @override
  void onInit() {
    super.onInit();
    _loadTargetCredits();
    loadUserMajorAndScheme();

    ever(scholar, (callback) {
      // 课表或成绩更新时，尝试再次检测专业
      if (!hasMajor || majorSource.value == 'none') {
        loadUserMajorAndScheme();
      }
      update();
    });
  }

  void _loadTargetCredits() {
    try {
      final saved = _db.optionsBox.get(_kTargetCreditsKey);
      if (saved is num && saved > 0) {
        targetGraduationCredits.value = saved.toDouble();
      }
    } catch (e) {
      debugPrint('读取目标毕业学分配置失败: $e');
    }
  }

  /// 加载或从 ZDBK 自动拉取用户专业与培养方案要求
  void loadUserMajorAndScheme() {
    try {
      // 1. 优先检查用户手动保存的专业
      final savedManualMajor = _db.optionsBox.get(_kUserMajorKey);
      final savedSource = _db.optionsBox.get(_kMajorSourceKey);
      if (savedManualMajor is String && savedManualMajor.trim().isNotEmpty) {
        userMajor.value = savedManualMajor.trim();
        majorSource.value = (savedSource as String?) ?? 'manual';
        _applySchemeForMajor(userMajor.value);
        return;
      }

      // 2. 检查 ZDBK 缓存中拉取的专业
      final zdbkMajor = _db.getCachedWebPage(_kZdbkMajorCacheKey);
      if (zdbkMajor != null && zdbkMajor.trim().isNotEmpty) {
        userMajor.value = zdbkMajor.trim();
        majorSource.value = 'zdbk';
        _applySchemeForMajor(userMajor.value);
        return;
      }

      // 3. 尝试从学生信息、课表及各成绩缓存中动态解析 zymc
      final majorFromGrade = _extractMajorFromZdbkCaches();
      if (majorFromGrade != null && majorFromGrade.isNotEmpty) {
        userMajor.value = majorFromGrade;
        majorSource.value = 'zdbk';
        _db.setCachedWebPage(_kZdbkMajorCacheKey, majorFromGrade);
        _applySchemeForMajor(userMajor.value);
        return;
      }

      // 4. 根据当前已选修的课程推测候选大类/专业
      inferredMajor.value = inferMajorFromCourses() ?? '';

      // 5. 若已登录，尝试后台异步主动向教务网查询个人学籍专业
      if (scholar.value.isLogan) {
        syncMajorFromZdbk();
      }

      majorSource.value = 'none';
      _applyDefaultScheme();
    } catch (e) {
      debugPrint('加载用户专业与培养方案失败: $e');
      majorSource.value = 'none';
      _applyDefaultScheme();
    }
  }

  /// 主动向教务网拉取并同步学生学籍专业与培养方案
  Future<void> syncMajorFromZdbk() async {
    if (isSyncingMajor.value) return;
    isSyncingMajor.value = true;
    try {
      final remoteMajor = await scholar.value.fetchStudentMajor();
      if (remoteMajor != null && remoteMajor.trim().isNotEmpty) {
        userMajor.value = remoteMajor.trim();
        majorSource.value = 'zdbk';
        _db.setCachedWebPage(_kZdbkMajorCacheKey, remoteMajor.trim());
        _applySchemeForMajor(remoteMajor.trim());
        inferredMajor.value = '';
        update();
      }
    } catch (e) {
      debugPrint('主动同步教务网专业失败: $e');
    } finally {
      isSyncingMajor.value = false;
    }
  }

  /// 根据修读课程智能推断大类或专业
  String? inferMajorFromCourses() {
    final allCourseNames = <String>{};
    for (final s in scholar.value.semesters) {
      for (final c in s.courses.values) {
        if (c.name.isNotEmpty) allCourseNames.add(c.name);
      }
      for (final p in s.periods) {
        if (p.summary.isNotEmpty) allCourseNames.add(p.summary);
      }
    }

    final hasMathAlpha = allCourseNames
        .any((c) => c.contains('微积分（甲）') || c.contains('微积分(甲)'));
    final hasLinAlgAlpha = allCourseNames
        .any((c) => c.contains('线性代数（甲）') || c.contains('线性代数(甲)'));
    final hasEngDrawing = allCourseNames.any((c) => c.contains('工程图学'));
    final hasProgramming = allCourseNames.any(
        (c) => c.contains('程序设计') || c.contains('C语言') || c.contains('Python'));
    final hasMed = allCourseNames.any((c) =>
        c.contains('解剖') ||
        c.contains('生理') ||
        c.contains('基础医学') ||
        c.contains('临床'));
    final hasArch = allCourseNames.any((c) => c.contains('建筑设计') || c.contains('建筑学'));

    if (hasArch) return '建筑学';
    if (hasMed) return '临床医学';
    if (hasMathAlpha && (hasEngDrawing || hasProgramming || hasLinAlgAlpha)) {
      return '工科试验班（信息）';
    }
    if (hasMathAlpha || hasLinAlgAlpha) {
      return '工科试验班';
    }
    return null;
  }

  String? _extractMajorFromZdbkCaches() {
    // 检查学生个人信息缓存（由课表或学籍接口写入）
    final studentInfo = _db.getCachedWebPage('zdbk_student_info');
    if (studentInfo != null && studentInfo.isNotEmpty) {
      try {
        final decoded = jsonDecode(studentInfo);
        final map = asStringMap(decoded);
        if (map != null) {
          final major = asString(map['ZYMC']) ??
              asString(map['zymc']) ??
              asString(map['ZYFXMC']) ??
              asString(map['zyfxmc']) ??
              asString(map['XYMC']) ??
              asString(map['xymc']);
          if (major != null && major.trim().isNotEmpty && major != '未知') {
            return major.trim();
          }
        }
      } catch (_) {}
    }

    // 检查各成绩接口缓存
    for (final cacheKey in [
      'zdbk_MajorGrade',
      'zdbk_Transcript',
      'zdbk_exams',
    ]) {
      final cachedJson = _db.getCachedWebPage(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson);
          final items =
              asDynamicList(decoded is Map ? decoded['items'] : decoded);
          if (items != null && items.isNotEmpty) {
            for (final item in items) {
              final map = asStringMap(item);
              if (map != null) {
                final zymc = asString(map['zymc']) ??
                    asString(map['ZYMC']) ??
                    asString(map['zyfxmc']) ??
                    asString(map['ZYFXMC']) ??
                    asString(map['xymc']) ??
                    asString(map['XYMC']) ??
                    asString(map['major']);
                if (zymc != null && zymc.trim().isNotEmpty && zymc != '未知') {
                  return zymc.trim();
                }
              }
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// 用户手动设置/更改主修专业培养方案
  void setUserMajor(String major, {double? targetCredits}) {
    final cleaned = major.trim();
    if (cleaned.isEmpty) return;

    userMajor.value = cleaned;
    majorSource.value = 'manual';
    try {
      _db.optionsBox.put(_kUserMajorKey, cleaned);
      _db.optionsBox.put(_kMajorSourceKey, 'manual');
    } catch (e) {
      debugPrint('保存用户专业失败: $e');
    }

    _applySchemeForMajor(cleaned, overrideTarget: targetCredits);
    update();
  }

  /// 根据专业配置学分要求分布（支持标准四年制及五年制医学/建筑）
  void _applySchemeForMajor(String major, {double? overrideTarget}) {
    final isFiveYear = major.contains('建筑') ||
        major.contains('临床') ||
        major.contains('口腔') ||
        major.contains('医学') ||
        major.contains('规划');

    if (overrideTarget != null && overrideTarget > 0) {
      setTargetCredits(overrideTarget);
    } else {
      setTargetCredits(isFiveYear ? 210.0 : 160.0);
    }

    if (isFiveYear) {
      categoryTargetCredits.value = {
        '通识必修课': 38.0,
        '通识选修课': 10.0,
        '大类基础课': 40.0,
        '专业必修课': 65.0,
        '专业选修课': 35.0,
        '实践与毕业设计': 22.0,
      };
    } else {
      categoryTargetCredits.value = {
        '通识必修课': 34.0,
        '通识选修课': 10.0,
        '大类基础课': 35.0,
        '专业必修课': 40.0,
        '专业选修课': 25.0,
        '实践与毕业设计': 16.0,
      };
    }
  }

  void _applyDefaultScheme() {
    _applySchemeForMajor('');
  }

  void setTargetCredits(double credits) {
    if (credits > 0) {
      targetGraduationCredits.value = double.parse(credits.toStringAsFixed(1));
      try {
        _db.optionsBox.put(_kTargetCreditsKey, targetGraduationCredits.value);
      } catch (e) {
        debugPrint('保存目标毕业学分配置失败: $e');
      }
    }
  }

  /// 获取去重后的所有有效成绩课程列表
  List<Grade> getAllUniqueGrades() {
    final Map<String, Grade> uniqueMap = {};
    for (final list in scholar.value.grades.values) {
      for (final g in list) {
        // 如果有重复选修/重修，保留高绩点记录
        if (!uniqueMap.containsKey(g.id) ||
            (g.fivePoint > uniqueMap[g.id]!.fivePoint)) {
          uniqueMap[g.id] = g;
        }
      }
    }
    return uniqueMap.values.toList();
  }

  /// 总已获学分
  double get totalEarnedCredits {
    return getAllUniqueGrades().fold<double>(
        0.0, (sum, g) => sum + g.earnedCredit);
  }

  /// 计入 GPA 的总学分
  double get totalGpaCredits {
    return getAllUniqueGrades()
        .where((g) => g.gpaIncluded)
        .fold<double>(0.0, (sum, g) => sum + g.credit);
  }

  /// 总体 GPA
  Tuple<List<double>, double> get overallGpa {
    final list = getAllUniqueGrades().where((g) => g.gpaIncluded).toList();
    if (list.isEmpty) {
      return Tuple([0.0, 0.0, 0.0, 0.0], 0.0);
    }
    return GpaHelper.calculateGpa(list);
  }

  /// 毕业达成率 (0.0 ~ 1.0)
  double get completionRatio {
    final target = targetGraduationCredits.value;
    if (target <= 0) return 1.0;
    return (totalEarnedCredits / target).clamp(0.0, 1.0);
  }

  /// 尚缺学分
  double get remainingCredits {
    final diff = targetGraduationCredits.value - totalEarnedCredits;
    return diff > 0 ? diff : 0.0;
  }

  /// 课程性质标准化映射
  static String normalizeCategory(String rawCat, Grade g) {
    final cat = rawCat.trim();
    if (cat.contains('通识必修') || cat.contains('思想政治') || cat.contains('军政')) {
      return '通识必修课';
    }
    if (cat.contains('通识选修') || cat.contains('通识核心')) {
      return '通识选修课';
    }
    if (cat.contains('大类基础') || cat.contains('学科基础')) {
      return '大类基础课';
    }
    if (cat.contains('专业必修') || cat.contains('专业核心')) {
      return '专业必修课';
    }
    if (cat.contains('专业选修') || cat.contains('专业方向')) {
      return '专业选修课';
    }
    if (cat.contains('实践') ||
        cat.contains('实习') ||
        cat.contains('毕业论文') ||
        cat.contains('毕业设计')) {
      return '实践与毕业设计';
    }
    if (cat.contains('体育') || cat.contains('体测') || g.id.contains('xtwkc')) {
      return '体育与体测';
    }
    if (cat.contains('跨专业') || cat.contains('个性化') || cat.contains('自主发展')) {
      return '跨专业与个性修读';
    }
    if (g.major) {
      return '专业主修课';
    }
    return '其他课程';
  }

  /// 标准分类的推荐展示顺序
  static const List<String> categoryOrder = [
    '通识必修课',
    '通识选修课',
    '大类基础课',
    '专业必修课',
    '专业选修课',
    '专业主修课',
    '跨专业与个性修读',
    '实践与毕业设计',
    '体育与体测',
    '其他课程',
  ];

  /// 按类别聚合的所有课程群组
  List<CourseCategoryGroup> getCategoryGroups() {
    final all = getAllUniqueGrades();
    final Map<String, List<Grade>> groupMap = {};

    for (final g in all) {
      final key = normalizeCategory(g.category, g);
      groupMap.putIfAbsent(key, () => []).add(g);
    }

    final List<CourseCategoryGroup> result = [];

    for (final catName in categoryOrder) {
      if (groupMap.containsKey(catName)) {
        final list = groupMap[catName]!;
        // 按成绩降序排列，方便同学查阅优秀科目
        list.sort((a, b) => b.fivePoint.compareTo(a.fivePoint));

        final earned = list.fold<double>(0.0, (p, e) => p + e.earnedCredit);
        final gpaGrades = list.where((e) => e.gpaIncluded).toList();
        final avgGpa = gpaGrades.isEmpty
            ? 0.0
            : (GpaHelper.calculateGpa(gpaGrades).item1[0]);
        final excellentCount = list.where((e) => e.fivePoint >= 4.5).length;
        final excellentRate =
            list.isEmpty ? 0.0 : (excellentCount / list.length);

        result.add(CourseCategoryGroup(
          name: catName,
          earnedCredits: earned,
          targetCredits: categoryTargetCredits[catName],
          courseCount: list.length,
          courses: list,
          averageGpa: avgGpa,
          excellentRate: excellentRate,
          initiallyExpanded: false,
        ));
      }
    }

    // 处理其他未在预定义列表中的分类
    groupMap.forEach((key, list) {
      if (!categoryOrder.contains(key)) {
        list.sort((a, b) => b.fivePoint.compareTo(a.fivePoint));
        final earned = list.fold<double>(0.0, (p, e) => p + e.earnedCredit);
        final gpaGrades = list.where((e) => e.gpaIncluded).toList();
        final avgGpa = gpaGrades.isEmpty
            ? 0.0
            : (GpaHelper.calculateGpa(gpaGrades).item1[0]);
        final excellentCount = list.where((e) => e.fivePoint >= 4.5).length;
        final excellentRate =
            list.isEmpty ? 0.0 : (excellentCount / list.length);

        result.add(CourseCategoryGroup(
          name: key,
          earnedCredits: earned,
          targetCredits: categoryTargetCredits[key],
          courseCount: list.length,
          courses: list,
          averageGpa: avgGpa,
          excellentRate: excellentRate,
          initiallyExpanded: false,
        ));
      }
    });

    return result;
  }
}
