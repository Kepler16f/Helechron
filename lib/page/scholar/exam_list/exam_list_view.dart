import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoPageScaffold;
import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/exam.dart';
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
    _examListController = Get.put(
      ExamListController(initialName: widget.initialSemesterName),
    );
  }

  @override
  void dispose() {
    Get.delete<ExamListController>();
    super.dispose();
  }

  /// 考试冲刺模式卡片（展示下一场即将到来的考试及倒计时）
  Widget _buildSprintHeader(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final next = _examListController.nextExam;
    if (next == null) return const SizedBox.shrink();

    final countdown = _examListController.countdownText(next);
    final remainingCount = _examListController.upcomingExams.length;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: AelSectionCard(
        backgroundColor: colors.warningContainer,
        cornerRadius: AelRadius.tile,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AelIcons.exam, color: colors.warning, size: 18),
                const SizedBox(width: 6),
                Text(
                  '考试周冲刺',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colors.warning,
                  ),
                ),
                const Spacer(),
                AelChip(label: countdown, tone: AelChipTone.warning),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              next.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '时间：${next.chineseTime}',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(AelIcons.location, size: 15, color: colors.primary),
                  const SizedBox(width: 2),
                  Text(
                    '导航',
                    style: TextStyle(fontSize: 12, color: colors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '本学期剩余 $remainingCount 门未考，加油冲刺！',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  /// 单门考试的详情块（含冲突/连考标记、倒计时芯片与考场导航入口）
  Widget _buildSingleExamItem(BuildContext context, Exam exam) {
    final colors = AelTheme.colorsOf(context);
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
                color: colors.primary,
                shape: exam.type == ExamType.midterm
                    ? BoxShape.circle
                    : BoxShape.rectangle,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                '${exam.name}${exam.type == ExamType.midterm ? "（期中）" : ""}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (countdown.isNotEmpty) ...[
              AelChip(
                label: countdown,
                tone: countdown == '进行中'
                    ? AelChipTone.error
                    : AelChipTone.primary,
              ),
            ],
          ],
        ),
        if (conflict || backToBack) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (conflict) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AelChip(
                    label: '时间冲突',
                    leadingIcon: AelIcons.warning,
                    tone: AelChipTone.error,
                  ),
                ),
              ],
              if (backToBack) ...[
                AelChip(label: '同天连考(间隔$gapMins分)', tone: AelChipTone.warning),
              ],
            ],
          ),
        ],
        const SizedBox(height: 4.0),
        Row(
          children: [
            Icon(AelIcons.tabFlow, size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '时间：${exam.chineseTime}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: colors.textSecondary,
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
              Icon(AelIcons.location, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '地点：${exam.location ?? '未知'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: colors.primary,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Icon(AelIcons.location, size: 13, color: colors.primary),
              const SizedBox(width: 2),
              Text('导航', style: TextStyle(fontSize: 12, color: colors.primary)),
            ],
          ),
        ),
        const SizedBox(height: 2.0),
        Row(
          children: [
            Icon(AelIcons.activity, size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '座位：${exam.seat ?? '未知'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: colors.textSecondary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _examCard(
    BuildContext context,
    List<Exam> exams, {
    bool isPast = false,
  }) {
    final colors = AelTheme.colorsOf(context);
    return Column(
      children: [
        SubSubtitleRow(subtitle: exams[0].chineseDate),
        Opacity(
          opacity: isPast ? 0.65 : 1.0,
          child: AelSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            cornerRadius: AelRadius.tile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSingleExamItem(context, exams[0]),
                for (var i = 1; i < exams.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.divider,
                    ),
                  ),
                  _buildSingleExamItem(context, exams[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _semesterPicker(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      cornerRadius: AelRadius.tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AelIcons.warning, color: colors.error, size: 15),
              const SizedBox(width: 6),
              Text(
                '请务必前往教务网核对',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _examListController.semesters.length,
              separatorBuilder: (_, __) => const SizedBox(width: AelSpacing.sm),
              itemBuilder: (context, index) {
                final semester = _examListController.semesters[index];
                final label =
                    '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
                return Obx(() {
                  final selected =
                      _examListController.semesterIndex.value == index;
                  return AelChip(
                    label: label,
                    tone: selected ? AelChipTone.primary : AelChipTone.neutral,
                    onTap: () {
                      _examListController.semesterIndex.value = index;
                      _examListController.semesterIndex.refresh();
                    },
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: CustomScrollView(
        slivers: [
          const CelechronSliverTextHeader(subtitle: '考试'),
          SliverPinnedToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 10,
                top: 10,
              ),
              child: _semesterPicker(context),
            ),
          ),
          Obx(() {
            if (_examListController.isSprintMode) {
              return SliverToBoxAdapter(child: _buildSprintHeader(context));
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
                    child: AelEmptyState(
                      icon: AelIcons.check,
                      title: '本学期暂无考试安排',
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildListDelegate([
                for (final dayExams in upcoming)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: _examCard(context, dayExams),
                  ),
                if (past.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _examListController.showPastExams.value
                                ? AelIcons.chevronRight
                                : AelIcons.chevronRight,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_examListController.showPastExams.value)
                    for (final dayExams in past)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
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
