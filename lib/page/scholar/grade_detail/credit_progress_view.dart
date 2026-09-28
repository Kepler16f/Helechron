import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, Divider;
import 'package:get/get.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/grade_detail/credit_progress_controller.dart';

/// 培养方案与学分进度看板（P2）
class CreditProgressPage extends StatelessWidget {
  final _controller = Get.put(CreditProgressController());

  CreditProgressPage({super.key});

  // ==================== 顶部进度大卡片 ====================

  Widget _buildOverviewProgressCard(BuildContext context) {
    return Obx(() {
      final earned = _controller.totalEarnedCredits;
      final target = _controller.targetGraduationCredits.value;
      final ratio = _controller.completionRatio;
      final remaining = _controller.remainingCredits;
      final gpa = _controller.overallGpa.item1[0];

      return RoundRectangleCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 20,
                        color: CupertinoDynamicColor.resolve(
                            CustomCupertinoDynamicColors.sakura, context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '培养方案达成进度',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakura, context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(ratio * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: CupertinoDynamicColor.resolve(
                        CupertinoColors.tertiarySystemFill, context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakura, context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已获: ${earned.toStringAsFixed(1)} 学分',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                  Text(
                    '目标要求: ${target.toStringAsFixed(1)} 学分',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 四宫格统计指标
              Row(
                children: [
                  Expanded(
                    child: TwoLineCard(
                      title: '已修学分',
                      content: earned.toStringAsFixed(1),
                      backgroundColor: CustomCupertinoDynamicColors.sakura,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TwoLineCard(
                      title: '尚缺学分',
                      content: remaining.toStringAsFixed(1),
                      backgroundColor: CustomCupertinoDynamicColors.sand,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TwoLineCard(
                      title: '总平均绩点',
                      content: gpa.toStringAsFixed(2),
                      backgroundColor: CustomCupertinoDynamicColors.cyan,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  // ==================== 智能达标建议提示卡片 ====================

  Widget _buildAdviceCard(BuildContext context) {
    return Obx(() {
      final remaining = _controller.remainingCredits;
      final target = _controller.targetGraduationCredits.value;
      final ratio = _controller.completionRatio;

      String title;
      String message;
      IconData icon;
      Color color;

      if (ratio >= 1.0) {
        title = '已达成毕业总学分要求';
        message = '恭喜！你已累计修满 $target 学分，请确保各项必修课程与毕业论文均已通过审核。';
        icon = CupertinoIcons.check_mark_circled_solid;
        color = CupertinoColors.activeGreen;
      } else if (remaining <= 20.0) {
        title = '毕业冲刺阶段';
        message = '当前仅差 ${remaining.toStringAsFixed(1)} 学分（约 5~8 门课），建议重点核对专业必修课与通识选修要求。';
        icon = CupertinoIcons.flag_fill;
        color = CupertinoColors.activeBlue;
      } else {
        title = '平稳修读中';
        message = '距毕业目标学分还需 ${remaining.toStringAsFixed(1)} 学分，可点击下方各分类查看具体课程达成明细。';
        icon = CupertinoIcons.info_circle_fill;
        color = CustomCupertinoDynamicColors.sakura;
      }

      return RoundRectangleCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: CupertinoDynamicColor.resolve(color, context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: CupertinoDynamicColor.resolve(color, context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ==================== 课程性质分类折叠卡片 ====================

  Widget _buildCategoryGroupCard(
      BuildContext context, CourseCategoryGroup group) {
    return RoundRectangleCard(
      child: Column(
        children: [
          // 分类标题行（点击可展开/折叠）
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onPressed: () {
              group.isExpanded.value = !group.isExpanded.value;
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            group.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.tertiarySystemFill, context),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${group.courseCount} 门',
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已修 ${group.earnedCredits.toStringAsFixed(1)} 学分 · 均绩 ${group.averageGpa > 0 ? group.averageGpa.toStringAsFixed(2) : '-'} · 优秀率 ${(group.excellentRate * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ],
                  ),
                ),
                Obx(
                  () => Icon(
                    group.isExpanded.value
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 16,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                  ),
                ),
              ],
            ),
          ),
          // 展开的课程明细列表
          Obx(() {
            if (!group.isExpanded.value) return const SizedBox.shrink();

            return Column(
              children: [
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.separator, context),
                ),
                for (int i = 0; i < group.courses.length; i++) ...[
                  _buildCourseItemTile(context, group.courses[i]),
                  if (i != group.courses.length - 1)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                    ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCourseItemTile(BuildContext context, Grade grade) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grade.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label, context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${grade.credit.toStringAsFixed(1)} 学分${grade.gpaIncluded ? '' : ' · 不计绩点'}',
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: grade.fivePoint >= 4.5
                  ? CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context)
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill, context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${grade.fivePoint.toStringAsFixed(1)} (${grade.original})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: grade.fivePoint >= 4.5
                    ? null
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.label, context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 弹窗：自定义毕业学分 ====================

  void _showSetTargetDialog(BuildContext context) {
    final textController = TextEditingController(
      text: _controller.targetGraduationCredits.value.toStringAsFixed(1),
    );

    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('设置毕业目标总学分'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              Text(
                '浙大本科常规毕业学分要求为 160.0，部分专业（如医学、建筑、交叉双学位等）可按培养方案微调：',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, dialogCtx),
                ),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: textController,
                placeholder: '目标总学分 (例如: 160.0)',
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('重置为 160.0'),
            onPressed: () {
              _controller.setTargetCredits(160.0);
              Navigator.of(dialogCtx).pop();
            },
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final val = double.tryParse(textController.text.trim());
              if (val != null && val > 0) {
                _controller.setTargetCredits(val);
              }
              Navigator.of(dialogCtx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ==================== 主界面构建 ====================

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: '学分看板',
            right: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Text(
                  '目标设置',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () => _showSetTargetDialog(context),
              ),
            ),
          ),
          // 总体进度与统计
          SliverToBoxAdapter(
            child: _buildOverviewProgressCard(context),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 8),
          ),
          // 建议提示卡片
          SliverToBoxAdapter(
            child: _buildAdviceCard(context),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 12),
          ),
          // 分类标题
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '各类别达成明细',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(点击展开课程)',
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
          // 课程分类折叠卡片列表
          Obx(() {
            final groups = _controller.getCategoryGroups();
            if (groups.isEmpty) {
              return SliverToBoxAdapter(
                child: RoundRectangleCard(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        '暂无课程成绩记录',
                        style: TextStyle(
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildCategoryGroupCard(context, groups[index]),
                  );
                },
                childCount: groups.length,
              ),
            );
          }),
          const SliverToBoxAdapter(
            child: NativeBottomBarSpacer(),
          ),
        ],
      ),
    );
  }
}
