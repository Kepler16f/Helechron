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

  // ==================== 顶部专业状态与引导卡片 ====================

  Widget _buildMajorCard(BuildContext context) {
    return Obx(() {
      final hasMajor = _controller.hasMajor;
      final major = _controller.userMajor.value;
      final source = _controller.majorSource.value;

      if (hasMajor) {
        return RoundRectangleCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.book_fill,
                  size: 16,
                  color: CupertinoColors.white,
                ),
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
                            major,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              source == 'zdbk_pyfa'
                                  ? CustomCupertinoDynamicColors.sakura
                                  : (source == 'zdbk'
                                      ? CustomCupertinoDynamicColors.spring
                                      : CupertinoColors.tertiarySystemFill),
                              context,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            source == 'zdbk_pyfa'
                                ? '官方培养方案'
                                : (source == 'zdbk' ? '教务网同步' : '手动设置'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: CupertinoDynamicColor.resolve(
                                  source == 'zdbk_pyfa'
                                      ? CupertinoColors.white
                                      : CupertinoColors.label,
                                  context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _controller.trainingPlanName.value.isNotEmpty
                          ? '${_controller.trainingPlanName.value}（${_controller.targetGraduationCredits.value.toStringAsFixed(1)} 学分）'
                          : '培养方案要求：${_controller.targetGraduationCredits.value.toStringAsFixed(1)} 学分',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (source == 'manual') ...[
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minSize: 0,
                  onPressed: () => _controller.resetManualMajor(),
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 18,
                    color: CupertinoColors.destructiveRed,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showSetMajorDialog(context),
                child: const Icon(
                  CupertinoIcons.pencil_circle,
                  size: 22,
                ),
              ),
            ],
          ),
        );
      }

      // 正在从教务网同步
      if (_controller.isSyncingMajor.value) {
        return RoundRectangleCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正在从教务网同步主修专业与培养方案...',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // 未检测到专业时的引导填写卡片
      return RoundRectangleCard(
        onTap: () => _showSetMajorDialog(context),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CustomCupertinoDynamicColors.sand, context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                CupertinoIcons.exclamationmark,
                size: 18,
                color: CupertinoColors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '未检测到专业培养方案',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '点击从教务网同步或选择您的主修专业 >',
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.right_chevron,
              size: 14,
              color: CupertinoColors.systemGrey,
            ),
          ],
        ),
      );
    });
  }

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
                      // 若有该分类的目标学分要求，显示模块达成进度条
                      if (group.targetCredits != null &&
                          group.targetCredits! > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: group.completionRate,
                              backgroundColor: CupertinoDynamicColor.resolve(
                                  CupertinoColors.tertiarySystemFill, context),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CupertinoDynamicColor.resolve(
                                    CustomCupertinoDynamicColors.sakura,
                                    context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '已修 ${group.earnedCredits.toStringAsFixed(1)} / 要求 ${group.targetCredits!.toStringAsFixed(1)} 学分',
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                            Text(
                              '${(group.completionRate * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: CupertinoDynamicColor.resolve(
                                    CustomCupertinoDynamicColors.sakura,
                                    context),
                              ),
                            ),
                          ],
                        ),
                      ],
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
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: group.courses.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.separator, context),
                  ),
                  itemBuilder: (context, index) {
                    final grade = group.courses[index];
                    return _buildCourseItemRow(context, grade);
                  },
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ==================== 单门课程行 ====================

  Widget _buildCourseItemRow(BuildContext context, Grade grade) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

  // ==================== 弹窗：设置主修专业与培养方案 ====================

  void _showSetMajorDialog(BuildContext context) {
    final majorTextController =
        TextEditingController(text: _controller.userMajor.value);
    final creditsTextController = TextEditingController(
      text: _controller.targetGraduationCredits.value.toStringAsFixed(1),
    );

    const popularMajors = [
      '工科试验班（信息）',
      '计算机科学与技术',
      '软件工程',
      '人工智能',
      '工科试验班',
      '信息与电子工程',
      '自动化',
      '电气工程及其自动化',
      '机械工程',
      '理科试验班',
      '数学与应用数学',
      '物理学',
      '经济学',
      '社会科学试验班',
      '人文科学试验班',
      '临床医学',
      '建筑学',
      '竺可桢学院荣誉课程',
    ];

    showCupertinoModalPopup<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return CupertinoActionSheet(
            title: const Text('设置主修专业与培养方案'),
            message: const Text('从教务网同步或选择你的专业，将自动匹配该专业的毕业学分和各模块分类要求：'),
            actions: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '主修专业/大类名称',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, dialogCtx),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: _controller.isSyncingMajor.value
                              ? null
                              : () async {
                                  await _controller.syncMajorFromZdbk();
                                  setModalState(() {
                                    if (_controller.userMajor.value.isNotEmpty) {
                                      majorTextController.text =
                                          _controller.userMajor.value;
                                      creditsTextController.text = _controller
                                          .targetGraduationCredits.value
                                          .toStringAsFixed(1);
                                    }
                                  });
                                },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_controller.isSyncingMajor.value) ...[
                                const CupertinoActivityIndicator(radius: 6),
                                const SizedBox(width: 4),
                              ] else ...[
                                Icon(
                                  CupertinoIcons.arrow_2_circlepath,
                                  size: 13,
                                  color: CupertinoDynamicColor.resolve(
                                      CustomCupertinoDynamicColors.sakura,
                                      dialogCtx),
                                ),
                                const SizedBox(width: 2),
                              ],
                              Text(
                                _controller.isSyncingMajor.value
                                    ? '正在同步...'
                                    : '从教务网同步',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                      CustomCupertinoDynamicColors.sakura,
                                      dialogCtx),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: majorTextController,
                      placeholder: '请输入专业名称（例如：工科试验班（信息））',
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '常见大类与专业快捷选择：',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: popularMajors.map((m) {
                        final isSelected = majorTextController.text == m;
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              majorTextController.text = m;
                              final isFiveYear = m.contains('建筑') ||
                                  m.contains('医学') ||
                                  m.contains('临床');
                              creditsTextController.text = (isFiveYear
                                      ? 210.0
                                      : 160.0)
                                  .toStringAsFixed(1);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: CupertinoDynamicColor.resolve(
                                isSelected
                                    ? CustomCupertinoDynamicColors.sakura
                                    : CupertinoColors.tertiarySystemFill,
                                dialogCtx,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              m,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: CupertinoDynamicColor.resolve(
                                  isSelected
                                      ? CupertinoColors.white
                                      : CupertinoColors.label,
                                  dialogCtx,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '毕业目标学分要求',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.label, dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: creditsTextController,
                      placeholder: '常规专业为 160.0，五年制医学/建筑为 210.0',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton.filled(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: const Text('保存培养方案'),
                            onPressed: () async {
                              final major = majorTextController.text.trim();
                              if (major.isNotEmpty) {
                                final credits = double.tryParse(
                                    creditsTextController.text.trim());
                                _controller.setUserMajor(major,
                                    targetCredits: credits);
                              } else {
                                await _controller.resetManualMajor();
                              }
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_controller.hasMajor ||
                        _controller.majorSource.value == 'manual') ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          color:
                              CupertinoColors.destructiveRed.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                CupertinoIcons.trash,
                                size: 16,
                                color: CupertinoColors.destructiveRed,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '删除手动设置 / 恢复默认',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.destructiveRed,
                                ),
                              ),
                            ],
                          ),
                          onPressed: () async {
                            await _controller.resetManualMajor();
                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
          );
        },
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
                  '方案设置',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () => _showSetMajorDialog(context),
              ),
            ),
          ),
          // 专业培养方案状态与引导卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildMajorCard(context),
            ),
          ),
          // 总体进度与统计
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildOverviewProgressCard(context),
            ),
          ),
          // 建议提示卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: _buildAdviceCard(context),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 4),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
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
