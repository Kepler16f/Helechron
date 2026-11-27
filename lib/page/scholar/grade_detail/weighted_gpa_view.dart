import 'package:flutter/cupertino.dart'
    show CupertinoPageScaffold, CupertinoSlider;
import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/grade_detail/weighted_gpa_controller.dart';
import 'semester_gpa_trend_card.dart';

/// 加权成绩页面（各课程加权测算）
class WeightedGpaPage extends StatelessWidget {
  final _controller = Get.put(WeightedGpaController());

  WeightedGpaPage({super.key});

  Widget _buildWeightedGpaBrief(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      padding: const EdgeInsets.all(12),
      cornerRadius: AelRadius.tile,
      child: Obx(() {
        final gpaResult = _controller.calculateCurrentSemesterWeightedGpa();
        final gpa = gpaResult.item1;
        final credits = gpaResult.item2;

        return Row(
          children: [
            Expanded(
              child: AelStatTile(
                label: '加权学分',
                value: credits.toStringAsFixed(1),
                backgroundColor: colors.primaryContainer,
              ),
            ),
            const SizedBox(width: AelSpacing.sm),
            Expanded(
              child: AelStatTile(
                label: '加权五分制',
                value: gpa[0].toStringAsFixed(2),
                backgroundColor: colors.infoContainer,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSemesterPicker(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      cornerRadius: AelRadius.tile,
      child: SizedBox(
        height: 84,
        child: Obx(
          () => ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _controller.semestersWithGrades.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final semester = _controller.semestersWithGrades[index];

              return Obx(() {
                final selected = _controller.semesterIndex.value == index;
                final label =
                    '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
                final value =
                    '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}';

                return SizedBox(
                  width: 120,
                  child: AelStatTile(
                    label: label,
                    value: value,
                    backgroundColor: selected
                        ? colors.primaryContainer
                        : colors.tonalTileBg,
                    valueColor: selected
                        ? colors.onPrimaryContainer
                        : colors.textPrimary,
                    onTap: () {
                      _controller.semesterIndex.value = index;
                      _controller.semesterIndex.refresh();
                    },
                  ),
                );
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCourseWeightSliders(
    BuildContext context,
    List<Grade> affectGpaGrades,
  ) {
    final colors = AelTheme.colorsOf(context);

    if (affectGpaGrades.isEmpty) {
      return AelSectionCard(
        padding: const EdgeInsets.all(24),
        cornerRadius: AelRadius.tile,
        child: AelEmptyState(icon: AelIcons.folder, title: '暂无计入绩点的课程'),
      );
    }

    return AelSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      cornerRadius: AelRadius.tile,
      child: Column(
        children: [
          for (int i = 0; i < affectGpaGrades.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Obx(() {
                        final weight = _controller.getWeight(
                          affectGpaGrades[i].id,
                        );
                        return Text(
                          '${affectGpaGrades[i].fivePoint.toStringAsFixed(1)} (${affectGpaGrades[i].credit.toStringAsFixed(1)}学分) × ${weight.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '权重: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Obx(() {
                          final currentWeight = _controller.getWeight(
                            affectGpaGrades[i].id,
                          );
                          return CupertinoSlider(
                            value: currentWeight,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: colors.primary,
                            onChanged: (val) {
                              _controller.setWeight(
                                affectGpaGrades[i].id,
                                double.parse(val.toStringAsFixed(2)),
                              );
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
              Divider(height: 1, color: colors.divider),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return Obx(() {
      final semesterGrades = _controller.getCurrentSemesterGrades();
      final affectGpaGrades = semesterGrades
          .where((g) => g.gpaIncluded)
          .toList();
      affectGpaGrades.sort((a, b) => a.name.compareTo(b.name));

      return CupertinoPageScaffold(
        backgroundColor: colors.pageBg,
        child: CustomScrollView(
          slivers: [
            CelechronSliverTextHeader(
              subtitle: '加权成绩',
              right: Obx(
                () => Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AelChip(
                        label: '重置',
                        tone: AelChipTone.neutral,
                        onTap: () {
                          _controller.weightedMap.value = {};
                          _controller.refreshWeightedGpa();
                        },
                      ),
                      const SizedBox(width: 8),
                      AelChip(
                        label: _controller.showAllSemesters.value
                            ? '按学期'
                            : '全选',
                        tone: AelChipTone.primary,
                        onTap: () {
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
              child: AelConstrainedWidth(
                maxWidth: AelBreakpointSpec.maxDetailWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 8,
                      ),
                      child: _buildWeightedGpaBrief(context),
                    ),
                    if (!_controller.showAllSemesters.value &&
                        _controller.semestersWithGrades.length >= 2)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 8,
                        ),
                        child: SemesterGpaTrendCard(
                          semesters: _controller.semestersWithGrades,
                          selectedIndex: _controller.semesterIndex.value,
                          onSemesterSelected: (idx) {
                            _controller.semesterIndex.value = idx;
                            _controller.semesterIndex.refresh();
                          },
                        ),
                      ),
                    if (!_controller.showAllSemesters.value)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 8,
                        ),
                        child: _buildSemesterPicker(context),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 8,
                      ),
                      child: _buildCourseWeightSliders(
                        context,
                        affectGpaGrades,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      );
    });
  }
}
