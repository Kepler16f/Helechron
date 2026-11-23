import 'package:flutter/cupertino.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';
import 'package:celechron/utils/time_helper.dart';

class TaskEditPage extends StatefulWidget {
  final Task deadline;
  const TaskEditPage(this.deadline, {super.key});

  @override
  State<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<TaskEditPage> {
  late Task now;
  int __got = 0;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _descriptionCtrl;

  @override
  void initState() {
    super.initState();
    now = widget.deadline.copyWith();
    if (now.startTime.isAfter(now.endTime)) {
      now.startTime = now.endTime.add(const Duration(minutes: -1));
    }
    final baseDate = now.type == TaskType.fixed ? now.startTime : now.endTime;
    if (now.repeatEndsTime.isAfter(DateTime(2099, 1, 1)) ||
        dateOnly(now.repeatEndsTime).isBefore(dateOnly(baseDate))) {
      now.repeatEndsTime = dateOnly(baseDate);
    }
    __got = 1;
    _summaryCtrl = TextEditingController(text: now.summary);
    _locationCtrl = TextEditingController(text: now.location);
    _descriptionCtrl = TextEditingController(text: now.description);
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void saveAndExit() {
    if (now.type == TaskType.fixed && !now.startTime.isBefore(now.endTime)) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text('开始时间必须晚于结束时间'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return;
    }

    if (now.type == TaskType.fixed &&
        now.repeatType != TaskRepeatType.norepeat &&
        dateOnly(now.startTime).isAfter(dateOnly(now.repeatEndsTime))) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text('开始时间不能晚于重复截止日期'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return;
    }

    if (now.type == TaskType.fixed &&
        now.repeatType != TaskRepeatType.norepeat) {
      int length = now.endTime.difference(now.startTime).inMinutes;
      if ((now.repeatType == TaskRepeatType.days &&
              length > now.repeatPeriod * 24 * 60) ||
          (now.repeatType == TaskRepeatType.month && length > 28 * 24 * 60) ||
          (now.repeatType == TaskRepeatType.year && length > 365 * 24 * 60)) {
        showCupertinoDialog(
          context: context,
          builder: (BuildContext context) {
            return CupertinoAlertDialog(
              title: const Text('这个重复日程的持续时间太长'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('确定'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
        return;
      }
    }

    FormState().save();
    now.forceRefreshStatus();
    Navigator.of(context).pop(now);
  }

  void removeAndExit() {
    now.status = TaskStatus.deleted;
    Navigator.of(context).pop(now);
  }

  void exitWithoutSave() {
    now = widget.deadline.copyWith();
    Navigator.of(context).pop(now);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    if (__got == 0) {
      now = widget.deadline.copyWith();
      __got = 1;
    }

    List<String> deadlineRepeatTypeNameList = [];
    for (var i in TaskRepeatType.values) {
      deadlineRepeatTypeNameList.add(deadlineRepeatTypeName[i]!);
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    AelCircleIconButton(
                      icon: AelIcons.close,
                      size: 36,
                      iconSize: 18,
                      tooltip: '取消',
                      onPressed: exitWithoutSave,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '编辑任务',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    AelCircleIconButton(
                      icon: AelIcons.check,
                      size: 36,
                      iconSize: 18,
                      tooltip: '保存',
                      onPressed: saveAndExit,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AelSegmented<TaskType>(
                      stackedIcon: false,
                      value: now.type,
                      items: [
                        AelSegmentItem(
                          value: TaskType.deadline,
                          label: '${deadlineTypeName[TaskType.deadline]}',
                          icon: AelIcons.tabTask,
                        ),
                        AelSegmentItem(
                          value: TaskType.fixed,
                          label: '${deadlineTypeName[TaskType.fixed]}',
                          icon: AelIcons.tabCalendar,
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          now.type = value;
                          if (now.type == TaskType.fixed) {
                            now.status = TaskStatus.running;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: AelSpacing.md),
                    AelSectionCard(
                      title: '基本信息',
                      icon: AelIcons.edit,
                      child: Column(
                        children: [
                          CupertinoTextField(
                            placeholder: '任务名',
                            controller: _summaryCtrl,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            style: TextStyle(color: colors.textPrimary),
                            placeholderStyle: TextStyle(
                              color: colors.textTertiary,
                            ),
                            decoration: BoxDecoration(
                              color: colors.tonalTileBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onChanged: (value) => now.summary = value,
                          ),
                          if (now.type == TaskType.fixed) ...[
                            const SizedBox(height: AelSpacing.sm),
                            AelListRow(
                              icon: AelIcons.tabFlow,
                              title: '开始时间',
                              trailing: Text(
                                TimeHelper.chineseDateTime(now.startTime),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return CupertinoPageScaffold(
                                      backgroundColor: colors.pageBg,
                                      child: SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height /
                                            3,
                                        child: CupertinoDatePicker(
                                          initialDateTime: now.startTime,
                                          use24hFormat: true,
                                          minuteInterval: 1,
                                          mode: CupertinoDatePickerMode
                                              .dateAndTime,
                                          onDateTimeChanged:
                                              (DateTime newTime) {
                                                setState(() {
                                                  now.startTime = newTime;
                                                });
                                              },
                                        ),
                                      ),
                                    );
                                  },
                                );
                                if (now.endTime.isBefore(now.startTime)) {
                                  setState(() {
                                    now.endTime = now.startTime;
                                  });
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: AelSpacing.sm),
                          AelListRow(
                            icon: AelIcons.tabCalendar,
                            title: now.type == TaskType.deadline
                                ? '截止时间'
                                : '结束时间',
                            trailing: Text(
                              TimeHelper.chineseDateTime(now.endTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            onTap: () async {
                              await showCupertinoModalPopup(
                                context: context,
                                builder: (BuildContext context) {
                                  return CupertinoPageScaffold(
                                    backgroundColor: colors.pageBg,
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height /
                                          3,
                                      child: CupertinoDatePicker(
                                        initialDateTime: now.endTime,
                                        use24hFormat: true,
                                        minuteInterval: 1,
                                        mode:
                                            CupertinoDatePickerMode.dateAndTime,
                                        onDateTimeChanged: (DateTime newTime) {
                                          setState(() {
                                            now.endTime = newTime;
                                          });
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                              if (now.type == TaskType.fixed &&
                                  now.startTime.isAfter(now.endTime)) {
                                setState(() {
                                  now.startTime = now.endTime;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    if (now.type == TaskType.deadline) ...[
                      const SizedBox(height: AelSpacing.md),
                      AelSectionCard(
                        title: '时间安排',
                        icon: AelIcons.tabFlow,
                        child: Column(
                          children: [
                            AelListRow(
                              title: '预期用时',
                              trailing: Text(
                                durationToString(now.timeNeeded),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return CupertinoPageScaffold(
                                      backgroundColor: colors.pageBg,
                                      child: SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height /
                                            3,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 150,
                                              child: CupertinoPicker(
                                                itemExtent: 32,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                      initialItem: now
                                                          .timeNeeded
                                                          .inHours,
                                                    ),
                                                onSelectedItemChanged: (value) {
                                                  now.timeNeeded = Duration(
                                                    hours: value,
                                                    minutes:
                                                        now
                                                            .timeNeeded
                                                            .inMinutes %
                                                        60,
                                                  );
                                                  if (now.timeNeeded <=
                                                      Duration.zero) {
                                                    now.timeNeeded =
                                                        const Duration(
                                                          minutes: 1,
                                                        );
                                                  }
                                                  setState(() {});
                                                },
                                                children: List.generate(
                                                  1000,
                                                  (index) => Center(
                                                    child: Text('$index'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const Text('小时'),
                                            SizedBox(
                                              width: 150,
                                              child: CupertinoPicker(
                                                itemExtent: 32,
                                                looping: true,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                      initialItem:
                                                          now
                                                              .timeNeeded
                                                              .inMinutes %
                                                          60,
                                                    ),
                                                onSelectedItemChanged: (value) {
                                                  now.timeNeeded = Duration(
                                                    hours:
                                                        now
                                                            .timeNeeded
                                                            .inMinutes ~/
                                                        60,
                                                    minutes: value,
                                                  );
                                                  if (now.timeNeeded <=
                                                      Duration.zero) {
                                                    now.timeNeeded =
                                                        const Duration(
                                                          minutes: 1,
                                                        );
                                                  }
                                                  setState(() {});
                                                },
                                                children: List.generate(
                                                  60,
                                                  (index) => Center(
                                                    child: Text('$index'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const Text('分钟'),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: AelSpacing.sm),
                            AelListRow(
                              title: '已经用时',
                              trailing: Text(
                                durationToString(now.timeSpent),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return CupertinoPageScaffold(
                                      backgroundColor: colors.pageBg,
                                      child: SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height /
                                            3,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 150,
                                              child: CupertinoPicker(
                                                itemExtent: 32,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                      initialItem:
                                                          now.timeSpent.inHours,
                                                    ),
                                                onSelectedItemChanged: (value) {
                                                  now.timeSpent = Duration(
                                                    hours: value,
                                                    minutes:
                                                        now
                                                            .timeSpent
                                                            .inMinutes %
                                                        60,
                                                  );
                                                  setState(() {});
                                                },
                                                children: List.generate(
                                                  1000,
                                                  (index) => Center(
                                                    child: Text('$index'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const Text('小时'),
                                            SizedBox(
                                              width: 150,
                                              child: CupertinoPicker(
                                                itemExtent: 32,
                                                looping: true,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                      initialItem:
                                                          now
                                                              .timeSpent
                                                              .inMinutes %
                                                          60,
                                                    ),
                                                onSelectedItemChanged: (value) {
                                                  now.timeSpent = Duration(
                                                    hours:
                                                        now
                                                            .timeSpent
                                                            .inMinutes ~/
                                                        60,
                                                    minutes: value,
                                                  );
                                                  setState(() {});
                                                },
                                                children: List.generate(
                                                  60,
                                                  (index) => Center(
                                                    child: Text('$index'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const Text('分钟'),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: AelSpacing.sm),
                            AelSwitchTile(
                              useTonalContainer: true,
                              title: '允许插入休息时间',
                              value: now.isBreakable,
                              onChanged: (value) {
                                setState(() {
                                  now.isBreakable = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AelSpacing.md),
                    AelSectionCard(
                      title: now.type == TaskType.fixed ? '日程设置' : '重复设置',
                      icon: AelIcons.refresh,
                      child: Column(
                        children: [
                          AelListRow(
                            title: '重复',
                            trailing: Text(
                              deadlineRepeatTypeName[now.repeatType]!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            onTap: () async {
                              await showCupertinoModalPopup(
                                context: context,
                                builder: (BuildContext context) {
                                  return CupertinoPageScaffold(
                                    backgroundColor: colors.pageBg,
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height /
                                          3,
                                      child: CupertinoPicker(
                                        itemExtent: 32,
                                        scrollController:
                                            FixedExtentScrollController(
                                              initialItem: now.repeatType.index,
                                            ),
                                        onSelectedItemChanged: (int value) {
                                          setState(() {
                                            now.repeatType =
                                                TaskRepeatType.values[value];
                                            final baseDate =
                                                now.type == TaskType.fixed
                                                ? now.startTime
                                                : now.endTime;
                                            if (now.repeatType !=
                                                    TaskRepeatType.norepeat &&
                                                dateOnly(
                                                  now.repeatEndsTime,
                                                ).isBefore(
                                                  dateOnly(baseDate),
                                                )) {
                                              now.repeatEndsTime = dateOnly(
                                                baseDate,
                                              );
                                            }
                                          });
                                        },
                                        children: List<Widget>.generate(
                                          deadlineRepeatTypeNameList.length,
                                          (int index) => Center(
                                            child: Text(
                                              deadlineRepeatTypeNameList[index],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          if (now.repeatType == TaskRepeatType.days) ...[
                            const SizedBox(height: AelSpacing.sm),
                            AelListRow(
                              title: '重复周期',
                              trailing: Text(
                                '${now.repeatPeriod} 天',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return CupertinoPageScaffold(
                                      backgroundColor: colors.pageBg,
                                      child: SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height /
                                            3,
                                        child: CupertinoPicker(
                                          itemExtent: 32,
                                          scrollController:
                                              FixedExtentScrollController(
                                                initialItem:
                                                    now.repeatPeriod - 1,
                                              ),
                                          onSelectedItemChanged: (int value) {
                                            setState(() {
                                              now.repeatPeriod = value + 1;
                                            });
                                          },
                                          children: List<Widget>.generate(
                                            999,
                                            (int index) => Center(
                                              child: Text(
                                                (index + 1).toString(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                          if (now.repeatType != TaskRepeatType.norepeat) ...[
                            const SizedBox(height: AelSpacing.sm),
                            AelListRow(
                              title: '重复截止日期',
                              trailing: Text(
                                TimeHelper.chineseDate(now.repeatEndsTime),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return CupertinoPageScaffold(
                                      backgroundColor: colors.pageBg,
                                      child: SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height /
                                            3,
                                        child: CupertinoDatePicker(
                                          mode: CupertinoDatePickerMode.date,
                                          initialDateTime: now.repeatEndsTime,
                                          onDateTimeChanged: (value) {
                                            setState(() {
                                              now.repeatEndsTime = value;
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                          if (now.type == TaskType.fixed) ...[
                            const SizedBox(height: AelSpacing.sm),
                            AelSwitchTile(
                              useTonalContainer: true,
                              title: '不在这个日程中安排任务',
                              value: now.blockArrangements,
                              onChanged: (value) {
                                setState(() {
                                  now.blockArrangements = value;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AelSpacing.md),
                    AelSectionCard(
                      title: '附加信息',
                      icon: AelIcons.info,
                      child: Column(
                        children: [
                          CupertinoTextField(
                            placeholder: '地点',
                            controller: _locationCtrl,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            style: TextStyle(color: colors.textPrimary),
                            placeholderStyle: TextStyle(
                              color: colors.textTertiary,
                            ),
                            decoration: BoxDecoration(
                              color: colors.tonalTileBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onChanged: (value) => now.location = value,
                          ),
                          const SizedBox(height: AelSpacing.sm),
                          CupertinoTextField(
                            placeholder: '说明',
                            controller: _descriptionCtrl,
                            maxLines: 3,
                            minLines: 1,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            style: TextStyle(color: colors.textPrimary),
                            placeholderStyle: TextStyle(
                              color: colors.textTertiary,
                            ),
                            decoration: BoxDecoration(
                              color: colors.tonalTileBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onChanged: (value) => now.description = value,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AelSpacing.lg),
                    AelButton(
                      expanded: true,
                      variant: AelButtonVariant.destructive,
                      icon: AelIcons.delete,
                      label: '删除任务',
                      onPressed: removeAndExit,
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }
}
