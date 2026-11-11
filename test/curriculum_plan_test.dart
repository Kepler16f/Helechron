import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/services/curriculum_matching_engine.dart';

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
}
