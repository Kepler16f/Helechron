import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/curriculum_matching_engine.dart';
import 'package:celechron/services/plan_audit_engine.dart';

void main() {
  group('CurriculumPlan 行政班与年级解析测试', () {
    test('行政班末四位推导年级（取前两位 + 2000，防把 2606 读成 2006）', () {
      expect(gradeFromClassName('工科试验班（计算机）2606'), '2026');
      expect(gradeFromClassName('人工智能2501班'), '2025');
      expect(gradeFromClassName('软件工程2402'), '2024');
      expect(gradeFromClassName('求是科学班2301'), '2023');
      expect(gradeFromClassName('普通无班号专业'), isNull);
    });
  });

  group('CurriculumPlan 培养方案匹配打分算法测试', () {
    final catalog = [
      PlanSummary(
        id: 'p1',
        jxjhh: '202601',
        zymc: '计算机科学与技术',
        synj: '2026',
        dlbsmc: '主修专业方案',
        zdbyxf: 160.0,
      ),
      PlanSummary(
        id: 'p2',
        jxjhh: '202501',
        zymc: '计算机科学与技术',
        synj: '2025',
        dlbsmc: '主修专业方案',
        zdbyxf: 160.0,
      ),
      PlanSummary(
        id: 'p3',
        jxjhh: '202602',
        zymc: '计算机科学与技术（拔尖班）',
        synj: '2026',
        dlbsmc: '主修专业方案',
        zdbyxf: 165.0,
      ),
      PlanSummary(
        id: 'p4',
        jxjhh: '202701',
        zymc: '计算机科学与技术',
        synj: '2027',
        dlbsmc: '主修专业方案',
        zdbyxf: 160.0,
      ),
      PlanSummary(
        id: 'p5',
        jxjhh: '202603',
        zymc: '机械工程',
        synj: '2026',
        dlbsmc: '主修专业方案',
        zdbyxf: 160.0,
      ),
    ];

    test('全称完全一致且同年级时获得最高分', () {
      final res = matchPlans(catalog, majorName: '计算机科学与技术', grade: '2026');
      expect(res.candidates, isNotEmpty);
      expect(res.candidates.first.plan.id, 'p1');
      expect(res.candidates.first.level, PlanMatchLevel.exact);
      expect(res.candidates.first.gradeMatch, isTrue);
    });

    test('往届方案按年级差距递减，未来年级获得惩罚（严防错套高年级新方案）', () {
      final res = matchPlans(catalog, majorName: '计算机科学与技术', grade: '2026');
      final p2Candidate = res.candidates.firstWhere((c) => c.plan.id == 'p2');
      final p4Candidate = res.candidates.firstWhere((c) => c.plan.id == 'p4');
      expect(p2Candidate.score > p4Candidate.score, isTrue);
    });

    test('多条相近或方向班方案时触发歧义检测（绝不替用户盲选）', () {
      final res = matchPlans(catalog, majorName: '计算机科学与技术', grade: '2026');
      // 同年级存在 p1(全称) 与 p3(前缀)，两者均达到强匹配
      expect(res.ambiguous, isTrue);
      expect(res.notes.any((n) => n.contains('相近方向')), isTrue);
    });
  });

  group('CurriculumPlan 课程变体签名与变体安全匹配测试', () {
    test('变体签名提取', () {
      expect(courseVariantSignature('大学英语(I)'), '1');
      expect(courseVariantSignature('大学英语（II）'), '2');
      expect(courseVariantSignature('大学英语(III)'), '3');
      expect(courseVariantSignature('高等数学(H)'), 'H');
      expect(courseVariantSignature('微积分（甲）1'), '1|A');
      expect(courseVariantSignature('微积分（乙）2'), '2|B');
      expect(courseVariantSignature('普通物理学'), '');
    });

    test('变体签名冲突时直接排除，严防英语I/II/H串级误判', () {
      const candidates = ['大学英语(I)', '大学英语(II)', '大学英语(III)', '大学英语(H)'];

      // 修了英语 I，绝不模糊匹配到 英语 II 或 H！
      expect(bestVariantAwareMatch('大学英语(I)', candidates), '大学英语(I)');
      expect(bestVariantAwareMatch('大学英语(II)', candidates), '大学英语(II)');
      expect(bestVariantAwareMatch('大学英语(H)', candidates), '大学英语(H)');
    });
  });

  group('CurriculumPlan 2026 级外语应修学分动态规则引擎测试', () {
    test('2026 级起 L3 免修政策（应修学分强制为 0.0）', () {
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2026, level: 'L3'),
        0.0,
      );
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2027, level: 'L3'),
        0.0,
      );
      expect(
        ForeignLanguageRule.isExemptByGrade(gradeYear: 2026, level: 'L3'),
        isTrue,
      );
    });

    test('2026 级前老生 L3 按封顶 3.0 学分口径，不享受免修', () {
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2025, level: 'L3'),
        3.0,
      );
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2024, level: 'L3'),
        3.0,
      );
      expect(
        ForeignLanguageRule.isExemptByGrade(gradeYear: 2025, level: 'L3'),
        isFalse,
      );
    });

    test('L1 与 L2 各年级均要求必修大学英语IV（6.0 与 4.5 学分）', () {
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2026, level: 'L1'),
        6.0,
      );
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2026, level: 'L2'),
        4.5,
      );
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2025, level: 'L1'),
        6.0,
      );
      expect(
        ForeignLanguageRule.getRequiredCredits(gradeYear: 2025, level: 'L2'),
        4.5,
      );
    });

    test('用户自选学分优先级最高', () {
      expect(
        ForeignLanguageRule.getRequiredCredits(
          gradeYear: 2026,
          level: 'L3',
          customCredits: 1.5,
        ),
        1.5,
      );
    });
  });

  group('CurriculumPlan 选课组约束与学分有效折算测试', () {
    test('N选M全量和指纹校验：4选1且全量和等于要求学分时取最便宜课程折算', () {
      final effective = GroupRuleHelper.effectiveRequiredCredits(
        rawRequiredCredits: 10.0, // 2+2.5+2.5+3 = 10
        courseCredits: [2.0, 2.5, 2.5, 3.0],
        nSelect: 1,
      );
      // 取最便宜的 1 门 = 2.0
      expect(effective, 2.0);
    });

    test('普通无选课组模块保持原要求学分', () {
      final effective = GroupRuleHelper.effectiveRequiredCredits(
        rawRequiredCredits: 8.0,
        courseCredits: [2.0, 2.0, 2.0, 2.0],
        nSelect: null,
      );
      expect(effective, 8.0);
    });
  });

  group('Compass PDF 培养方案解析与三色学业审计引擎测试', () {
    const samplePdfText = '''
一、通识课程 14学分
1.通识必修课程 14学分
(1)思政类 14学分
1)必修课程 12学分
课程号 课程名称 学分 周学时 总学时 建议学年学期
MARX1004G 大学生思想文化素养 2.0 2.0-0.0 32 一(秋冬)
MARX2001G 马克思主义基本原理 3.0 3.0-0.0 48 二(春夏)
2)选修课程 2学分
在思政类“选择性必修课程”中至少修读2学分。
二、专业课程 10学分
1.专业核心课程 10学分
课程号 课程名称 学分 周学时 总学时 建议学年学期
CS1001M 数据结构基础 4.0 3.0-2.0 64 一(春夏)
CS2002M 操作系统 4.0 3.0-2.0 64 二(秋冬)
CS2003M 计算机组成 4.0 3.0-2.0 64 二(秋冬)
''';

    test('parsePlanPdfText + planFileFromPdf 正确构建四级树与叶子优先学分', () {
      final sections = parsePlanPdfText(samplePdfText);
      expect(sections.isEmpty, isFalse);
      expect(sections.topCount, 2);
      expect(sections.courseCount, 5);

      final plan = planFileFromPdf(
        sections,
        major: '计算机科学与技术',
        grade: '2026',
        totalCredits: 24.0,
      );
      final modules = plan['modules'] as List;
      final courses = plan['courses'] as List;
      expect(modules, isNotEmpty);
      expect(courses.length, 5);
    });

    test('AuditEngine.build 产出精准三色模块统计与 totals', () {
      final sections = parsePlanPdfText(samplePdfText);
      final plan = planFileFromPdf(
        sections,
        major: '计算机科学与技术',
        grade: '2026',
        totalCredits: 24.0,
      );
      final record = <String, dynamic>{
        'student': {
          'student_id': '3260100001',
          'major': '计算机科学与技术',
          'grade': '2026',
          'current_semester': '2026-A',
        },
        'courses': [
          {
            'course_id': 'MARX1004G',
            'name': '大学生思想文化素养',
            'credits': 2.0,
            'grade': 92.0,
            'original': '92',
            'passed': true,
            'credit_included': true,
          },
          {
            'course_id': 'CS1001M',
            'name': '数据结构基础',
            'credits': 4.0,
            'grade': 88.0,
            'original': '88',
            'passed': true,
            'credit_included': true,
          },
        ],
        'planned_courses': [
          {
            'course_id': 'CS2002M',
            'name': '操作系统',
            'credits': 4.0,
            'semester': '2026-A',
          },
        ],
      };

      final report = AuditEngine(const {}).build(
        record,
        plan,
        action: {'foreign_lang_level': 'L3'},
        uiActiveNames: {'操作系统'},
      );
      final totals = report['totals'] as Map<String, dynamic>;
      expect((totals['required'] as num).toDouble(), 24.0);
      expect((totals['earned'] as num).toDouble(), 6.0);
      expect((totals['gap'] as num).toDouble(), 18.0);
      final summary = report['summary'] as List;
      expect(summary, isNotEmpty);
    });

    test('PlanAuditHelper 学期格式化与认定类关键词分类', () {
      expect(PlanAuditHelper.prettySemester('一(秋冬)'), '大一秋冬');
      expect(PlanAuditHelper.prettySemester('二（春夏）'), '大二春夏');
      expect(PlanAuditHelper.extractCourseCode('(2025-2026-1)-MARX1004G-000123-1'),
          'MARX1004G');
      expect(certifiedCategoryOf('劳动教育实践'), '劳育类');
      expect(isForeignCourseName('大学英语(H)'), isTrue);
      expect(isForeignCourseName('初级日语'), isTrue);
      expect(PlanAuditHelper.practiceClassroomIndex('第二课堂'), 2);
      expect(PlanAuditHelper.practiceClassroomIndex('第三课堂'), 3);
      expect(PlanAuditHelper.practiceClassroomIndex('第四课堂'), 4);
      expect(PlanAuditHelper.practiceClassroomIndex('第二/三/四课堂'), 0);
    });

    test('外语类锚定已修外语课程并随 L1/L2/L3 级别同步更新总毕业学分', () {
      const pdfWithForeignAndMinor = '''
一、通识课程 10学分
1.外语类 4.5学分
课程号 课程名称 学分 周学时 总学时 建议学年学期
FL1001 大学英语IV 3.0 3.0-0.0 48 二(春夏)
2.第二课堂 4学分
3.第三课堂 2学分
4.第四课堂 2学分
二、微辅修 12学分
1.微辅修专业课程 12学分
课程号 课程名称 学分 周学时 总学时 建议学年学期
MIN101 微辅修导论 3.0 3.0-0.0 48 二(秋冬)
''';
      final sections = parsePlanPdfText(pdfWithForeignAndMinor);
      final minorCount =
          sections.sections.where(PlanAuditHelper.isMinorSection).length;
      expect(minorCount, greaterThan(0));

      final planL2 = planFileFromPdf(
        sections,
        major: '计算机科学与技术',
        grade: '2026',
        totalCredits: 150.0,
      );
      final planL3 = planFileFromPdf(
        sections,
        major: '计算机科学与技术',
        grade: '2026',
        totalCredits: 150.0,
      );

      final rec = <String, dynamic>{
        'student': {
          'student_id': '3260100001',
          'major': '计算机科学与技术',
          'grade': '2026',
          'current_semester': '2026-A',
        },
        'courses': [
          {
            'course_id': 'JAP1001',
            'name': '初级日语Ⅰ',
            'credits': 3.0,
            'grade': 91.0,
            'original': '91',
            'passed': true,
            'credit_included': true,
          },
        ],
        'planned_courses': [
          {
            'course_id': '',
            'name': '大学英语(H)',
            'credits': 3.0,
            'semester': '2026-A',
          },
        ],
      };

      final r2 = AuditEngine(const {}).build(
        rec,
        planL2,
        action: {'foreign_lang_level': 'L2'},
      );
      final r3 = AuditEngine(const {}).build(
        rec,
        planL3,
        action: {'foreign_lang_level': 'L3'},
      );

      final modForeign2 = (r2['summary'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(isForeignLangModule);
      final modForeign3 = (r3['summary'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(isForeignLangModule);

      // 已修 日语 应自动锚定进外语类并获得 3.0 学分；在修 大学英语(H) 应在 plan_courses 中展示
      expect((modForeign2['earned'] as num).toDouble(), 3.0);
      expect((modForeign2['required'] as num).toDouble(), 4.5);
      expect((modForeign3['required'] as num).toDouble(), 0.0);
      expect(
        (modForeign2['plan_courses'] as List)
            .any((c) => c['name'] == '大学英语(H)'),
        isTrue,
      );

      // L2 (4.5) 与 L3 免修 (0.0) 应同步带动总要求学分下降 4.5 分
      final req2 = ((r2['totals'] as Map)['required'] as num).toDouble();
      final req3 = ((r3['totals'] as Map)['required'] as num).toDouble();
      expect(req2 - req3, closeTo(4.5, 0.01));
    });

    test('二三四课堂素拓分打通三色审计并按单课堂上限计入已获学分', () {
      const pdfWithPractice = '''
一、素质拓展 8学分
1.第二课堂 4学分
2.第三课堂 2学分
3.第四课堂 2学分
''';
      final sections = parsePlanPdfText(pdfWithPractice);
      final plan = planFileFromPdf(
        sections,
        major: '计算机科学与技术',
        grade: '2025',
        totalCredits: 150.0,
      );
      final record = <String, dynamic>{
        'student': {
          'student_id': '3250100001',
          'major': '计算机科学与技术',
          'grade': '2025',
          'current_semester': '2026-A',
        },
        'courses': <Map<String, dynamic>>[],
        'planned_courses': <Map<String, dynamic>>[],
      };

      final s = Scholar()
        ..username = '3250100001'
        ..pt2 = 6.5 // 超过要求 4.0，仅有效计 4.0，不溢抵第三课堂缺口
        ..pt3 = 1.0
        ..pt4 = 2.0
        ..isPracticeScoresGet = true;

      PlanAuditHelper.injectPracticeScoresIntoPlanAndRecord(
        planFile: plan,
        record: record,
        scholar: s,
      );

      final report = AuditEngine(const {}).build(record, plan);
      final summary =
          (report['summary'] as List).cast<Map<String, dynamic>>();
      final m2 = summary.firstWhere((m) => '${m['title']}'.contains('第二课堂'));
      final m3 = summary.firstWhere((m) => '${m['title']}'.contains('第三课堂'));
      final m4 = summary.firstWhere((m) => '${m['title']}'.contains('第四课堂'));

      expect((m2['earned'] as num).toDouble(), 4.0);
      expect((m2['practice_raw_points'] as num).toDouble(), 6.5);
      expect(m2['color'], 'green');

      expect((m3['earned'] as num).toDouble(), 1.0);
      expect(m3['color'], 'yellow');
      expect((m3['gap'] as num).toDouble(), 1.0);

      expect((m4['earned'] as num).toDouble(), 2.0);
      expect(m4['color'], 'green');

      final totals = report['totals'] as Map<String, dynamic>;
      expect((totals['required'] as num).toDouble(), 158.0);
      expect((totals['earned'] as num).toDouble(), 7.0);
      expect((totals['gap'] as num).toDouble(), 151.0);
    });
  });
}
