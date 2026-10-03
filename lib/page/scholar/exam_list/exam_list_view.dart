import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:celechron/model/exam.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/animate_button.dart';
import 'package:celechron/design/custom_colors.dart';

import 'exam_list_controller.dart';

class ExamListPage extends StatefulWidget {
  final String initialSemesterName;

  const ExamListPage({required this.initialSemesterName, super.key});

  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<ExamListPage> {
  late final ExamListController _examListController;

  @override
  void initState() {
    super.initState();
    Get.delete<ExamListController>();
    _examListController =
        Get.put(ExamListController(initialName: widget.initialSemesterName));
  }

  @override
  void dispose() {
    Get.delete<ExamListController>();
    super.dispose();
  }

  /// 考试冲刺模式卡片（展示下一场即将到来的考试及倒计时）
  Widget _buildSprintHeader(BuildContext context) {
    final next = _examListController.nextExam;
    if (next == null) return const SizedBox.shrink();

    final countdown = _examListController.countdownText(next);
    final remainingCount = _examListController.upcomingExams.length;

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemOrange
            .resolveFrom(context)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CupertinoColors.systemOrange
              .resolveFrom(context)
              .withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.flame_fill,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '考试周冲刺',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.systemOrange.resolveFrom(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  countdown,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            next.name,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '时间：${next.chineseTime}',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .color!
                  .withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () =>
                _examListController.openLocationNavigation(context, next),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '考场：${next.location ?? "未知"} · 座位：${next.seat ?? "未知"}',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.compass,
                  size: 15,
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                ),
                const SizedBox(width: 2),
                Text(
                  '导航',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '本学期剩余 $remainingCount 门未考，加油冲刺！',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .color!
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 单门考试的详情块（含冲突/连考标记、倒计时芯片与考场导航入口）
  Widget _buildSingleExamItem(BuildContext context, Exam exam) {
    final conflict = _examListController.hasConflict(exam);
    final (backToBack, gapMins) = _examListController.checkBackToBack(exam);
    final countdown = _examListController.countdownText(exam);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10.0,
              height: 10.0,
              decoration: BoxDecoration(
                color: CupertinoColors.systemPink,
                shape: exam.type == ExamType.midterm
                    ? BoxShape.circle
                    : BoxShape.rectangle,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                '${exam.name}${exam.type == ExamType.midterm ? "（期中）" : ""}',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                    ),
              ),
            ),
            if (countdown.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (countdown == '进行中'
                          ? CupertinoColors.systemRed
                          : CupertinoColors.activeBlue)
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  countdown,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (countdown == '进行中'
                            ? CupertinoColors.systemRed
                            : CupertinoColors.activeBlue)
                        .resolveFrom(context),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (conflict || backToBack) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (conflict) ...[
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed
                        .resolveFrom(context)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        size: 11,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '时间冲突',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (backToBack) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange
                        .resolveFrom(context)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_right_arrow_left,
                        size: 11,
                        color:
                            CupertinoColors.systemOrange.resolveFrom(context),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '同天连考 (间隔$gapMins分)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color:
                              CupertinoColors.systemOrange.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 4.0),
        Row(
          children: [
            Icon(
              CupertinoIcons.time_solid,
              size: 14,
              color: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .color!
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '时间：${exam.chineseTime}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .color!
                      .withValues(alpha: 0.75),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              _examListController.openLocationNavigation(context, exam),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.location_solid,
                size: 14,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '地点：${exam.location ?? '未知'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.compass,
                size: 13,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
              const SizedBox(width: 2),
              Text(
                '导航',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2.0),
        Row(
          children: [
            Icon(
              CupertinoIcons.map_pin_ellipse,
              size: 14,
              color: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .color!
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '座位：${exam.seat ?? '未知'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .color!
                      .withValues(alpha: 0.75),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _examCard(BuildContext context, List<Exam> exams,
      {bool isPast = false}) {
    return Column(
      children: [
        SubSubtitleRow(subtitle: exams[0].chineseDate),
        Opacity(
          opacity: isPast ? 0.65 : 1.0,
          child: RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSingleExamItem(context, exams[0]),
                  for (var i = 1; i < exams.length; i++) ...[
                    Divider(
                      height: 16,
                      thickness: 1,
                      indent: 0,
                      endIndent: 0,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemFill, context),
                    ),
                    _buildSingleExamItem(context, exams[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _semesterPicker(BuildContext context) {
    return RoundRectangleCardWithForehead(
      forehead: const Row(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 12, top: 4, bottom: 4),
            child: Icon(
              CupertinoIcons.exclamationmark_circle_fill,
              color: CupertinoColors.white,
              size: 14,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 4, top: 4, bottom: 4),
            child: Text(
              '请务必前往教务网核对',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
                color: CupertinoColors.white,
              ),
            ),
          ),
        ],
      ),
      foreheadColor: CupertinoColors.systemRed,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _examListController.semesters.length,
                    itemBuilder: (context, index) {
                      final semester = _examListController.semesters[index];
                      return Obx(() => Stack(
                            children: [
                              AnimateButton(
                                text:
                                    '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                                onTap: () {
                                  _examListController.semesterIndex.value =
                                      index;
                                  _examListController.semesterIndex.refresh();
                                },
                                backgroundColor:
                                    _examListController.semesterIndex.value ==
                                            index
                                        ? CustomCupertinoDynamicColors.cyan
                                        : CupertinoColors.systemFill,
                              ),
                              const SizedBox(width: 90),
                            ],
                          ));
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          const CelechronSliverTextHeader(
            subtitle: '考试',
          ),
          SliverPinnedToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 10, top: 10),
              child: _semesterPicker(context),
            ),
          ),
          Obx(() {
            if (_examListController.isSprintMode) {
              return SliverToBoxAdapter(
                child: _buildSprintHeader(context),
              );
            }
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }),
          Obx(() {
            final upcoming = _examListController.upcomingGroupedExams;
            final past = _examListController.pastGroupedExams;

            if (upcoming.isEmpty && past.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_seal,
                          size: 48,
                          color:
                              CupertinoColors.inactiveGray.resolveFrom(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '本学期暂无考试安排',
                          style: TextStyle(
                            fontSize: 16,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildListDelegate([
                for (final dayExams in upcoming)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: _examCard(context, dayExams),
                  ),
                if (past.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _examListController.showPastExams.toggle();
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _examListController.showPastExams.value
                                ? '收起已结束的考试'
                                : '展开已结束的考试 (${_examListController.pastExams.length} 门)',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                          Icon(
                            _examListController.showPastExams.value
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 14,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_examListController.showPastExams.value)
                    for (final dayExams in past)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                        child: _examCard(context, dayExams, isPast: true),
                      ),
                ],
              ]),
            );
          }),
        ],
      ),
    );
  }
}
