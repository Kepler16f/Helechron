import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/custom_decoration.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/calendar/schedule_view.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:celechron/utils/swap_day_helper.dart';
import 'package:celechron/utils/utils.dart';

import 'calendar_controller.dart';

class CalendarPage extends StatelessWidget {
  CalendarPage({super.key});

  final _calendarController = Get.put(CalendarController());
  final _taskController = Get.put(TaskController());
  final _flowController = Get.put(FlowController());
  final deadlineList = Get.find<RxList<Task>>(tag: 'taskList');

  void _showJumpToDatePicker(BuildContext context) {
    DateTime tempDate = _calendarController.selectedDay.value;
    showAelBottomSheet<void>(
      context: context,
      title: '跳转日期',
      builder: (sheetCtx) {
        final colors = AelTheme.colorsOf(sheetCtx);
        final brightness = CupertinoTheme.brightnessOf(sheetCtx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 216,
              decoration: ShapeDecoration(
                color: colors.tonalTileBg,
                shape: AelShapes.squircle(AelRadius.card - 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: brightness,
                  primaryColor: colors.primary,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: tempDate,
                  minimumDate: DateTime(2022, 9, 1),
                  maximumDate: DateTime(2030, 12, 31),
                  onDateTimeChanged: (DateTime newDate) {
                    tempDate = newDate;
                  },
                ),
              ),
            ),
            const SizedBox(height: AelSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AelButton(
                    label: '回到今天',
                    variant: AelButtonVariant.tonal,
                    expanded: true,
                    onPressed: () {
                      final now = DateTime.now();
                      _calendarController.focusedDay.value = now;
                      _calendarController.selectedDay.value = now;
                      _calendarController.focusedDay.refresh();
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                ),
                const SizedBox(width: AelSpacing.md),
                Expanded(
                  child: AelButton(
                    label: '确定',
                    expanded: true,
                    onPressed: () {
                      _calendarController.focusedDay.value = tempDate;
                      _calendarController.selectedDay.value = tempDate;
                      _calendarController.focusedDay.refresh();
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.pageBg),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() {
              final isCal =
                  _calendarController.viewMode.value ==
                  CalendarViewMode.calendar;
              final title = isCal
                  ? '${_calendarController.focusedDay.value.year} 年 ${_calendarController.focusedDay.value.month} 月'
                  : _calendarController.getCurrentSemesterDisplayName();
              return AelLargeTitleBar(
                title: title,
                actions: [
                  if (isCal) ...[
                    AelCircleIconButton(
                      icon: AelIcons.add,
                      tooltip: '新建日程',
                      onPressed: () async {
                        await newDeadline(
                          context,
                          time: DateTime(
                            _calendarController.selectedDay.value.year,
                            _calendarController.selectedDay.value.month,
                            _calendarController.selectedDay.value.day,
                            DateTime.now().hour,
                            DateTime.now().minute,
                          ),
                        );
                        _taskController.updateDeadlineList();
                        _taskController.taskList.refresh();
                      },
                    ),
                    AelCircleIconButton(
                      icon: AelIcons.tabCalendar,
                      tooltip: '跳转日期',
                      onPressed: () => _showJumpToDatePicker(context),
                    ),
                  ],
                  AelCircleIconButton(
                    icon: isCal ? AelIcons.layers : AelIcons.tabCalendar,
                    tooltip: isCal ? '切换课表视图' : '切换日历视图',
                    onPressed: () {
                      _calendarController.toggleViewMode();
                    },
                  ),
                ],
              );
            }),
            Expanded(
              child: Obx(() {
                if (_calendarController.viewMode.value ==
                    CalendarViewMode.schedule) {
                  return ScheduleView(controller: _calendarController);
                }
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AelSpacing.pageHorizontal,
                        0,
                        AelSpacing.pageHorizontal,
                        AelSpacing.sectionGap,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildCalendarCard(context, colors),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AelSpacing.pageHorizontal,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Obx(() {
                          final selected = _calendarController.selectedDay.value
                              .copyWith(isUtc: false);
                          final events = _calendarController.getEventsForDay(
                            _calendarController.selectedDay.value,
                          );
                          final swapInfo = swapDayInfoFor(
                            selected,
                            _calendarController.scholar.value.specialDates,
                          );
                          final specialDesc = _calendarController
                              .scholar
                              .value
                              .specialDates[selected];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (swapInfo != null) ...[
                                _buildSwapDayBanner(context, swapInfo, colors),
                                const SizedBox(height: AelSpacing.sectionGap),
                              ],
                              _buildDayEventsCard(
                                context,
                                colors,
                                _calendarController.dayDescription(selected),
                                specialDesc,
                                events,
                              ),
                              SizedBox(
                                height:
                                    MediaQuery.paddingOf(context).bottom + 20,
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, AelColorTokens colors) {
    final dayTextStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final weekendTextStyle = TextStyle(
      color: colors.textSecondary,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return AelSectionCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: TableCalendar(
        locale: 'zh_CN',
        firstDay: DateTime.utc(2022, 9, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        rowHeight: 48.0,
        daysOfWeekHeight: 22.0,
        startingDayOfWeek: StartingDayOfWeek.monday,
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          weekendStyle: TextStyle(
            color: colors.textTertiary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          dowTextFormatter: (date, locale) =>
              <String>['', '一', '二', '三', '四', '五', '六', '日'][date.weekday],
        ),
        availableGestures: AvailableGestures.all,
        availableCalendarFormats: const {
          CalendarFormat.month: '显示整月',
          CalendarFormat.week: '显示一周',
        },
        headerVisible: false,
        focusedDay: _calendarController.focusedDay.value,
        selectedDayPredicate: (day) {
          return isSameDay(_calendarController.selectedDay.value, day);
        },
        calendarFormat: _calendarController.calendarFormat.value,
        onPageChanged: (focusedDay) {
          _calendarController.focusedDay.value = focusedDay;
        },
        onDaySelected: (selectedDay, focusedDay) {
          _calendarController.focusedDay.value = focusedDay;
          _calendarController.selectedDay.value = selectedDay;
          _calendarController.focusedDay.refresh();
        },
        onFormatChanged: (format) {
          _calendarController.calendarFormat.value = format;
        },
        eventLoader: (day) {
          return _calendarController.getEventsForDay(day);
        },
        calendarStyle: CalendarStyle(
          markersMaxCount: 10,
          selectedDecoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: dayTextStyle.copyWith(
            color: colors.onPrimary,
            fontWeight: FontWeight.w700,
          ),
          todayDecoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          todayTextStyle: dayTextStyle.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
          defaultTextStyle: dayTextStyle,
          weekendTextStyle: weekendTextStyle,
          outsideTextStyle: dayTextStyle.copyWith(
            color: colors.textTertiary.withValues(alpha: 0.65),
          ),
        ),
        calendarBuilders: CalendarBuilders<Period>(
          singleMarkerBuilder: singleMarkerBuilder,
          markerBuilder: (context, day, events) {
            final swapInfo = swapDayInfoFor(
              day,
              _calendarController.scholar.value.specialDates,
            );
            final hasSwap =
                swapInfo != null && swapInfo.kind != SwapDayKind.unknown;
            if (events.isEmpty && !hasSwap) {
              return const SizedBox.shrink();
            }

            final isHoliday = swapInfo?.kind == SwapDayKind.holiday;
            final badgeBg = isHoliday
                ? colors.errorContainer
                : colors.infoContainer;
            final badgeFg = isHoliday
                ? colors.onErrorContainer
                : colors.onInfoContainer;

            return Positioned.fill(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (hasSwap)
                    Positioned(
                      top: 2,
                      right: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 0.5,
                          ),
                          child: Text(
                            isHoliday ? '休' : '班',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: badgeFg,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (events.isNotEmpty)
                    Positioned(
                      bottom: 2,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var event in events.take(4))
                            singleMarkerBuilder(context, day, event),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDayEventsCard(
    BuildContext context,
    AelColorTokens colors,
    String dayDescription,
    String? specialDateLabel,
    List<Period> events,
  ) {
    return AelSectionCard(
      icon: AelIcons.tabFlow,
      title: dayDescription,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (specialDateLabel != null) ...[
            AelChip(label: specialDateLabel, tone: AelChipTone.success),
            const SizedBox(width: 6),
          ],
          AelChip(
            label: '${events.length} 项',
            tone: events.isEmpty ? AelChipTone.neutral : AelChipTone.primary,
          ),
        ],
      ),
      child: events.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '当日暂无课程或日程安排',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
                ),
              ),
            )
          : Column(
              children: [
                for (int i = 0; i < events.length; i++) ...[
                  if (i > 0) const SizedBox(height: AelSpacing.sm),
                  _buildEventRow(context, events[i], colors),
                ],
              ],
            ),
    );
  }

  Color _periodAccentColor(BuildContext context, Period period) {
    final colors = AelTheme.colorsOf(context);
    if (period.type == PeriodType.classes) {
      return TimeColors.colorFromHour(period.startTime.hour);
    }
    if (period.type == PeriodType.test) return colors.error;
    if (period.type == PeriodType.user && period.fromUid != null) {
      return UidColors.colorFromUid(period.fromFromUid ?? period.fromUid);
    }
    return colors.textTertiary;
  }

  IconData _periodIcon(PeriodType type) {
    return switch (type) {
      PeriodType.classes => AelIcons.tabScholar,
      PeriodType.test => AelIcons.exam,
      PeriodType.user => AelIcons.tabTask,
      PeriodType.flow => AelIcons.tabFlow,
      PeriodType.virtual => AelIcons.sparkles,
    };
  }

  Widget _buildEventRow(
    BuildContext context,
    Period period,
    AelColorTokens colors,
  ) {
    final accent = _periodAccentColor(context, period);
    final subtitleParts = <String>[
      period.friendlyTimeStartDayBased,
      if (period.location.isNotEmpty) period.location,
    ];

    VoidCallback? onTap;
    if (period.type == PeriodType.classes || period.type == PeriodType.test) {
      onTap = () async => Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (context) =>
              CourseDetailPage(courseId: period.fromUid, period: period),
        ),
      );
    } else if (period.type == PeriodType.user) {
      onTap = () {
        Task? deadline;
        for (var x in deadlineList) {
          if (x.uid == period.fromUid) {
            deadline = x;
            break;
          }
        }
        if (deadline != null) {
          showCardDialog(context, deadline);
        }
      };
    }

    return AelListRow(
      title: period.summary,
      subtitle: subtitleParts.join(' · '),
      icon: _periodIcon(period.type),
      iconBgColor: accent.withValues(alpha: colors.isDark ? 0.22 : 0.14),
      iconColor: accent,
      showChevron: onTap != null,
      onTap: onTap,
    );
  }

  Future<void> newDeadline(
    BuildContext context, {
    required DateTime time,
  }) async {
    Task? deadline = Task(endTime: time, startTime: time, repeatEndsTime: time);
    deadline.reset();
    deadline.startTime = time.copyWith();
    deadline.endTime = time.copyWith();
    deadline.repeatEndsTime = time.copyWith();
    deadline.type = TaskType.fixed;
    deadline.status = TaskStatus.running;
    Task? res = await showAelModalPage<Task>(
      context: context,
      builder: (BuildContext context) {
        return TaskEditPage(deadline);
      },
    );
    if (res != null &&
        res.checkTimeValid() &&
        res.status != TaskStatus.deleted) {
      _taskController.taskList.add(res);
      _taskController.updateDeadlineListTime();
      _taskController.taskList.refresh();
    }
  }

  Future<void> showCardDialog(BuildContext context, Task deadline) async {
    return showAelDialog<void>(
      context: context,
      title: deadline.summary,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (deadline.repeatType != TaskRepeatType.norepeat)
            const Text('重复日程，接下来的时段：'),
          Text('开始于 ${toStringHumanReadable(deadline.startTime)}'),
          Text('结束于 ${toStringHumanReadable(deadline.endTime)}'),
          if (deadline.location.isNotEmpty) Text('地点：${deadline.location}'),
          if (deadline.description.isNotEmpty)
            Text('说明：${deadline.description}'),
        ],
      ),
      actions: [
        const AelDialogAction<void>(
          label: '返回',
          variant: AelButtonVariant.tonal,
        ),
        if (deadline.type == TaskType.fixed)
          AelDialogAction<void>(
            label: '编辑',
            variant: AelButtonVariant.primary,
            onPressed: () async {
              Task res =
                  await showAelModalPage<Task>(
                    context: context,
                    builder: (BuildContext context) {
                      return TaskEditPage(deadline);
                    },
                  ) ??
                  deadline;
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
            },
          ),
        if (deadline.type == TaskType.fixedlegacy)
          AelDialogAction<void>(
            label: '删除',
            isDestructive: true,
            onPressed: () async {
              deadline.status = TaskStatus.deleted;
              _taskController.updateDeadlineList();
              _taskController.taskList.refresh();
            },
          ),
      ],
    );
  }

  Widget _buildSwapDayBanner(
    BuildContext context,
    SwapDayInfo info,
    AelColorTokens colors,
  ) {
    final isHoliday = info.kind == SwapDayKind.holiday;
    final (
      Color bg,
      Color fg,
      IconData icon,
      AelChipTone chipTone,
      String tag,
    ) = switch (info.kind) {
      SwapDayKind.holiday => (
        colors.errorContainer,
        colors.onErrorContainer,
        AelIcons.moon,
        AelChipTone.error,
        '放假',
      ),
      SwapDayKind.makeUp => (
        colors.infoContainer,
        colors.onInfoContainer,
        AelIcons.refresh,
        AelChipTone.info,
        '调休',
      ),
      _ => (
        colors.successContainer,
        colors.onSuccessContainer,
        AelIcons.info,
        AelChipTone.success,
        '节假日',
      ),
    };

    return AelSectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AelIconBadge(
            icon: icon,
            style: AelIconBadgeStyle.cookie,
            size: 40,
            iconSize: 18,
            backgroundColor: bg,
            iconColor: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: isHoliday ? colors.error : colors.textPrimary,
                  ),
                ),
                if (info.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    info.detail!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          AelChip(label: tag, tone: chipTone),
        ],
      ),
    );
  }

  static Widget singleMarkerBuilder(
    BuildContext context,
    DateTime day,
    Period event,
  ) {
    if (event.type == PeriodType.virtual) {
      return const SizedBox.shrink();
    }

    Color color = AelTheme.colorsOf(context).error;
    if (event.type == PeriodType.classes) {
      color = TimeColors.colorFromHour(event.startTime.hour);
    } else if (event.type == PeriodType.user) {
      color = UidColors.colorFromUid(event.fromFromUid ?? event.fromUid);
    }

    double size = 4.5;
    if (event.type == PeriodType.test) {
      size = 6;
    }

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 0.3),
      decoration: customDecoration(
        color: color,
        shape: periodTypeShape[event.type]!,
      ),
    );
  }
}
