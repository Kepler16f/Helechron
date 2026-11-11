import 'package:celechron/model/course.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/curriculum_matching_engine.dart'
    as legacy_match;
import 'package:celechron/services/plan_audit/course_state.dart'
    as compass_state;
import 'package:celechron/services/plan_audit/matching.dart' as compass_match;

export 'package:celechron/services/plan_audit/audit.dart'
    show
        AuditEngine,
        ModuleGroupRule,
        foreignCapForLevel,
        kForeignLangCaps,
        kForeignLangCaps2026,
        kForeignNewRuleGradeYear;
export 'package:celechron/services/plan_audit/course_state.dart'
    show
        PlanCourseEvidence,
        choosedCourseTranscriptState,
        collectPlanCourseEvidence,
        courseStateLabel,
        resolvePassedNames,
        resolvePlanCourseStates;
export 'package:celechron/services/plan_audit/foreign_grade_rule.dart';
export 'package:celechron/services/plan_audit/plan_audit_adapter.dart'
    show
        ChoiceRule,
        applyPlanCategories,
        certifiedCategoryOf,
        coursesCategoryMap,
        planFileFromPdf;
export 'package:celechron/services/plan_pdf_extractor.dart' show extractPdfText;
export 'package:celechron/services/plan_pdf_parser.dart';

typedef CompassCourseState = compass_state.PlanCourseState;

extension CompassCourseStateX on compass_state.PlanCourseState {
  bool get isEarned => this == compass_state.PlanCourseState.earned;
  bool get isActive => this == compass_state.PlanCourseState.active;
  bool get isNoCredit => this == compass_state.PlanCourseState.noCredit;
  bool get isUnknown => this == compass_state.PlanCourseState.unknown;
  String get label => compass_state.courseStateLabel(this);
}

class PlanAuditHelper {
  /// 从选课课号 xkkh 提取课程代码，如 `(2025-2026-1)-MARX1004G-0012345-1` -> `MARX1004G`
  static String extractCourseCode(String xkkh) {
    final trimmed = xkkh.trim();
    if (trimmed.isEmpty) return '';
    final m = RegExp(r'^\([^)]+\)-([A-Za-z0-9]+)-').firstMatch(trimmed);
    if (m != null) return m.group(1)!.trim();
    if (!trimmed.contains('(') && RegExp(r'^[A-Za-z]{2,8}\d+').hasMatch(trimmed)) {
      return trimmed;
    }
    return '';
  }

  /// 将 PDF/教务中的原始学期格式归一化为易读中文（参考 compass_app）
  static String prettySemester(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final normalized = t
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll(' ', '');
    final m = RegExp(r'^([一二三四五六1-6])(?:\(([^)]+)\))?$')
        .firstMatch(normalized);
    if (m != null) {
      const yearMap = {
        '一': '大一',
        '1': '大一',
        '二': '大二',
        '2': '大二',
        '三': '大三',
        '3': '大三',
        '四': '大四',
        '4': '大四',
        '五': '大五',
        '5': '大五',
        '六': '大六',
        '6': '大六',
      };
      final y = yearMap[m.group(1)!] ?? m.group(1)!;
      final term = m.group(2) ?? '';
      return term.isEmpty ? y : '$y$term';
    }
    return t;
  }

  /// 当前学期标记，如 `2026-A`（秋冬）或 `2026-B`（春夏），匹配 Timeline.semIdx 口径
  static String currentCompassSemester() {
    final now = DateTime.now();
    if (now.month >= 8) {
      return '${now.year}-A';
    }
    if (now.month == 1) {
      return '${now.year - 1}-A';
    }
    return '${now.year - 1}-B';
  }

  /// 构造 Compass AuditEngine 所需的成绩单与在修记录结构
  static Map<String, dynamic> buildRecordFromScholar(
    Scholar scholar, {
    required String majorName,
    required String grade,
  }) {
    final rows = <Map<String, dynamic>>[];
    final plannedRows = <Map<String, dynamic>>[];
    final uiActiveNames = <String>{};

    final yearNum = int.tryParse(grade.trim()) ?? DateTime.now().year;
    final safeGrade = '$yearNum';

    for (final sem in scholar.semesters) {
      for (final g in sem.grades) {
        final name = g.name.trim();
        if (name.isEmpty) continue;
        final code = extractCourseCode(g.id);
        final passed = _isGradePassed(g);
        rows.add(<String, dynamic>{
          'course_id': code,
          'name': name,
          'credits': g.credit,
          'grade': g.hundredPoint.toDouble(),
          'original': g.original,
          'passed': passed,
          'credit_included': g.creditIncluded,
          'category': g.category,
          'semester': sem.name,
        });
      }
    }

    // 首学期视作当前学期在修课表，剔除已经出正式成绩的课程后放入 planned_courses / uiActiveNames
    final currentCourses = scholar.semesters.isNotEmpty
        ? scholar.semesters.first.courses.values
        : const Iterable<Course>.empty();
    final curSemStr = currentCompassSemester();
    for (final c in currentCourses) {
      final cname = c.name.trim();
      if (cname.isEmpty) continue;
      uiActiveNames.add(cname);
      final code = extractCourseCode(c.id ?? '');
      final hasCreditRecord = c.grade != null && _isGradePassed(c.grade!);
      if (!hasCreditRecord) {
        plannedRows.add(<String, dynamic>{
          'course_id': code,
          'name': cname,
          'credits': c.credit,
          'semester': curSemStr,
        });
      }
    }

    return <String, dynamic>{
      'student': <String, dynamic>{
        'student_id': scholar.username ?? '',
        'major': majorName,
        'grade': safeGrade,
        'current_semester': curSemStr,
      },
      'courses': rows,
      'planned_courses': plannedRows,
      'uiActiveNames': uiActiveNames,
    };
  }

  static bool _isGradePassed(Grade g) {
    if (!g.creditIncluded) return false;
    if (g.fivePoint > 0 || g.hundredPoint >= 60) return true;
    final orig = g.original.trim().toUpperCase();
    return orig == '合格' ||
        orig == '通过' ||
        orig == '免修' ||
        orig == '及格' ||
        orig == '中等' ||
        orig == '良好' ||
        orig == '优秀' ||
        g.id.contains('xtwkc');
  }

  /// 计算四态课程映射（优先使用 PDF 解析模块树与成绩单，兼容原有核心课展示）
  static Map<String, CompassCourseState> computeCourseStates({
    required Scholar scholar,
    required Iterable<String> courseNames,
    Map<String, dynamic>? auditReport,
    List<Map<String, dynamic>>? transcriptRows,
  }) {
    final rows = transcriptRows ??
        (buildRecordFromScholar(
          scholar,
          majorName: '',
          grade: '${DateTime.now().year}',
        )['courses'] as List<Map<String, dynamic>>);

    final activeCourses = scholar.semesters.isNotEmpty
        ? scholar.semesters.first.courses.values.map((c) => c.name).toList()
        : const <String>[];

    final reportPlanCourses = <Map<String, dynamic>>[];
    if (auditReport != null && auditReport['summary'] is List) {
      for (final m in (auditReport['summary'] as List)) {
        if (m is Map && m['plan_courses'] is List) {
          for (final pc in (m['plan_courses'] as List)) {
            if (pc is Map<String, dynamic>) {
              reportPlanCourses.add(pc);
            } else if (pc is Map) {
              reportPlanCourses.add(Map<String, dynamic>.from(pc));
            }
          }
        }
      }
    }

    final ev = compass_state.collectPlanCourseEvidence(
      transcript: rows,
      timetableNames: activeCourses,
      reportPlanCourses: reportPlanCourses,
    );
    return compass_state.resolvePlanCourseStates(courseNames, ev);
  }

  /// 基于方案摘要 + 可选教务课程明细构建兜底 PlanFile（PDF 尚未下载时使用）
  static Map<String, dynamic> planFileFromSummary(
    PlanSummary summary, {
    List<Map<String, dynamic>> courseRows = const [],
  }) {
    final modules = <Map<String, dynamic>>[];
    final courses = <Map<String, dynamic>>[];
    final seenCourseKeys = <String>{};

    if (courseRows.isNotEmpty) {
      final modMap = <String, List<Map<String, dynamic>>>{};
      for (final r in courseRows) {
        final name = '${r['kcmc'] ?? r['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final code = '${r['kch'] ?? r['course_id'] ?? ''}'.trim();
        final cr = double.tryParse('${r['xf'] ?? r['credits'] ?? 0}') ?? 0.0;
        final modName =
            '${r['kcxzmc'] ?? r['kclbmc'] ?? r['module'] ?? '专业课程'}'.trim();
        final bucket = modName.isEmpty ? '专业课程' : modName;
        modMap.putIfAbsent(bucket, () => []).add(<String, dynamic>{
          'course_id': code,
          'name': name,
          'credits': cr,
          'nature': '${r['kcxzmc'] ?? r['nature'] ?? ''}'.trim(),
          'offered': null,
          'grade_cycle': null,
          'offered_years': null,
          'prereq': const <String>[],
        });
      }
      var idx = 0;
      for (final e in modMap.entries) {
        idx++;
        final mid = 'summary_mod_$idx';
        final sumCr = e.value.fold<double>(
            0, (s, c) => s + ((c['credits'] as num?)?.toDouble() ?? 0));
        final ids = <String>[];
        for (final c in e.value) {
          final cid = '${c['course_id']}'.trim().isNotEmpty
              ? '${c['course_id']}'.trim()
              : '${c['name']}';
          if (seenCourseKeys.add('$mid|$cid')) {
            ids.add(cid);
            courses.add(<String, dynamic>{
              ...c,
              'course_id': cid,
              'module_id': mid,
            });
          }
        }
        modules.add(<String, dynamic>{
          'module_id': mid,
          'module_path': e.key,
          'title': e.key,
          'level': 2,
          'category': e.key,
          'required_credits': sumCr,
          'plan_credits_raw': sumCr.toStringAsFixed(1),
          'plan_credits_unit': '学分',
          'course_ids': ids,
          'notes': const <String>[],
        });
      }
    }

    if (modules.isEmpty) {
      // 由摘要核心课 / 核心实践课 / 前沿课构造基础模块用于审计兜底
      void addSummaryBucket(
          String id, String title, List<String> names, double reqCredits) {
        if (names.isEmpty && reqCredits <= 0) return;
        final ids = <String>[];
        for (final n in names) {
          final clean = n.trim();
          if (clean.isEmpty || !seenCourseKeys.add('$id|$clean')) continue;
          ids.add(clean);
          courses.add(<String, dynamic>{
            'course_id': '',
            'name': clean,
            'credits': 0.0,
            'module_id': id,
            'nature': title,
            'offered': null,
            'grade_cycle': null,
            'offered_years': null,
            'prereq': const <String>[],
          });
        }
        modules.add(<String, dynamic>{
          'module_id': id,
          'module_path': title,
          'title': title,
          'level': 2,
          'category': title,
          'required_credits': reqCredits,
          'plan_credits_raw': reqCredits.toStringAsFixed(1),
          'plan_credits_unit': '学分',
          'course_ids': ids,
          'notes': const <String>[],
        });
      }

      addSummaryBucket(
          'major_core', '专业核心课程', summary.zyhxkc, 0.0);
      addSummaryBucket(
          'intensive_practice', '专业核心实践环节', summary.zyhxsjkc, 0.0);
      addSummaryBucket(
          'frontier', '前沿与荣誉课程', summary.qywkc, 0.0);
      final ptSum = (summary.dektxf ?? 0) +
          (summary.dektxf3 ?? 0) +
          (summary.dektxf4 ?? 0);
      if (ptSum > 0) {
        modules.add(<String, dynamic>{
          'module_id': 'practice_points',
          'module_path': '第二/三/四课堂',
          'title': '第二/三/四课堂',
          'level': 1,
          'category': '第二/三/四课堂',
          'required_credits': ptSum,
          'plan_credits_raw': ptSum.toStringAsFixed(1),
          'plan_credits_unit': '学分',
          'course_ids': const <String>[],
          'notes': const <String>[],
        });
      }
    }

    return <String, dynamic>{
      'meta': <String, dynamic>{
        'major': summary.zymc,
        'grade': summary.synj,
        'source_doc': '教务方案摘要（${summary.zymc} ${summary.synj}级）',
        'total_credits': summary.zdbyxf,
        'extracted_by': 'helechron.planFileFromSummary',
        'verified': false,
        'quality': const <String>[
          '当前展示基于教务培养方案摘要接口；点击下方「下载并解析官方 PDF 方案」可获取完整四级模块与每门必修课清单。',
        ],
      },
      'modules': modules,
      'courses': courses,
    };
  }

  /// 将旧版 CourseVariant 匹配桥接到 Compass 统一逻辑
  static String? matchVariant(String target, List<String> candidates) =>
      compass_match.bestVariantAwareMatch(target, candidates) ??
      legacy_match.bestVariantAwareMatch(target, candidates);
}
