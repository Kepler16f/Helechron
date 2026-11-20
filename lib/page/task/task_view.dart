import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AlwaysStoppedAnimation, LinearProgressIndicator;
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/scholar/todo/todo_card.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/services/todo_task_sync.dart';
import 'package:celechron/utils/utils.dart';

import 'homework_submission_page.dart';
import 'task_edit_page.dart';

class TaskPage extends StatelessWidget {
  TaskPage({super.key});

  final _taskController = Get.put(TaskController());
  final _flowController = Get.put(FlowController());

  String deadlineProgress(Task deadline) {
    return '${(deadline.getProgress() * 100).toInt()}% 已完成：预期 ${durationToString(deadline.timeNeeded)}，还要 ${durationToString(deadline.timeNeeded <= deadline.timeSpent ? Duration.zero : (deadline.timeNeeded - deadline.timeSpent))}';
  }

  String _getHomeworkCourseName(Task task) {
    for (final line in task.description.split('\n')) {
      if (line.startsWith('课程：')) {
        return line.substring(3).trim();
      }
    }
    return '学在浙大';
  }

  ({bool isSubmitted, bool isGraded, double? score, bool isQuiz})
  _resolveTaskHomeworkState(Task deadline) {
    String? aid;
    if (deadline.fromUid != null &&
        deadline.fromUid!.startsWith('courses-todo:')) {
      aid = deadline.fromUid!.substring('courses-todo:'.length);
    }
    final recorded = aid != null ? TodoTaskSync.getHomeworkStatus(aid) : null;
    final score = (recorded?['score'] as num?)?.toDouble();
    final completeness = recorded?['completeness']?.toString();
    final isQuiz = deadline.isQuiz || (recorded?['is_quiz'] == true);
    final isExplicitlyIncomplete =
        completeness != null && completeness != 'full' && score == null;
    final isSubmitted =
        !isExplicitlyIncomplete &&
        (completeness == 'full' ||
            score != null ||
            deadline.status == TaskStatus.completed);
    return (
      isSubmitted: isSubmitted,
      isGraded: score != null,
      score: score,
      isQuiz: isQuiz,
    );
  }

  Widget _buildHomeworkRefreshButton(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Obx(() {
      final refreshing = _taskController.isRefreshingHomework.value;
      return GestureDetector(
        onTap: refreshing ? null : () => _taskController.refreshHomework(),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.primaryContainer,
            shape: AelShapes.squircle(AelRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (refreshing)
                  const CupertinoActivityIndicator(radius: 5.5)
                else
                  Icon(
                    AelIcons.refresh,
                    size: 12,
                    color: colors.onPrimaryContainer,
                  ),
                const SizedBox(width: 4),
                Text(
                  refreshing ? '同步中' : '刷新',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> showCardDialog(BuildContext context, Task deadline) async {
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        String titleType;
        if (deadline.type == TaskType.homework) {
          titleType = deadline.status == TaskStatus.completed
              ? '已完成'
              : (deadline.endTime.isBefore(DateTime.now()) ? '已过期' : '待提交');
        } else if (deadline.type == TaskType.deadline) {
          titleType = deadlineStatusName[deadline.status]!;
        } else if (deadline.type == TaskType.fixed) {
          titleType = deadlineTypeName[TaskType.fixed]!;
        } else {
          titleType = '';
        }

        return CupertinoAlertDialog(
          title: Text(
            '${deadline.summary}：$titleType',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (deadline.type == TaskType.fixed) ...[
                    Text('开始于 ${toStringHumanReadable(deadline.startTime)}'),
                    Text('结束于 ${toStringHumanReadable(deadline.endTime)}'),
                  ],
                  if (deadline.type == TaskType.deadline ||
                      deadline.type == TaskType.homework) ...[
                    Text(
                      '截止于 ${toStringHumanReadable(deadline.endTime)}${deadline.endTime.isBefore(DateTime.now()) ? ' - 已过期' : ''}',
                    ),
                  ],
                  if (deadline.type == TaskType.deadline) ...[
                    Text(deadlineProgress(deadline)),
                  ],
                  if (deadline.location.isNotEmpty) ...[
                    Text('地点：${deadline.location}'),
                  ],
                  if (deadline.description.isNotEmpty) ...[
                    Text('说明：${deadline.description}'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('返回'),
            ),
            if (extractCoursesUrl(deadline.description) != null)
              CupertinoDialogAction(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  String? aid;
                  if (deadline.fromUid != null &&
                      deadline.fromUid!.startsWith('courses-todo:')) {
                    aid = deadline.fromUid!.substring('courses-todo:'.length);
                  }
                  showTodoSubmitSheet(
                    context,
                    extractCoursesUrl(deadline.description)!,
                    title: deadline.summary,
                    activityId: aid,
                  );
                },
                child: const Text('作业选项与状态探测'),
              ),
            if (deadline.type == TaskType.homework)
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status != TaskStatus.completed) {
                    deadline.status = TaskStatus.completed;
                  } else {
                    deadline.forceRefreshStatus();
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(dialogContext).pop();
                },
                child: Text(
                  '标记为${deadline.status == TaskStatus.completed ? '未' : ''}完成',
                ),
              ),
            if (deadline.type == TaskType.deadline &&
                deadline.timeSpent < deadline.timeNeeded)
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status != TaskStatus.completed) {
                    deadline.status = TaskStatus.completed;
                  } else {
                    deadline.forceRefreshStatus();
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(dialogContext).pop();
                },
                child: Text(
                  '标记为${deadline.status == TaskStatus.completed ? '未' : ''}完成',
                ),
              ),
            if (deadline.type == TaskType.deadline &&
                (deadline.status == TaskStatus.running ||
                    deadline.status == TaskStatus.suspended))
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status == TaskStatus.running) {
                    deadline.status = TaskStatus.suspended;
                  } else {
                    deadline.status = TaskStatus.running;
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(dialogContext).pop();
                },
                child: Text(
                  deadline.status == TaskStatus.running ? '暂停' : '继续',
                ),
              ),
            if (deadline.type == TaskType.deadline ||
                deadline.type == TaskType.fixed)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  Task res =
                      await showCupertinoModalPopup(
                        context: context,
                        builder: (BuildContext context) {
                          return TaskEditPage(deadline);
                        },
                      ) ??
                      deadline;
                  bool needUpdate = deadline.differentForFlow(res);
                  deadline.copy(res);
                  _taskController.updateDeadlineList();
                  if (needUpdate) {
                    _taskController.updateDeadlineListTime();
                  }
                  _taskController.taskList.refresh();
                  _taskController.saveDeadlineListToDb();
                },
                child: const Text('编辑'),
              ),
            if (deadline.type == TaskType.fixedlegacy ||
                deadline.type == TaskType.homework)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  deadline.status = TaskStatus.deleted;
                  _taskController.updateDeadlineList();
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                },
                child: const Text('删除'),
              ),
          ],
        );
      },
    );
  }

  Future<void> newDeadline(BuildContext context) async {
    DateTime time = DateTime.now();
    Task? deadline = Task(endTime: time, startTime: time, repeatEndsTime: time);
    deadline.reset();
    Task? res = await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return TaskEditPage(deadline);
      },
    );
    if (res != null && res.status != TaskStatus.deleted) {
      _taskController.lastChangeIsHomeworkOnly.value = false;
      _taskController.taskList.add(res);
      _taskController.updateDeadlineList();
      _taskController.updateDeadlineListTime();
      _flowController.removeFlowInFlowList();
      DateTime now = DateTime.now();
      DateTime startsAt = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      );
      _flowController.generateNewFlowList(startsAt);
      _taskController.taskList.refresh();
    }
  }

  Widget _buildDismissibleTaskTile(
    BuildContext context,
    Task deadline,
    Color color,
    AelColorTokens colors,
  ) {
    final bool canSwipeComplete =
        deadline.type == TaskType.deadline ||
        deadline.type == TaskType.homework;
    final bool isDone = deadline.status == TaskStatus.completed;

    return Dismissible(
      key: Key(deadline.uid),
      direction: canSwipeComplete
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      movementDuration: AelDurations.normal,
      resizeDuration: AelDurations.normal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      background: canSwipeComplete
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: isDone ? colors.warning : colors.success,
                shape: AelShapes.squircle(AelRadius.tile),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: AelIconBadge(
                    icon: isDone ? AelIcons.refresh : AelIcons.check,
                    style: AelIconBadgeStyle.circle,
                    size: 36,
                    iconSize: 18,
                    backgroundColor: colors.cardBg.withValues(alpha: 0.25),
                    iconColor: colors.onPrimary,
                  ),
                ),
              ),
            )
          : null,
      secondaryBackground: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.error,
          shape: AelShapes.squircle(AelRadius.tile),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AelIconBadge(
              icon: AelIcons.delete,
              style: AelIconBadgeStyle.circle,
              size: 36,
              iconSize: 18,
              backgroundColor: colors.cardBg.withValues(alpha: 0.25),
              iconColor: colors.onPrimary,
            ),
          ),
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (deadline.type == TaskType.deadline) {
            if (deadline.status == TaskStatus.completed) {
              deadline.timeSpent = const Duration(minutes: 0);
              deadline.forceRefreshStatus();
            } else {
              deadline.timeSpent = deadline.timeNeeded;
              deadline.status = TaskStatus.completed;
            }
            _taskController.lastChangeIsHomeworkOnly.value = false;
            _taskController.updateDeadlineList();
            _taskController.updateDeadlineListTime();
            _flowController.removeFlowInFlowList();
            DateTime now = DateTime.now();
            DateTime startsAt = DateTime(
              now.year,
              now.month,
              now.day,
              now.hour,
              now.minute,
            );
            _flowController.generateNewFlowList(startsAt);
            _taskController.taskList.refresh();
          } else if (deadline.type == TaskType.homework) {
            if (deadline.status == TaskStatus.completed) {
              deadline.forceRefreshStatus();
            } else {
              deadline.status = TaskStatus.completed;
            }
            final isCompleted = deadline.status == TaskStatus.completed;
            if (deadline.fromUid != null &&
                deadline.fromUid!.startsWith('courses-todo:')) {
              final aid = deadline.fromUid!.substring('courses-todo:'.length);
              TodoTaskSync.recordHomeworkStatus(
                aid,
                completeness: isCompleted ? 'full' : 'incomplete',
                clearIfIncomplete: !isCompleted,
                isQuiz: deadline.isQuiz ? true : null,
              );
              if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
                final scholarRx = Get.find<Rx<Scholar>>(tag: 'scholar');
                for (final todo in scholarRx.value.todos) {
                  if (todo.id == aid) {
                    todo.completeness = isCompleted ? 'full' : 'incomplete';
                    todo.submissionStatus = isCompleted
                        ? HomeworkSubmissionStatus.submitted
                        : HomeworkSubmissionStatus.unsubmitted;
                    break;
                  }
                }
                scholarRx.refresh();
              }
            }
            _taskController.lastChangeIsHomeworkOnly.value = true;
            _taskController.updateDeadlineList();
            _taskController.updateDeadlineListTime();
            _taskController.taskList.refresh();
          }
          return false;
        } else if (direction == DismissDirection.endToStart) {
          return true;
        }
        return false;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          deadline.status = TaskStatus.deleted;
          _taskController.lastChangeIsHomeworkOnly.value =
              deadline.type == TaskType.homework;
          _taskController.updateDeadlineList();
          _taskController.updateDeadlineListTime();
          _flowController.removeFlowInFlowList();
          DateTime now = DateTime.now();
          DateTime startsAt = DateTime(
            now.year,
            now.month,
            now.day,
            now.hour,
            now.minute,
          );
          _flowController.generateNewFlowList(startsAt);
          _taskController.taskList.refresh();
        }
      },
      child: AelSectionCard(
        cornerRadius: AelRadius.tile,
        backgroundColor: colors.tonalTileBg,
        padding: const EdgeInsets.all(14),
        onTap: () async {
          if (deadline.type == TaskType.homework) {
            await Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute(
                builder: (context) => HomeworkSubmissionPage(task: deadline),
              ),
            );
            return;
          }
          Task? res = await Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (context) => TaskEditPage(deadline)),
          );
          if (res != null && res.status != TaskStatus.deleted) {
            deadline.copy(res);
            _taskController.updateDeadlineList();
            _taskController.updateDeadlineListTime();
            _flowController.removeFlowInFlowList();
            DateTime now = DateTime.now();
            DateTime startsAt = DateTime(
              now.year,
              now.month,
              now.day,
              now.hour,
              now.minute,
            );
            _flowController.generateNewFlowList(startsAt);
            _taskController.taskList.refresh();
          }
        },
        onLongPress: () async {
          if (deadline.type == TaskType.homework) {
            await showCardDialog(context, deadline);
          }
        },
        child: deadline.type == TaskType.homework
            ? Builder(
                builder: (context) {
                  final state = _resolveTaskHomeworkState(deadline);
                  final hasUrl =
                      extractCoursesUrl(deadline.description) != null;
                  return HomeworkTaskItemContent(
                    indicatorColor: color,
                    title: deadline.summary,
                    courseName: _getHomeworkCourseName(deadline),
                    endTime: deadline.endTime,
                    isQuiz: state.isQuiz,
                    isSubmitted: state.isSubmitted,
                    isGraded: state.isGraded,
                    score: state.score,
                    onOpenSubmission: hasUrl
                        ? () {
                            Navigator.of(context, rootNavigator: true).push(
                              CupertinoPageRoute(
                                builder: (context) =>
                                    HomeworkSubmissionPage(task: deadline),
                              ),
                            );
                          }
                        : null,
                  );
                },
              )
            : _buildRegularTaskBody(context, deadline, color, colors),
      ),
    );
  }

  Widget _buildRegularTaskBody(
    BuildContext context,
    Task deadline,
    Color color,
    AelColorTokens colors,
  ) {
    final progress = deadline.getProgress();
    final isOverdue =
        deadline.type == TaskType.deadline &&
        deadline.status != TaskStatus.completed &&
        deadline.endTime.isBefore(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AelIconBadge(
              icon: deadline.type == TaskType.fixed
                  ? AelIcons.tabCalendar
                  : AelIcons.tabTask,
              style: AelIconBadgeStyle.circle,
              size: 32,
              iconSize: 15,
              backgroundColor: color.withValues(
                alpha: colors.isDark ? 0.24 : 0.16,
              ),
              iconColor: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                deadline.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(() {
              final now = _flowController.timeNow.value;
              final String statusText;
              final AelChipTone tone;
              if (deadline.type == TaskType.deadline) {
                statusText = deadlineStatusName[deadline.status]!;
                tone = switch (deadline.status) {
                  TaskStatus.completed => AelChipTone.success,
                  TaskStatus.failed => AelChipTone.error,
                  TaskStatus.suspended => AelChipTone.warning,
                  _ => isOverdue ? AelChipTone.error : AelChipTone.primary,
                };
              } else {
                if (now.isBefore(deadline.startTime)) {
                  statusText = '未开始';
                  tone = AelChipTone.neutral;
                } else if (!now.isBefore(deadline.endTime)) {
                  statusText = '已结束';
                  tone = AelChipTone.neutral;
                } else {
                  statusText = '进行中';
                  tone = AelChipTone.primary;
                }
              }
              return AelChip(label: statusText, tone: tone);
            }),
          ],
        ),
        const SizedBox(height: 10),
        _metaLine(
          colors,
          AelIcons.tabFlow,
          deadline.type == TaskType.fixed
              ? '开始于：${toStringHumanReadable(deadline.startTime)}'
              : '截止于：${toStringHumanReadable(deadline.endTime)}${deadline.endTime.isBefore(DateTime.now()) ? ' · 已过期' : ''}',
        ),
        if (deadline.type == TaskType.fixed) ...[
          const SizedBox(height: 4),
          _metaLine(
            colors,
            AelIcons.tabFlow,
            '结束于：${toStringHumanReadable(deadline.endTime)}',
          ),
        ],
        if (deadline.location.isNotEmpty) ...[
          const SizedBox(height: 4),
          _metaLine(colors, AelIcons.location, '地点：${deadline.location}'),
        ],
        if (deadline.type == TaskType.deadline) ...[
          const SizedBox(height: 4),
          _metaLine(colors, AelIcons.video, deadlineProgress(deadline)),
        ],
        if (deadline.type == TaskType.fixed ||
            deadline.type == TaskType.deadline) ...[
          const SizedBox(height: 10),
          Obx(() {
            final _ = _flowController.timeNow.value;
            final double barVal;
            if (deadline.type == TaskType.fixed ||
                deadline.status == TaskStatus.running) {
              barVal = deadline.getProgress();
            } else if (deadline.status == TaskStatus.suspended) {
              barVal = progress;
            } else if (deadline.status == TaskStatus.completed) {
              barVal = 1.0;
            } else {
              barVal = 0.0;
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(AelRadius.pill),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: barVal,
                backgroundColor: colors.cardBg,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _metaLine(AelColorTokens colors, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13.5, color: colors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Task> items,
    required AelColorTokens colors,
    Widget? trailing,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AelSpacing.sectionGap),
      child: AelSectionCard(
        icon: icon,
        title: title,
        trailing:
            trailing ??
            AelChip(label: '${items.length} 项', tone: AelChipTone.neutral),
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AelSpacing.sm),
              _buildDismissibleTaskTile(
                context,
                items[i],
                UidColors.colorFromUid(items[i].uid),
                colors,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMoreActions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        actions: <Widget>[
          CupertinoActionSheetAction(
            child: const Text('删除已完成任务'),
            onPressed: () async {
              _taskController.removeCompletedDeadline(sheetContext);
              _taskController.updateDeadlineList();
              _taskController.taskList.refresh();
              Navigator.of(sheetContext).pop();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('删除已过期任务'),
            onPressed: () async {
              _taskController.removeFailedDeadline(sheetContext);
              _taskController.updateDeadlineList();
              _taskController.taskList.refresh();
              Navigator.of(sheetContext).pop();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('刷新学在浙大作业'),
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              await _taskController.refreshHomework();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('暂停所有任务'),
            onPressed: () {
              if (_taskController.suspendAllDeadline(sheetContext) > 0) {
                _flowController.removeFlowInFlowList();
                _taskController.updateDeadlineListTime();
                _taskController.taskList.refresh();
              }
              Navigator.of(sheetContext).pop();
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('继续所有任务'),
            onPressed: () {
              if (_taskController.continueAllDeadline(sheetContext) > 0) {
                _flowController.removeFlowInFlowList();
                _taskController.updateDeadlineListTime();
                _taskController.taskList.refresh();
              }
              Navigator.of(sheetContext).pop();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.pageBg),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AelLargeTitleBar(
                title: '任务',
                actions: [
                  AelCircleIconButton(
                    icon: AelIcons.add,
                    tooltip: '新建任务',
                    onPressed: () async {
                      await newDeadline(context);
                      _taskController.updateDeadlineList();
                      _taskController.taskList.refresh();
                    },
                  ),
                  AelCircleIconButton(
                    icon: AelIcons.more,
                    tooltip: '更多操作',
                    onPressed: () => _showMoreActions(context),
                  ),
                ],
              ),
            ),
            Obx(() {
              final hw = _taskController.todoHomeworkList;
              final todo = _taskController.todoDeadlineList;
              final done = _taskController.doneDeadlineList;
              final fixed = _taskController.fixedDeadlineList;

              if (hw.isEmpty && todo.isEmpty && done.isEmpty && fixed.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AelSpacing.pageHorizontal,
                      vertical: AelSpacing.xl,
                    ),
                    child: AelEmptyState(
                      icon: AelIcons.tabTask,
                      title: '没有任务',
                      subtitle: '当前没有待办作业或任务安排',
                      actionLabel: '新建任务',
                      onAction: () async {
                        await newDeadline(context);
                        _taskController.updateDeadlineList();
                        _taskController.taskList.refresh();
                      },
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.pageHorizontal,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSection(
                      context,
                      icon: AelIcons.homework,
                      title: '课程作业',
                      items: hw,
                      colors: colors,
                      trailing: _buildHomeworkRefreshButton(context),
                    ),
                    _buildSection(
                      context,
                      icon: AelIcons.tabTask,
                      title: '待办',
                      items: todo,
                      colors: colors,
                    ),
                    _buildSection(
                      context,
                      icon: AelIcons.success,
                      title: '已完成',
                      items: done,
                      colors: colors,
                    ),
                    _buildSection(
                      context,
                      icon: AelIcons.tabCalendar,
                      title: '日程列表',
                      items: fixed,
                      colors: colors,
                    ),
                  ]),
                ),
              );
            }),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
