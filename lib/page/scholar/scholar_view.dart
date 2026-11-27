import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/refresh_status_indicator.dart';
import 'package:celechron/design/rolling_shimmer_text.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/page/scholar/todo/todo_card.dart';
import 'package:celechron/page/search/search_view.dart';
import 'package:celechron/utils/platform_features.dart';

import 'course_list/course_list_view.dart';
import 'course_schedule/course_schedule_view.dart';
import 'curriculum_plan/curriculum_plan_page.dart';
import 'exam_list/exam_list_view.dart';
import 'grade_detail/grade_detail_view.dart';
import 'practice_score/practice_score_page.dart';
import 'scholar_controller.dart';

Future<void> showRefreshResultDialog(
  BuildContext context,
  List<String?> results,
) async {
  final messages = results.whereType<String>().toList();
  // 完全成功只通过数据、更新时间和页面状态反馈，不主动打断用户。
  if (messages.isEmpty) return;
  final degraded = messages
      .where(isDegradedRefreshText)
      .toList(growable: false);
  final failures = messages
      .where((message) => !isDegradedRefreshText(message))
      .toList(growable: false);
  if (!context.mounted) return;
  final summaryLines = messages.map((error) {
    final compact = shortErrorText(
      error,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = isDegradedRefreshText(error) ? '降级：' : '失败：';
    final line = '$prefix$compact';
    return line.length <= 100 ? line : '${line.substring(0, 100)}…';
  }).toList();

  await showAelDialog<void>(
    context: context,
    title: '刷新遇到问题：${degraded.length} 项降级，${failures.length} 项失败',
    message: summaryLines.join('\n'),
    actions: [
      if (messages.isNotEmpty)
        AelDialogAction<void>(
          label: '查看详情',
          variant: AelButtonVariant.tonal,
          onPressed: () {
            showAelAlertDialog(
              context: context,
              title: '刷新详情',
              message: messages
                  .map((error) {
                    final short = shortErrorText(error);
                    final details = detailedErrorText(error);
                    return details == short ? short : '$short\n$details';
                  })
                  .join('\n\n'),
            );
          },
        ),
      const AelDialogAction<void>(
        label: '确定',
        variant: AelButtonVariant.primary,
      ),
    ],
  );
}

class ScholarErrorHandler extends StatelessWidget {
  final FlutterErrorDetails errorDetails;
  final _scholarController = Get.put(ScholarController());

  ScholarErrorHandler({super.key, required this.errorDetails});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(AelSpacing.pageHorizontal),
          child: AelSectionCard(
            title: '数据加载异常',
            icon: AelIcons.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '获取数据时遇到问题。请检查网络连接情况，并尝试重新获取数据。\n注意：你需要完成所有的教学评价才能获取成绩信息。',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AelSpacing.lg),
                AelButton(
                  label: '重新获取数据',
                  icon: AelIcons.refresh,
                  expanded: true,
                  onPressed: () async {
                    final results = await _scholarController.fetchData();
                    if (context.mounted &&
                        results.any((result) => result != null)) {
                      await showRefreshResultDialog(context, results);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class ScholarPage extends StatelessWidget {
  ScholarPage({super.key}) {
    ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
      return ScholarErrorHandler(errorDetails: errorDetails);
    };
  }

  final _scholarController = Get.put(ScholarController());
  final ValueNotifier<bool> _isRefreshing = ValueNotifier(false);

  // 让页内横向列表在桌面端也响应鼠标拖动。外层 PageView 为支持鼠标切页开启了
  // 鼠标拖动，横向列表若不响应鼠标，拖动会漏到 PageView 上造成误切页；
  // 内层可滚动组件在手势竞技中优先，包上后拖动由列表自己消费（触屏行为不变）
  Widget _mouseDraggable(BuildContext context, Widget child) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: child,
    );
  }

  Widget _buildSyncChip(Duration age) {
    final minutes = age.inMinutes;
    if (minutes > 10000000) {
      return const AelChip(
        label: '同步异常',
        leadingIcon: AelIcons.warning,
        tone: AelChipTone.warning,
      );
    }
    return AelChip(
      label: '更新于 $minutes 分钟前',
      leadingIcon: minutes < 5 ? AelIcons.success : AelIcons.info,
      tone: minutes < 5 ? AelChipTone.success : AelChipTone.neutral,
    );
  }

  Widget _buildGradeBrief(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final optionController = Get.find<OptionController>(
      tag: 'optionController',
    );

    String maskGPA(String s) {
      // 绩点隐藏功能
      if (!optionController.hideHomeGpa) return s;
      return s.replaceAll('.', '').replaceAll(RegExp(r'[\d.]'), '*');
    }

    return Hero(
      tag: 'gradeBrief',
      child: AelSectionCard(
        title: '成绩',
        icon: AelIcons.award,
        trailing: Obx(
          () => _buildSyncChip(_scholarController.durationToLastUpdateGrade),
        ),
        onTap: () async => Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute(
            builder: (context) => GradeDetailPage(),
            fullscreenDialog: true,
          ),
        ),
        child: Obx(
          () => Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AelStatTile(
                        label: '五分制',
                        value: maskGPA(
                          _scholarController.gpa[0].toStringAsFixed(2),
                        ),
                        backgroundColor: colors.primaryContainer,
                        valueColor: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: AelSpacing.sm),
                    Expanded(
                      child: AelStatTile(
                        label: '获得学分',
                        value: maskGPA(
                          _scholarController.scholar.credit.toStringAsFixed(1),
                        ),
                      ),
                    ),
                    const SizedBox(width: AelSpacing.sm),
                    Expanded(
                      child: AelStatTile(
                        label: '四分制',
                        value: maskGPA(
                          _scholarController.gpa[1].toStringAsFixed(2),
                        ),
                        subtitle:
                            '均绩 ${maskGPA(_scholarController.gpa[2].toStringAsFixed(2))}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AelSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AelStatTile(
                        label: '主修均绩',
                        value: maskGPA(
                          _scholarController.scholar.majorGpaAndCredit[0]
                              .toStringAsFixed(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: AelSpacing.sm),
                    Expanded(
                      child: AelStatTile(
                        label: '主修学分',
                        value: maskGPA(
                          _scholarController.scholar.majorGpaAndCredit[1]
                              .toStringAsFixed(1),
                        ),
                      ),
                    ),
                    const SizedBox(width: AelSpacing.sm),
                    Expanded(
                      child: AelStatTile(
                        label: '百分制',
                        value: maskGPA(
                          _scholarController.gpa[3].toStringAsFixed(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemester(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      title: '课程',
      icon: AelIcons.book,
      trailing: Obx(
        () => _buildSyncChip(_scholarController.durationToLastUpdateCourse),
      ),
      child: Obx(() {
        final semester = _scholarController.selectedSemester;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '课程',
                    value: semester.courses.length.toString(),
                    unit: '门',
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => CourseListPage(
                              initialSemesterName: semester.name,
                            ),
                            title: '课程',
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '学分',
                    value: semester.courseCredit.toString(),
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => const CurriculumPlanPage(),
                            title: '培养方案查看',
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '考试',
                    value: semester.examCount.toString(),
                    unit: '场',
                    valueColor: semester.examCount > 0 ? colors.primary : null,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => ExamListPage(
                              initialSemesterName: semester.name,
                            ),
                            title: '考试',
                          ),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AelSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '${semester.firstHalfName}学期课时',
                    value: '${semester.firstHalfSessionCount}',
                    unit: '节/两周',
                    subtitle: '点击查看课表',
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => CourseSchedulePage(
                              '${semester.name} ${semester.firstHalfName}',
                              true,
                            ),
                            title: '${semester.name} ${semester.firstHalfName}',
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '${semester.secondHalfName}学期课时',
                    value: '${semester.secondHalfSessionCount}',
                    unit: '节/两周',
                    subtitle: '点击查看课表',
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => CourseSchedulePage(
                              '${semester.name} ${semester.secondHalfName}',
                              false,
                            ),
                            title:
                                '${semester.name} ${semester.secondHalfName}',
                          ),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AelSpacing.sm),
            AelListRow(
              title: '培养方案查看',
              subtitle: '学分进度 · 修读要求',
              icon: AelIcons.file,
              iconBgColor: colors.primaryContainer,
              iconColor: colors.onPrimaryContainer,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const CurriculumPlanPage(),
                  title: '培养方案查看',
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildTodos(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      title: '作业',
      icon: AelIcons.homework,
      trailing: Obx(
        () => _buildSyncChip(_scholarController.durationToLastUpdateHomework),
      ),
      child: Obx(
        () => Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '总计',
                    value: _scholarController.todos.length.toString(),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '一天内',
                    value: _scholarController.todosInOneDay.length.toString(),
                    valueColor: _scholarController.todosInOneDay.isNotEmpty
                        ? colors.warning
                        : null,
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '本周截止',
                    value: _scholarController.todosInOneWeek.length.toString(),
                  ),
                ),
              ],
            ),
            if (_scholarController.todos.isNotEmpty) ...[
              const SizedBox(height: AelSpacing.md),
              SizedBox(
                height: 102,
                child: _mouseDraggable(
                  context,
                  ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _scholarController.todos.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AelSpacing.sm),
                    itemBuilder: (context, index) {
                      final todo = _scholarController.todos[index];
                      return SizedBox(width: 200, child: TodoCard(todo: todo));
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPractice(BuildContext context) {
    return AelSectionCard(
      title: '实践',
      icon: AelIcons.sparkles,
      trailing: Obx(
        () => _scholarController.scholar.isPracticeScoresGet
            ? const SizedBox.shrink()
            : const AelChip(
                label: '实践记点异常',
                leadingIcon: AelIcons.warning,
                tone: AelChipTone.warning,
              ),
      ),
      child: Obx(
        () => PracticeScoreColumns(scholar: _scholarController.scholar),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(
          context,
          rootNavigator: true,
        ).push(CupertinoPageRoute(builder: (context) => SearchPage()));
      },
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.cardBg,
          shape: AelShapes.squircle(AelRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(AelIcons.search, size: 18, color: colors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '搜索课程、事项...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textTertiary, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: CustomScrollView(
        slivers: [
          SliverPinnedToBoxAdapter(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.pageBg,
                border: Border(
                  bottom: BorderSide(color: colors.divider, width: 0.5),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AelSpacing.pageHorizontal,
                  topPadding + AelSpacing.sm,
                  AelSpacing.pageHorizontal,
                  AelSpacing.sm,
                ),
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxWideContentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '学业',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(width: AelSpacing.md),
                          Expanded(child: _buildSearchBar(context)),
                          if (PlatformFeatures.isDesktop) ...[
                            const SizedBox(width: AelSpacing.sm),
                            ValueListenableBuilder<bool>(
                              valueListenable: _isRefreshing,
                              builder: (context, isRefreshing, _) {
                                if (isRefreshing) {
                                  return const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: CupertinoActivityIndicator(),
                                    ),
                                  );
                                }
                                return AelCircleIconButton(
                                  icon: AelIcons.refresh,
                                  tooltip: '刷新学业数据',
                                  onPressed: () async {
                                    _isRefreshing.value = true;
                                    late final List<String?> results;
                                    try {
                                      results = await _scholarController
                                          .fetchData();
                                    } finally {
                                      _isRefreshing.value = false;
                                    }
                                    if (context.mounted &&
                                        results.any(
                                          (result) => result != null,
                                        )) {
                                      await showRefreshResultDialog(
                                        context,
                                        results,
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AelSpacing.md),
                      SizedBox(
                        height: 34,
                        child: _mouseDraggable(
                          context,
                          Obx(
                            () => ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _scholarController.semesters.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: AelSpacing.sm),
                              itemBuilder: (context, index) {
                                final semester =
                                    _scholarController.semesters[index];
                                return Obx(() {
                                  final selected =
                                      _scholarController.semesterIndex.value ==
                                      index;
                                  return MiuixPressable(
                                    feedbackType: MiuixPressFeedbackType.sink,
                                    onPressed: () {
                                      _scholarController.semesterIndex.value =
                                          index;
                                      _scholarController.semesterIndex
                                          .refresh();
                                    },
                                    child: AnimatedContainer(
                                      duration: AelDurations.fast,
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: selected
                                            ? colors.primary
                                            : colors.cardBg,
                                        shape: AelShapes.squircle(
                                          AelRadius.pill,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                                        style: TextStyle(
                                          color: selected
                                              ? colors.onPrimary
                                              : colors.textSecondary,
                                          fontSize: 13.5,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      // 桌面端刷新超过 5 秒后的状态条：小转圈 + 滚动文案，随刷新结束收起。
                      // 移动端的状态文案由下方 CupertinoSliverRefreshControl 的 builder 展示
                      if (PlatformFeatures.isDesktop)
                        Obx(() {
                          final message =
                              _scholarController.refreshStatusMessage.value;
                          return AnimatedSize(
                            duration: AelDurations.normal,
                            curve: Curves.easeInOut,
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: AelDurations.fast,
                              child: message == null
                                  ? const SizedBox(
                                      key: ValueKey('refreshStatusStripEmpty'),
                                      width: double.infinity,
                                    )
                                  : Padding(
                                      key: const ValueKey('refreshStatusStrip'),
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 2,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const CupertinoActivityIndicator(
                                            radius: 7,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: RollingShimmerText(message),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_scholarController.scholar.isLogan)
            CupertinoSliverRefreshControl(
              // 复刻原生转圈，刷新超过 5 秒后在其右侧滚动展示状态文案。
              // Obx 是必需的：刷新驻留期间 sliver 高度不变、builder 不会被重调，
              // 文案更新只能靠响应式重建
              builder:
                  (
                    context,
                    refreshState,
                    pulledExtent,
                    refreshTriggerPullDistance,
                    refreshIndicatorExtent,
                  ) => Obx(
                    () => RefreshStatusIndicator(
                      refreshState: refreshState,
                      pulledExtent: pulledExtent,
                      refreshTriggerPullDistance: refreshTriggerPullDistance,
                      refreshIndicatorExtent: refreshIndicatorExtent,
                      message: _scholarController.refreshStatusMessage.value,
                    ),
                  ),
              onRefresh: () async {
                final results = await _scholarController.fetchData();
                if (context.mounted &&
                    results.any((result) => result != null)) {
                  await showRefreshResultDialog(context, results);
                }
              },
            ),
          SliverToBoxAdapter(
            child: Obx(() {
              if (_scholarController.scholar.semesters.isNotEmpty) {
                final cards = _scholarController.scholar.isGrs
                    ? [_buildSemester(context), _buildTodos(context)]
                    : [
                        _buildGradeBrief(context),
                        _buildSemester(context),
                        _buildTodos(context),
                        _buildPractice(context),
                      ];
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    AelSpacing.pageHorizontal,
                    AelSpacing.md,
                    AelSpacing.pageHorizontal,
                    MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  child: AelConstrainedWidth(
                    maxWidth: AelBreakpointSpec.maxWideContentWidth,
                    child: AelAdaptiveGrid(
                      maxColumns: 2,
                      minItemWidth: 360,
                      children: cards,
                    ),
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  AelSpacing.pageHorizontal,
                  64,
                  AelSpacing.pageHorizontal,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                child: AelConstrainedWidth(
                  maxWidth: 520,
                  child: AelEmptyState(
                    icon: _scholarController.scholar.isLogan
                        ? AelIcons.refresh
                        : AelIcons.tabOption,
                    title: _scholarController.scholar.isLogan
                        ? '下拉刷新以获取数据'
                        : '未登录',
                    subtitle: _scholarController.scholar.isLogan
                        ? '离线数据将在同步失败时自动使用'
                        : '前往设置登录浙大通行证后即可同步学业数据',
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
