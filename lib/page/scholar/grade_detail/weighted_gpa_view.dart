import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/grade_detail/weighted_gpa_controller.dart';

/// 加权成绩页面（各课程加权测算）
class WeightedGpaPage extends StatelessWidget {
  final _controller = Get.put(WeightedGpaController());

  WeightedGpaPage({super.key});

  Widget _buildWeightedGpaBrief(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Hero(
                tag: 'weightedGpaBrief',
                child: RoundRectangleCard(
                  child: Obx(() {
                    final gpaResult =
                        _controller.calculateCurrentSemesterWeightedGpa();
                    final gpa = gpaResult.item1;
                    final credits = gpaResult.item2;

                    return Row(
                      children: [
                        Expanded(
                          child: TwoLineCard(
                            title: '加权学分',
                            content: credits.toStringAsFixed(1),
                            backgroundColor: CustomCupertinoDynamicColors.sand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TwoLineCard(
                            title: '加权五分制',
                            content: gpa[0].toStringAsFixed(2),
                            backgroundColor:
                                CustomCupertinoDynamicColors.sakura,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSemesterPicker(BuildContext context) {
    return RoundRectangleCard(
      animate: false,
      child: Column(
        children: [
          SizedBox(
            height: 81,
            child: Obx(
              () => ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _controller.semestersWithGrades.length,
                itemBuilder: (context, index) {
                  final semester = _controller.semestersWithGrades[index];

                  return Obx(
                    () => Row(
                      children: [
                        TwoLineCard(
                          animate: true,
                          withColoredFont: true,
                          width: 120,
                          title:
                              '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                          content:
                              '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                          onTap: () {
                            _controller.semesterIndex.value = index;
                            _controller.semesterIndex.refresh();
                          },
                          backgroundColor:
                              _controller.semesterIndex.value == index
                                  ? CustomCupertinoDynamicColors.cyan
                                  : CupertinoColors.systemFill,
                        ),
                        if (index != _controller.semestersWithGrades.length - 1)
                          const SizedBox(width: 6),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCourseWeightSliders(
      BuildContext context, List<Grade> affectGpaGrades) {
    if (affectGpaGrades.isEmpty) {
      return RoundRectangleCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                CupertinoIcons.tray,
                size: 40,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
              const SizedBox(height: 8),
              Text(
                '暂无计入绩点的课程',
                style: TextStyle(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RoundRectangleCard(
      child: Column(
        children: [
          for (int i = 0; i < affectGpaGrades.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          affectGpaGrades[i].name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Obx(() {
                        final weight =
                            _controller.getWeight(affectGpaGrades[i].id);
                        return Text(
                          '${affectGpaGrades[i].fivePoint.toStringAsFixed(1)} (${affectGpaGrades[i].credit.toStringAsFixed(1)}学分) × ${weight.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel, context),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('权重: ', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Obx(() {
                          final currentWeight =
                              _controller.getWeight(affectGpaGrades[i].id);
                          return CupertinoSlider(
                            value: currentWeight,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: CustomCupertinoDynamicColors.sakura,
                            onChanged: (val) {
                              _controller.setWeight(
                                  affectGpaGrades[i].id,
                                  double.parse(val.toStringAsFixed(2)));
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (i != affectGpaGrades.length - 1)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.separator, context),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final semesterGrades = _controller.getCurrentSemesterGrades();
      final affectGpaGrades =
          semesterGrades.where((g) => g.gpaIncluded).toList();
      affectGpaGrades.sort((a, b) => a.name.compareTo(b.name));

      return CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: CustomScrollView(
          slivers: [
            CelechronSliverTextHeader(
              subtitle: '加权成绩',
              right: Obx(
                () => Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Text(
                          '重置',
                          style: TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          _controller.weightedMap.value = {};
                          _controller.refreshWeightedGpa();
                        },
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Text(
                          _controller.showAllSemesters.value ? '按学期' : '全选',
                          style: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          _controller.showAllSemesters.value =
                              !_controller.showAllSemesters.value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildWeightedGpaBrief(context),
            ),
            if (!_controller.showAllSemesters.value)
              SliverToBoxAdapter(
                child: _buildSemesterPicker(context),
              ),
            SliverToBoxAdapter(
              child: _buildCourseWeightSliders(context, affectGpaGrades),
            ),
            const SliverToBoxAdapter(
              child: NativeBottomBarSpacer(),
            ),
          ],
        ),
      );
    });
  }
}
