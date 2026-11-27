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
  final bool embedded;
  final ValueChanged<Task>? onSaved;
  final VoidCallback? onDeleted;

  const TaskEditPage(
    this.deadline, {
    super.key,
    this.embedded = false,
    this.onSaved,
    this.onDeleted,
  });

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
      showAelAlertDialog(
        context: context,
        title: '时间设置无效',
        message: '开始时间必须早于结束时间',
      );
      return;
    }

    if (now.type == TaskType.fixed &&
        now.repeatType != TaskRepeatType.norepeat &&
        dateOnly(now.startTime).isAfter(dateOnly(now.repeatEndsTime))) {
      showAelAlertDialog(
        context: context,
        title: '时间设置无效',
        message: '开始时间不能晚于重复截止日期',
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
        showAelAlertDialog(
          context: context,
          title: '重复日程无效',
          message: '这个重复日程的持续时间太长',
        );
        return;
      }
    }

    FormState().save();
    now.forceRefreshStatus();
    if (widget.embedded) {
      widget.onSaved?.call(now.copyWith());
      return;
    }
    Navigator.of(context).pop(now);
  }

  void removeAndExit() {
    now.status = TaskStatus.deleted;
    if (widget.embedded) {
      widget.onDeleted?.call();
      return;
    }
    Navigator.of(context).pop(now);
  }

  void exitWithoutSave() {
    now = widget.deadline.copyWith();
    if (widget.embedded) {
      setState(() {
        _summaryCtrl.text = now.summary;
        _locationCtrl.text = now.location;
        _descriptionCtrl.text = now.description;
      });
      return;
    }
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
        top: !widget.embedded,
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxDetailWidth,
                  child: Row(
                    children: [
                      if (!widget.embedded) ...[
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
                      ] else ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            now.summary.isNotEmpty ? now.summary : '详情与编辑',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
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
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxDetailWidth,
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
                                  DateTime temp = now.startTime;
                                  final picked =
                                      await showAelPickerSheet<DateTime>(
                                        context: context,
                                        title: '选择开始时间',
                                        pickerBuilder: (_) =>
                                            CupertinoDatePicker(
                                              initialDateTime: temp,
                                              use24hFormat: true,
                                              minuteInterval: 1,
                                              mode: CupertinoDatePickerMode
                                                  .dateAndTime,
                                              onDateTimeChanged:
                                                  (DateTime newTime) {
                                                    temp = newTime;
                                                  },
                                            ),
                                        onConfirm: () => temp,
                                      );
                                  if (picked != null && mounted) {
                                    setState(() {
                                      now.startTime = picked;
                                      if (now.endTime.isBefore(now.startTime)) {
                                        now.endTime = now.startTime;
                                      }
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
                                DateTime temp = now.endTime;
                                final picked =
                                    await showAelPickerSheet<DateTime>(
                                      context: context,
                                      title: now.type == TaskType.deadline
                                          ? '选择截止时间'
                                          : '选择结束时间',
                                      pickerBuilder: (_) => CupertinoDatePicker(
                                        initialDateTime: temp,
                                        use24hFormat: true,
                                        minuteInterval: 1,
                                        mode:
                                            CupertinoDatePickerMode.dateAndTime,
                                        onDateTimeChanged: (DateTime newTime) {
                                          temp = newTime;
                                        },
                                      ),
                                      onConfirm: () => temp,
                                    );
                                if (picked != null && mounted) {
                                  setState(() {
                                    now.endTime = picked;
                                    if (now.type == TaskType.fixed &&
                                        now.startTime.isAfter(now.endTime)) {
                                      now.startTime = now.endTime;
                                    }
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
                                  int hours = now.timeNeeded.inHours;
                                  int mins = now.timeNeeded.inMinutes % 60;
                                  final picked = await showAelPickerSheet<Duration>(
                                    context: context,
                                    title: '设置预期用时',
                                    pickerBuilder: (pickerCtx) {
                                      final pickerColors = AelTheme.colorsOf(
                                        pickerCtx,
                                      );
                                      final itemStyle = TextStyle(
                                        fontSize: 19,
                                        color: pickerColors.textPrimary,
                                      );
                                      final unitStyle = TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: pickerColors.textSecondary,
                                      );
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 110,
                                            child: CupertinoPicker(
                                              itemExtent: 34,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                    initialItem: hours,
                                                  ),
                                              onSelectedItemChanged: (v) =>
                                                  hours = v,
                                              children: List.generate(
                                                1000,
                                                (i) => Center(
                                                  child: Text(
                                                    '$i',
                                                    style: itemStyle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text('小时', style: unitStyle),
                                          SizedBox(
                                            width: 110,
                                            child: CupertinoPicker(
                                              itemExtent: 34,
                                              looping: true,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                    initialItem: mins,
                                                  ),
                                              onSelectedItemChanged: (v) =>
                                                  mins = v,
                                              children: List.generate(
                                                60,
                                                (i) => Center(
                                                  child: Text(
                                                    '$i',
                                                    style: itemStyle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text('分钟', style: unitStyle),
                                        ],
                                      );
                                    },
                                    onConfirm: () {
                                      final d = Duration(
                                        hours: hours,
                                        minutes: mins,
                                      );
                                      return d <= Duration.zero
                                          ? const Duration(minutes: 1)
                                          : d;
                                    },
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => now.timeNeeded = picked);
                                  }
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
                                  int hours = now.timeSpent.inHours;
                                  int mins = now.timeSpent.inMinutes % 60;
                                  final picked = await showAelPickerSheet<Duration>(
                                    context: context,
                                    title: '设置已经用时',
                                    pickerBuilder: (pickerCtx) {
                                      final pickerColors = AelTheme.colorsOf(
                                        pickerCtx,
                                      );
                                      final itemStyle = TextStyle(
                                        fontSize: 19,
                                        color: pickerColors.textPrimary,
                                      );
                                      final unitStyle = TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: pickerColors.textSecondary,
                                      );
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 110,
                                            child: CupertinoPicker(
                                              itemExtent: 34,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                    initialItem: hours,
                                                  ),
                                              onSelectedItemChanged: (v) =>
                                                  hours = v,
                                              children: List.generate(
                                                1000,
                                                (i) => Center(
                                                  child: Text(
                                                    '$i',
                                                    style: itemStyle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text('小时', style: unitStyle),
                                          SizedBox(
                                            width: 110,
                                            child: CupertinoPicker(
                                              itemExtent: 34,
                                              looping: true,
                                              scrollController:
                                                  FixedExtentScrollController(
                                                    initialItem: mins,
                                                  ),
                                              onSelectedItemChanged: (v) =>
                                                  mins = v,
                                              children: List.generate(
                                                60,
                                                (i) => Center(
                                                  child: Text(
                                                    '$i',
                                                    style: itemStyle,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text('分钟', style: unitStyle),
                                        ],
                                      );
                                    },
                                    onConfirm: () =>
                                        Duration(hours: hours, minutes: mins),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => now.timeSpent = picked);
                                  }
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
                              onTap: () {
                                showAelActionSheet<TaskRepeatType>(
                                  context: context,
                                  title: '选择重复方式',
                                  actions: TaskRepeatType.values
                                      .map(
                                        (rt) => AelActionOption<TaskRepeatType>(
                                          value: rt,
                                          label: deadlineRepeatTypeName[rt]!,
                                          isSelected: now.repeatType == rt,
                                          onTap: () {
                                            setState(() {
                                              now.repeatType = rt;
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
                                        ),
                                      )
                                      .toList(),
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
                                  int tempPeriod = now.repeatPeriod;
                                  final picked = await showAelPickerSheet<int>(
                                    context: context,
                                    title: '设置重复周期（天）',
                                    pickerBuilder: (pickerCtx) {
                                      final pickerColors = AelTheme.colorsOf(
                                        pickerCtx,
                                      );
                                      return CupertinoPicker(
                                        itemExtent: 34,
                                        scrollController:
                                            FixedExtentScrollController(
                                              initialItem: tempPeriod - 1,
                                            ),
                                        onSelectedItemChanged: (int value) {
                                          tempPeriod = value + 1;
                                        },
                                        children: List<Widget>.generate(
                                          999,
                                          (int index) => Center(
                                            child: Text(
                                              '${index + 1} 天',
                                              style: TextStyle(
                                                fontSize: 19,
                                                color: pickerColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    onConfirm: () => tempPeriod,
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => now.repeatPeriod = picked);
                                  }
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
                                  DateTime tempDate = now.repeatEndsTime;
                                  final picked =
                                      await showAelPickerSheet<DateTime>(
                                        context: context,
                                        title: '选择重复截止日期',
                                        pickerBuilder: (_) =>
                                            CupertinoDatePicker(
                                              mode:
                                                  CupertinoDatePickerMode.date,
                                              initialDateTime: tempDate,
                                              onDateTimeChanged: (value) {
                                                tempDate = value;
                                              },
                                            ),
                                        onConfirm: () => tempDate,
                                      );
                                  if (picked != null && mounted) {
                                    setState(() => now.repeatEndsTime = picked);
                                  }
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
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }
}
