import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/zjuServices/zdbk.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/plan_audit_engine.dart';
import 'package:celechron/utils/json_utils.dart';

class CurriculumPlanController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  /// 方案目录全量列表（~3000 条）
  final catalog = <PlanSummary>[].obs;

  /// 当前选定的培养方案
  final selectedPlan = Rxn<PlanSummary>();

  /// 智能匹配结果与候选列表
  final matchResult = Rxn<PlanMatchResult>();

  /// 学籍画像（专业/学院/行政班/年级）
  final studentProfile = Rxn<StudentProfile>();
  final userMajor = ''.obs;
  final collegeName = ''.obs;
  final adminClass = ''.obs;
  final studentGrade = ''.obs;

  /// 已获学分总和 / 本学期在修学分
  final earnedCredits = 0.0.obs;
  final activeCredits = 0.0.obs;

  /// 外语等级（L1 / L2 / L3）及用户自定义覆盖
  final foreignLevel = 'L2'.obs;
  final customForeignCredits = RxnDouble();
  final customGraduationCredits = RxnDouble();

  /// 同步与 PDF 解析状态
  final isSyncing = false.obs;
  final syncError = RxnString();
  final isPdfLoading = false.obs;
  final pdfError = RxnString();
  final pdfPath = RxnString();
  final pdfSections = Rxn<PlanPdfSections>();

  /// Compass 审计引擎产出：PlanFile + 审计报告（三色状态 + 总学分 + 口径说明 + 警告）
  final planFile = Rxn<Map<String, dynamic>>();
  final auditReport = Rxn<Map<String, dynamic>>();

  /// 课程列表与实时四态映射
  final coreCourses = <String>[].obs;
  final practiceCourses = <String>[].obs;
  final honorCourses = <String>[].obs;
  final courseStates = <String, CompassCourseState>{}.obs;

  /// 全校方案搜索关键字
  final searchQuery = ''.obs;

  static const String _kSavedPlanIdKey = 'curriculum_saved_plan_id';
  static const String _kForeignLevelKey = 'curriculum_foreign_level';
  static const String _kCustomForeignCreditsKey =
      'curriculum_custom_foreign_credits';
  static const String _kCustomGraduationCreditsKey =
      'curriculum_custom_total_credits';

  bool _initialAutoSyncAttempted = false;

  @override
  void onInit() {
    super.onInit();
    loadProfileAndCatalog();

    ever(scholar, (_) {
      _loadProfile();
      _collectEvidence();
      if (catalog.isEmpty &&
          scholar.value.isLogan &&
          !_initialAutoSyncAttempted) {
        _initialAutoSyncAttempted = true;
        syncCatalog(silent: true);
      } else {
        _rebuildPlanAndAudit();
      }
    });
  }

  /// 有效最低毕业总学分（优先用户覆盖，其次审计引擎口径，再其次方案声明 zdbyxf）
  double get effectiveGraduationCredits {
    if (customGraduationCredits.value != null &&
        customGraduationCredits.value! > 0) {
      return customGraduationCredits.value!;
    }
    final totals = auditReport.value?['totals'];
    if (totals is Map && totals['required'] is num) {
      final v = (totals['required'] as num).toDouble();
      if (v > 0) return v;
    }
    return selectedPlan.value?.zdbyxf ?? 160.0;
  }

  /// 审计引擎统计已获学分；若尚未产生审计则回落到成绩单总已获学分
  double get auditEarnedCredits {
    final totals = auditReport.value?['totals'];
    if (totals is Map && totals['earned'] is num) {
      return (totals['earned'] as num).toDouble();
    }
    return earnedCredits.value;
  }

  /// 剩余学分缺口
  double get creditGap {
    final totals = auditReport.value?['totals'];
    if (totals is Map && totals['gap'] is num) {
      return (totals['gap'] as num).toDouble();
    }
    final gap = effectiveGraduationCredits - auditEarnedCredits;
    return gap > 0 ? gap : 0.0;
  }

  /// 学分达成比例（0.0 ~ 1.0）
  double get completionRate {
    final total = effectiveGraduationCredits;
    if (total <= 0) return 1.0;
    return (auditEarnedCredits / total).clamp(0.0, 1.0);
  }

  /// 外语模块有效要求学分（严格对齐 2026 级 L3 免修 / 往届封顶 3.0 口径）
  double get effectiveForeignCredits {
    if (customForeignCredits.value != null) {
      return customForeignCredits.value!;
    }
    final gradeYear = parseForeignGradeYear(studentGrade.value);
    return foreignCapForLevel(foreignLevel.value, gradeYear) ?? 3.0;
  }

  /// 过滤后的全校培养方案列表
  List<PlanSummary> get filteredCatalog {
    final q = searchQuery.value.trim().toLowerCase();
    final Iterable<PlanSummary> source = q.isEmpty
        ? catalog
        : catalog.where((p) {
            return p.zymc.toLowerCase().contains(q) ||
                p.xymc.toLowerCase().contains(q) ||
                p.synj.toLowerCase().contains(q) ||
                p.jxjhh.toLowerCase().contains(q) ||
                p.dlbsmc.toLowerCase().contains(q);
          });
    final list = source.toList()
      ..sort((a, b) {
        final gCmp = b.gradeYear.compareTo(a.gradeYear);
        if (gCmp != 0) return gCmp;
        return a.zymc.compareTo(b.zymc);
      });
    return list;
  }

  Future<void> loadProfileAndCatalog({bool silent = false}) async {
    _loadSavedPrefs();
    _loadProfile();
    _collectEvidence();
    _loadCachedCatalog();

    if (catalog.isEmpty && !silent) {
      _initialAutoSyncAttempted = true;
      await syncCatalog(silent: true);
    } else if (selectedPlan.value != null) {
      await _loadCachedPdfForPlan(selectedPlan.value!);
      await _rebuildPlanAndAudit();
    }
  }

  void _loadSavedPrefs() {
    final savedFl = _db.optionsBox.get(_kForeignLevelKey);
    if (savedFl is String &&
        (savedFl == 'L1' || savedFl == 'L2' || savedFl == 'L3')) {
      foreignLevel.value = savedFl;
    }
    final savedFc = _db.optionsBox.get(_kCustomForeignCreditsKey);
    if (savedFc is num) {
      customForeignCredits.value = savedFc.toDouble();
    }
    final savedGc = _db.optionsBox.get(_kCustomGraduationCreditsKey);
    if (savedGc is num) {
      customGraduationCredits.value = savedGc.toDouble();
    }
  }

  void _loadProfile() {
    final rawInfo = _db.getCachedWebPage('zdbk_student_info');
    if (rawInfo != null && rawInfo.trim().startsWith('{')) {
      try {
        final m = jsonDecode(rawInfo);
        if (m is Map) {
          final map = <String, dynamic>{};
          m.forEach((k, v) => map[k.toString()] = v);
          final profile = StudentProfile.fromJson(map);
          if (!profile.isEmpty) {
            studentProfile.value = profile;
            if (profile.majorName.isNotEmpty) {
              userMajor.value = Zdbk.normalizeMajorName(profile.majorName);
            }
            if (profile.college.isNotEmpty) {
              collegeName.value = profile.college;
            }
            if (profile.adminClass.isNotEmpty) {
              adminClass.value = profile.adminClass;
            }
            if (profile.grade != null && profile.grade!.isNotEmpty) {
              studentGrade.value = profile.grade!;
            }
          }
        }
      } catch (_) {}
    }

    if (studentGrade.value.isEmpty) {
      final gradeFromClass = gradeFromClassName(adminClass.value);
      if (gradeFromClass != null) {
        studentGrade.value = gradeFromClass;
      } else if (scholar.value.username?.isNotEmpty == true) {
        final inferred = Zdbk.inferGradeFromStudentId(scholar.value.username!);
        if (inferred != null) {
          studentGrade.value = inferred;
        }
      }
    }

    if (userMajor.value.isEmpty) {
      final cachedMajor = _db.getCachedWebPage('zdbk_user_major');
      if (cachedMajor != null && cachedMajor.trim().isNotEmpty) {
        userMajor.value = Zdbk.normalizeMajorName(cachedMajor.trim());
      }
    }
  }

  void _collectEvidence() {
    var earned = 0.0;
    for (final s in scholar.value.semesters) {
      for (final g in s.grades) {
        if (g.earnedCredit > 0) {
          earned += g.earnedCredit;
        }
      }
    }
    earnedCredits.value = earned;

    final currentCourses = scholar.value.semesters.isNotEmpty
        ? scholar.value.semesters.first.courses.values
        : const Iterable<Course>.empty();
    var active = 0.0;
    for (final c in currentCourses) {
      active += c.credit;
    }
    activeCredits.value = active;
  }

  void _loadCachedCatalog() {
    final cached = _db.getCachedWebPage('zdbk_training_plans');
    if (cached != null && cached.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        final rawItems =
            asDynamicList(decoded is Map ? decoded['items'] : decoded);
        if (rawItems != null && rawItems.isNotEmpty) {
          final list = <PlanSummary>[];
          for (final item in rawItems) {
            final m = asStringMap(item);
            if (m != null) list.add(PlanSummary.fromJson(m));
          }
          if (list.isNotEmpty) {
            catalog.value = list;
            _runMatching();
          }
        }
      } catch (_) {}
    }
  }

  /// 全量拉取学籍画像 + 方案目录，并在客户端打分匹配与下载官方 PDF
  Future<void> syncCatalog({bool silent = false}) async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    syncError.value = null;
    try {
      final profile = await scholar.value.fetchStudentProfile(refresh: !silent);
      if (profile != null && !profile.isEmpty) {
        studentProfile.value = profile;
        if (profile.majorName.isNotEmpty) {
          userMajor.value = Zdbk.normalizeMajorName(profile.majorName);
        }
        if (profile.college.isNotEmpty) {
          collegeName.value = profile.college;
        }
        if (profile.adminClass.isNotEmpty) {
          adminClass.value = profile.adminClass;
        }
        if (profile.grade != null && profile.grade!.isNotEmpty) {
          studentGrade.value = profile.grade!;
        }
      }

      final res =
          await scholar.value.fetchPlanCatalogWithError(refresh: !silent);
      if (res.item2.isNotEmpty) {
        catalog.value = res.item2;
        syncError.value = null;
        await _runMatching(downloadPdfIfMissing: true);
      } else {
        syncError.value = res.item1 ?? '未获取到任何培养方案数据';
      }
    } catch (e) {
      syncError.value = '同步培养方案异常: $e';
      if (kDebugMode) {
        debugPrint('syncCatalog failed: $e');
      }
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _runMatching({bool downloadPdfIfMissing = false}) async {
    if (catalog.isEmpty) return;

    final major = userMajor.value.isNotEmpty ? userMajor.value : '工科试验班';
    final result = matchPlans(
      catalog,
      majorName: major,
      grade: studentGrade.value.isNotEmpty ? studentGrade.value : null,
      maxCandidates: 20,
    );
    matchResult.value = result;

    final savedId = _db.optionsBox.get(_kSavedPlanIdKey);
    PlanSummary? planToUse;
    if (savedId is String && savedId.isNotEmpty) {
      planToUse = catalog.firstWhereOrNull((p) => p.id == savedId);
    }
    planToUse ??= result.bestPlan ?? catalog.first;

    await selectPlan(
      planToUse,
      persist: false,
      downloadPdfIfMissing: downloadPdfIfMissing,
    );
  }

  /// 切换培养方案，加载本地/在线官方 PDF，并重算三色审计与课程四态
  Future<void> selectPlan(
    PlanSummary plan, {
    bool persist = true,
    bool downloadPdfIfMissing = true,
  }) async {
    selectedPlan.value = plan;
    if (persist) {
      await _db.optionsBox.put(_kSavedPlanIdKey, plan.id);
    }

    coreCourses.value = plan.zyhxkc;
    practiceCourses.value = plan.zyhxsjkc;
    honorCourses.value = plan.qywkc;

    final loaded = await _loadCachedPdfForPlan(plan);
    if (!loaded && downloadPdfIfMissing) {
      await downloadAndParsePdf(target: plan, silent: true);
    } else {
      await _rebuildPlanAndAudit();
    }
  }

  Future<File> _pdfCacheFileFor(PlanSummary plan) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/curriculum_pdfs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final rawKey = plan.jxjhh.trim().isNotEmpty ? plan.jxjhh : plan.id;
    final safeKey = rawKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${dir.path}/plan_$safeKey.pdf');
  }

  Future<bool> _loadCachedPdfForPlan(PlanSummary plan) async {
    pdfError.value = null;
    try {
      final file = await _pdfCacheFileFor(plan);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 100) {
          final text = extractPdfText(bytes);
          final parsed = parsePlanPdfText(text);
          if (!parsed.isEmpty) {
            pdfPath.value = file.path;
            pdfSections.value = parsed;
            return true;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_loadCachedPdfForPlan error: $e');
      }
    }
    pdfPath.value = null;
    pdfSections.value = null;
    return false;
  }

  /// 下载官方培养方案 PDF 并运行 Compass 字体感知 PDF 解析器
  Future<void> downloadAndParsePdf({
    PlanSummary? target,
    bool silent = false,
  }) async {
    final plan = target ?? selectedPlan.value;
    if (plan == null || isPdfLoading.value) return;
    isPdfLoading.value = true;
    pdfError.value = null;

    List<Map<String, dynamic>>? fallbackCourseRows;
    try {
      final res = await scholar.value.fetchPlanPdf(plan);
      final bytes = res.item2;
      if (bytes != null && bytes.isNotEmpty) {
        final file = await _pdfCacheFileFor(plan);
        await file.writeAsBytes(bytes, flush: true);
        final text = extractPdfText(bytes);
        final parsed = parsePlanPdfText(text);
        pdfPath.value = file.path;
        pdfSections.value = parsed;
        if (parsed.isEmpty) {
          pdfError.value = 'PDF 已保存，但文本结构未识别，已按方案摘要口径核算';
        }
      } else {
        pdfError.value = res.item1 ?? '未能从教务网获取官方 PDF';
        fallbackCourseRows = await scholar.value.fetchPlanCourseTable(plan);
      }
    } catch (e) {
      pdfError.value = '下载或解析方案 PDF 失败: $e';
    } finally {
      await _rebuildPlanAndAudit(fallbackCourseRows: fallbackCourseRows);
      isPdfLoading.value = false;
    }
  }

  Future<void> openPdfWithSystem() async {
    final path = pdfPath.value;
    if (path == null || path.isEmpty) {
      await downloadAndParsePdf();
      return;
    }
    final title = '${selectedPlan.value?.zymc ?? '培养方案'}.pdf';
    await OhosNativeService.instance.openFileWithSystem(
      path,
      mimeType: 'application/pdf',
      title: title,
    );
  }

  Future<void> _rebuildPlanAndAudit({
    List<Map<String, dynamic>>? fallbackCourseRows,
  }) async {
    final plan = selectedPlan.value;
    final gradeStr = studentGrade.value.isNotEmpty
        ? studentGrade.value
        : (plan?.synj.isNotEmpty == true
            ? plan!.synj
            : '${DateTime.now().year}');
    final majorStr = userMajor.value.isNotEmpty
        ? userMajor.value
        : (plan?.zymc ?? '主修专业');

    final record = PlanAuditHelper.buildRecordFromScholar(
      scholar.value,
      majorName: majorStr,
      grade: gradeStr,
    );
    final uiActiveNames =
        (record['uiActiveNames'] as Set<String>?) ?? const <String>{};
    final transcriptRows =
        (record['courses'] as List).cast<Map<String, dynamic>>();

    Map<String, dynamic>? pf;
    final ps = pdfSections.value;
    if (plan != null && ps != null && !ps.isEmpty) {
      pf = planFileFromPdf(
        ps,
        major: majorStr,
        grade: gradeStr,
        totalCredits: customGraduationCredits.value ?? plan.zdbyxf,
        sourceDoc: '${plan.zymc} ${plan.synj}级官方培养方案',
        transcript: transcriptRows,
      );
    } else if (plan != null) {
      pf = PlanAuditHelper.planFileFromSummary(
        plan,
        courseRows: fallbackCourseRows ?? const [],
      );
    }

    if (pf != null &&
        customGraduationCredits.value != null &&
        customGraduationCredits.value! > 0) {
      final meta = Map<String, dynamic>.from(pf['meta'] as Map? ?? const {});
      meta['total_credits'] = customGraduationCredits.value;
      pf['meta'] = meta;
    }
    planFile.value = pf;

    if (pf != null) {
      try {
        final action = <String, dynamic>{
          if (customForeignCredits.value != null)
            'foreign_lang_credits': customForeignCredits.value
          else
            'foreign_lang_level': foreignLevel.value,
        };
        auditReport.value = AuditEngine(const {}).build(
          record,
          pf,
          action: action,
          uiActiveNames: uiActiveNames,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('AuditEngine build error: $e');
        }
      }
    } else {
      auditReport.value = null;
    }

    final allCourseNames = <String>{
      ...coreCourses,
      ...practiceCourses,
      ...honorCourses,
      if (ps != null)
        for (final sec in ps.sections)
          for (final c in sec.courses) c.name,
    };
    courseStates.value = PlanAuditHelper.computeCourseStates(
      scholar: scholar.value,
      courseNames: allCourseNames,
      auditReport: auditReport.value,
      transcriptRows: transcriptRows,
    );
  }

  /// 重置为智能算法推荐方案
  Future<void> resetToAutoMatch() async {
    await _db.optionsBox.delete(_kSavedPlanIdKey);
    final best = matchResult.value?.bestPlan;
    if (best != null) {
      await selectPlan(best, persist: false);
    }
  }

  void setForeignLevel(String level) {
    foreignLevel.value = level;
    _db.optionsBox.put(_kForeignLevelKey, level);
    _rebuildPlanAndAudit();
  }

  void setCustomForeignCredits(double? val) {
    customForeignCredits.value = val;
    if (val != null) {
      _db.optionsBox.put(_kCustomForeignCreditsKey, val);
    } else {
      _db.optionsBox.delete(_kCustomForeignCreditsKey);
    }
    _rebuildPlanAndAudit();
  }

  void setCustomGraduationCredits(double? val) {
    customGraduationCredits.value = val;
    if (val != null) {
      _db.optionsBox.put(_kCustomGraduationCreditsKey, val);
    } else {
      _db.optionsBox.delete(_kCustomGraduationCreditsKey);
    }
    _rebuildPlanAndAudit();
  }
}
