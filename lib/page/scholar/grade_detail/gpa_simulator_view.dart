import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import 'package:get/get.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/native_bar_spacer.dart';
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
      final deltaColor = delta > 0.0001
          ? CupertinoColors.activeGreen
          : (delta < -0.0001
              ? CupertinoColors.destructiveRed
              : CupertinoColors.secondaryLabel);

      return Column(
        children: [
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TwoLineCard(
                          title: '模拟后总 GPA (${scale.label})',
                          content: scale == GpaScaleType.hundredPoint
                              ? simGpa.toStringAsFixed(1)
                              : simGpa.toStringAsFixed(2),
                          backgroundColor:
                              CustomCupertinoDynamicColors.sakura,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TwoLineCard(
                          title: '当前实际总 GPA',
                          content: scale == GpaScaleType.hundredPoint
                              ? currGpa.toStringAsFixed(1)
                              : currGpa.toStringAsFixed(2),
                          backgroundColor: CustomCupertinoDynamicColors.sand,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TwoLineCard(
                          title: '模拟学期自身 GPA',
                          content: scale == GpaScaleType.hundredPoint
                              ? simSemGpa.toStringAsFixed(1)
                              : simSemGpa.toStringAsFixed(2),
                          backgroundColor: CustomCupertinoDynamicColors.cyan,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.tertiarySystemFill, context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '总绩点浮动 Δ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondaryLabel, context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                deltaStr,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoDynamicColor.resolve(
                                      deltaColor, context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    });
  }

  // ==================== 目标逆推卡片 ====================

  Widget _buildTargetGpaCard(BuildContext context) {
    return Obx(() {
      final goal = _controller.calculateGoalSeek();
      final target = _controller.targetGpa.value;

      return Column(
        children: [
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                              CustomCupertinoDynamicColors.sakura, context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          target.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CupertinoSlider(
                    value: target,
                    min: 3.0,
                    max: 5.0,
                    divisions: 40,
                    activeColor: CustomCupertinoDynamicColors.sakura,
                    onChanged: (v) {
                      _controller.targetGpa.value =
                          double.parse(v.toStringAsFixed(2));
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                          goal.isImpossible
                              ? CupertinoColors.destructiveRed.withOpacity(0.12)
                              : (goal.isAlreadyAchieved
                                  ? CupertinoColors.activeGreen.withOpacity(0.12)
                                  : CupertinoColors.secondarySystemFill),
                          context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              goal.isImpossible
                                  ? CupertinoIcons.exclamationmark_circle_fill
                                  : (goal.isAlreadyAchieved
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.info_circle_fill),
                              size: 16,
                              color: CupertinoDynamicColor.resolve(
                                  goal.isImpossible
                                      ? CupertinoColors.destructiveRed
                                      : (goal.isAlreadyAchieved
                                          ? CupertinoColors.activeGreen
                                          : CupertinoColors.activeBlue),
                                  context),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              goal.isImpossible
                                  ? '目标不可达'
                                  : (goal.isAlreadyAchieved
                                      ? '目标已锁定'
                                      : '目标逆推结论'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: CupertinoDynamicColor.resolve(
                                    goal.isImpossible
                                        ? CupertinoColors.destructiveRed
                                        : (goal.isAlreadyAchieved
                                            ? CupertinoColors.activeGreen
                                            : CupertinoColors.activeBlue),
                                    context),
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
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    });
  }

  // ==================== 快捷操作栏 ====================

  Widget _buildPresetActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemFill, context),
              borderRadius: BorderRadius.circular(8),
              minSize: 32,
              child: Text(
                '一键全部满绩',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              onPressed: () => _controller.presetAllScores(5.0),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemFill, context),
              borderRadius: BorderRadius.circular(8),
              minSize: 32,
              child: Text(
                '全设 4.5 (A-)',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              onPressed: () => _controller.presetAllScores(4.5),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemFill, context),
              borderRadius: BorderRadius.circular(8),
              minSize: 32,
              child: Text(
                '全设 4.0 (B+)',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                ),
              ),
              onPressed: () => _controller.presetAllScores(4.0),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: CupertinoDynamicColor.resolve(
                  CustomCupertinoDynamicColors.sakura, context),
              borderRadius: BorderRadius.circular(8),
              minSize: 32,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.plus_circle, size: 14),
                  SizedBox(width: 4),
                  Text(
                    '添加模拟课程',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              onPressed: () => _showAddCourseDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 模拟课程列表 ====================

  Widget _buildSimulatedCourseList(BuildContext context) {
    return Obx(() {
      final courses = _controller.simulatedCourses;
      if (courses.isEmpty) {
        return RoundRectangleCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.tray,
                  size: 40,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
                const SizedBox(height: 8),
                Text(
                  '暂无待模拟课程',
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Text('添加模拟课程', style: TextStyle(fontSize: 14)),
                  onPressed: () => _showAddCourseDialog(context),
                ),
              ],
            ),
          ),
        );
      }

      return RoundRectangleCard(
        child: Column(
          children: [
            for (int i = 0; i < courses.length; i++) ...[
              _buildSimulatedCourseTile(context, courses[i]),
              if (i != courses.length - 1)
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.separator, context),
                ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSimulatedCourseTile(
      BuildContext context, SimulatedCourse course) {
    final letter = Grade.fivePointToLetter(course.expectedFivePoint);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CupertinoSwitch(
                value: course.isEnabled,
                activeColor: CustomCupertinoDynamicColors.sakura,
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
                            ? CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context)
                            : CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel, context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course.credit.toStringAsFixed(1)} 学分${course.isCustom ? ' · 自定义' : ''}',
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
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: course.isEnabled
                      ? CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakura, context)
                      : CupertinoDynamicColor.resolve(
                          CupertinoColors.tertiarySystemFill, context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${course.expectedFivePoint.toStringAsFixed(1)} ($letter)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: course.isEnabled
                        ? null
                        : CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                  ),
                ),
              ),
              if (course.isCustom) ...[
                const SizedBox(width: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 28,
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 16,
                    color: CupertinoColors.destructiveRed,
                  ),
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
                    activeColor: CustomCupertinoDynamicColors.sakura,
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

    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text('添加模拟课程'),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: nameController,
                      placeholder: '课程名称 (例如: 计算机系统)',
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: creditController,
                      placeholder: '学分 (例如: 3.5)',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('预估绩点:'),
                        Text(
                          '${selectedScore.toStringAsFixed(1)} (${Grade.fivePointToLetter(selectedScore)})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    CupertinoSlider(
                      value: selectedScore,
                      min: 0.0,
                      max: 5.0,
                      divisions: 10,
                      activeColor: CustomCupertinoDynamicColors.sakura,
                      onChanged: (v) {
                        setDialogState(() {
                          selectedScore = snapToZjuStep(v);
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () {
                    final name = nameController.text.trim();
                    final credit =
                        double.tryParse(creditController.text.trim()) ?? 2.0;
                    if (name.isNotEmpty) {
                      _controller.addCustomCourse(
                        name: name,
                        credit: credit,
                        expectedFivePoint: selectedScore,
                      );
                    }
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSimulatorResetActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('重置 GPA 模拟器'),
        message: const Text('选择重置范围'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.resetSimulatedScores();
            },
            child: const Text('恢复原始预估分'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.resetCoursesFromCurrentSemester();
            },
            child: const Text('重新读取本学期在读课程'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.presetAllScores(5.0);
            },
            child: const Text('一键全部拉满 5.0'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  // ==================== 主构建流程 ====================

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: 'GPA 模拟器',
            right: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Text(
                  '重置',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () => _showSimulatorResetActionSheet(context),
              ),
            ),
          ),
          // 模式切换分段控件：正向推演 vs 目标逆推
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: Obx(
                  () => CupertinoSlidingSegmentedControl<SimulatorSubTab>(
                    groupValue: _controller.simulatorSubTab.value,
                    children: const {
                      SimulatorSubTab.whatIf: Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          '正向推演 (What-If)',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      SimulatorSubTab.goalSeek: Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          '目标逆推 (Goal-Seek)',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    },
                    onValueChanged: (val) {
                      if (val != null) {
                        _controller.simulatorSubTab.value = val;
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          // 绩点体制分段选择（仅在正向推演模式下展示）
          SliverToBoxAdapter(
            child: Obx(() {
              if (_controller.simulatorSubTab.value != SimulatorSubTab.whatIf) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<GpaScaleType>(
                    groupValue: _controller.selectedScale.value,
                    children: const {
                      GpaScaleType.fivePoint: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('五分制', style: TextStyle(fontSize: 12)),
                      ),
                      GpaScaleType.fourPointScale: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('出国 4.3', style: TextStyle(fontSize: 12)),
                      ),
                      GpaScaleType.legacyFourPoint: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('原始 4.0', style: TextStyle(fontSize: 12)),
                      ),
                      GpaScaleType.hundredPoint: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('百分制', style: TextStyle(fontSize: 12)),
                      ),
                    },
                    onValueChanged: (val) {
                      if (val != null) {
                        _controller.selectedScale.value = val;
                      }
                    },
                  ),
                ),
              );
            }),
          ),
          // 推演核心结果卡片
          SliverToBoxAdapter(
            child: Obx(() {
              if (_controller.simulatorSubTab.value == SimulatorSubTab.whatIf) {
                return _buildSimulatorSummaryCard(context);
              } else {
                return _buildTargetGpaCard(context);
              }
            }),
          ),
          // 快捷操作栏
          SliverToBoxAdapter(
            child: _buildPresetActions(context),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 8),
          ),
          // 模拟课程列表
          SliverToBoxAdapter(
            child: _buildSimulatedCourseList(context),
          ),
          const SliverToBoxAdapter(
            child: NativeBottomBarSpacer(),
          ),
        ],
      ),
    );
  }
}
