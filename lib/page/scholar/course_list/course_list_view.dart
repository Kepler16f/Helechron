import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoPageScaffold, CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:celechron/page/scholar/curriculum_plan/curriculum_plan_page.dart';
import 'course_list_controller.dart';

class CourseListPage extends StatelessWidget {
  late final CourseListController _courseListController;

  CourseListPage({required String initialSemesterName, super.key}) {
    Get.delete<CourseListController>();
    _courseListController = Get.put(
      CourseListController(initialName: initialSemesterName),
    );
  }

  Widget _semesterPicker(BuildContext context) {
    return AelSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      cornerRadius: AelRadius.tile,
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _courseListController.semesters.length,
          separatorBuilder: (_, __) => const SizedBox(width: AelSpacing.sm),
          itemBuilder: (context, index) {
            final semester = _courseListController.semesters[index];
            final label =
                '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
            return Obx(() {
              final selected =
                  _courseListController.semesterIndex.value == index;
              return AelChip(
                label: label,
                tone: selected ? AelChipTone.primary : AelChipTone.neutral,
                onTap: () {
                  _courseListController.semesterIndex.value = index;
                  _courseListController.semesterIndex.refresh();
                },
              );
            });
          },
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
          return CustomScrollView(
            slivers: [
              CelechronSliverTextHeader(
                subtitle: '课程',
                right: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AelChip(
                    label: '培养方案',
                    leadingIcon: AelIcons.book,
                    tone: AelChipTone.primary,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute(
                            builder: (context) => const CurriculumPlanPage(),
                            title: '培养方案查看',
                          ),
                        ),
                  ),
                ),
              ),
              SliverPinnedToBoxAdapter(
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxWideContentWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 10,
                    ),
                    child: Obx(() => _semesterPicker(context)),
                  ),
                ),
              ),
              Obx(() {
                final courses = _courseListController.courses;
                if (!isWide) {
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Container(
                        padding: index == 0
                            ? const EdgeInsets.only(
                                top: 0,
                                bottom: 5,
                                left: 16,
                                right: 16,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                        child: CourseBriefCard(
                          course: courses[index],
                          allowDirect: true,
                          showZhiyunInDetail: false,
                        ),
                      ),
                      childCount: courses.length,
                    ),
                  );
                }

                final rowCount = (courses.length + 1) ~/ 2;
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, rowIndex) {
                    final leftIdx = rowIndex * 2;
                    final rightIdx = leftIdx + 1;
                    return AelConstrainedWidth(
                      maxWidth: AelBreakpointSpec.maxWideContentWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CourseBriefCard(
                                course: courses[leftIdx],
                                allowDirect: true,
                                showZhiyunInDetail: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: rightIdx < courses.length
                                  ? CourseBriefCard(
                                      course: courses[rightIdx],
                                      allowDirect: true,
                                      showZhiyunInDetail: false,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: rowCount),
                );
              }),
              const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
            ],
          );
        },
      ),
    );
  }
}
