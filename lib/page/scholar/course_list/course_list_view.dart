import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';

import 'package:get/get.dart';

import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';

import 'package:celechron/design/animate_button.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/page/scholar/curriculum_plan/curriculum_plan_page.dart';
import 'course_list_controller.dart';

class CourseListPage extends StatelessWidget {
  late final CourseListController _courseListController;

  CourseListPage({required String initialSemesterName, super.key}) {
    Get.delete<CourseListController>();
    _courseListController =
        Get.put(CourseListController(initialName: initialSemesterName));
  }

  Widget _semesterPicker(BuildContext context) {
    return RoundRectangleCard(
      animate: false,
      child: Column(children: [
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _courseListController.semesters.length,
                  itemBuilder: (context, index) {
                    final semester = _courseListController.semesters[index];
                    return Obx(() => Stack(children: [
                          AnimateButton(
                            text:
                                '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                            onTap: () {
                              _courseListController.semesterIndex.value = index;
                              _courseListController.semesterIndex.refresh();
                            },
                            backgroundColor:
                                _courseListController.semesterIndex.value ==
                                        index
                                    ? CustomCupertinoDynamicColors.cyan
                                    : CupertinoColors.systemFill,
                          ),
                          const SizedBox(width: 90),
                        ]));
                  }),
            ),
          ),
        ]),
      ]),
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
            subtitle: '课程',
            right: CupertinoButton(
              padding: const EdgeInsets.only(right: 12),
              minSize: 32,
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const CurriculumPlanPage(),
                  title: '培养方案查看',
                ),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakuraInk, context)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CupertinoDynamicColor.resolve(
                            CustomCupertinoDynamicColors.sakuraInk, context)
                        .withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.doc_text_search,
                      size: 13,
                      color: CupertinoDynamicColor.resolve(
                          CustomCupertinoDynamicColors.sakuraInk, context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '培养方案',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoDynamicColor.resolve(
                            CustomCupertinoDynamicColors.sakuraInk, context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPinnedToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                child: Obx(() => _semesterPicker(context))),
          ),
          Obx(() => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Container(
                    padding: index == 0
                        ? const EdgeInsets.only(
                            top: 0, bottom: 5, left: 16, right: 16)
                        : const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                    child: CourseBriefCard(
                      course: _courseListController.courses[index],
                      allowDirect: true,
                      showZhiyunInDetail: false,
                    ),
                  ),
                  childCount: _courseListController.courses.length,
                ),
              )),
        ],
      ),
    );
  }
}

/*class _SemesterPickerPersistentHeaderBuilder extends SliverPersistentHeaderDelegate {

  final StatelessWidget child;

  _SemesterPickerPersistentHeaderBuilder(this.child);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Padding(
        padding: const EdgeInsets.only(left: 16, right:16, bottom: 10),
        child: child);
  }

  // min and max extents are both determined by child size
  @override
  double get minExtent => child;

  @override
  double get maxExtent =>

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}*/
