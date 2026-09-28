import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:get/get.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/simulated_course.dart';
import 'package:celechron/page/scholar/grade_detail/weighted_gpa_controller.dart';

/// 加权成绩与 GPA 模拟器（What-If 计算器）页面
class WeightedGpaPage extends StatelessWidget {
  final _controller = Get.put(WeightedGpaController());

  WeightedGpaPage({super.key});

  static double snapToZjuStep(double val) {
    double closest = WeightedGpaController.zjuFivePointSteps.first;
    double minDiff = (val - closest).abs();
    for (final step in WeightedGpaController.zjuFivePointSteps) {
      final diff = (val - step).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = step;
      }
    }
    return closest;
  }

  // ==================== 原版加权绩点 UI ====================

  Widget _buildWeightedGpaBrief(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Hero(
                tag: 'weightedGpaBrief',
                child: RoundRectangleCard(
                  child: Obx(() {
                    final gpaResult =
                        _controller.calculateCurrentSemesterWeightedGpa();
                    final gpa = gpaResult.item1;
                    final credits = gpaResult.item2;

                    return Row(
                      children: [
                        Expanded(
                          child: TwoLineCard(
                            title: '加权学分',
                            content: credits.toStringAsFixed(1),
                            backgroundColor: CustomCupertinoDynamicColors.sand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TwoLineCard(
                            title: '加权五分制',
                            content: gpa[0].toStringAsFixed(2),
                            backgroundColor:
                                CustomCupertinoDynamicColors.sakura,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSemesterPicker(BuildContext context) {
    return RoundRectangleCard(
      animate: false,
      child: Column(
        children: [
          SizedBox(
            height: 81,
            child: Obx(
              () => ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _controller.semestersWithGrades.length,
                itemBuilder: (context, index) {
                  final semester = _controller.semestersWithGrades[index];

                  return Obx(
                    () => Row(
                      children: [
                        TwoLineCard(
                          animate: true,
                          withColoredFont: true,
                          width: 120,
                          title:
                              '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                          content:
                              '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                          onTap: () {
                            _controller.semesterIndex.value = index;
                            _controller.semesterIndex.refresh();
                          },
                          backgroundColor:
                              _controller.semesterIndex.value == index
                                  ? CustomCupertinoDynamicColors.cyan
                                  : CupertinoColors.systemFill,
                        ),
                        if (index != _controller.semestersWithGrades.length - 1)
                          const SizedBox(width: 6),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== GPA 模拟器 UI 组件 ====================

  /// 模拟器顶部 KPI 仪表板
  Widget _buildSimulatorBrief(BuildContext context) {
    return Obx(() {
      final currTotal = _controller.calculateCurrentTotalGpa();
      final simTotal = _controller.calculateSimulatedTotalGpa();
      final simSemester = _controller.calculateSimulatedSemesterGpa();
      final scale = _controller.selectedScale.value;

      final currVal = _controller.getGpaValue(currTotal.item1, scale);
      final simVal = _controller.getGpaValue(simTotal.item1, scale);
      final delta = simVal - currVal;
      final deltaText = delta >= 0
          ? '+${delta.toStringAsFixed(2)}'
          : delta.toStringAsFixed(2);

      final deltaColor = delta > 0.001
          ? CupertinoColors.systemGreen
          : (delta < -0.001
              ? CupertinoColors.systemRed
              : CupertinoColors.secondaryLabel);

      return Column(
        children: [
          RoundRectangleCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                              CustomCupertinoDynamicColors.sakura, context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '模拟后总 GPA (${scale.label})',
                              style: TextStyle(
                                fontSize: 12,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  simVal.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: deltaColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    deltaText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: deltaColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '当前实际: ${currVal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                              CustomCupertinoDynamicColors.sand, context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '模拟总学分',
                              style: TextStyle(
                                fontSize: 12,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${simTotal.item2.toStringAsFixed(1)} 学分',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '模拟学期均绩: ${_controller.getGpaValue(simSemester.item1, scale).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                              overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 12),
        ],
      );
    });
  }

  /// 模拟器控制栏（体制切换、模式切换、快捷赋分）
  Widget _buildSimulatorControls(BuildContext context) {
    return Obx(() {
      final subTab = _controller.simulatorSubTab.value;
      return RoundRectangleCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 绩点体制选择
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<GpaScaleType>(
                groupValue: _controller.selectedScale.value,
                children: {
                  for (final scale in GpaScaleType.values)
                    scale: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        scale.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                },
                onValueChanged: (val) {
                  if (val != null) _controller.selectedScale.value = val;
                },
              ),
            ),
            const SizedBox(height: 10),
            // 子模式选择
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<SimulatorSubTab>(
                groupValue: subTab,
                children: const {
                  SimulatorSubTab.whatIf: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'What-If 成绩推演',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  SimulatorSubTab.goalSeek: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '目标 GPA 逆推',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                },
                onValueChanged: (val) {
                  if (val != null) _controller.simulatorSubTab.value = val;
                },
              ),
            ),
            const SizedBox(height: 10),
            // 根据子模式展示操作区
            if (subTab == SimulatorSubTab.whatIf) ...[
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildQuickPresetButton(context, '全满 (5.0)', 5.0),
                  _buildQuickPresetButton(context, '全优 (4.5)', 4.5),
                  _buildQuickPresetButton(context, '全良 (4.2)', 4.2),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemFill, context),
                    borderRadius: BorderRadius.circular(8),
                    minSize: 30,
                    child: Text(
                      '恢复初值',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.label, context),
                      ),
                    ),
                    onPressed: () => _controller.resetSimulatedScores(),
                  ),
                ],
              ),
            ] else ...[
              _buildGoalSeekPanel(context),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildQuickPresetButton(
      BuildContext context, String text, double score) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color:
          CupertinoDynamicColor.resolve(CupertinoColors.systemFill, context),
      borderRadius: BorderRadius.circular(8),
      minSize: 30,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.activeBlue, context),
        ),
      ),
      onPressed: () => _controller.presetAllScores(score),
    );
  }

  /// 目标逆推控制面板
  Widget _buildGoalSeekPanel(BuildContext context) {
    final goalResult = _controller.calculateGoalSeek();
    final target = _controller.targetGpa.value;

    Color badgeColor = CupertinoColors.activeBlue;
    String badgeTitle = '测算完成';
    if (goalResult.isImpossible) {
      badgeColor = CupertinoColors.systemRed;
      badgeTitle = '不可达成';
    } else if (goalResult.isAlreadyAchieved) {
      badgeColor = CupertinoColors.systemGreen;
      badgeTitle = '稳操胜券';
    } else if (goalResult.requiredGpa >= 4.8) {
      badgeColor = CupertinoColors.systemOrange;
      badgeTitle = '极具挑战';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '期望目标总 GPA (五分制):',
              style: TextStyle(fontSize: 13),
            ),
            Text(
              target.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.activeBlue,
              ),
            ),
          ],
        ),
        CupertinoSlider(
          value: target,
          min: 3.0,
          max: 5.0,
          divisions: 40,
          activeColor: CupertinoColors.activeBlue,
          onChanged: (val) {
            _controller.targetGpa.value = (val * 20).round() / 20;
          },
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (goalResult.hasCredits && !goalResult.isImpossible)
                    Text(
                      '需达到平均 ${goalResult.requiredGpa.toStringAsFixed(2)} 绩点',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                goalResult.message,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 模拟课程列表头部
  Widget _buildSimulatorListHeader(BuildContext context) {
    return Obx(() {
      final total = _controller.simulatedCourses.length;
      final enabled =
          _controller.simulatedCourses.where((c) => c.isEnabled).length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '待考与模拟课程 ($enabled/$total 门参算)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 20,
              child: const Row(
                children: [
                  Icon(CupertinoIcons.plus_circle_fill, size: 16),
                  SizedBox(width: 4),
                  Text('添加课程', style: TextStyle(fontSize: 13)),
                ],
              ),
              onPressed: () => _showAddCustomCourseDialog(context),
            ),
          ],
        ),
      );
    });
  }

  /// 单门模拟课程卡片
  Widget _buildSimulatedCourseCard(
      BuildContext context, SimulatedCourse course) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题、学分、成绩与开关
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CupertinoSwitch(
                value: course.isEnabled,
                onChanged: (_) => _controller.toggleCourseEnabled(course.id),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            course.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: course.isEnabled
                                  ? CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context)
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.tertiaryLabel, context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (course.isCustom) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemIndigo
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '自定义',
                              style: TextStyle(
                                fontSize: 10,
                                color: CupertinoColors.systemIndigo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course.credit.toStringAsFixed(1)} 学分',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 绩点微标（点击可弹窗直接选择等级）
              GestureDetector(
                onTap: () => _showGradePickerSheet(context, course),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondarySystemBackground, context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: CupertinoColors.activeBlue.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        course.expectedFivePoint.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${course.gradeLetter})',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (course.isCustom)
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 6),
                  minSize: 24,
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 16,
                    color: CupertinoColors.systemRed,
                  ),
                  onPressed: () => _controller.removeCourse(course.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 绩点快速滑动条
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '预期绩点',
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.tertiaryLabel, context),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 16,
                  child: CupertinoSlider(
                    value: course.expectedFivePoint,
                    min: 0.0,
                    max: 5.0,
                    divisions: 10,
                    activeColor: course.isEnabled
                        ? CupertinoDynamicColor.resolve(
                            CupertinoColors.activeBlue, context)
                        : CupertinoColors.systemGrey4,
                    onChanged: course.isEnabled
                        ? (val) {
                            final snapped = snapToZjuStep(val);
                            _controller.setCourseScore(course.id, snapped);
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 弹窗与选择器 ====================

  void _showAddCustomCourseDialog(BuildContext context) {
    final nameController = TextEditingController();
    final creditController = TextEditingController(text: '3.0');
    double selectedScore = 4.5;

    showCupertinoDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text('添加模拟课程'),
              content: Column(
                children: [
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: nameController,
                    placeholder: '课程名称（如：计算机体系结构）',
                    clearButtonMode: OverlayVisibilityMode.editing,
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: creditController,
                    placeholder: '学分（如：3.0）',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('预期成绩:'),
                      Text(
                        '${selectedScore.toStringAsFixed(1)} 分 (${Grade.fivePointToLetter(selectedScore)})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                    ],
                  ),
                  CupertinoSlider(
                    value: selectedScore,
                    min: 0.0,
                    max: 5.0,
                    divisions: 10,
                    onChanged: (val) {
                      setDialogState(() {
                        selectedScore = snapToZjuStep(val);
                      });
                    },
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('添加'),
                  onPressed: () {
                    final name = nameController.text.trim();
                    final credit =
                        double.tryParse(creditController.text.trim()) ?? 2.0;
                    _controller.addCustomCourse(
                      name: name.isEmpty ? '自定义课程' : name,
                      credit: credit,
                      expectedFivePoint: selectedScore,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showGradePickerSheet(BuildContext context, SimulatedCourse course) {
    showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('${course.name} · 选择预期绩点'),
        actions: WeightedGpaController.zjuFivePointSteps.map((step) {
          final letter = Grade.fivePointToLetter(step);
          final isSelected = (course.expectedFivePoint - step).abs() < 0.05;
          return CupertinoActionSheetAction(
            onPressed: () {
              _controller.setCourseScore(course.id, step);
              Navigator.of(sheetContext).pop();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${step.toStringAsFixed(1)} 绩点  ($letter)',
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? CupertinoColors.activeBlue : null,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark_alt, size: 18),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showSimulatorResetActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('重置选项'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('恢复课程初始成绩'),
            onPressed: () {
              _controller.resetSimulatedScores();
              Navigator.of(sheetContext).pop();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('重新载入最新学期课程'),
            onPressed: () {
              _controller.resetCoursesFromCurrentSemester();
              Navigator.of(sheetContext).pop();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  // ==================== 主构建函数 ====================

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tab = _controller.currentTab.value;
      final semesterGrades = _controller.getCurrentSemesterGrades();
      final affectGpaGrades =
          semesterGrades.where((g) => g.gpaIncluded).toList();
      affectGpaGrades.sort((a, b) => a.name.compareTo(b.name));

      return CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: CustomScrollView(
          slivers: [
            CelechronSliverTextHeader(
              subtitle: tab == WeightedGpaTab.weight ? '加权成绩' : 'GPA 模拟器',
              right: Obx(
                () => Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tab == WeightedGpaTab.weight) ...[
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: const Text(
                            '重置',
                            style: TextStyle(fontSize: 16),
                          ),
                          onPressed: () {
                            _controller.weightedMap.value = {};
                            _controller.refreshWeightedGpa();
                          },
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: Text(
                            _controller.showAllSemesters.value ? '按学期' : '全选',
                            style: const TextStyle(fontSize: 16),
                          ),
                          onPressed: () {
                            _controller.showAllSemesters.value =
                                !_controller.showAllSemesters.value;
                          },
                        ),
                      ] else ...[
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: const Text(
                            '重置',
                            style: TextStyle(fontSize: 16),
                          ),
                          onPressed: () =>
                              _showSimulatorResetActionSheet(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // 模式选择分段控件
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<WeightedGpaTab>(
                    groupValue: tab,
                    children: const {
                      WeightedGpaTab.weight: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          '加权比例测算',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      WeightedGpaTab.simulator: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'GPA 模拟器 (What-If)',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    },
                    onValueChanged: (val) {
                      if (val != null) _controller.currentTab.value = val;
                    },
                  ),
                ),
              ),
            ),

            // 根据模式切换主内容
            if (tab == WeightedGpaTab.weight) ...[
              // 原版加权成绩部分
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 18),
                        Expanded(
                          child: _buildWeightedGpaBrief(context),
                        ),
                        const SizedBox(width: 18),
                      ],
                    ),
                    Obx(
                      () => _controller.showAllSemesters.value
                          ? const SizedBox.shrink()
                          : Row(
                              children: [
                                const SizedBox(width: 18),
                                Expanded(
                                  child: _buildSemesterPicker(context),
                                ),
                                const SizedBox(width: 18),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final grade = affectGpaGrades[index];
                    return Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 18),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.only(
                                    left: 12, right: 12, bottom: 16, top: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemBackground,
                                      context),
                                  boxShadow: [
                                    BoxShadow(
                                      color: CupertinoColors.black
                                          .withValues(alpha: 0.1),
                                      spreadRadius: 0,
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                grade.name,
                                                style: CupertinoTheme.of(
                                                        context)
                                                    .textTheme
                                                    .textStyle
                                                    .copyWith(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.normal,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                              ),
                                              Text(
                                                '${grade.realId} / ${grade.credit.toStringAsFixed(1)} 学分',
                                                style: CupertinoTheme.of(
                                                        context)
                                                    .textTheme
                                                    .textStyle
                                                    .copyWith(
                                                      color: CupertinoTheme.of(
                                                              context)
                                                          .textTheme
                                                          .textStyle
                                                          .color!
                                                          .withValues(
                                                              alpha: 0.5),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.normal,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${grade.original} / ${grade.fivePoint.toStringAsFixed(1)}',
                                          style: CupertinoTheme.of(context)
                                              .textTheme
                                              .textStyle
                                              .copyWith(
                                                fontSize: 20,
                                                fontWeight: FontWeight.normal,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Obx(() {
                                      const double minValue = 0.8;
                                      const double maxValue = 1.2;
                                      const double devideStep = 0.2;
                                      final int divisions =
                                          ((maxValue - minValue) / devideStep)
                                              .round();

                                      final currentWeight =
                                          _controller.getWeight(grade.id);

                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 56,
                                            child: Text(
                                              '加权比例',
                                              style: CupertinoTheme.of(
                                                      context)
                                                  .textTheme
                                                  .textStyle
                                                  .copyWith(
                                                    fontSize: 12,
                                                    color: CupertinoTheme.of(
                                                            context)
                                                        .textTheme
                                                        .textStyle
                                                        .color!
                                                        .withValues(
                                                            alpha: 0.5),
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: SizedBox(
                                              height: 8,
                                              child: CupertinoSlider(
                                                value: currentWeight,
                                                min: minValue,
                                                max: maxValue,
                                                divisions: divisions,
                                                activeColor:
                                                    CupertinoDynamicColor.resolve(
                                                        CupertinoColors
                                                            .systemTeal,
                                                        context),
                                                onChanged: (value) {
                                                  _controller.setWeight(
                                                      grade.id, value);
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 24,
                                            child: Text(
                                              currentWeight
                                                  .toStringAsFixed(1),
                                              textAlign: TextAlign.right,
                                              style: CupertinoTheme.of(
                                                      context)
                                                  .textTheme
                                                  .textStyle
                                                  .copyWith(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    color: CupertinoTheme.of(
                                                            context)
                                                        .textTheme
                                                        .textStyle
                                                        .color!
                                                        .withValues(
                                                            alpha: 0.7),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                  childCount: affectGpaGrades.length,
                ),
              ),
            ] else ...[
              // GPA 模拟器部分
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      _buildSimulatorBrief(context),
                      _buildSimulatorControls(context),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildSimulatorListHeader(context),
              ),
              Obx(
                () => SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final course = _controller.simulatedCourses[index];
                      return _buildSimulatedCourseCard(context, course);
                    },
                    childCount: _controller.simulatedCourses.length,
                  ),
                ),
              ),
            ],
            // 底部原生避让留白
            const SliverToBoxAdapter(
              child: NativeBottomBarSpacer(extra: 24),
            ),
          ],
        ),
      );
    });
  }
}
