import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/utils/utils.dart';

import 'exam_week_banner.dart';
import 'flow_controller.dart';

class FlowPage extends StatefulWidget {
  const FlowPage({super.key});

  @override
  State<FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends State<FlowPage> {
  final _flowController = Get.put(FlowController());
  final db = Get.find<DatabaseHelper>(tag: 'db');
  bool _isPromptingOutdated = false;
  Worker? _taskListWorker;

  @override
  void initState() {
    super.initState();
    _taskListWorker = ever(_flowController.taskListLastUpdate, (_) {
      _checkAndPromptOutdated();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptOutdated();
    });
  }

  @override
  void dispose() {
    _taskListWorker?.dispose();
    super.dispose();
  }

  void _checkAndPromptOutdated() {
    if (!mounted) return;
    if (_isPromptingOutdated) return;
    if (!_flowController.isFlowListOutdated()) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _isPromptingOutdated = true;
    final isHomework = _flowController.isOutdatedDueToHomeworkOnly();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isPromptingOutdated = false;
        return;
      }
      final curRoute = ModalRoute.of(context);
      if (curRoute != null && !curRoute.isCurrent) {
        _isPromptingOutdated = false;
        return;
      }
      final colors = AelTheme.colorsOf(context);
      showAelDialog<void>(
        context: context,
        barrierDismissible: false,
        titleIcon: Container(
          width: 44,
          height: 44,
          decoration: ShapeDecoration(
            color: (isHomework ? colors.primary : colors.warning).withValues(
              alpha: 0.14,
            ),
            shape: AelShapes.squircle(14),
          ),
          alignment: Alignment.center,
          child: Icon(
            isHomework ? AelIcons.book : AelIcons.warning,
            size: 22,
            color: isHomework ? colors.primary : colors.warning,
          ),
        ),
        title: isHomework ? '作业状态已变化' : '规划方案已过期',
        message: isHomework
            ? '检测到作业状态已更新，当前规划方案可能需要同步或确认。'
            : '任务列表已发生变更，原有的时间规划方案已过期，是否立即重新规划？',
        actions: [
          AelDialogAction<void>(
            label: '忽略',
            variant: AelButtonVariant.tonal,
            onPressed: () => _flowController.updateDeadlineListTime(),
          ),
          AelDialogAction<void>(
            label: isHomework ? '知道了' : '重新规划',
            variant: AelButtonVariant.primary,
            onPressed: () async {
              if (isHomework) {
                _flowController.updateDeadlineListTime();
              } else {
                await newFlowList(context);
                _flowController.flowList.refresh();
              }
            },
          ),
        ],
      ).then((_) {
        _isPromptingOutdated = false;
      });
    });
  }

  Color _periodAccentColor(BuildContext context, Period period) {
    final colors = AelTheme.colorsOf(context);
    if (period.type == PeriodType.flow || period.type == PeriodType.user) {
      return UidColors.colorFromUid(period.fromUid);
    }
    if (period.type == PeriodType.test) return colors.error;
    if (period.type == PeriodType.classes) {
      return TimeColors.colorFromHour(period.startTime.hour);
    }
    return colors.info;
  }

  IconData _periodIcon(PeriodType type) {
    return switch (type) {
      PeriodType.classes => AelIcons.tabScholar,
      PeriodType.test => AelIcons.exam,
      PeriodType.flow => AelIcons.tabFlow,
      PeriodType.user => AelIcons.tabTask,
      PeriodType.virtual => AelIcons.sparkles,
    };
  }

  String _periodTypeLabel(PeriodType type) {
    return switch (type) {
      PeriodType.classes => '课程',
      PeriodType.test => '考试',
      PeriodType.flow => '规划任务',
      PeriodType.user => '日程',
      PeriodType.virtual => '日程',
    };
  }

  void _openPeriodDetail(BuildContext context, Period period) {
    if (period.type != PeriodType.classes) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (context) =>
            CourseDetailPage(courseId: period.fromUid, period: period),
      ),
    );
  }

  /// 参考图顶部 Hero 状态卡：左侧花瓣图标 + 日程标题 + 2 个 tonal 数字块 + 进度条 + 右侧柔和波浪装饰。
  Widget _buildHeroPeriodCard(
    BuildContext context,
    Period period,
    String sectionTitle,
  ) {
    final colors = AelTheme.colorsOf(context);
    final accent = _periodAccentColor(context, period);
    final isOngoing = period.hasStarted;

    return AelSectionCard(
      icon: AelIcons.activity,
      title: sectionTitle,
      trailing: AelChip(
        label: isOngoing ? '进行中' : _periodTypeLabel(period.type),
        tone: isOngoing ? AelChipTone.primary : AelChipTone.neutral,
      ),
      onTap: period.type == PeriodType.classes
          ? () => _openPeriodDetail(context, period)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AelIconBadge(
                icon: _periodIcon(period.type),
                style: AelIconBadgeStyle.cookie,
                size: 46,
                iconSize: 21,
                backgroundColor: isOngoing
                    ? colors.primary
                    : colors.primaryContainer,
                iconColor: isOngoing
                    ? colors.onPrimary
                    : colors.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      period.friendlyTimeTodayBased,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (period.type == PeriodType.classes)
                AelHeroButton(
                  icon: AelIcons.chevronRight,
                  size: 44,
                  iconSize: 20,
                  tooltip: '查看课程详情',
                  onPressed: () => _openPeriodDetail(context, period),
                ),
            ],
          ),
          const SizedBox(height: AelSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Obx(() {
                    final now = _flowController.timeNow.value;
                    final started = period.startTime.isBefore(now);
                    final diff = started
                        ? period.endTime.difference(now)
                        : period.startTime.difference(now);
                    return AelStatTile(
                      icon: AelIcons.tabFlow,
                      iconColor: isOngoing ? colors.primary : accent,
                      label: started ? '离结束还有' : '开始还有',
                      value: TimeHelper.toHMS(diff),
                      valueFontSize: 20,
                      valueColor: isOngoing
                          ? colors.primary
                          : colors.textPrimary,
                      subtitle: started ? '专注当前安排' : '准备下一程',
                    );
                  }),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    icon: AelIcons.location,
                    iconColor: accent,
                    label: '地点',
                    value: period.location.isNotEmpty ? period.location : '未指定',
                    valueFontSize: 15,
                    valueMaxLines: 2,
                    subtitle: _periodTypeLabel(period.type),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AelSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                SizedBox(
                  height: 8,
                  width: constraints.maxWidth,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colors.tonalTileBg,
                      shape: AelShapes.squircle(AelRadius.pill),
                    ),
                  ),
                ),
                Obx(() {
                  final double ratio;
                  if (_flowController.isDuringFlow) {
                    final elapsed = _flowController.timeNow.value
                        .difference(period.startTime)
                        .inMilliseconds;
                    final total = period.endTime
                        .difference(period.startTime)
                        .inMilliseconds;
                    ratio = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
                  } else {
                    ratio = 1.0;
                  }
                  return AnimatedContainer(
                    duration: AelDurations.fast,
                    height: 8,
                    width: max(constraints.maxWidth * ratio, 0.0),
                    decoration: ShapeDecoration(
                      color: isOngoing ? colors.primary : accent,
                      shape: AelShapes.squircle(AelRadius.pill),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 之后的安排：以单张大分区卡片聚合展示，内部是统一圆角 tonal 列表行。
  Widget _buildUpcomingSection(BuildContext context, List<Period> upcoming) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      icon: AelIcons.tabCalendar,
      title: '之后的安排',
      trailing: AelChip(
        label: '${upcoming.length} 项',
        tone: AelChipTone.neutral,
      ),
      child: Column(
        children: [
          for (int i = 0; i < upcoming.length; i++) ...[
            if (i > 0) const SizedBox(height: AelSpacing.sm),
            _buildUpcomingRow(context, upcoming[i], colors),
          ],
        ],
      ),
    );
  }

  Widget _buildUpcomingRow(
    BuildContext context,
    Period period,
    AelColorTokens colors,
  ) {
    final accent = _periodAccentColor(context, period);
    final subtitleParts = <String>[
      period.friendlyTimeTodayBased,
      if (period.location.isNotEmpty) period.location,
    ];
    return AelListRow(
      title: period.summary,
      subtitle: subtitleParts.join(' · '),
      icon: _periodIcon(period.type),
      iconBgColor: accent.withValues(alpha: colors.isDark ? 0.22 : 0.14),
      iconColor: accent,
      showChevron: period.type == PeriodType.classes,
      onTap: period.type == PeriodType.classes
          ? () => _openPeriodDetail(context, period)
          : null,
    );
  }

  Future<void> newFlowList(BuildContext context) async {
    DateTime newTime = DateTime.now()
        .add(const Duration(seconds: 90))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
    await showAelBottomSheet<void>(
      context: context,
      title: '开始规划',
      subtitle:
          '工作 ${durationToString(db.getWorkTime())} - 休息 ${durationToString(db.getRestTime())}',
      showCloseButton: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final colors = AelTheme.colorsOf(sheetCtx);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AelListRow(
                  title: '开始时间',
                  icon: AelIcons.tabFlow,
                  trailing: Text(
                    TimeHelper.chineseDateTime(newTime),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                  onTap: () async {
                    DateTime temp = newTime;
                    final picked = await showAelPickerSheet<DateTime>(
                      context: sheetCtx,
                      title: '选择开始时间',
                      pickerBuilder: (_) => CupertinoDatePicker(
                        initialDateTime: temp,
                        use24hFormat: true,
                        minuteInterval: 1,
                        mode: CupertinoDatePickerMode.dateAndTime,
                        onDateTimeChanged: (val) => temp = val,
                      ),
                      onConfirm: () => temp,
                    );
                    if (picked != null) {
                      setSheetState(() => newTime = picked);
                    }
                  },
                ),
                const SizedBox(height: AelSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AelButton(
                        label: '返回',
                        variant: AelButtonVariant.tonal,
                        expanded: true,
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ),
                    const SizedBox(width: AelSpacing.md),
                    Expanded(
                      child: AelButton(
                        label: '创建',
                        expanded: true,
                        onPressed: () async {
                          if (!newTime.isAfter(DateTime.now())) {
                            await showAelAlertDialog(
                              context: sheetCtx,
                              title: '开始时间必须晚于现在',
                              message: '请调整开始时间。',
                            );
                            return;
                          }
                          final ret = _flowController.generateNewFlowList(
                            newTime,
                          );
                          if (ret < 0) {
                            if (!sheetCtx.mounted) return;
                            await showAelAlertDialog(
                              context: sheetCtx,
                              title: '时间不够了！',
                              message:
                                  '即使是完全不休息也有任务无法完成。请压缩任务的预期时间，或者检查是否有任务在规划开始时间之前就结束。',
                            );
                          } else if (ret != db.getRestTime().inMinutes) {
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            if (!context.mounted) return;
                            await showAelAlertDialog(
                              context: context,
                              title: '休息时间已压缩',
                              message:
                                  '因为任务过多，你需要把休息时间压缩到 ${durationToString(Duration(minutes: ret))}才能完成任务。',
                            );
                          } else {
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptOutdated();
    });
    final colors = AelTheme.colorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.pageBg),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AelLargeTitleBar(
                title: '接下来',
                actions: [
                  AelCircleIconButton(
                    icon: AelIcons.refresh,
                    tooltip: '开始规划',
                    onPressed: () async {
                      await newFlowList(context);
                      _flowController.flowList.refresh();
                    },
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: ExamWeekBanner(now: _flowController.timeNow),
            ),
            Obx(() {
              final list = _flowController.flowList;
              if (list.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AelSpacing.pageHorizontal,
                      vertical: AelSpacing.xl,
                    ),
                    child: AelEmptyState(
                      icon: AelIcons.sparkles,
                      title: '今日无事可做',
                      subtitle: '当前没有即将进行的课程或待办安排',
                      actionLabel: '开始规划',
                      onAction: () async {
                        await newFlowList(context);
                        _flowController.flowList.refresh();
                      },
                    ),
                  ),
                );
              }

              final hero = list.first;
              final heroTitle = hero.hasStarted ? '正在进行' : '即将开始';
              final activeExtras = <Period>[];
              final upcoming = <Period>[];
              for (int i = 1; i < list.length; i++) {
                if (list[i].hasStarted) {
                  activeExtras.add(list[i]);
                } else {
                  upcoming.add(list[i]);
                }
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.pageHorizontal,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeroPeriodCard(context, hero, heroTitle),
                    for (final p in activeExtras) ...[
                      const SizedBox(height: AelSpacing.sectionGap),
                      _buildHeroPeriodCard(context, p, '同时进行'),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      const SizedBox(height: AelSpacing.sectionGap),
                      _buildUpcomingSection(context, upcoming),
                    ],
                  ]),
                ),
              );
            }),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
