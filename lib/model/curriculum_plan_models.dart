import 'package:celechron/http/zjuServices/zdbk.dart';

/// 行政班尾四位 = 年级(2 位) + 班号(2 位)：工科试验班（计算机）2606 → 2026。
/// （历史教训：若取末两位，会把 2606 读成 2006，导致年级与方案匹配全错。）
String? gradeFromClassName(String? className) {
  final m = RegExp(r'(\d{4})\s*班?\s*$').firstMatch((className ?? '').trim());
  if (m == null) return null;
  final yy = int.tryParse(m.group(1)!.substring(0, 2));
  if (yy == null) return null;
  return (2000 + yy).toString();
}

/// 专业与方案名称归一化：展开别名、去除空格、全半角括号转换、转小写
String normalizePlanName(String s) {
  return Zdbk.normalizeMajorName(s)
      .replaceAll(RegExp(r'[\s\u3000]+'), '')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .toLowerCase();
}

/// 切分教务网用空格、斜杠、顿号或分号拼接的多门课程名
List<String> splitCourseNames(String? raw) {
  if (raw == null) return const [];
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return const [];
  return cleaned
      .split(RegExp(r'[\s,;/、；，\n\r]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// 匹配强度等级
enum PlanMatchLevel {
  exact(100),
  prefix(80),
  contains(55),
  category(25),
  none(0);

  final double weight;
  const PlanMatchLevel(this.weight);
}

/// 学籍画像（从正方课表接口 xskbcx_cxXsKb 响应顶层或 xsxx 提取，参考 D:\compass）
class StudentProfile {
  final String majorName; // zy / zymc
  final String college; // xy / jgmc
  final String adminClass; // xzb / bjmc
  final String studentId; // xh
  final String name; // xm
  final String gradeOverride; // njdm_id / njmc

  const StudentProfile({
    this.majorName = '',
    this.college = '',
    this.adminClass = '',
    this.studentId = '',
    this.name = '',
    String grade = '',
  }) : gradeOverride = grade;

  bool get isEmpty =>
      majorName.isEmpty && adminClass.isEmpty && studentId.isEmpty;

  String? get grade {
    final fromClass = gradeFromClassName(adminClass);
    if (fromClass != null && fromClass.isNotEmpty) return fromClass;
    if (RegExp(r'^20\d{2}$').hasMatch(gradeOverride.trim())) {
      return gradeOverride.trim();
    }
    if (studentId.startsWith('3') && studentId.length >= 3) {
      final yy = int.tryParse(studentId.substring(1, 3));
      if (yy != null && yy >= 10 && yy <= 50) {
        return '${2000 + yy}';
      }
    }
    return null;
  }

  int? get gradeYear {
    final g = grade;
    return g == null ? null : int.tryParse(g);
  }

  factory StudentProfile.fromJson(Map<String, dynamic> m) {
    String clean(List<String> keys) {
      for (final k in keys) {
        final raw = (m[k] ?? '').toString().trim();
        if (raw.isNotEmpty &&
            raw != '未知' &&
            raw != '无' &&
            raw != '-' &&
            raw != '--' &&
            raw != '/' &&
            !raw.contains('&nbsp;')) {
          return raw;
        }
      }
      return '';
    }

    return StudentProfile(
      majorName: clean(const ['zy', 'zymc', 'majorName', '专业名称', '专业']),
      college: clean(const ['xy', 'jgmc', 'college', '学院', '所属学院']),
      adminClass: clean(const ['xzb', 'bjmc', 'bj', 'adminClass', '行政班']),
      studentId: clean(const ['xh', 'xh_id', 'studentId', '学号']),
      name: clean(const ['xm', 'name', '姓名']),
      grade: clean(const ['njdm_id', 'njmc', 'nj', 'grade']),
    );
  }

  Map<String, dynamic> toJson() => {
        'zy': majorName,
        'xy': college,
        'xzb': adminClass,
        'xh': studentId,
        'xm': name,
        if (gradeOverride.isNotEmpty) 'njdm_id': gradeOverride,
      };
}

/// 培养方案摘要数据模型（映射正方教务网 pyfaxxcx_cxPyfaxscxIndex.html 扁平字段）
class PlanSummary {
  final String id; // pyfaxx_id 或 pyfa_id
  final String jxjhh; // 教学计划号
  final String zymc; // 专业名称
  final String zydm; // 专业代码
  final String xymc; // 开课学院/机构名称
  final String xz; // 学制（年）
  final String synj; // 适用年级
  final String dlbsmc; // 方案大类标识（如：主修专业方案、辅修专业方案）
  final String zydlmc; // 专业大类名称
  final String zydlmc2; // 专业大类名称2
  final String syxw; // 授予学位
  final double? zdbyxf; // 最低毕业学分
  final double? kcdlxfyq; // 课程大类总学分要求
  final double? dektxf; // 第二课堂学分
  final double? dektxf3; // 第三课堂学分
  final double? dektxf4; // 第四课堂学分
  final double? fxxf; // 辅修学分
  final String pymb; // 培养目标
  final String pyyq; // 培养要求
  final String bz; // 备注说明
  final List<String> zyhxkc; // 专业核心课程
  final List<String> zyhxsjkc; // 核心实践课程
  final List<String> qywkc; // 前沿/荣誉课程
  final Map<String, dynamic> raw; // 保留教务网原始所有 61 个字段

  PlanSummary({
    required this.id,
    required this.jxjhh,
    required this.zymc,
    this.zydm = '',
    this.xymc = '',
    this.xz = '4',
    this.synj = '',
    this.dlbsmc = '',
    this.zydlmc = '',
    this.zydlmc2 = '',
    this.syxw = '',
    this.zdbyxf,
    this.kcdlxfyq,
    this.dektxf,
    this.dektxf3,
    this.dektxf4,
    this.fxxf,
    this.pymb = '',
    this.pyyq = '',
    this.bz = '',
    this.zyhxkc = const [],
    this.zyhxsjkc = const [],
    this.qywkc = const [],
    this.raw = const {},
  });

  bool get isMajorPlan =>
      dlbsmc.isEmpty || dlbsmc.contains('主修') || dlbsmc.contains('专业');

  int get gradeYear => int.tryParse(synj) ?? 0;

  String get creditsLabel =>
      zdbyxf != null ? '${zdbyxf!.toStringAsFixed(1)} 学分' : '160.0 学分';

  /// 判断本方案与目标专业的名称匹配层级
  PlanMatchLevel levelFor(String targetMajor) {
    final m = normalizePlanName(targetMajor);
    if (m.isEmpty) return PlanMatchLevel.none;
    final zy = normalizePlanName(zymc);
    if (zy.isEmpty) return PlanMatchLevel.none;
    if (zy == m) return PlanMatchLevel.exact;
    if (zy.startsWith(m) || m.startsWith(zy)) return PlanMatchLevel.prefix;
    if (zy.contains(m) || m.contains(zy)) return PlanMatchLevel.contains;
    final dl = normalizePlanName('$zydlmc$zydlmc2');
    if (dl.isNotEmpty && (dl.contains(m) || m.contains(dl))) {
      return PlanMatchLevel.category;
    }
    return PlanMatchLevel.none;
  }

  factory PlanSummary.fromJson(Map<String, dynamic> m) {
    final id = (m['pyfaxx_id'] ?? m['pyfa_id'] ?? m['id'] ?? '').toString();
    final jxjhh = (m['jxjhh'] ?? '').toString();
    final zymc = (m['zymc'] ?? m['pyfamc'] ?? '').toString().trim();
    final zydm = (m['zydm'] ?? '').toString().trim();
    final xymc = (m['xymc'] ?? m['jgmc'] ?? '').toString().trim();
    final xz = (m['xz'] ?? '4').toString().trim();
    final synj = (m['synj'] ?? m['njdm_id'] ?? '').toString().trim();
    final dlbsmc = (m['dlbsmc'] ?? '').toString().trim();
    final zydlmc = (m['zydlmc'] ?? '').toString().trim();
    final zydlmc2 = (m['zydlmc2'] ?? '').toString().trim();
    final syxw = (m['syxw'] ?? '').toString().trim();

    double? parseD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    final zdbyxf = parseD(m['zdbyxf'] ?? m['bbyq']);
    final kcdlxfyq = parseD(m['kcdlxfyq']);
    final dektxf = parseD(m['dektxf']);
    final dektxf3 = parseD(m['dektxf3']);
    final dektxf4 = parseD(m['dektxf4']);
    final fxxf = parseD(m['fxxf']);

    final pymb = (m['pymb'] ?? '').toString().trim();
    final pyyq = (m['pyyq'] ?? '').toString().trim();
    final bz = (m['bz'] ?? '').toString().trim();

    final zyhxkc = splitCourseNames(m['zyhxkc']?.toString());
    final zyhxsjkc = splitCourseNames(m['zyhxsjkc']?.toString());
    final qywkc = splitCourseNames(m['qywkc']?.toString());

    return PlanSummary(
      id: id,
      jxjhh: jxjhh,
      zymc: zymc,
      zydm: zydm,
      xymc: xymc,
      xz: xz,
      synj: synj,
      dlbsmc: dlbsmc,
      zydlmc: zydlmc,
      zydlmc2: zydlmc2,
      syxw: syxw,
      zdbyxf: zdbyxf,
      kcdlxfyq: kcdlxfyq,
      dektxf: dektxf,
      dektxf3: dektxf3,
      dektxf4: dektxf4,
      fxxf: fxxf,
      pymb: pymb,
      pyyq: pyyq,
      bz: bz,
      zyhxkc: zyhxkc,
      zyhxsjkc: zyhxsjkc,
      qywkc: qywkc,
      raw: m,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jxjhh': jxjhh,
        'zymc': zymc,
        'zydm': zydm,
        'xymc': xymc,
        'xz': xz,
        'synj': synj,
        'dlbsmc': dlbsmc,
        'zydlmc': zydlmc,
        'zydlmc2': zydlmc2,
        'syxw': syxw,
        'zdbyxf': zdbyxf,
        'kcdlxfyq': kcdlxfyq,
        'dektxf': dektxf,
        'dektxf3': dektxf3,
        'dektxf4': dektxf4,
        'fxxf': fxxf,
        'pymb': pymb,
        'pyyq': pyyq,
        'bz': bz,
        'zyhxkc': zyhxkc,
        'zyhxsjkc': zyhxsjkc,
        'qywkc': qywkc,
        'raw': raw,
      };
}

/// 匹配候选条目
class PlanCandidate {
  final PlanSummary plan;
  final PlanMatchLevel level;
  final bool gradeMatch;
  final double score;

  const PlanCandidate(this.plan, this.level, this.gradeMatch, this.score);
}

/// 培养方案智能匹配结果
class PlanMatchResult {
  final String majorName;
  final String? grade;
  final List<PlanCandidate> candidates;
  final List<String> notes;
  final bool ambiguous;

  const PlanMatchResult({
    required this.majorName,
    this.grade,
    required this.candidates,
    required this.notes,
    required this.ambiguous,
  });

  PlanSummary? get bestPlan =>
      candidates.isNotEmpty ? candidates.first.plan : null;
}

double _gradeScore(String itemGrade, String target) {
  if (target.isEmpty) return 0;
  if (itemGrade == target) return 60;
  final t = int.tryParse(target), i = int.tryParse(itemGrade);
  if (t == null || i == null) return 0;
  if (i < t) return (30 - (t - i) * 5).clamp(0, 30).toDouble();
  return -20; // 比本人年级还新（新方案对老生不适用，严防低年级错套高年级）
}

/// 纯函数：全量培养方案目录 → 多候选多层级评分与排序（参考 ClassArk 匹配核心）
PlanMatchResult matchPlans(
  List<PlanSummary> catalog, {
  required String majorName,
  String? grade,
  int maxCandidates = 12,
}) {
  final g = (grade ?? '').trim();
  final byId = <String, PlanCandidate>{};
  for (final p in catalog) {
    final level = p.levelFor(majorName);
    if (level == PlanMatchLevel.none || p.id.isEmpty) continue;
    final gradeMatch = g.isNotEmpty && p.synj == g;
    var score = level.weight + _gradeScore(p.synj, g);
    if (p.isMajorPlan) score += 6;
    final candidate = PlanCandidate(p, level, gradeMatch, score);
    final prev = byId[p.id];
    if (prev == null || candidate.score > prev.score) {
      byId[p.id] = candidate;
    }
  }

  final candidates = byId.values.toList()
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byGrade = b.plan.gradeYear.compareTo(a.plan.gradeYear);
      if (byGrade != 0) return byGrade;
      return a.plan.jxjhh.compareTo(b.plan.jxjhh);
    });

  // 歧义判定：前两名分差 < 20 或 同一年级存在多条达到 exact / prefix 级别的命中
  final strongPerGrade = <String, int>{};
  for (final c in candidates) {
    if (c.level == PlanMatchLevel.exact || c.level == PlanMatchLevel.prefix) {
      strongPerGrade[c.plan.synj] = (strongPerGrade[c.plan.synj] ?? 0) + 1;
    }
  }
  final tied =
      candidates.length > 1 && candidates[0].score - candidates[1].score < 20;
  final ambiguous = tied || strongPerGrade.values.any((n) => n > 1);

  final notes = <String>[];
  if (candidates.isEmpty) {
    notes.add('未在教务系统中检索到与「$majorName」直接匹配的培养方案');
  } else {
    final best = candidates.first;
    if (g.isNotEmpty && best.plan.synj != g) {
      notes.add('未检索到 $g 级对应方案，已自动降级推荐最接近的往届方案（${best.plan.synj} 级）');
    }
    if (ambiguous) {
      notes.add('检测到该专业包含多个相近方向或大类分流方案，请核对并可手动切换');
    }
  }

  return PlanMatchResult(
    majorName: majorName,
    grade: g.isEmpty ? null : g,
    candidates: candidates.take(maxCandidates).toList(),
    notes: notes,
    ambiguous: ambiguous,
  );
}
