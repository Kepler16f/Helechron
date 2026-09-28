import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/simulated_course.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/utils/gpa_helper.dart';

/// 绩点显示体制
enum GpaScaleType {
  fivePoint('五分制', 5.0),
  fourPointScale('出国 4.3', 4.3),
  legacyFourPoint('原始 4.0', 4.0),
  hundredPoint('百分制', 100.0);

  final String label;
  final double maxScore;
  const GpaScaleType(this.label, this.maxScore);
}

/// 模拟器子功能模式
enum SimulatorSubTab {
  whatIf, // 正向推演
  goalSeek, // 目标逆推
}

/// 目标逆推测算结果
class GoalSeekResult {
  final bool hasCredits;
  final bool isImpossible;
  final bool isAlreadyAchieved;
  final double requiredGpa;
  final double maxPossibleGpa;
  final double remainingCredits;
  final String message;

  const GoalSeekResult({
    required this.hasCredits,
    required this.isImpossible,
    required this.isAlreadyAchieved,
    required this.requiredGpa,
    required this.maxPossibleGpa,
    required this.remainingCredits,
    required this.message,
  });
}

/// GPA 模拟器独立控制器
class GpaSimulatorController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  // ==================== 视图状态 ====================
  final selectedScale = GpaScaleType.fivePoint.obs;
  final simulatorSubTab = SimulatorSubTab.whatIf.obs;
  final targetGpa = 4.5.obs;

  // ==================== 模拟课程状态 ====================
  final RxList<SimulatedCourse> simulatedCourses = <SimulatedCourse>[].obs;

  /// 浙大标准五分制绩点阶梯
  static const List<double> zjuFivePointSteps = [
    5.0,
    4.8,
    4.5,
    4.2,
    3.9,
    3.6,
    3.3,
    3.0,
    2.5,
    2.0,
    0.0,
  ];

  @override
  void onInit() {
    super.onInit();
    _initSimulatedCourses();

    ever(scholar, (callback) {
      _initSimulatedCourses();
    });
  }

  /// 初始化模拟课程列表：优先提取最新学期中尚未出分的课程；若已全部出分，则载入最新学期全部课程
  void _initSimulatedCourses() {
    try {
      final cachedJson = _db.optionsBox.get('simulated_courses_cache');
      if (cachedJson is String && cachedJson.isNotEmpty) {
        final list = (jsonDecode(cachedJson) as List)
            .map((item) =>
                SimulatedCourse.fromJson(item as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          simulatedCourses.value = list;
          return;
        }
      }
    } catch (e) {
      debugPrint('恢复模拟课程缓存失败: $e');
    }

    resetCoursesFromCurrentSemester();
  }

  /// 从当前最新学期重新扫描构建模拟课程列表
  void resetCoursesFromCurrentSemester() {
    final list = <SimulatedCourse>[];
    if (scholar.value.semesters.isNotEmpty) {
      final latest = scholar.value.semesters.first;

      // 1. 优先提取当前学期尚未出分的课程
      for (final course in latest.courses.values) {
        final cid = course.id ?? course.name;
        final grade = course.grade;
        final isPending = grade == null ||
            grade.original == '待录' ||
            !grade.gpaIncluded;
        if (isPending) {
          list.add(SimulatedCourse(
            id: cid,
            name: course.name,
            credit: course.credit > 0 ? course.credit : 2.0,
            expectedFivePoint: 4.5,
            originalFivePoint: 4.5,
            isEnabled: true,
            isCustom: false,
          ));
        }
      }

      // 2. 若全部已出分，则载入当前学期已有成绩的课程供推演
      if (list.isEmpty && latest.grades.isNotEmpty) {
        for (final g in latest.grades.where((e) => e.gpaIncluded)) {
          list.add(SimulatedCourse(
            id: g.id,
            name: g.name,
            credit: g.credit,
            expectedFivePoint: g.fivePoint,
            originalFivePoint: g.fivePoint,
            isEnabled: true,
            isCustom: false,
          ));
        }
      }
    }

    // 3. 兜底示例课程
    if (list.isEmpty) {
      list.add(SimulatedCourse(
        id: 'sim_default_1',
        name: '模拟专业基础课',
        credit: 4.0,
        expectedFivePoint: 4.8,
        isCustom: true,
      ));
      list.add(SimulatedCourse(
        id: 'sim_default_2',
        name: '模拟专业核心课',
        credit: 3.5,
        expectedFivePoint: 4.5,
        isCustom: true,
      ));
      list.add(SimulatedCourse(
        id: 'sim_default_3',
        name: '模拟通识选修课',
        credit: 2.0,
        expectedFivePoint: 4.2,
        isCustom: true,
      ));
    }

    simulatedCourses.value = list;
    _saveSimulatedCoursesCache();
  }

  void _saveSimulatedCoursesCache() {
    try {
      final data =
          jsonEncode(simulatedCourses.map((e) => e.toJson()).toList());
      _db.optionsBox.put('simulated_courses_cache', data);
    } catch (e) {
      debugPrint('保存模拟课程缓存失败: $e');
    }
  }

  /// 获取历史有效成绩列表（若模拟课程中包含已有课程ID，则剔除原课，实现重修/提分替换）
  List<Grade> getBaseGrades() {
    final simulatedIds = {
      for (final c in simulatedCourses)
        if (c.isEnabled) c.id
    };
    final allGrades = scholar.value.grades.values
        .map((list) => list.first)
        .where((g) => g.gpaIncluded && !simulatedIds.contains(g.id))
        .toList();
    return allGrades;
  }

  /// 计算当前实际总 GPA
  Tuple<List<double>, double> calculateCurrentTotalGpa() {
    final base = scholar.value.grades.values
        .map((list) => list.first)
        .where((g) => g.gpaIncluded)
        .toList();
    if (base.isEmpty) {
      return Tuple([0.0, 0.0, 0.0, 0.0], 0.0);
    }
    return GpaHelper.calculateGpa(base);
  }

  /// 计算模拟后的总 GPA
  Tuple<List<double>, double> calculateSimulatedTotalGpa() {
    final base = getBaseGrades();
    final simulated = simulatedCourses
        .where((c) => c.isEnabled && c.credit > 0)
        .map((c) => c.toGrade())
        .toList();
    final combined = [...base, ...simulated];
    if (combined.isEmpty) {
      return Tuple([0.0, 0.0, 0.0, 0.0], 0.0);
    }
    return GpaHelper.calculateGpa(combined);
  }

  /// 计算模拟学期自身的学期 GPA
  Tuple<List<double>, double> calculateSimulatedSemesterGpa() {
    final simulated = simulatedCourses
        .where((c) => c.isEnabled && c.credit > 0)
        .map((c) => c.toGrade())
        .toList();
    if (simulated.isEmpty) {
      return Tuple([0.0, 0.0, 0.0, 0.0], 0.0);
    }
    return GpaHelper.calculateGpa(simulated);
  }

  /// 按当前选中的体制提取 GPA 数值
  double getGpaValue(List<double> gpas, GpaScaleType scale) {
    if (gpas.isEmpty) return 0.0;
    switch (scale) {
      case GpaScaleType.fivePoint:
        return gpas[0];
      case GpaScaleType.fourPointScale:
        return gpas[1];
      case GpaScaleType.legacyFourPoint:
        return gpas[2];
      case GpaScaleType.hundredPoint:
        return gpas[3];
    }
  }

  /// 计算模拟后相比当前实际 GPA 的差值
  double getGpaDelta(GpaScaleType scale) {
    final curr = getGpaValue(calculateCurrentTotalGpa().item1, scale);
    final sim = getGpaValue(calculateSimulatedTotalGpa().item1, scale);
    return sim - curr;
  }

  /// 目标逆推计算器：根据设定的 targetGpa，求解后续剩余学分需考到的平均绩点
  GoalSeekResult calculateGoalSeek() {
    final currResult = calculateCurrentTotalGpa();
    final currGpa = currResult.item1[0]; // 依据五分制测算
    final baseGrades = scholar.value.grades.values
        .map((list) => list.first)
        .where((g) => g.gpaIncluded)
        .toList();
    final currCredits = baseGrades.fold<double>(0.0, (p, e) => p + e.credit);

    final remainCredits = simulatedCourses
        .where((c) => c.isEnabled && c.credit > 0)
        .fold<double>(0.0, (p, e) => p + e.credit);

    if (remainCredits <= 0.0) {
      return const GoalSeekResult(
        hasCredits: false,
        isImpossible: false,
        isAlreadyAchieved: false,
        requiredGpa: 0,
        maxPossibleGpa: 0,
        remainingCredits: 0,
        message: '请先在下方勾选或添加待修课程，以计算目标所需绩点',
      );
    }

    final totalCredits = currCredits + remainCredits;
    final currPointSum = currGpa * currCredits;
    final target = targetGpa.value;
    final requiredGpa = (target * totalCredits - currPointSum) / remainCredits;
    final maxPossibleGpa =
        (currPointSum + 5.0 * remainCredits) / totalCredits;

    if (requiredGpa > 5.0) {
      return GoalSeekResult(
        hasCredits: true,
        isImpossible: true,
        isAlreadyAchieved: false,
        requiredGpa: requiredGpa,
        maxPossibleGpa: maxPossibleGpa,
        remainingCredits: remainCredits,
        message:
            '超出上限：即使剩余 ${remainCredits.toStringAsFixed(1)} 学分全部考满绩（5.0），最高也只能达到 ${maxPossibleGpa.toStringAsFixed(2)}。',
      );
    } else if (requiredGpa <= 1.5) {
      return GoalSeekResult(
        hasCredits: true,
        isImpossible: false,
        isAlreadyAchieved: true,
        requiredGpa: requiredGpa,
        maxPossibleGpa: maxPossibleGpa,
        remainingCredits: remainCredits,
        message:
            '当前基础极佳：剩余 ${remainCredits.toStringAsFixed(1)} 学分即便仅达到及格线（1.5 绩点），总绩点也能稳定达成 ${target.toStringAsFixed(2)} 目标！',
      );
    } else {
      final letter = Grade.fivePointToLetter(requiredGpa);
      return GoalSeekResult(
        hasCredits: true,
        isImpossible: false,
        isAlreadyAchieved: false,
        requiredGpa: requiredGpa,
        maxPossibleGpa: maxPossibleGpa,
        remainingCredits: remainCredits,
        message:
            '剩余 ${remainCredits.toStringAsFixed(1)} 学分平均需考到 ${requiredGpa.toStringAsFixed(2)} 绩点（约合 $letter 档），即可达成总 GPA ${target.toStringAsFixed(2)}。',
      );
    }
  }

  // ==================== 模拟课程操作 ====================

  /// 更新某门课程的期望成绩
  void setCourseScore(String id, double score) {
    final index = simulatedCourses.indexWhere((c) => c.id == id);
    if (index != -1) {
      simulatedCourses[index].expectedFivePoint = score;
      simulatedCourses.refresh();
      _saveSimulatedCoursesCache();
    }
  }

  /// 切换课程是否参与模拟
  void toggleCourseEnabled(String id) {
    final index = simulatedCourses.indexWhere((c) => c.id == id);
    if (index != -1) {
      simulatedCourses[index].isEnabled = !simulatedCourses[index].isEnabled;
      simulatedCourses.refresh();
      _saveSimulatedCoursesCache();
    }
  }

  /// 添加自定义模拟课程
  void addCustomCourse({
    required String name,
    required double credit,
    double expectedFivePoint = 4.5,
  }) {
    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    simulatedCourses.add(SimulatedCourse(
      id: newId,
      name: name.trim().isEmpty ? '自定义课程' : name.trim(),
      credit: credit > 0 ? credit : 1.0,
      expectedFivePoint: expectedFivePoint,
      originalFivePoint: expectedFivePoint,
      isEnabled: true,
      isCustom: true,
    ));
    _saveSimulatedCoursesCache();
  }

  /// 删除某门课程（限自定义课程或从列表移除）
  void removeCourse(String id) {
    simulatedCourses.removeWhere((c) => c.id == id);
    _saveSimulatedCoursesCache();
  }

  /// 一键预设所有启用课程的成绩
  void presetAllScores(double score) {
    for (final course in simulatedCourses) {
      if (course.isEnabled) {
        course.expectedFivePoint = score;
      }
    }
    simulatedCourses.refresh();
    _saveSimulatedCoursesCache();
  }

  /// 一键恢复所有课程的原始分数
  void resetSimulatedScores() {
    for (final course in simulatedCourses) {
      course.expectedFivePoint = course.originalFivePoint;
    }
    simulatedCourses.refresh();
    _saveSimulatedCoursesCache();
  }
}
