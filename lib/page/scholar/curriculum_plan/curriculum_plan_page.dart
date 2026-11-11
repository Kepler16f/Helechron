import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/model/curriculum_plan_models.dart';
import 'package:celechron/services/curriculum_matching_engine.dart';
import 'curriculum_plan_controller.dart';

class CurriculumPlanPage extends StatelessWidget {
  final _c = Get.put(CurriculumPlanController());

  CurriculumPlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: '培养方案查看',
            right: Obx(() => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minSize: 32,
                      onPressed: () => _showPlanSelector(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                              CustomCupertinoDynamicColors.sakura
                                  .withValues(alpha: 0.15),
                              context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.arrow_right_arrow_left,
                              size: 13,
                              color: CupertinoDynamicColor.resolve(
                                  CustomCupertinoDynamicColors.sakura, context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '切换方案',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: CupertinoDynamicColor.resolve(
                                    CustomCupertinoDynamicColors.sakura,
                                    context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minSize: 32,
                      onPressed: _c.isSyncing.value
                          ? null
                          : () => _c.syncCatalog(),
                      child: _c.isSyncing.value
                          ? const CupertinoActivityIndicator(radius: 8)
                          : Icon(
                              CupertinoIcons.arrow_2_circlepath,
                              size: 18,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                            ),
                    ),
                  ],
                )),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Obx(() {
                final plan = _c.selectedPlan.value;
                if (plan == null && _c.catalog.isEmpty && _c.isSyncing.value) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          CupertinoActivityIndicator(radius: 12),
                          SizedBox(height: 12),
                          Text('正在拉取教务系统全量培养方案目录...'),
                        ],
                      ),
                    ),
                  );
                }

                if (plan == null) {
                  return _buildEmptyState(context);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlanOverviewCard(context, plan),
                    const SizedBox(height: 12),
                    _buildCreditAuditCard(context, plan),
                    const SizedBox(height: 12),
                    _buildForeignLanguageCard(context),
                    const SizedBox(height: 12),
                    _buildCoreCoursesCard(context, plan),
                    const SizedBox(height: 12),
                    if (plan.pymb.isNotEmpty || plan.pyyq.isNotEmpty) ...[
                      _buildObjectivesCard(context, plan),
                      const SizedBox(height: 12),
                    ],
                    _buildOfficialMetaCard(context, plan),
                    const SizedBox(height: 20),
                  ],
                );
              }),
            ),
          ),
          const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
        ],
      ),
    );
  }

  // ==================== 1. 方案概览与学籍画像 ====================

  Widget _buildPlanOverviewCard(BuildContext context, PlanSummary plan) {
    final match = _c.matchResult.value;
    final isAmbiguous = match?.ambiguous == true;

    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  CupertinoIcons.book_fill,
                  size: 18,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.zymc,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plan.synj.isNotEmpty ? "${plan.synj} 级 · " : ""}${plan.xymc.isNotEmpty ? plan.xymc : "浙江大学本科"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    plan.isMajorPlan
                        ? CustomCupertinoDynamicColors.sakura
                            .withValues(alpha: 0.15)
                        : CupertinoColors.tertiarySystemFill,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.dlbsmc.isNotEmpty ? plan.dlbsmc : '主修方案',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: CupertinoDynamicColor.resolve(
                      plan.isMajorPlan
                          ? CustomCupertinoDynamicColors.sakura
                          : CupertinoColors.secondaryLabel,
                      context,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_c.adminClass.value.isNotEmpty)
                _buildInfoBadge(context, '行政班', _c.adminClass.value),
              if (_c.studentGrade.value.isNotEmpty)
                _buildInfoBadge(context, '推导年级', '${_c.studentGrade.value} 级'),
              _buildInfoBadge(context, '学制', '${plan.xz} 年'),
              if (plan.syxw.isNotEmpty) _buildInfoBadge(context, '学位', plan.syxw),
              if (plan.jxjhh.isNotEmpty)
                _buildInfoBadge(context, '教学计划号', plan.jxjhh),
            ],
          ),
          if (isAmbiguous) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showPlanSelector(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.peach.withValues(alpha: 0.15),
                      context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.info_circle_fill,
                      size: 15,
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.peach, context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '该专业包含多个相近方向或大类分流方案，点击可随时核对切换',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoBadge(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill, context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel, context),
        ),
      ),
    );
  }

  // ==================== 2. 三色学分达成度审计看板 ====================

  Widget _buildCreditAuditCard(BuildContext context, PlanSummary plan) {
    final earned = _c.earnedCredits.value;
    final active = _c.activeCredits.value;
    final total = _c.effectiveGraduationCredits;
    final gap = _c.creditGap;
    final rate = _c.completionRate;

    final earnedRatio = total > 0 ? (earned / total).clamp(0.0, 1.0) : 0.0;
    final activeRatio =
        total > 0 ? (active / total).clamp(0.0, 1.0 - earnedRatio) : 0.0;

    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '学分达成进度',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () => _showEditTargetCreditsDialog(context),
                child: Text(
                  '${(rate * 100).toStringAsFixed(1)}% 完成',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: CupertinoDynamicColor.resolve(
                        CustomCupertinoDynamicColors.sakura, context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 三色分段进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.tertiarySystemFill, context),
                  ),
                  FractionallySizedBox(
                    widthFactor: (earnedRatio + activeRatio).clamp(0.0, 1.0),
                    child: Container(
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.cyan, context),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: earnedRatio,
                    child: Container(
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.spring, context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildAuditStat(
                context,
                title: '要求学分',
                value: total.toStringAsFixed(1),
                color: CupertinoColors.secondaryLabel,
                isEditable: true,
                onTap: () => _showEditTargetCreditsDialog(context),
              ),
              _buildAuditStat(
                context,
                title: '已获学分 🟢',
                value: earned.toStringAsFixed(1),
                color: CustomCupertinoDynamicColors.spring,
              ),
              _buildAuditStat(
                context,
                title: '在修学分 🔵',
                value: active.toStringAsFixed(1),
                color: CustomCupertinoDynamicColors.cyan,
              ),
              _buildAuditStat(
                context,
                title: '仍需学分 ⚪',
                value: gap.toStringAsFixed(1),
                color: gap == 0
                    ? CustomCupertinoDynamicColors.spring
                    : CustomCupertinoDynamicColors.peach,
              ),
            ],
          ),
          if (plan.dektxf != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('第二课堂要求：', style: TextStyle(fontSize: 12)),
                  Text(
                    '${plan.dektxf!.toStringAsFixed(1)} 学分',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  if (plan.kcdlxfyq != null) ...[
                    const Spacer(),
                    const Text('课程大类总学分：', style: TextStyle(fontSize: 12)),
                    Text(
                      '${plan.kcdlxfyq!.toStringAsFixed(1)} 学分',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditStat(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
    bool isEditable = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CupertinoDynamicColor.resolve(color, context),
                  ),
                ),
                if (isEditable)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      CupertinoIcons.pencil,
                      size: 11,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 3. 外语（英语）动态规则看板 ====================

  Widget _buildForeignLanguageCard(BuildContext context) {
    final gradeYear = int.tryParse(_c.studentGrade.value);
    final level = _c.foreignLevel.value;
    final isNewRule = gradeYear != null &&
        gradeYear >= ForeignLanguageRule.kNewRuleStartYear;
    final isExempt = ForeignLanguageRule.isExemptByGrade(
      gradeYear: gradeYear,
      level: level,
    );

    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '外语修读要求',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () => _showForeignLanguageSheet(context),
                child: Row(
                  children: [
                    Text(
                      ForeignLanguageRule.levelLabel(
                          gradeYear: gradeYear, level: level),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: CupertinoDynamicColor.resolve(
                            CustomCupertinoDynamicColors.sakura, context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 13,
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakura, context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                isExempt
                    ? CustomCupertinoDynamicColors.spring.withValues(alpha: 0.15)
                    : CupertinoColors.tertiarySystemFill,
                context,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isExempt
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.info_circle,
                  size: 16,
                  color: CupertinoDynamicColor.resolve(
                    isExempt
                        ? CustomCupertinoDynamicColors.spring
                        : CupertinoColors.secondaryLabel,
                    context,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isNewRule
                        ? (isExempt
                            ? '适用 2026 级新规：L3 档次享受外语免修政策（应修学分：0.0）'
                            : '适用 2026 级新规：L1 要求 6.0 分，L2 要求 4.5 分，需修读《大学英语IV》')
                        : '适用老生口径：外语最高封顶（L1=6.0 / L2=4.5 / L3=3.0 只降不升）',
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '当前应修外语学分：${_c.effectiveForeignCredits.toStringAsFixed(1)} 学分',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_c.customForeignCredits.value != null)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => _c.setCustomForeignCredits(null),
                  child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 4. 专业核心课程 Chips 矩阵 ====================

  Widget _buildCoreCoursesCard(BuildContext context, PlanSummary plan) {
    final core = _c.coreCourses;
    final practice = _c.practiceCourses;
    final honor = _c.honorCourses;

    final totalCount = core.length + practice.length + honor.length;

    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '专业核心课程',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${totalCount > 0 ? "$totalCount 门" : "未单独列出"})',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (core.isNotEmpty) ...[
            _buildCourseSectionHeader(context, '专业核心课', core.length),
            const SizedBox(height: 8),
            _buildCourseChips(context, core),
            const SizedBox(height: 12),
          ],
          if (practice.isNotEmpty) ...[
            _buildCourseSectionHeader(context, '核心实践课', practice.length),
            const SizedBox(height: 8),
            _buildCourseChips(context, practice),
            const SizedBox(height: 12),
          ],
          if (honor.isNotEmpty) ...[
            _buildCourseSectionHeader(context, '前沿/荣誉课', honor.length),
            const SizedBox(height: 8),
            _buildCourseChips(context, honor),
            const SizedBox(height: 12),
          ],
          if (totalCount == 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '本培养方案目录中未内嵌扁平核心课程名单，请点击下方官方大纲查看完整教学计划表。',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ),
          ],
          _buildStateLegend(context),
        ],
      ),
    );
  }

  Widget _buildCourseSectionHeader(
      BuildContext context, String title, int count) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
                CustomCupertinoDynamicColors.sakura, context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$title（$count）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel, context),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseChips(BuildContext context, List<String> courses) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: courses.map((c) {
        final state = _c.courseStates[c] ?? PlanCourseState.unknown;
        return _buildSingleCourseChip(context, c, state);
      }).toList(),
    );
  }

  Widget _buildSingleCourseChip(
      BuildContext context, String name, PlanCourseState state) {
    Color bg;
    Color fg;
    IconData icon;

    switch (state) {
      case PlanCourseState.earned:
        bg = CustomCupertinoDynamicColors.spring.withValues(alpha: 0.15);
        fg = CustomCupertinoDynamicColors.spring;
        icon = CupertinoIcons.check_mark_circled_solid;
        break;
      case PlanCourseState.active:
        bg = CustomCupertinoDynamicColors.cyan.withValues(alpha: 0.15);
        fg = CustomCupertinoDynamicColors.cyan;
        icon = CupertinoIcons.time_solid;
        break;
      case PlanCourseState.noCredit:
        bg = CustomCupertinoDynamicColors.peach.withValues(alpha: 0.15);
        fg = CustomCupertinoDynamicColors.peach;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        break;
      case PlanCourseState.unknown:
        bg = CupertinoColors.tertiarySystemFill;
        fg = CupertinoColors.secondaryLabel;
        icon = CupertinoIcons.circle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(bg, context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: CupertinoDynamicColor.resolve(fg, context),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoDynamicColor.resolve(
                  state == PlanCourseState.unknown
                      ? CupertinoColors.label
                      : fg,
                  context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateLegend(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.separator, context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(
              context, '已修完 🟢', CustomCupertinoDynamicColors.spring),
          _buildLegendItem(
              context, '在修中 🔵', CustomCupertinoDynamicColors.cyan),
          _buildLegendItem(
              context, '需重修 🟠', CustomCupertinoDynamicColors.peach),
          _buildLegendItem(context, '未修读 ⚪', CupertinoColors.secondaryLabel),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: CupertinoDynamicColor.resolve(color, context),
      ),
    );
  }

  // ==================== 5. 培养目标与要求 ====================

  Widget _buildObjectivesCard(BuildContext context, PlanSummary plan) {
    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '培养目标与要求',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.label, context),
            ),
          ),
          if (plan.pymb.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '【培养目标】',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              plan.pymb,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
          if (plan.pyyq.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '【培养要求】',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              plan.pyyq,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 6. 官方大纲与外部链接 ====================

  Widget _buildOfficialMetaCard(BuildContext context, PlanSummary plan) {
    return RoundRectangleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '官方教学计划大纲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.label, context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正方教务系统培养方案预览与打印版提供完整板块树及逐门先修要求，支持在浏览器中查看官方原始文档。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondaryLabel, context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context),
                  onPressed: () {
                    final url =
                        'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxsView.html?pyfa_id=${plan.id}&gnmkdm=N153020';
                    launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  },
                  child: const Text('查看官方方案', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill, context),
                  onPressed: () {
                    final url =
                        'https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_dyPyfaxs.html?pyfa_id=${plan.id}&gnmkdm=N153020';
                    launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  },
                  child: Text(
                    '打印版大纲',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            const Icon(CupertinoIcons.doc_text_search, size: 48),
            const SizedBox(height: 12),
            const Text('暂无培养方案数据，请登录教务系统后同步'),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: () => _c.syncCatalog(),
              child: const Text('从教务系统同步方案'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 弹窗交互 ====================

  void _showPlanSelector(BuildContext context) {
    final match = _c.matchResult.value;
    final candidates = match?.candidates ?? [];

    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('选择适用的培养方案'),
        message: Text(
          match?.notes.isNotEmpty == true
              ? match!.notes.join('\n')
              : '匹配算法已根据您的专业与年级排序推荐最符合的方案：',
        ),
        actions: [
          ...candidates.map((c) {
            final p = c.plan;
            final isCurrent = p.id == _c.selectedPlan.value?.id;
            String badge = '';
            if (c.level == PlanMatchLevel.exact) badge = '【全称匹配】';
            if (c.level == PlanMatchLevel.prefix) badge = '【前缀匹配】';
            if (c.gradeMatch) badge += '同年级';

            return CupertinoActionSheetAction(
              child: Row(
                children: [
                  if (isCurrent)
                    const Icon(CupertinoIcons.checkmark, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.zymc} (${p.synj}级)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (badge.isNotEmpty || p.xymc.isNotEmpty)
                          Text(
                            '$badge · ${p.xymc}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                _c.selectPlan(p);
              },
            );
          }),
          CupertinoActionSheetAction(
            child: const Text('重置为系统智能推荐'),
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              _c.resetToAutoMatch();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('取消'),
          onPressed: () => Navigator.of(sheetCtx).pop(),
        ),
      ),
    );
  }

  void _showForeignLanguageSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择外语等级'),
        message: const Text('2026 级起 L3 档次享受外语免修；更早年级按传统封顶口径。'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('L3（2026级免修 / 往届3.0学分）'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.setForeignLevel('L3');
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('L2（要求 4.5 学分，必修大学英语IV）'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.setForeignLevel('L2');
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('L1（要求 6.0 学分，必修大学英语IV）'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _c.setForeignLevel('L1');
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('取消'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  void _showEditTargetCreditsDialog(BuildContext context) {
    final textController = TextEditingController(
      text: _c.effectiveGraduationCredits.toStringAsFixed(1),
    );

    showCupertinoDialog<void>(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('调整目标毕业学分'),
        content: Column(
          children: [
            const SizedBox(height: 10),
            const Text('浙大本科标准为 160.0 学分，部分五年制或大类专业为 210.0 学分。'),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: textController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CupertinoDialogAction(
            child: const Text('恢复默认'),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _c.setCustomGraduationCredits(null);
            },
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('保存'),
            onPressed: () {
              final val = double.tryParse(textController.text.trim());
              if (val != null && val > 0) {
                _c.setCustomGraduationCredits(val);
              }
              Navigator.of(dialogCtx).pop();
            },
          ),
        ],
      ),
    );
  }
}
