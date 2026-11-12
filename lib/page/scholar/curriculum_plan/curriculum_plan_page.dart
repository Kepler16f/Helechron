import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/page/scholar/practice_score/practice_score_page.dart';
import 'package:celechron/services/plan_audit_engine.dart';
import 'curriculum_plan_controller.dart';

class _SecTreeNode {
  final PdfModuleSection sec;
  final List<_SecTreeNode> children = <_SecTreeNode>[];
  _SecTreeNode(this.sec);
}

class CurriculumPlanPage extends StatefulWidget {
  const CurriculumPlanPage({super.key});

  @override
  State<CurriculumPlanPage> createState() => _CurriculumPlanPageState();
}

class _CurriculumPlanPageState extends State<CurriculumPlanPage> {
  final _c = Get.put(CurriculumPlanController());
  final Set<String> _collapsedSections = <String>{};
  final Set<String> _expandedAuditModules = <String>{};
  bool _showAuditDetails = false;
  bool _showPdfModuleList = true;
  bool _showMoreSimilarPlans = false;
  bool _showObjectivesAndNotes = false;

  Color _sakuraInk(BuildContext context) => CupertinoDynamicColor.resolve(
      CustomCupertinoDynamicColors.sakuraInk, context);

  Color _springInk(BuildContext context) => CupertinoDynamicColor.resolve(
      CustomCupertinoDynamicColors.springInk, context);

  Color _cyanInk(BuildContext context) =>
      CupertinoDynamicColor.resolve(CustomCupertinoDynamicColors.cyanInk, context);

  Color _peachInk(BuildContext context) => CupertinoDynamicColor.resolve(
      CustomCupertinoDynamicColors.peachInk, context);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: '培养方案查看',
            right: Obx(() {
              final blue = CupertinoDynamicColor.resolve(
                  CupertinoColors.activeBlue, context);
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minSize: 30,
                      onPressed: () => _showPlanSelector(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.square_grid_2x2,
                              size: 14, color: blue),
                          const SizedBox(width: 3),
                          Text(
                            '全校',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      minSize: 30,
                      onPressed: _c.isSyncing.value
                          ? null
                          : () => _c.syncCatalog(silent: false),
                      child: _c.isSyncing.value
                          ? const CupertinoActivityIndicator(radius: 7)
                          : Icon(CupertinoIcons.refresh,
                              size: 16, color: blue),
                    ),
                  ],
                ),
              );
            }),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Obx(() => _buildSyncNoticeBanner(context)),
                Obx(() => _buildIdentityPlanCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildGraduationProgressCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildAuditModulesCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildForeignLanguageCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildPdfTreeCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildCoreCoursesCard(context)),
                const SizedBox(height: 14),
                Obx(() => _buildObjectivesCard(context)),
                const SizedBox(height: 24),
                const NativeBottomBarSpacer(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncNoticeBanner(BuildContext context) {
    final err = _c.syncError.value ?? _c.pdfError.value;
    if (err == null || err.isEmpty) return const SizedBox.shrink();
    final warnColor = _peachInk(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: warnColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warnColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle_fill,
                size: 16, color: warnColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                err,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minSize: 28,
              color: warnColor,
              borderRadius: BorderRadius.circular(8),
              onPressed: _c.isSyncing.value
                  ? null
                  : () {
                      if (_c.syncError.value != null) {
                        _c.syncCatalog(silent: false);
                      } else {
                        _c.downloadAndParsePdf();
                      }
                    },
              child: const Text(
                '重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityPlanCard(BuildContext context) {
    final plan = _c.selectedPlan.value;
    final match = _c.matchResult.value;
    final accent = _sakuraInk(context);
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  CupertinoIcons.doc_text_search,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan != null
                          ? '${plan.zymc} (${plan.synj}级)'
                          : (_c.isSyncing.value
                              ? '正在从教务系统同步...'
                              : '暂无本地培养方案缓存'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (_c.userMajor.value.isNotEmpty)
                          '学籍: ${_c.userMajor.value}',
                        if (_c.collegeName.value.isNotEmpty)
                          _c.collegeName.value,
                        if (_c.studentGrade.value.isNotEmpty)
                          '${_c.studentGrade.value}级',
                        if (_c.adminClass.value.isNotEmpty)
                          _c.adminClass.value,
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: secondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_c.catalog.isNotEmpty)
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minSize: 30,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () => _showPlanSelector(context),
                  child: Text(
                    '切换',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.activeBlue, context),
                    ),
                  ),
                ),
            ],
          ),
          if (plan == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: accent,
                borderRadius: BorderRadius.circular(10),
                onPressed: _c.isSyncing.value
                    ? null
                    : () => _c.syncCatalog(silent: false),
                child: Text(
                  _c.isSyncing.value ? '正在拉取教务系统方案目录...' : '立即同步培养方案',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (plan.xymc.isNotEmpty) _metaChip(context, plan.xymc),
                if (plan.dlbsmc.isNotEmpty) _metaChip(context, plan.dlbsmc),
                if (plan.syxw.isNotEmpty)
                  _metaChip(context, '${plan.syxw}学士 · ${plan.xz}年制'),
                if (plan.jxjhh.isNotEmpty)
                  _metaChip(context, '计划号 ${plan.jxjhh}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    minSize: 36,
                    color: _c.pdfPath.value != null
                        ? _springInk(context).withValues(alpha: 0.14)
                        : accent,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _c.isPdfLoading.value
                        ? null
                        : () {
                            if (_c.pdfPath.value != null) {
                              _c.openPdfWithSystem();
                            } else {
                              _c.downloadAndParsePdf();
                            }
                          },
                    child: _c.isPdfLoading.value
                        ? const CupertinoActivityIndicator(radius: 8)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _c.pdfPath.value != null
                                    ? CupertinoIcons.doc_fill
                                    : CupertinoIcons.cloud_download,
                                size: 15,
                                color: _c.pdfPath.value != null
                                    ? _springInk(context)
                                    : CupertinoColors.white,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _c.pdfPath.value != null
                                      ? '打开官方 PDF (${_c.pdfSections.value?.courseCount ?? 0}门课)'
                                      : '下载并解析官方 PDF 方案',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _c.pdfPath.value != null
                                        ? _springInk(context)
                                        : CupertinoColors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_c.pdfPath.value != null) ...[
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    minSize: 36,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondarySystemFill, context),
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _c.isPdfLoading.value
                        ? null
                        : () => _c.downloadAndParsePdf(),
                    child: Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 16,
                      color: label,
                    ),
                  ),
                ],
              ],
            ),
            if (match != null && (match.ambiguous || match.notes.isNotEmpty)) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _peachInk(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final note in match.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '• $note',
                          style: TextStyle(
                            fontSize: 12,
                            color: _peachInk(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (match.candidates.length > 1) ...[
                      Builder(builder: (ctx) {
                        final targetGrade = _c.studentGrade.value.trim().isNotEmpty
                            ? _c.studentGrade.value.trim()
                            : match.candidates.first.plan.synj.trim();
                        final sameGrade = match.candidates
                            .where((c) =>
                                c.plan.synj.trim() == targetGrade ||
                                c.plan.id == plan.id)
                            .toList();
                        final primaryList = sameGrade.isNotEmpty
                            ? sameGrade
                            : match.candidates.take(4).toList();
                        final primaryIds =
                            primaryList.map((e) => e.plan.id).toSet();
                        final otherGrade = match.candidates
                            .where((c) => !primaryIds.contains(c.plan.id))
                            .take(10)
                            .toList();

                        Widget buildCandidateChip(PlanCandidate c) {
                          final isSelected = c.plan.id == plan.id;
                          return GestureDetector(
                            onTap: () => _c.selectPlan(c.plan),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accent
                                    : accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${c.plan.zymc} (${c.plan.synj})',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? CupertinoColors.white
                                      : label,
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: primaryList
                                  .take(6)
                                  .map(buildCandidateChip)
                                  .toList(),
                            ),
                            if (otherGrade.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() =>
                                    _showMoreSimilarPlans =
                                        !_showMoreSimilarPlans),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '更多类似方案 (${otherGrade.length})',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.activeBlue,
                                            context),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      _showMoreSimilarPlans
                                          ? CupertinoIcons.chevron_up
                                          : CupertinoIcons.chevron_down,
                                      size: 11,
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.activeBlue, context),
                                    ),
                                  ],
                                ),
                              ),
                              if (_showMoreSimilarPlans) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children:
                                      otherGrade.map(buildCandidateChip).toList(),
                                ),
                              ],
                            ],
                          ],
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildGraduationProgressCard(BuildContext context) {
    final earned = _c.auditEarnedCredits;
    final total = _c.effectiveGraduationCredits;
    final active = _c.activeCredits.value;
    final gap = _c.creditGap;
    final rate = _c.completionRate;

    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final accent = _sakuraInk(context);
    final spring = _springInk(context);
    final cyan = _cyanInk(context);
    final peach = _peachInk(context);
    final barBg = CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemFill, context);

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '毕业学分达成度',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: label,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showEditGraduationCreditsDialog(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.pencil, size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      '要求 ${total.toStringAsFixed(1)} 分',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                earned.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: label,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ ${total.toStringAsFixed(1)} 学分 (${(rate * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 10,
              color: barBg,
              child: LayoutBuilder(builder: (ctx, box) {
                final earnedW = box.maxWidth * rate;
                final activeRatio = total > 0 ? (active / total) : 0.0;
                final activeW = box.maxWidth *
                    (rate + activeRatio > 1.0 ? 1.0 - rate : activeRatio);
                return Row(
                  children: [
                    if (earnedW > 0)
                      Container(width: earnedW, color: spring),
                    if (activeW > 0)
                      Container(width: activeW, color: cyan),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statPill(context, '已获', '${earned.toStringAsFixed(1)}分', spring),
              const SizedBox(width: 8),
              _statPill(context, '在修', '+${active.toStringAsFixed(1)}分', cyan),
              const SizedBox(width: 8),
              _statPill(
                context,
                gap > 0 ? '尚需' : '状态',
                gap > 0 ? '${gap.toStringAsFixed(1)}分' : '已达标',
                gap > 0 ? peach : spring,
              ),
            ],
          ),
          if (_c.practiceRequiredTotal > 0 || _c.practiceRawTotal > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill, context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '第一课堂 ${_c.firstClassroomEarnedCredits.toStringAsFixed(1)}/${_c.firstClassroomRequiredCredits.toStringAsFixed(1)} · 二/三/四课堂 ${_c.practiceEffectiveEarned.toStringAsFixed(1)}/${_c.practiceRequiredTotal.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: label,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (_) =>
                                PracticeScorePage(scholar: _c.scholar.value),
                            title: '素拓记点明细',
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '素拓明细',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.activeBlue, context),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              size: 11,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.activeBlue, context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '二课 ${_c.pt2Earned.toStringAsFixed(1)}/${_c.pt2Required.toStringAsFixed(1)} · 三课 ${_c.pt3Earned.toStringAsFixed(1)}/${_c.pt3Required.toStringAsFixed(1)} · 四课 ${_c.pt4Earned.toStringAsFixed(1)}/${_c.pt4Required.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditModulesCard(BuildContext context) {
    final report = _c.auditReport.value;
    if (report == null) return const SizedBox.shrink();

    final summary = (report['summary'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) {
          final text = '${m['module_path'] ?? ''} ${m['title'] ?? ''}';
          return !text.contains('微辅修');
        })
        .toList();
    final greenCount = summary.where((m) => m['color'] == 'green').length;
    final yellowCount = summary.where((m) => m['color'] == 'yellow').length;
    final redCount = summary.where((m) => m['color'] == 'red').length;
    final warnings = (report['warnings'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final caliberNotes = (report['caliber_notes'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();

    if (summary.isEmpty) return const SizedBox.shrink();

    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final green = _springInk(context);
    final yellow = _peachInk(context);
    final red = CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    Color colorOf(String c) {
      if (c == 'green') return green;
      if (c == 'red') return red;
      return yellow;
    }

    String colorLabel(String c) {
      if (c == 'green') return '已达标';
      if (c == 'red') return '风险';
      return '进行中';
    }

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showAuditDetails = !_showAuditDetails),
            child: Row(
              children: [
                Text(
                  '模块三色学业审计 (${summary.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: label,
                  ),
                ),
                const SizedBox(width: 8),
                if (greenCount > 0)
                  Text(
                    '●$greenCount',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: green),
                  ),
                if (yellowCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '●$yellowCount',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: yellow),
                  ),
                ],
                if (redCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '●$redCount',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: red),
                  ),
                ],
                const Spacer(),
                Icon(
                  _showAuditDetails
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: secondary,
                ),
              ],
            ),
          ),
          if (_showAuditDetails) ...[
            const SizedBox(height: 10),
            for (final m in summary) ...[
              Builder(builder: (ctx) {
                final mid = '${m['module_id'] ?? m['title'] ?? ''}';
                final title = '${m['module_path'] ?? m['title'] ?? '未命名模块'}';
                final req = (m['required'] as num?)?.toDouble() ?? 0.0;
                final got = (m['earned'] as num?)?.toDouble() ?? 0.0;
                final gap = (m['gap'] as num?)?.toDouble() ?? 0.0;
                final rawPracticePts =
                    (m['practice_raw_points'] as num?)?.toDouble();
                final selNoCredit =
                    (m['selected_no_credit'] as num?)?.toInt() ?? 0;
                final cStr = '${m['color'] ?? 'yellow'}';
                final badgeColor = colorOf(cStr);
                final expanded = _expandedAuditModules.contains(mid);
                final planCourses = (m['plan_courses'] as List? ?? const [])
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                final isPractice = isPracticeModule(m);
                final isForeign = isForeignLangModule(m);
                if (isForeign) {
                  final seenForeignNames = planCourses
                      .map((pc) => '${pc['name'] ?? ''}'.trim())
                      .where((n) => n.isNotEmpty)
                      .toSet();
                  for (final fc in _c.foreignCourses) {
                    if (seenForeignNames.add(fc.name)) {
                      planCourses.add(<String, dynamic>{
                        'course_id': fc.courseId,
                        'name': fc.name,
                        'credits': fc.credits,
                        'passed': fc.passed,
                        'planned_only': fc.active,
                      });
                    }
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (expanded) {
                              _expandedAuditModules.remove(mid);
                            } else {
                              _expandedAuditModules.add(mid);
                            }
                          });
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                colorLabel(cStr),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: CupertinoColors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: label,
                                ),
                              ),
                            ),
                            Text(
                              '${got.toStringAsFixed(1)}/${req.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                            if (planCourses.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Icon(
                                expanded
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 13,
                                color: secondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (gap > 0 ||
                          selNoCredit > 0 ||
                          m['choice_rule'] != null ||
                          (isPractice && rawPracticePts != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (isPractice && rawPracticePts != null)
                                '素拓实获 ${rawPracticePts.toStringAsFixed(1)} 分 · 有效计 ${got.toStringAsFixed(1)} 分',
                              if (gap > 0) '缺口 ${gap.toStringAsFixed(1)} 分',
                              if (selNoCredit > 0) '已选/重修未获 $selNoCredit 门',
                              if (m['choice_rule'] is Map)
                                '选课约束: ${(m['choice_rule'] as Map)['label'] ?? '选修组'}',
                            ].join(' · '),
                            style: TextStyle(fontSize: 11.5, color: secondary),
                          ),
                        ),
                      if (expanded && planCourses.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: planCourses.map((pc) {
                            final name = '${pc['name'] ?? ''}'.trim();
                            final passed = pc['passed'] == true;
                            final planned = pc['planned_only'] == true ||
                                pc['active'] == true;
                            final cr = (pc['credits'] as num?)?.toDouble();
                            final state = passed
                                ? CompassCourseState.earned
                                : planned
                                    ? CompassCourseState.active
                                    : (_c.courseStates[name] ??
                                        CompassCourseState.unknown);
                            return _buildCourseChip(
                              context,
                              name: name,
                              credits: cr,
                              state: state,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '审计提示 (${warnings.length})',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: label,
                ),
              ),
              const SizedBox(height: 4),
              for (final w in warnings.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${w['text'] ?? ''}',
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ),
            ],
            if (caliberNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final note in caliberNotes.take(3))
                Text(
                  note,
                  style: TextStyle(fontSize: 11, color: secondary),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildForeignLanguageCard(BuildContext context) {
    final gradeYear = parseForeignGradeYear(_c.studentGrade.value);
    final req = _c.effectiveForeignCredits;
    final level = _c.foreignLevel.value;
    final isExempt = isForeignExemptByGrade(gradeYear: gradeYear, level: level);
    final gradeHint = foreignGradeHint(gradeYear: gradeYear) ??
        '已按当前年级政策自动换算外语类学分口径';

    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final accent = _sakuraInk(context);
    final spring = _springInk(context);
    final neutralBg = CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemFill, context);

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '外语分级与应修学分',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: label,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showEditForeignCreditsDialog(context),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.slider_horizontal_3,
                        size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      '自选学分',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: ['L1', 'L2', 'L3'].map((lv) {
              final selected = level == lv;
              final titleText = lv == 'L3'
                  ? foreignL3Label(gradeYear: gradeYear)
                  : lv == 'L1'
                      ? 'L1 (6分)'
                      : 'L2 (4.5分)';
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: lv == 'L3' ? 0 : 8),
                  child: GestureDetector(
                    onTap: () {
                      _c.setCustomForeignCredits(null);
                      _c.setForeignLevel(lv);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? accent : neutralBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        titleText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? CupertinoColors.white : label,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isExempt
                  ? spring.withValues(alpha: 0.12)
                  : accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前生效外语应修：${req.toStringAsFixed(1)} 学分'
                  '${_c.customForeignCredits.value != null ? '（已手动锁定）' : isExempt ? '（符合免修政策）' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isExempt ? spring : label,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  gradeHint,
                  style: TextStyle(fontSize: 11.5, color: secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '已选 / 已修外语类课程 (${_c.foreignCourses.length})',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: 6),
          if (_c.foreignCourses.isEmpty)
            Text(
              '暂未在成绩单或本学期课表中检测到外语类课程',
              style: TextStyle(fontSize: 12, color: secondary),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _c.foreignCourses
                  .map((fc) => _buildCourseChip(
                        context,
                        name: fc.name,
                        credits: fc.credits,
                        extra: fc.passed ? '已通过' : (fc.active ? '在修' : '未获学分'),
                        state: fc.state,
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  List<_SecTreeNode> _buildSecTree(List<PdfModuleSection> sections) {
    final roots = <_SecTreeNode>[];
    final stack = <_SecTreeNode>[];
    for (final s in sections) {
      final node = _SecTreeNode(s);
      while (stack.isNotEmpty && stack.last.sec.level >= s.level) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }
    return roots;
  }

  bool _hasCourseOrRequirement(_SecTreeNode node) {
    if (PlanAuditHelper.isMinorSection(node.sec)) return false;
    if (node.sec.courses.isNotEmpty) return true;
    if (PlanAuditHelper.isForeignSection(node.sec)) return true;
    final pText = '${node.sec.title} ${node.sec.parentPath}';
    if (PlanAuditHelper.practiceClassroomIndex(pText) != null) return true;
    if (certifiedCategoryOf(node.sec.title) != null) return true;
    if (node.sec.creditsRaw.isNotEmpty && node.sec.level >= 2) return true;
    return node.children.any(_hasCourseOrRequirement);
  }

  List<PdfModuleSection> _filteredCourseSections(PlanPdfSections ps) {
    final roots = _buildSecTree(ps.sections);
    final out = <PdfModuleSection>[];
    void walk(_SecTreeNode node) {
      if (PlanAuditHelper.isMinorSection(node.sec)) return;
      if (!_hasCourseOrRequirement(node)) return;
      out.add(node.sec);
      for (final c in node.children) {
        walk(c);
      }
    }
    for (final r in roots) {
      walk(r);
    }
    return out;
  }

  List<PdfModuleSection> _mergedIntroSections(PlanPdfSections ps) {
    final roots = _buildSecTree(ps.sections);
    final out = <PdfModuleSection>[];
    for (final r in roots) {
      if (PlanAuditHelper.isMinorSection(r.sec)) continue;
      if (!_hasCourseOrRequirement(r)) {
        void collect(_SecTreeNode node) {
          if (node.sec.notes.isNotEmpty || node.sec.title.isNotEmpty) {
            out.add(node.sec);
          }
          for (final c in node.children) {
            collect(c);
          }
        }
        collect(r);
      }
    }
    return out;
  }

  Widget _buildPdfTreeCard(BuildContext context) {
    final ps = _c.pdfSections.value;
    if (ps == null || ps.isEmpty) return const SizedBox.shrink();

    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final accent = _sakuraInk(context);
    final cyan = _cyanInk(context);
    final green = _springInk(context);
    final yellow = _peachInk(context);

    final sections = _filteredCourseSections(ps);
    if (sections.isEmpty) return const SizedBox.shrink();
    final visibleSections =
        _showPdfModuleList ? sections : sections.take(0).toList();

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '课程修读要求',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: label,
                ),
              ),
              const Spacer(),
              Text(
                '${sections.where((s) => s.level == 1).length}大类 · ${ps.courseCount}门课',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < visibleSections.length; i++) ...[
            Builder(builder: (ctx) {
              final sec = visibleSections[i];
              final secKey = '${i}_${sec.label}';
              final indent = ((sec.level - 1) * 12.0).clamp(0.0, 36.0);
              final isExpanded = !_collapsedSections.contains(secKey);
              final isForeign = PlanAuditHelper.isForeignSection(sec);
              final practiceIdx = PlanAuditHelper.practiceClassroomIndex(
                  '${sec.title} ${sec.parentPath}');

              final mergedForeignExtras = <ForeignCourseEntry>[];
              if (isForeign) {
                final existingNames =
                    sec.courses.map((c) => c.name.trim()).toSet();
                for (final fc in _c.foreignCourses) {
                  if (!existingNames.contains(fc.name)) {
                    mergedForeignExtras.add(fc);
                  }
                }
              }

              final hasBody = sec.notes.isNotEmpty ||
                  sec.courses.isNotEmpty ||
                  mergedForeignExtras.isNotEmpty ||
                  practiceIdx != null;

              String badgeText = '';
              Color badgeColor = accent;
              if (isForeign) {
                badgeText =
                    '要求 ${_c.effectiveForeignCredits.toStringAsFixed(1)}学分';
              } else if (practiceIdx != null &&
                  (practiceIdx == 2 || practiceIdx == 3 || practiceIdx == 4)) {
                final reqP = practiceIdx == 2
                    ? _c.pt2Required
                    : practiceIdx == 3
                        ? _c.pt3Required
                        : _c.pt4Required;
                final gotP = practiceIdx == 2
                    ? _c.pt2Earned
                    : practiceIdx == 3
                        ? _c.pt3Earned
                        : _c.pt4Earned;
                final displayReq =
                    reqP > 0 ? reqP : (double.tryParse(sec.creditsRaw) ?? 0.0);
                badgeText = displayReq > 0
                    ? '已获 ${gotP.toStringAsFixed(1)}/${displayReq.toStringAsFixed(1)}分'
                    : '已获 ${gotP.toStringAsFixed(1)}分';
                badgeColor =
                    displayReq > 0 && gotP >= displayReq ? green : yellow;
              } else if (practiceIdx == 0) {
                badgeText =
                    '已获 ${_c.practiceEffectiveEarned.toStringAsFixed(1)}/${_c.practiceRequiredTotal.toStringAsFixed(1)}分';
                badgeColor = _c.practiceRequiredTotal > 0 &&
                        _c.practiceEffectiveEarned >= _c.practiceRequiredTotal
                    ? green
                    : yellow;
              } else if (sec.creditsRaw.isNotEmpty) {
                badgeText = sec.isCountRule
                    ? '规则:${sec.creditsRaw}门'
                    : '${sec.creditsRaw}${sec.creditsUnit}';
                badgeColor = sec.isCountRule ? cyan : accent;
              }

              return Padding(
                padding: EdgeInsets.only(left: indent, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: hasBody
                          ? () {
                              setState(() {
                                if (isExpanded) {
                                  _collapsedSections.add(secKey);
                                } else {
                                  _collapsedSections.remove(secKey);
                                }
                              });
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: sec.level == 1
                              ? accent.withValues(alpha: 0.1)
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.tertiarySystemFill, context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                sec.title,
                                style: TextStyle(
                                  fontSize: sec.level <= 2 ? 13.5 : 12.5,
                                  fontWeight: sec.level <= 2
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: sec.level == 1 ? accent : label,
                                ),
                              ),
                            ),
                            if (badgeText.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            ],
                            if (sec.courses.isNotEmpty ||
                                mergedForeignExtras.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${sec.courses.length + mergedForeignExtras.length}门',
                                style:
                                    TextStyle(fontSize: 11, color: secondary),
                              ),
                            ],
                            if (hasBody) ...[
                              const SizedBox(width: 4),
                              Icon(
                                isExpanded
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 12,
                                color: secondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      if (practiceIdx != null)
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 6, left: 6, right: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  practiceIdx == 0
                                      ? '二课 ${_c.pt2Earned.toStringAsFixed(1)} · 三课 ${_c.pt3Earned.toStringAsFixed(1)} · 四课 ${_c.pt4Earned.toStringAsFixed(1)}（已与素拓看板实时同步）'
                                      : '第${practiceIdx == 2 ? '二' : practiceIdx == 3 ? '三' : '四'}课堂实获 ${practiceIdx == 2 ? _c.pt2Earned.toStringAsFixed(1) : practiceIdx == 3 ? _c.pt3Earned.toStringAsFixed(1) : _c.pt4Earned.toStringAsFixed(1)} 分（已同步素拓看板）',
                                  style:
                                      TextStyle(fontSize: 11.5, color: secondary),
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                minSize: 24,
                                onPressed: () => Navigator.of(context,
                                        rootNavigator: true)
                                    .push(
                                  CupertinoPageRoute(
                                    builder: (_) => PracticeScorePage(
                                        scholar: _c.scholar.value),
                                    title: '素拓记点明细',
                                  ),
                                ),
                                child: Text(
                                  '查看明细',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoDynamicColor.resolve(
                                        CupertinoColors.activeBlue, context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (sec.notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 6, left: 6, right: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: sec.notes
                                .map((n) => Text(
                                      n,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        height: 1.4,
                                        color: secondary,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      if (sec.courses.isNotEmpty ||
                          mergedForeignExtras.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...sec.courses.map((course) {
                                final state = _c.courseStates[course.name] ??
                                    CompassCourseState.unknown;
                                final semLabel = PlanAuditHelper.prettySemester(
                                    course.semester);
                                return _buildCourseChip(
                                  context,
                                  name: course.name,
                                  credits: course.credits,
                                  extra: semLabel,
                                  state: state,
                                );
                              }),
                              ...mergedForeignExtras.map((fc) => _buildCourseChip(
                                    context,
                                    name: fc.name,
                                    credits: fc.credits,
                                    extra: fc.passed
                                        ? '已通过'
                                        : (fc.active ? '在修' : '未获学分'),
                                    state: fc.state,
                                  )),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              );
            }),
          ],
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 6),
            onPressed: () => setState(() {
              _showPdfModuleList = !_showPdfModuleList;
              if (_showPdfModuleList) {
                _collapsedSections.clear();
              }
            }),
            child: Text(
              _showPdfModuleList
                  ? '收起模块列表'
                  : '展开全部 ${sections.length} 个子模块',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoreCoursesCard(BuildContext context) {
    final core = _c.coreCourses;
    final practice = _c.practiceCourses;
    final honor = _c.honorCourses;
    final states = _c.courseStates;

    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final spring = _springInk(context);
    final cyan = _cyanInk(context);
    final peach = _peachInk(context);

    Widget buildCourseList(String title, List<String> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: list.map((name) {
              final state = states[name] ?? CompassCourseState.unknown;
              return _buildCourseChip(context, name: name, state: state);
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],
      );
    }

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '核心课程四态进度',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: label,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _legendItem(context, '已修完', spring),
              _legendItem(context, '在修中', cyan),
              _legendItem(context, '需重修', peach),
              _legendItem(context, '未修读', secondary),
            ],
          ),
          const SizedBox(height: 12),
          if (core.isEmpty && practice.isEmpty && honor.isEmpty)
            Text(
              '当前方案摘要未标注核心课程清单，请点击上方“下载并解析官方 PDF 方案”查看完整课程明细。',
              style: TextStyle(fontSize: 12.5, color: secondary),
            )
          else ...[
            buildCourseList('专业核心课程 (${core.length})', core),
            buildCourseList('核心实践环节 (${practice.length})', practice),
            buildCourseList('前沿/荣誉课程 (${honor.length})', honor),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseChip(
    BuildContext context, {
    required String name,
    required CompassCourseState state,
    double? credits,
    String? extra,
  }) {
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    Color bg;
    Color fg;
    switch (state) {
      case CompassCourseState.earned:
        fg = _springInk(context);
        bg = fg.withValues(alpha: 0.12);
        break;
      case CompassCourseState.active:
        fg = _cyanInk(context);
        bg = fg.withValues(alpha: 0.12);
        break;
      case CompassCourseState.noCredit:
        fg = _peachInk(context);
        bg = fg.withValues(alpha: 0.14);
        break;
      case CompassCourseState.unknown:
        bg = CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill, context);
        fg = secondary;
        break;
    }

    final suffixParts = <String>[
      if (credits != null && credits > 0) '${credits.toStringAsFixed(1)}分',
      if (extra != null && extra.isNotEmpty) extra,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: fg.withValues(alpha: state.isUnknown ? 0.2 : 0.45),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              suffixParts.isEmpty
                  ? name
                  : '$name (${suffixParts.join(' · ')})',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    state.isUnknown ? FontWeight.normal : FontWeight.w600,
                color: state.isUnknown ? label : fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectivesCard(BuildContext context) {
    final plan = _c.selectedPlan.value;
    final ps = _c.pdfSections.value;
    final introSections =
        ps != null && !ps.isEmpty ? _mergedIntroSections(ps) : const <PdfModuleSection>[];
    final hasPlanText = plan != null &&
        (plan.pymb.isNotEmpty || plan.pyyq.isNotEmpty || plan.bz.isNotEmpty);
    if (!hasPlanText && introSections.isEmpty) {
      return const SizedBox.shrink();
    }

    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(
                () => _showObjectivesAndNotes = !_showObjectivesAndNotes),
            child: Row(
              children: [
                Text(
                  '培养目标、毕业要求与说明',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: label,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showObjectivesAndNotes
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: secondary,
                ),
              ],
            ),
          ),
          if (_showObjectivesAndNotes) ...[
            if (plan != null && plan.pymb.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('【培养目标】',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: label)),
              const SizedBox(height: 4),
              Text(plan.pymb,
                  style: TextStyle(fontSize: 13, color: secondary, height: 1.5)),
            ],
            if (plan != null && plan.pyyq.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('【毕业/培养要求】',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: label)),
              const SizedBox(height: 4),
              Text(plan.pyyq,
                  style: TextStyle(fontSize: 13, color: secondary, height: 1.5)),
            ],
            if (plan != null && plan.bz.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('【备注说明】',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: label)),
              const SizedBox(height: 4),
              Text(plan.bz,
                  style: TextStyle(fontSize: 13, color: secondary, height: 1.5)),
            ],
            if (introSections.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('【培养方案文字说明汇总】',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: label)),
              const SizedBox(height: 4),
              for (final sec in introSections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sec.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: label,
                        ),
                      ),
                      for (final n in sec.notes)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            n,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, String text) {
    final bg = CupertinoDynamicColor.resolve(
        CupertinoColors.tertiarySystemFill, context);
    final fg = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: fg)),
    );
  }

  Widget _statPill(
      BuildContext context, String title, String value, Color fg) {
    final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 11, color: secondary)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(BuildContext context, String label, Color color) {
    final textColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: textColor)),
      ],
    );
  }

  void _showPlanSelector(BuildContext context) {
    _c.searchQuery.value = '';
    showCupertinoModalPopup(
      context: context,
      builder: (modalCtx) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground, context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Text(
                    '全校培养方案检索与切换',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 28,
                    onPressed: () {
                      Navigator.of(modalCtx).pop();
                      _c.resetToAutoMatch();
                    },
                    child: Text(
                      '恢复推荐',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _sakuraInk(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 28,
                    onPressed: () => Navigator.of(modalCtx).pop(),
                    child: const Text('关闭', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: CupertinoSearchTextField(
                placeholder: '搜索专业名称、学院、年级或计划号',
                onChanged: (v) => _c.searchQuery.value = v,
              ),
            ),
            Expanded(
              child: Obx(() {
                final filtered = _c.filteredCatalog;
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _c.catalog.isEmpty ? '暂无培养方案缓存' : '未匹配到相关培养方案',
                          style: TextStyle(
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel, context),
                          ),
                        ),
                        if (_c.catalog.isEmpty) ...[
                          const SizedBox(height: 12),
                          CupertinoButton.filled(
                            onPressed: () {
                              Navigator.of(modalCtx).pop();
                              _c.syncCatalog(silent: false);
                            },
                            child: const Text('从教务系统拉取全校方案'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                final limited = filtered.take(150).toList();
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: limited.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, idx) {
                    final item = limited[idx];
                    final isCurrent = _c.selectedPlan.value?.id == item.id;
                    final accent = _sakuraInk(context);
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(modalCtx).pop();
                        _c.selectPlan(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? accent.withValues(alpha: 0.14)
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondarySystemGroupedBackground,
                                  context),
                          borderRadius: BorderRadius.circular(10),
                          border: isCurrent
                              ? Border.all(color: accent, width: 1)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.zymc} (${item.synj}级)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.label, context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.xymc} · ${item.dlbsmc} · ${item.creditsLabel}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.secondaryLabel,
                                          context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              Icon(CupertinoIcons.checkmark_circle_fill,
                                  size: 18, color: accent),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditGraduationCreditsDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: _c.effectiveGraduationCredits.toStringAsFixed(1),
    );
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义毕业要求总学分'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            placeholder: '例如 160 或 156.5',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.setCustomGraduationCredits(null);
            },
            child: const Text('恢复默认'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v > 0) {
                _c.setCustomGraduationCredits(v);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showEditForeignCreditsDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: _c.effectiveForeignCredits.toStringAsFixed(1),
    );
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义外语模块应修学分'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            placeholder: '0 表示免修',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.setCustomForeignCredits(null);
            },
            child: const Text('按年级自动'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v >= 0) {
                _c.setCustomForeignCredits(v);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
