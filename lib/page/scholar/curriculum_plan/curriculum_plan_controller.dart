import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/curriculum_matching_engine.dart';
import 'package:celechron/utils/json_utils.dart';
import 'package:celechron/http/zjuServices/zdbk.dart';

class CurriculumPlanController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  /// 方案目录全量列表（~3000 条）
  final catalog = <PlanSummary>[].obs;

  /// 当前选定的培养方案
  final selectedPlan = Rxn<PlanSummary>();

  /// 智能匹配结果与候选列表
  final matchResult = Rxn<PlanMatchResult>();

  /// 学生所属主修专业
  final userMajor = ''.obs;

  /// 学生行政班级（如：工科试验班（计算机）2606）
  final adminClass = ''.obs;

  /// 从行政班或学号解析得出的入学年级（如：2026）
  final studentGrade = ''.obs;

  /// 学生已修与在修课程的四态证据库
  final evidence = <String, PlanCourseState>{}.obs;

  /// 已修完并获得的有效学分总和
  final earnedCredits = 0.0.obs;

  /// 本学期正在修读的学分总和
  final activeCredits = 0.0.obs;

  /// 外语等级（L1 / L2 / L3）
  final foreignLevel = 'L2'.obs;

  /// 用户自定义外语学分覆盖（若非空则强制生效）
  final customForeignCredits = RxnDouble();

  /// 用户自定义毕业总学分（若设置则覆盖方案默认）
  final customGraduationCredits = RxnDouble();

  /// 正在同步目录数据
  final isSyncing = false.obs;

  /// 专业核心课列表
  final coreCourses = <String>[].obs;

  /// 核心实践课列表
  final practiceCourses = <String>[].obs;

  /// 前沿/荣誉课列表
  final honorCourses = <String>[].obs;

  /// 各课程的实时四态映射
  final courseStates = <String, PlanCourseState>{}.obs;

  static const String _kSavedPlanIdKey = 'curriculum_saved_plan_id';
  static const String _kForeignLevelKey = 'curriculum_foreign_level';
  static const String _kCustomForeignCreditsKey = 'curriculum_custom_foreign_credits';
  static const String _kCustomGraduationCreditsKey = 'curriculum_custom_total_credits';

  @override
  void onInit() {
    super.onInit();
    loadProfileAndCatalog();

    ever(scholar, (_) {
      loadProfileAndCatalog(silent: true);
    });
  }

  /// 目标毕业学分计算
  double get effectiveGraduationCredits {
    if (customGraduationCredits.value != null &&
        customGraduationCredits.value! > 0) {
      return customGraduationCredits.value!;
    }
    return selectedPlan.value?.zdbyxf ?? 160.0;
  }

  /// 外语模块有效要求学分计算（依据 2026 规则引擎）
  double get effectiveForeignCredits {
    final gradeYear = int.tryParse(studentGrade.value);
    return ForeignLanguageRule.getRequiredCredits(
      gradeYear: gradeYear,
      level: foreignLevel.value,
      customCredits: customForeignCredits.value,
      fallbackCredits: 3.0,
    );
  }

  /// 剩余学分缺口
  double get creditGap {
    final gap = effectiveGraduationCredits - earnedCredits.value;
    return gap > 0 ? gap : 0.0;
  }

  /// 学分达成比例（0.0 ~ 1.0）
  double get completionRate {
    final total = effectiveGraduationCredits;
    if (total <= 0) return 1.0;
    return (earnedCredits.value / total).clamp(0.0, 1.0);
  }

  /// 加载学籍画像、四态证据与方案目录
  Future<void> loadProfileAndCatalog({bool silent = false}) async {
    try {
      _loadPreferences();
      _extractStudentProfile();
      _collectEvidence();
      _loadCachedCatalog();

      if (catalog.isEmpty || scholar.value.isLogan) {
        await syncCatalog(silent: silent);
      } else {
        _runMatching();
      }
    } catch (e) {
      debugPrint('CurriculumPlanController loadProfileAndCatalog failed: $e');
    }
  }

  void _loadPreferences() {
    try {
      final lvl = _db.optionsBox.get(_kForeignLevelKey);
      if (lvl is String && lvl.isNotEmpty) {
        foreignLevel.value = lvl;
      }
      final customForeign = _db.optionsBox.get(_kCustomForeignCreditsKey);
      if (customForeign is num) {
        customForeignCredits.value = customForeign.toDouble();
      }
      final customTotal = _db.optionsBox.get(_kCustomGraduationCreditsKey);
      if (customTotal is num) {
        customGraduationCredits.value = customTotal.toDouble();
      }
    } catch (_) {}
  }

  void _extractStudentProfile() {
    // 1. 尝试从学生信息缓存提取行政班与专业
    final studentInfoStr = _db.getCachedWebPage('zdbk_student_info');
    if (studentInfoStr != null && studentInfoStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(studentInfoStr);
        final map = asStringMap(decoded);
        if (map != null) {
          final cls = map['xzb'] ?? map['bh'] ?? map['bj'] ?? map['adminClass'];
          if (cls is String && cls.isNotEmpty) {
            adminClass.value = cls.trim();
          }
          final zy = Zdbk.extractMajorFromKeyValues(map);
          if (zy != null && zy.isNotEmpty) {
            userMajor.value = Zdbk.normalizeMajorName(zy);
          }
        }
      } catch (_) {}
    }

    // 2. 年级推导（优先从行政班尾四位的前两位提取）
    final gradeFromClass = gradeFromClassName(adminClass.value);
    if (gradeFromClass != null) {
      studentGrade.value = gradeFromClass;
    } else if (scholar.value.username?.isNotEmpty == true) {
      final inferred = Zdbk.inferGradeFromStudentId(scholar.value.username!);
      if (inferred != null) {
        studentGrade.value = inferred;
      }
    }

    // 3. 若专业为空，尝试从历史专业缓存提取
    if (userMajor.value.isEmpty) {
      final cachedMajor = _db.getCachedWebPage('zdbk_user_major');
      if (cachedMajor != null && cachedMajor.trim().isNotEmpty) {
        userMajor.value = Zdbk.normalizeMajorName(cachedMajor.trim());
      }
    }
  }

  void _collectEvidence() {
    final grades = <Grade>[];
    for (final s in scholar.value.semesters) {
      grades.addAll(s.grades);
    }

    final currentCourses = scholar.value.semesters.isNotEmpty
        ? scholar.value.semesters.first.courses.values.toList()
        : const <Course>[];
    evidence.value = collectCourseStateEvidence(
      grades: grades,
      currentSemesterCourses: currentCourses,
    );

    // 计算已获学分总额
    var earned = 0.0;
    for (final g in grades) {
      if (g.earnedCredit > 0) {
        earned += g.earnedCredit;
      }
    }
    earnedCredits.value = earned;

    // 计算当前在修学分
    var active = 0.0;
    for (final c in currentCourses) {
      active += c.credit;
    }
    activeCredits.value = active;
  }

  void _loadCachedCatalog() {
    final cached = _db.getCachedWebPage('zdbk_training_plans');
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        final rawItems = asDynamicList(decoded is Map ? decoded['items'] : decoded);
        if (rawItems != null && rawItems.isNotEmpty) {
          final list = <PlanSummary>[];
          for (final item in rawItems) {
            final m = asStringMap(item);
            if (m != null) list.add(PlanSummary.fromJson(m));
          }
          catalog.value = list;
          _runMatching();
        }
      } catch (_) {}
    }
  }

  /// 全量拉取方案目录并在客户端打分匹配
  Future<void> syncCatalog({bool silent = false}) async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    try {
      final remoteList = await scholar.value.fetchPlanCatalog();
      if (remoteList.isNotEmpty) {
        catalog.value = remoteList;
      }
      _runMatching();
    } catch (e) {
      debugPrint('syncCatalog failed: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  void _runMatching() {
    if (catalog.isEmpty) return;

    final major = userMajor.value.isNotEmpty ? userMajor.value : '工科试验班';
    final result = matchPlans(
      catalog,
      majorName: major,
      grade: studentGrade.value.isNotEmpty ? studentGrade.value : null,
      maxCandidates: 16,
    );
    matchResult.value = result;

    // 优先检查用户曾经手动保存的方案 ID
    final savedId = _db.optionsBox.get(_kSavedPlanIdKey);
    PlanSummary? planToUse;
    if (savedId is String && savedId.isNotEmpty) {
      planToUse = catalog.firstWhereOrNull((p) => p.id == savedId);
    }
    planToUse ??= result.bestPlan ?? catalog.first;

    selectPlan(planToUse, persist: false);
  }

  /// 切换方案并重新核算核心课程与修读四态
  void selectPlan(PlanSummary plan, {bool persist = true}) {
    selectedPlan.value = plan;
    if (persist) {
      _db.optionsBox.put(_kSavedPlanIdKey, plan.id);
    }

    coreCourses.value = plan.zyhxkc;
    practiceCourses.value = plan.zyhxsjkc;
    honorCourses.value = plan.qywkc;

    final allNames = <String>{
      ...plan.zyhxkc,
      ...plan.zyhxsjkc,
      ...plan.qywkc,
    };

    final states = <String, PlanCourseState>{};
    for (final name in allNames) {
      states[name] = resolveCourseState(name, evidence);
    }
    courseStates.value = states;
  }

  /// 重置为智能算法推荐方案
  void resetToAutoMatch() {
    _db.optionsBox.delete(_kSavedPlanIdKey);
    final best = matchResult.value?.bestPlan;
    if (best != null) {
      selectPlan(best, persist: false);
    }
  }

  void setForeignLevel(String level) {
    foreignLevel.value = level;
    _db.optionsBox.put(_kForeignLevelKey, level);
  }

  void setCustomForeignCredits(double? val) {
    customForeignCredits.value = val;
    if (val != null) {
      _db.optionsBox.put(_kCustomForeignCreditsKey, val);
    } else {
      _db.optionsBox.delete(_kCustomForeignCreditsKey);
    }
  }

  void setCustomGraduationCredits(double? val) {
    customGraduationCredits.value = val;
    if (val != null) {
      _db.optionsBox.put(_kCustomGraduationCreditsKey, val);
    } else {
      _db.optionsBox.delete(_kCustomGraduationCreditsKey);
    }
  }
}
