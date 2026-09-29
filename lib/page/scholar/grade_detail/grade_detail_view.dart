import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/semester.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'grade_card.dart';
import 'grade_detail_controller.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'weighted_gpa_view.dart';
import 'gpa_simulator_view.dart';
import 'credit_progress_view.dart';
import 'package:celechron/design/native_bar_spacer.dart';

class GradeDetailPage extends StatelessWidget {
  final _gradeDetailController = Get.put(GradeDetailController());

  GradeDetailPage({super.key}) {
    _gradeDetailController.init();
  }

  int getPairedSemesterIndex(int idx) {
    for (var i = 0;
        i < _gradeDetailController.semestersWithGrades.length;
        i++) {
      if (i != idx &&
          _gradeDetailController.semestersWithGrades[i].name.substring(2, 5) ==
              _gradeDetailController.semestersWithGrades[idx].name
                  .substring(2, 5)) {
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
            (int i) =>
                (s1.credits * s1.gpa[i] + s2.credits * s2.gpa[i]) / credits),
        credits);
  }

  Widget _buildGradeBrief(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Hero(
                tag: 'gradeBrief',
                child: RoundRectangleCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年学分',
                                content: getYearStats(_gradeDetailController
                                        .semesterIndex.value)
                                    .item2
                                    .toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sand)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年均绩',
                                content: getYearStats(_gradeDetailController
                                        .semesterIndex.value)
                                    .item1[0]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sakura)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年四分制',
                                content: getYearStats(_gradeDetailController
                                        .semesterIndex.value)
                                    .item1[1]
                                    .toStringAsFixed(2),
                                extraContent: getYearStats(
                                        _gradeDetailController
                                            .semesterIndex.value)
                                    .item1[2]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.magenta)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修学分',
                                content: _gradeDetailController
                                    .getYearMajorGpa(_gradeDetailController
                                        .semesterIndex.value)
                                    .item2
                                    .toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.peach)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修均绩',
                                content: _gradeDetailController
                                    .getYearMajorGpa(_gradeDetailController
                                        .semesterIndex.value)
                                    .item1[0]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.cyan)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修四分制',
                                content: _gradeDetailController
                                    .getYearMajorGpa(_gradeDetailController
                                        .semesterIndex.value)
                                    .item1[1]
                                    .toStringAsFixed(2),
                                extraContent: _gradeDetailController
                                    .getYearMajorGpa(_gradeDetailController
                                        .semesterIndex.value)
                                    .item1[2]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.spring)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomGpaBrief(BuildContext context) {
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
              child: Hero(
                tag: 'gradeBrief',
                child: RoundRectangleCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选学分',
                                content: inGpa.item2.toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sand)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选五分制',
                                content: inGpa.item1[0].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sakura)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选四分制',
                                content: inGpa.item1[1].toStringAsFixed(2),
                                extraContent: inGpa.item1[2].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.magenta)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选百分制',
                                content: inGpa.item1[3].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.peach)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '未选五分制',
                                content: notGpa.item1[0].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.cyan)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '未选四分制',
                                content: notGpa.item1[1].toStringAsFixed(2),
                                extraContent:
                                    notGpa.item1[2].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.spring)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RoundRectangleCard(
                animate: false,
                child: Column(
                  children: [
                    // Horizontal scrollable list to list all semesters
                    SizedBox(
                      height: 81,
                      child: Obx(
                        () => ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              _gradeDetailController.semestersWithGrades.length,
                          itemBuilder: (context, index) {
                            final semester = _gradeDetailController
                                .semestersWithGrades[index];

                            return Obx(
                              () => Row(
                                children: [
                                  Obx(
                                    () => TwoLineCard(
                                      animate: true,
                                      withColoredFont: true,
                                      width: 120,
                                      title:
                                          '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                                      content: _gradeDetailController
                                              .customGpaMode.value
                                          ? '${getSelectedGradeCount(semester)} / ${semester.grades.length}'
                                          : '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                                      onTap: () {
                                        _gradeDetailController
                                            .semesterIndex.value = index;
                                        _gradeDetailController.semesterIndex
                                            .refresh();
                                      },
                                      onLongPress: _gradeDetailController
                                              .customGpaMode.value
                                          ? () {
                                              _gradeDetailController
                                                  .semesterIndex.value = index;
                                              _gradeDetailController
                                                  .semesterIndex
                                                  .refresh();
                                              _gradeDetailController
                                                  .toggleSemesterSelection(
                                                      index);
                                            }
                                          : null,
                                      backgroundColor: _gradeDetailController
                                                  .semesterIndex.value ==
                                              index
                                          ? CustomCupertinoDynamicColors.cyan
                                          : CupertinoColors.systemFill,
                                    ),
                                  ),
                                  if (index !=
                                      _gradeDetailController
                                              .semestersWithGrades.length -
                                          1)
                                    const SizedBox(width: 6),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _showMoreActions(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetCtx) => CupertinoActionSheet(
        title: const Text('成绩分析与工具'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.chart_pie_fill, size: 20),
                SizedBox(width: 8),
                Text('学分看板（培养方案）'),
              ],
            ),
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => CreditProgressPage()),
              );
            },
          ),
          CupertinoActionSheetAction(
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.chart_bar_alt_fill, size: 20),
                SizedBox(width: 8),
                Text('加权成绩分析'),
              ],
            ),
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => WeightedGpaPage()),
              );
            },
          ),
          CupertinoActionSheetAction(
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.slider_horizontal_3, size: 20),
                SizedBox(width: 8),
                Text('GPA 模拟器'),
              ],
            ),
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => GpaSimulatorPage()),
              );
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('取消'),
          onPressed: () => Navigator.of(sheetCtx).pop(),
        ),
      ),
    );
  }

  Widget _buildQuickActionRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildQuickActionButton(
              context: context,
              icon: CupertinoIcons.chart_pie_fill,
              label: '学分看板',
              color: CustomCupertinoDynamicColors.sakura,
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => CreditProgressPage()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildQuickActionButton(
              context: context,
              icon: CupertinoIcons.chart_bar_alt_fill,
              label: '加权成绩',
              color: CustomCupertinoDynamicColors.cyan,
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => WeightedGpaPage()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildQuickActionButton(
              context: context,
              icon: CupertinoIcons.slider_horizontal_3,
              label: 'GPA模拟器',
              color: CustomCupertinoDynamicColors.peach,
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => GpaSimulatorPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required CupertinoDynamicColor color,
    required VoidCallback onTap,
  }) {
    return RoundRectangleCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      animate: true,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: CupertinoDynamicColor.resolve(color, context),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.label, context),
            ),
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
          CelechronSliverTextHeader(
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
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: const Text('长按清空'),
                          onPressed: () {},
                        ),
                        onLongPress: () {
                          _gradeDetailController.customGpaSelected.value = {};
                          _gradeDetailController.refreshCustomGpa();
                        },
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      // 更多工具入口（收纳加权、模拟、看板，彻底解决标题遮挡冲突）
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.ellipsis_circle,
                          semanticLabel: 'More Tools',
                        ),
                        onPressed: () => _showMoreActions(context),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // 自定义 GPA 开关
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        _gradeDetailController.customGpaMode.value
                            ? CupertinoIcons
                                .square_fill_line_vertical_square_fill
                            : CupertinoIcons.square_line_vertical_square,
                        semanticLabel: 'Custom GPA',
                      ),
                      onPressed: () {
                        _gradeDetailController.customGpaMode.value =
                            !_gradeDetailController.customGpaMode.value;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [
                          Obx(() => _gradeDetailController.customGpaMode.value
                              ? _buildCustomGpaBrief(context)
                              : _buildGradeBrief(context)),
                          Obx(() => !_gradeDetailController.customGpaMode.value
                              ? _buildQuickActionRow(context)
                              : const SizedBox.shrink()),
                          _buildHistory(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                )
              ],
            ),
          ),
          Obx(
            () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 18),
                          Expanded(
                            child: GradeCard(
                              grade: _gradeDetailController
                                  .semestersWithGrades[_gradeDetailController
                                      .semesterIndex.value]
                                  .grades[index],
                            ),
                          ),
                          const SizedBox(width: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
                childCount: _gradeDetailController
                    .semestersWithGrades[
                        _gradeDetailController.semesterIndex.value]
                    .grades
                    .length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
        ],
      ),
    );
  }
}
