import 'package:flutter/cupertino.dart'
    show
        CupertinoButton,
        CupertinoPageScaffold,
        CupertinoSlider,
        CupertinoSwitch,
        CupertinoTextField,
        OverlayVisibilityMode;
import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/simulated_course.dart';
import 'package:celechron/page/scholar/grade_detail/gpa_simulator_controller.dart';

/// 独立 GPA 模拟器（What-If 计算器与目标逆推）页面
class GpaSimulatorPage extends StatelessWidget {
  final _controller = Get.put(GpaSimulatorController());

  GpaSimulatorPage({super.key});

  static double snapToZjuStep(double val) {
    double closest = GpaSimulatorController.zjuFivePointSteps.first;
    double minDiff = (val - closest).abs();
    for (final step in GpaSimulatorController.zjuFivePointSteps) {
      final diff = (val - step).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = step;
      }
    }
    return closest;
  }

  // ==================== 顶部概览卡片 ====================

  Widget _buildSimulatorSummaryCard(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return Obx(() {
      final scale = _controller.selectedScale.value;
      final currTotalResult = _controller.calculateCurrentTotalGpa();
      final simTotalResult = _controller.calculateSimulatedTotalGpa();
      final simSemResult = _controller.calculateSimulatedSemesterGpa();

      final currGpa = _controller.getGpaValue(currTotalResult.item1, scale);
      final simGpa = _controller.getGpaValue(simTotalResult.item1, scale);
      final simSemGpa = _controller.getGpaValue(simSemResult.item1, scale);
      final delta = _controller.getGpaDelta(scale);

      final deltaStr = delta >= 0
          ? '+${delta.toStringAsFixed(3)}'
          : delta.toStringAsFixed(3);

      return AelSectionCard(
        padding: const EdgeInsets.all(12),
        cornerRadius: AelRadius.tile,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '模拟后总 GPA (${scale.label})',
                    value: scale == GpaScaleType.hundredPoint
                        ? simGpa.toStringAsFixed(1)
                        : simGpa.toStringAsFixed(2),
                    backgroundColor: colors.infoContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AelStatTile(
                    label: '当前实际总 GPA',
                    value: scale == GpaScaleType.hundredPoint
                        ? currGpa.toStringAsFixed(1)
                        : currGpa.toStringAsFixed(2),
                    backgroundColor: colors.primaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '模拟学期自身 GPA',
                    value: scale == GpaScaleType.hundredPoint
                        ? simSemGpa.toStringAsFixed(1)
                        : simSemGpa.toStringAsFixed(2),
                    backgroundColor: colors.tonalTileBg,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AelStatTile(
                    label: '总绩点浮动 Δ',
                    value: deltaStr,
                    backgroundColor: colors.tonalTileBg,
                    valueColor: delta > 0.0001
                        ? colors.success
                        : (delta < -0.0001 ? colors.error : colors.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ==================== 目标逆推卡片 ====================

  Widget _buildTargetGpaCard(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return Obx(() {
      final goal = _controller.calculateGoalSeek();
      final target = _controller.targetGpa.value;

      return AelSectionCard(
        padding: const EdgeInsets.all(14),
        cornerRadius: AelRadius.tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '期望目标总 GPA（五分制）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                AelChip(
                  label: target.toStringAsFixed(2),
                  tone: AelChipTone.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            CupertinoSlider(
              value: target,
              min: 3.0,
              max: 5.0,
              divisions: 40,
              activeColor: colors.primary,
              onChanged: (v) {
                _controller.targetGpa.value = double.parse(
                  v.toStringAsFixed(2),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: goal.isImpossible
                    ? colors.errorContainer
                    : (goal.isAlreadyAchieved
                          ? colors.successContainer
                          : colors.tonalTileBg),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        goal.isImpossible
                            ? AelIcons.error
                            : (goal.isAlreadyAchieved
                                  ? AelIcons.success
                                  : AelIcons.info),
                        size: 16,
                        color: goal.isImpossible
                            ? colors.error
                            : (goal.isAlreadyAchieved
                                  ? colors.success
                                  : colors.primary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        goal.isImpossible
                            ? '目标不可达'
                            : (goal.isAlreadyAchieved ? '目标已锁定' : '目标逆推结论'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: goal.isImpossible
                              ? colors.error
                              : (goal.isAlreadyAchieved
                                    ? colors.success
                                    : colors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    goal.message,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ==================== 快捷操作栏 ====================

  Widget _buildPresetActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AelButton(
              label: '一键全部满绩',
              variant: AelButtonVariant.tonal,
              onPressed: () => _controller.presetAllScores(5.0),
            ),
            const SizedBox(width: 8),
            AelButton(
              label: '全设 4.5 (A-)',
              variant: AelButtonVariant.tonal,
              onPressed: () => _controller.presetAllScores(4.5),
            ),
            const SizedBox(width: 8),
            AelButton(
              label: '全设 4.0 (B+)',
              variant: AelButtonVariant.tonal,
              onPressed: () => _controller.presetAllScores(4.0),
            ),
            const SizedBox(width: 8),
            AelButton(
              label: '添加模拟课程',
              icon: AelIcons.add,
              variant: AelButtonVariant.primary,
              onPressed: () => _showAddCourseDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 模拟课程列表 ====================

  Widget _buildSimulatedCourseList(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return Obx(() {
      final courses = _controller.simulatedCourses;
      if (courses.isEmpty) {
        return AelSectionCard(
          padding: const EdgeInsets.all(24),
          cornerRadius: AelRadius.tile,
          child: AelEmptyState(
            icon: AelIcons.folder,
            title: '暂无待模拟课程',
            actionLabel: '添加模拟课程',
            onAction: () => _showAddCourseDialog(context),
          ),
        );
      }

      return AelSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        cornerRadius: AelRadius.tile,
        child: Column(
          children: [
            for (int i = 0; i < courses.length; i++) ...[
              _buildSimulatedCourseTile(context, courses[i]),
              if (i != courses.length - 1)
                Divider(height: 1, color: colors.divider),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSimulatedCourseTile(
    BuildContext context,
    SimulatedCourse course,
  ) {
    final colors = AelTheme.colorsOf(context);
    final letter = Grade.fivePointToLetter(course.expectedFivePoint);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CupertinoSwitch(
                value: course.isEnabled,
                activeColor: colors.primary,
                onChanged: (val) {
                  _controller.toggleCourseEnabled(course.id);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: course.isEnabled
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course.credit.toStringAsFixed(1)} 学分${course.isCustom ? ' · 自定义' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AelChip(
                label:
                    '${course.expectedFivePoint.toStringAsFixed(1)} ($letter)',
                tone: course.isEnabled
                    ? AelChipTone.primary
                    : AelChipTone.neutral,
              ),
              if (course.isCustom) ...[
                const SizedBox(width: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 28,
                  child: Icon(AelIcons.delete, size: 16, color: colors.error),
                  onPressed: () => _controller.removeCourse(course.id),
                ),
              ],
            ],
          ),
          if (course.isEnabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoSlider(
                    value: course.expectedFivePoint,
                    min: 0.0,
                    max: 5.0,
                    divisions: 10,
                    activeColor: colors.primary,
                    onChanged: (val) {
                      final snapped = snapToZjuStep(val);
                      _controller.setCourseScore(course.id, snapped);
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 弹窗交互 ====================

  void _showAddCourseDialog(BuildContext context) {
    final nameController = TextEditingController(text: '');
    final creditController = TextEditingController(text: '2.0');
    double selectedScore = 4.5;

    showAelDialog<void>(
      context: context,
      title: '添加模拟课程',
      content: StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final colors = AelTheme.colorsOf(dialogCtx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoTextField(
                controller: nameController,
                placeholder: '课程名称 (例如: 计算机系统)',
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.md,
                  vertical: AelSpacing.md,
                ),
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                placeholderStyle: TextStyle(color: colors.textTertiary),
                decoration: BoxDecoration(
                  color: colors.tonalTileBg,
                  borderRadius: BorderRadius.circular(AelRadius.tile),
                ),
              ),
              const SizedBox(height: AelSpacing.sm + 2),
              CupertinoTextField(
                controller: creditController,
                placeholder: '学分 (例如: 3.5)',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.md,
                  vertical: AelSpacing.md,
                ),
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                placeholderStyle: TextStyle(color: colors.textTertiary),
                decoration: BoxDecoration(
                  color: colors.tonalTileBg,
                  borderRadius: BorderRadius.circular(AelRadius.tile),
                ),
              ),
              const SizedBox(height: AelSpacing.md + 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '预估绩点',
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  ),
                  Text(
                    '${selectedScore.toStringAsFixed(1)} (${Grade.fivePointToLetter(selectedScore)})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              CupertinoSlider(
                value: selectedScore,
                min: 0.0,
                max: 5.0,
                divisions: 10,
                activeColor: colors.primary,
                onChanged: (v) {
                  setDialogState(() {
                    selectedScore = snapToZjuStep(v);
                  });
                },
              ),
            ],
          );
        },
      ),
      actions: [
        const AelDialogAction<void>(
          label: '取消',
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<void>(
          label: '添加',
          variant: AelButtonVariant.primary,
          onPressed: () {
            final name = nameController.text.trim();
            final credit = double.tryParse(creditController.text.trim()) ?? 2.0;
            if (name.isNotEmpty) {
              _controller.addCustomCourse(
                name: name,
                credit: credit,
                expectedFivePoint: selectedScore,
              );
            }
          },
        ),
      ],
    ).then((_) {
      nameController.dispose();
      creditController.dispose();
    });
  }

  void _showSimulatorResetActionSheet(BuildContext context) {
    showAelActionSheet<void>(
      context: context,
      title: '重置 GPA 模拟器',
      message: '选择重置范围',
      actions: [
        AelActionOption<void>(
          label: '恢复原始预估分',
          icon: AelIcons.refresh,
          onTap: () => _controller.resetSimulatedScores(),
        ),
        AelActionOption<void>(
          label: '重新读取本学期在读课程',
          icon: AelIcons.book,
          onTap: () => _controller.resetCoursesFromCurrentSemester(),
        ),
        AelActionOption<void>(
          label: '一键全部拉满 5.0',
          icon: AelIcons.sparkles,
          isDestructive: true,
          onTap: () => _controller.presetAllScores(5.0),
        ),
      ],
    );
  }

  // ==================== 主构建流程 ====================

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: 'GPA 模拟器',
            right: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: AelChip(
                label: '重置',
                leadingIcon: AelIcons.refresh,
                tone: AelChipTone.neutral,
                onTap: () => _showSimulatorResetActionSheet(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildSimulatorSummaryCard(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '绩点计算标准:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Obx(
                      () => AelSegmented<GpaScaleType>(
                        value: _controller.selectedScale.value,
                        stackedIcon: false,
                        gap: 4,
                        onChanged: (val) =>
                            _controller.selectedScale.value = val,
                        items: GpaScaleType.values
                            .map(
                              (s) => AelSegmentItem(value: s, label: s.label),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildTargetGpaCard(context),
            ),
          ),
          SliverToBoxAdapter(child: _buildPresetActions(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: 8,
              ),
              child: _buildSimulatedCourseList(context),
            ),
          ),
          const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
        ],
      ),
    );
  }
}
