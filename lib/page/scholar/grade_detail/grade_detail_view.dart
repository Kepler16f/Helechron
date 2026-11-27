import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'package:celechron/utils/tuple.dart';

import 'gpa_simulator_view.dart';
import 'grade_card.dart';
import 'grade_detail_controller.dart';
import 'semester_gpa_trend_card.dart';
import 'weighted_gpa_view.dart';

class GradeDetailPage extends StatefulWidget {
  const GradeDetailPage({super.key});

  @override
  State<GradeDetailPage> createState() => _GradeDetailPageState();
}

class _GradeDetailPageState extends State<GradeDetailPage> {
  late final GradeDetailController _gradeDetailController;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<GradeDetailController>()) {
      _gradeDetailController = Get.find<GradeDetailController>();
      _gradeDetailController.resetState();
      _ownsController = false;
    } else {
      _gradeDetailController = Get.put(GradeDetailController());
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController && Get.isRegistered<GradeDetailController>()) {
      Get.delete<GradeDetailController>();
    }
    super.dispose();
  }

  int getPairedSemesterIndex(int idx) {
    for (
      var i = 0;
      i < _gradeDetailController.semestersWithGrades.length;
      i++
    ) {
      if (i != idx &&
          _gradeDetailController.semestersWithGrades[i].name.substring(2, 5) ==
              _gradeDetailController.semestersWithGrades[idx].name.substring(
                2,
                5,
              )) {
        return i;
      }
    }
    return idx;
  }

  Tuple<List<double>, double> getYearStats(int semesterIndex) {
    var s1 = _gradeDetailController.semestersWithGrades[semesterIndex];
    int another = getPairedSemesterIndex(semesterIndex);
    if (another == semesterIndex) {
      return Tuple([s1.gpa[0], s1.gpa[1], s1.gpa[2]], s1.credits);
    }
    var s2 = _gradeDetailController.semestersWithGrades[another];
    double credits = s1.credits + s2.credits;
    if (credits == 0) {
      return Tuple([0, 0, 0], 0);
    }
    return Tuple(
      List.generate(
        3,
        (int i) => (s1.credits * s1.gpa[i] + s2.credits * s2.gpa[i]) / credits,
      ),
      credits,
    );
  }

  Widget _buildGradeBrief(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      title: '学年成绩概览',
      icon: AelIcons.award,
      child: Obx(() {
        final semesters = _gradeDetailController.semestersWithGrades;
        if (semesters.isEmpty) {
          return const SizedBox.shrink();
        }
        final idx = _gradeDetailController.semesterIndex.value.clamp(
          0,
          semesters.length - 1,
        );
        final yearStats = getYearStats(idx);
        final majorStats = _gradeDetailController.getYearMajorGpa(idx);
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '学年学分',
                    value: yearStats.item2.toStringAsFixed(1),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '学年均绩',
                    value: yearStats.item1[0].toStringAsFixed(2),
                    backgroundColor: colors.primaryContainer,
                    valueColor: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '学年四分制',
                    value: yearStats.item1[1].toStringAsFixed(2),
                    subtitle: '均绩 ${yearStats.item1[2].toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AelSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '学年主修学分',
                    value: majorStats.item2.toStringAsFixed(1),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '学年主修均绩',
                    value: majorStats.item1[0].toStringAsFixed(2),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '学年主修四分制',
                    value: majorStats.item1[1].toStringAsFixed(2),
                    subtitle: '均绩 ${majorStats.item1[2].toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCustomGpaBrief(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      title: '自选 GPA 计算',
      icon: AelIcons.filter,
      child: Obx(() {
        List<Grade> inSelected = [], notSelected = [];
        for (var semester in _gradeDetailController.semestersWithGrades) {
          for (var grade in semester.grades) {
            if (_gradeDetailController.customGpaSelected[grade.id] ?? false) {
              inSelected.add(grade);
            } else {
              notSelected.add(grade);
            }
          }
        }
        var inGpa = GpaHelper.calculateGpa(inSelected);
        var notGpa = GpaHelper.calculateGpa(notSelected);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '已选学分',
                    value: inGpa.item2.toStringAsFixed(1),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '已选五分制',
                    value: inGpa.item1[0].toStringAsFixed(2),
                    backgroundColor: colors.primaryContainer,
                    valueColor: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '已选四分制',
                    value: inGpa.item1[1].toStringAsFixed(2),
                    subtitle: '均绩 ${inGpa.item1[2].toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AelSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AelStatTile(
                    label: '已选百分制',
                    value: inGpa.item1[3].toStringAsFixed(2),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '未选五分制',
                    value: notGpa.item1[0].toStringAsFixed(2),
                  ),
                ),
                const SizedBox(width: AelSpacing.sm),
                Expanded(
                  child: AelStatTile(
                    label: '未选四分制',
                    value: notGpa.item1[1].toStringAsFixed(2),
                    subtitle: '均绩 ${notGpa.item1[2].toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  int getSelectedGradeCount(Semester semester) {
    int selectedCount = 0;
    for (var i in semester.grades) {
      if (_gradeDetailController.customGpaSelected[i.id] ?? false) {
        selectedCount++;
      }
    }
    return selectedCount;
  }

  Widget _buildHistory(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      title: '学期记录',
      icon: AelIcons.tabCalendar,
      child: SizedBox(
        height: 78,
        child: Obx(
          () => ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _gradeDetailController.semestersWithGrades.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AelSpacing.sm),
            itemBuilder: (context, index) {
              final semester =
                  _gradeDetailController.semestersWithGrades[index];
              return Obx(() {
                final selected =
                    _gradeDetailController.semesterIndex.value == index;
                final customMode = _gradeDetailController.customGpaMode.value;
                return SizedBox(
                  width: 122,
                  child: MiuixPressable(
                    feedbackType: MiuixPressFeedbackType.sink,
                    onPressed: () {
                      _gradeDetailController.semesterIndex.value = index;
                      _gradeDetailController.semesterIndex.refresh();
                    },
                    onLongPress: customMode
                        ? () {
                            _gradeDetailController.semesterIndex.value = index;
                            _gradeDetailController.semesterIndex.refresh();
                            _gradeDetailController.toggleSemesterSelection(
                              index,
                            );
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: AelDurations.fast,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: ShapeDecoration(
                        color: selected
                            ? colors.primaryContainer
                            : colors.tonalTileBg,
                        shape: AelShapes.squircle(AelRadius.tile),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? colors.onPrimaryContainer.withValues(
                                      alpha: 0.78,
                                    )
                                  : colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            customMode
                                ? '${getSelectedGradeCount(semester)} / ${semester.grades.length}'
                                : '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              });
            },
          ),
        ),
      ),
    );
  }

  void _showMoreActions(BuildContext context) {
    showAelActionSheet<void>(
      context: context,
      title: '成绩分析与工具',
      actions: [
        AelActionOption<void>(
          label: '加权成绩分析',
          icon: AelIcons.activity,
          onTap: () {
            Navigator.of(
              context,
            ).push(CupertinoPageRoute(builder: (_) => WeightedGpaPage()));
          },
        ),
        AelActionOption<void>(
          label: 'GPA 模拟器',
          icon: AelIcons.filter,
          onTap: () {
            Navigator.of(
              context,
            ).push(CupertinoPageRoute(builder: (_) => GpaSimulatorPage()));
          },
        ),
        AelActionOption<void>(
          label: _gradeDetailController.showTrendChart.value
              ? '隐藏学期走势折线图'
              : '展示学期走势折线图',
          icon: AelIcons.sparkles,
          onTap: () {
            _gradeDetailController.showTrendChart.value =
                !_gradeDetailController.showTrendChart.value;
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionRow(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Row(
      children: [
        Expanded(
          child: _buildQuickActionButton(
            context: context,
            icon: AelIcons.activity,
            label: '加权成绩',
            accentColor: colors.primary,
            onTap: () {
              Navigator.of(
                context,
              ).push(CupertinoPageRoute(builder: (_) => WeightedGpaPage()));
            },
          ),
        ),
        const SizedBox(width: AelSpacing.sm),
        Expanded(
          child: _buildQuickActionButton(
            context: context,
            icon: AelIcons.filter,
            label: 'GPA模拟器',
            accentColor: colors.warning,
            onTap: () {
              Navigator.of(
                context,
              ).push(CupertinoPageRoute(builder: (_) => GpaSimulatorPage()));
            },
          ),
        ),
        const SizedBox(width: AelSpacing.sm),
        Expanded(
          child: Obx(() {
            final active = _gradeDetailController.showTrendChart.value;
            return _buildQuickActionButton(
              context: context,
              icon: AelIcons.sparkles,
              label: '学期走势',
              accentColor: active ? colors.primary : colors.textSecondary,
              selected: active,
              onTap: () {
                _gradeDetailController.showTrendChart.value = !active;
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final colors = AelTheme.colorsOf(context);
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: selected ? colors.primaryContainer : colors.cardBg,
          shape: AelShapes.squircle(AelRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.onPrimaryContainer : accentColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.textPrimary,
                  ),
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
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = AelResponsive.isWideBody(constraints.maxWidth);
          final header = CelechronSliverTextHeader(
            subtitle: '成绩',
            right: Obx(
              () => Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_gradeDetailController.customGpaMode.value) ...[
                      GestureDetector(
                        onLongPress: () {
                          _gradeDetailController.customGpaSelected.value = {};
                          _gradeDetailController.refreshCustomGpa();
                        },
                        child: const AelChip(
                          label: '长按清空',
                          tone: AelChipTone.error,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      // 更多工具入口（收纳加权、模拟、看板，彻底解决标题遮挡冲突）
                      AelCircleIconButton(
                        icon: AelIcons.more,
                        size: 36,
                        iconSize: 18,
                        tooltip: 'More Tools',
                        onPressed: () => _showMoreActions(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // 自定义 GPA 开关
                    AelCircleIconButton(
                      icon: _gradeDetailController.customGpaMode.value
                          ? AelIcons.check
                          : AelIcons.filter,
                      size: 36,
                      iconSize: 17,
                      backgroundColor:
                          _gradeDetailController.customGpaMode.value
                          ? colors.primary
                          : null,
                      iconColor: _gradeDetailController.customGpaMode.value
                          ? colors.onPrimary
                          : null,
                      tooltip: 'Custom GPA',
                      onPressed: () {
                        _gradeDetailController.customGpaMode.value =
                            !_gradeDetailController.customGpaMode.value;
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
          final summaryColumn = Column(
            children: [
              Obx(
                () => _gradeDetailController.customGpaMode.value
                    ? _buildCustomGpaBrief(context)
                    : _buildGradeBrief(context),
              ),
              Obx(() {
                if (_gradeDetailController.customGpaMode.value) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AelSpacing.md),
                  child: _buildQuickActionRow(context),
                );
              }),
              Obx(() {
                if (!_gradeDetailController.customGpaMode.value &&
                    _gradeDetailController.showTrendChart.value &&
                    _gradeDetailController.semestersWithGrades.length >= 2) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AelSpacing.md),
                    child: SemesterGpaTrendCard(
                      semesters: _gradeDetailController.semestersWithGrades,
                      selectedIndex: _gradeDetailController.semesterIndex.value,
                      onSemesterSelected: (idx) {
                        _gradeDetailController.semesterIndex.value = idx;
                        _gradeDetailController.semesterIndex.refresh();
                      },
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              const SizedBox(height: AelSpacing.sectionGap),
              _buildHistory(context),
            ],
          );

          return CustomScrollView(
            slivers: [
              header,
              if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AelSpacing.pageHorizontal,
                    AelSpacing.sm,
                    AelSpacing.pageHorizontal,
                    AelSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AelConstrainedWidth(
                      maxWidth: AelBreakpointSpec.maxWideContentWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: summaryColumn),
                          const SizedBox(width: AelSpacing.lg),
                          Expanded(
                            flex: 6,
                            child: Obx(() {
                              final semesters =
                                  _gradeDetailController.semestersWithGrades;
                              if (semesters.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final safeIdx = _gradeDetailController
                                  .semesterIndex
                                  .value
                                  .clamp(0, semesters.length - 1);
                              final grades = semesters[safeIdx].grades;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < grades.length; i++) ...[
                                    if (i > 0)
                                      const SizedBox(height: AelSpacing.sm),
                                    GradeCard(grade: grades[i]),
                                  ],
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AelSpacing.pageHorizontal,
                    AelSpacing.sm,
                    AelSpacing.pageHorizontal,
                    AelSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(child: summaryColumn),
                ),
                Obx(() {
                  final semesters = _gradeDetailController.semestersWithGrades;
                  if (semesters.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  final safeIdx = _gradeDetailController.semesterIndex.value
                      .clamp(0, semesters.length - 1);
                  final grades = semesters[safeIdx].grades;
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AelSpacing.pageHorizontal,
                    ),
                    sliver: SliverList.separated(
                      itemCount: grades.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AelSpacing.sm),
                      itemBuilder: (context, index) {
                        return GradeCard(grade: grades[index]);
                      },
                    ),
                  );
                }),
              ],
              const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
            ],
          );
        },
      ),
    );
  }
}
