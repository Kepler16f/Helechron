import 'dart:math' as math;
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/course.dart';

/// 课程修读四态标定模型（参考 ClassArk 规范）
enum PlanCourseState {
  /// 已修完且取得有效学分（绿色 🟢）
  earned,

  /// 本学期在修中（课表在修、本学期选课或待录，蓝色 🔵）
  active,

  /// 有记录但未获学分（不及格、缺考、弃修、缓考、需重修，橙色 🟠）
  noCredit,

  /// 未选修/无修读记录（灰色 ⚪）
  unknown;

  bool get isEarned => this == PlanCourseState.earned;
  bool get isActive => this == PlanCourseState.active;
  bool get isNoCredit => this == PlanCourseState.noCredit;
  bool get isUnknown => this == PlanCourseState.unknown;

  String get label {
    switch (this) {
      case PlanCourseState.earned:
        return '已修完';
      case PlanCourseState.active:
        return '在修中';
      case PlanCourseState.noCredit:
        return '需重修';
      case PlanCourseState.unknown:
        return '未修读';
    }
  }
}

/// 课程变体标记规范化映射（将 Ⅰ, I, 1, 一 均映射为统一 token "1"）
String? canonicalVariantToken(String s) {
  final clean = s.trim().toUpperCase();
  const map = {
    '1': '1', '一': '1', 'I': '1', 'Ⅰ': '1',
    '2': '2', '二': '2', 'II': '2', 'Ⅱ': '2',
    '3': '3', '三': '3', 'III': '3', 'Ⅲ': '3',
    '4': '4', '四': '4', 'IV': '4', 'Ⅳ': '4',
    '5': '5', '五': '5', 'V': '5', 'Ⅴ': '5',
    '6': '6', '六': '6', 'VI': '6', 'Ⅵ': '6',
    '7': '7', '七': '7', 'VII': '7', 'Ⅶ': '7',
    '8': '8', '八': '8', 'VIII': '8', 'Ⅷ': '8',
    '9': '9', '九': '9', 'IX': '9', 'Ⅸ': '9',
    '10': '10', '十': '10', 'X': '10', 'Ⅹ': '10',
    'H': 'H', 'HONOR': 'H', '荣誉': 'H',
    'A': 'A', '甲': 'A',
    'B': 'B', '乙': 'B',
    'C': 'C', '丙': 'C',
    'D': 'D', '丁': 'D',
    '上': 'UP',
    '中': 'MID',
    '下': 'DOWN',
  };
  return map[clean];
}

final _bracketRegex = RegExp(r'[（(]([^()（）]+)[)）]');
final _trailingRegex = RegExp(
    r'(?:[ _\-]+)?([ivxⅠ-Ⅹ0-9一二三四五六七八九十h甲乙丙丁上下中]+)$',
    caseSensitive: false);

/// 提取课程名称中的变体签名（如“大学英语(I)”→"1"，“高等数学(H)”→"H"，“微积分（甲）1”→"A|1"）
String courseVariantSignature(String name) {
  final s = name
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .trim();

  final sigs = <String>{};
  for (final m in _bracketRegex.allMatches(s)) {
    final inside = m.group(1) ?? '';
    final token = canonicalVariantToken(inside);
    if (token != null) {
      sigs.add(token);
    } else {
      // 检查括号内是否包含复合标记，如 "甲" 或 "1"
      for (var i = 0; i < inside.length; i++) {
        final cToken = canonicalVariantToken(inside[i]);
        if (cToken != null) sigs.add(cToken);
      }
    }
  }

  final withoutBrackets = s.replaceAll(_bracketRegex, '').trim();
  final tail = _trailingRegex.firstMatch(withoutBrackets);
  if (tail != null) {
    final token = canonicalVariantToken(tail.group(1) ?? '');
    if (token != null) sigs.add(token);
  }

  final sorted = sigs.toList()..sort();
  return sorted.join('|');
}

/// 字符序列相似度计算（Levenshtein 衍生 Ratio）
double stringSimilarityRatio(String s1, String s2) {
  if (s1 == s2) return 1.0;
  if (s1.isEmpty || s2.isEmpty) return 0.0;
  final len1 = s1.length;
  final len2 = s2.length;
  final matrix = List.generate(len1 + 1, (_) => List.filled(len2 + 1, 0));

  for (var i = 0; i <= len1; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= len2; j++) {
    matrix[0][j] = j;
  }

  for (var i = 1; i <= len1; i++) {
    for (var j = 1; j <= len2; j++) {
      final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
      matrix[i][j] = math.min(
        math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
        matrix[i - 1][j - 1] + cost,
      );
    }
  }
  final dist = matrix[len1][len2];
  return (1.0 - dist / math.max(len1, len2)).clamp(0.0, 1.0);
}

/// 变体安全的智能模糊匹配：签名冲突项直接排除，绝不串级
String? bestVariantAwareMatch(
  String target,
  List<String> candidates, {
  double cutoff = 0.82,
}) {
  final targetSig = courseVariantSignature(target);
  String? bestCandidate;
  var bestRatio = cutoff;

  for (final c in candidates) {
    final cSig = courseVariantSignature(c);
    // 关键核心：若两门课都有变体签名且签名不相同（例如 I 与 II、H），相似度再高也绝对剔除！
    if (targetSig.isNotEmpty && cSig.isNotEmpty && targetSig != cSig) {
      continue;
    }
    final r = stringSimilarityRatio(target, c);
    if (r > bestRatio) {
      bestRatio = r;
      bestCandidate = c;
    }
  }
  return bestCandidate;
}

/// 汇集学生已修记录、周课表与本学期选课，生成各课程的四态修读证据
Map<String, PlanCourseState> collectCourseStateEvidence({
  required List<Grade> grades,
  required List<Course> currentSemesterCourses,
}) {
  final result = <String, PlanCourseState>{};

  // 1. 扫描成绩单
  for (final g in grades) {
    final name = g.name.trim();
    if (name.isEmpty) continue;

    PlanCourseState state;
    final isExcluded = g.original.contains('弃修') ||
        g.original.contains('缓考') ||
        g.original.contains('缺考') ||
        g.original.contains('不及格') ||
        g.original.contains('不合格') ||
        g.original.contains('无效') ||
        g.original == 'F';

    if (g.original == '待录') {
      state = PlanCourseState.active;
    } else if (g.earnedCredit > 0 ||
        (g.creditIncluded &&
            !isExcluded &&
            (g.fivePoint > 0 || g.hundredPoint >= 60))) {
      state = PlanCourseState.earned;
    } else {
      state = PlanCourseState.noCredit;
    }

    // 状态优先级：earned > active > noCredit
    final prev = result[name];
    if (prev == null ||
        (state == PlanCourseState.earned) ||
        (state == PlanCourseState.active && prev != PlanCourseState.earned)) {
      result[name] = state;
    }
  }

  // 2. 扫描本学期课表中的正在修读课程
  for (final c in currentSemesterCourses) {
    final name = c.name.trim();
    if (name.isEmpty) continue;
    // 如果已经在成绩单修过且获得学分，保持 earned；否则标记为 active
    if (result[name] != PlanCourseState.earned) {
      result[name] = PlanCourseState.active;
    }
  }

  return result;
}

/// 解析单门培养方案课程在学生修读记录下的四态
PlanCourseState resolveCourseState(
  String courseName,
  Map<String, PlanCourseState> evidence,
) {
  final trimmed = courseName.trim();
  if (evidence.containsKey(trimmed)) {
    return evidence[trimmed]!;
  }

  // 尝试变体安全匹配
  final matchedName =
      bestVariantAwareMatch(trimmed, evidence.keys.toList(), cutoff: 0.85);
  if (matchedName != null) {
    return evidence[matchedName]!;
  }

  return PlanCourseState.unknown;
}

/// 2026 级外语应修学分动态规则引擎
class ForeignLanguageRule {
  static const int kNewRuleStartYear = 2026;

  /// 根据学生年级与外语分级（L1/L2/L3）计算要求学分
  /// - 2026 级以前：L1 封顶 6.0，L2 封顶 4.5，L3 封顶 3.0
  /// - 2026 级起新规：L1=6.0，L2=4.5，L3=0.0（免修！强制覆盖）
  static double getRequiredCredits({
    required int? gradeYear,
    required String? level,
    double? customCredits,
    double fallbackCredits = 3.0,
  }) {
    if (customCredits != null && customCredits >= 0) {
      return customCredits;
    }
    final lvl = (level ?? '').trim().toUpperCase();
    final isNewRule = gradeYear != null && gradeYear >= kNewRuleStartYear;

    if (lvl == 'L3') {
      return isNewRule ? 0.0 : 3.0;
    } else if (lvl == 'L2') {
      return 4.5;
    } else if (lvl == 'L1') {
      return 6.0;
    }
    return fallbackCredits;
  }

  static bool isExemptByGrade({required int? gradeYear, required String? level}) {
    if (gradeYear == null || level == null) return false;
    return gradeYear >= kNewRuleStartYear && level.trim().toUpperCase() == 'L3';
  }

  static String levelLabel({required int? gradeYear, required String? level}) {
    final lvl = (level ?? '').trim().toUpperCase();
    if (lvl == 'L3') {
      return isExemptByGrade(gradeYear: gradeYear, level: lvl)
          ? 'L3（免修）'
          : 'L3（3.0学分）';
    }
    if (lvl == 'L2') return 'L2（4.5学分）';
    if (lvl == 'L1') return 'L1（6.0学分）';
    return '未设定等级';
  }
}

/// 选课组规则约束计算器（处理 N选M、至少修读 N 门，防止虚假缺口）
class GroupRuleHelper {
  /// 计算板块有效要求学分（纯函数）：
  /// 若标注为 N选M，且要求学分等于组内所有课程学分之和，取最便宜的 N 门折算
  static double effectiveRequiredCredits({
    required double rawRequiredCredits,
    required List<double> courseCredits,
    int? nSelect,
  }) {
    if (nSelect == null || nSelect <= 0 || courseCredits.isEmpty) {
      return rawRequiredCredits;
    }
    final sorted = List<double>.from(courseCredits)..sort();
    final totalSum = sorted.fold<double>(0.0, (acc, e) => acc + e);

    // 仅当原始要求学分等于全量课程之和（说明教务网简单求和导致虚增）时进行最便宜折算
    if ((rawRequiredCredits - totalSum).abs() < 0.1 && sorted.length >= nSelect) {
      final cheapestN = sorted.take(nSelect).fold<double>(0.0, (acc, e) => acc + e);
      return math.min(rawRequiredCredits, cheapestN);
    }
    return rawRequiredCredits;
  }
}
