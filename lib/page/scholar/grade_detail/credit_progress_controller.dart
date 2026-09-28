import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/utils/gpa_helper.dart';

/// 单个课程类别的学分与成绩聚合模型
class CourseCategoryGroup {
  final String name;
  final double earnedCredits;
  final int courseCount;
  final List<Grade> courses;
  final double averageGpa;
  final double excellentRate; // 优秀率 (>= 4.5 比例)
  final RxBool isExpanded;

  CourseCategoryGroup({
    required this.name,
    required this.earnedCredits,
    required this.courseCount,
    required this.courses,
    required this.averageGpa,
    required this.excellentRate,
    bool initiallyExpanded = false,
  }) : isExpanded = initiallyExpanded.obs;
}

/// 培养方案与学分进度控制器
class CreditProgressController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  /// 目标毕业学分（默认浙大本科标准 160.0，支持自定义）
  final targetGraduationCredits = 160.0.obs;

  static const String _kTargetCreditsKey = 'graduation_target_credits';

  @override
  void onInit() {
    super.onInit();
    _loadTargetCredits();

    ever(scholar, (callback) {
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
    if (cat.contains('实践') || cat.contains('实习') || cat.contains('毕业论文') || cat.contains('毕业设计')) {
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
