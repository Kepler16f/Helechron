import 'dart:math';

import 'package:celechron/utils/tuple.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'course_schedule_controller.dart';
import 'package:get/get.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'course_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/page/scholar/curriculum_plan/curriculum_plan_page.dart';

class CourseSchedulePage extends StatelessWidget {
  late final CourseScheduleController _courseScheduleController;

  CourseSchedulePage(String name, bool first, {super.key}) {
    bool initialHideCourseInfomation = false;
    try {
      initialHideCourseInfomation =
          Get.find<CourseScheduleController>().hideCourseInfomation.value;
    } catch (e) {
      // not initialized
    }
    Get.delete<CourseScheduleController>();
    _courseScheduleController = Get.put(
      CourseScheduleController(
        initialName: name,
        initialFirstOrSecondSemester: first,
        initialHideCourseInfomation: initialHideCourseInfomation,
      ),
    );
  }

  Widget _semesterPicker(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      padding: const EdgeInsets.all(AelSpacing.md),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _courseScheduleController.semesters.length,
              itemBuilder: (context, index) {
                final semester = _courseScheduleController.semesters[index];
                return Obx(
                  () => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: AelChip(
                        label:
                            '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                        tone:
                            _courseScheduleController.semesterIndex.value ==
                                index
                            ? AelChipTone.primary
                            : AelChipTone.neutral,
                        onTap: () {
                          _courseScheduleController.semesterIndex.value = index;
                          _courseScheduleController.semesterIndex.refresh();
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => Hero(
              tag: 'courseSchedule',
              child: Row(
                children: [
                  Expanded(
                    child: AelStatTile(
                      label:
                          '${_courseScheduleController.semester.firstHalfName}学期课时',
                      value:
                          '${_courseScheduleController.semester.firstHalfSessionCount}',
                      unit: '节/两周',
                      backgroundColor:
                          _courseScheduleController.firstOrSecondSemester.value
                          ? colors.primaryContainer
                          : colors.tonalTileBg,
                      valueColor:
                          _courseScheduleController.firstOrSecondSemester.value
                          ? colors.onPrimaryContainer
                          : colors.textPrimary,
                      onTap: () {
                        _courseScheduleController.firstOrSecondSemester.value =
                            true;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AelStatTile(
                      label:
                          '${_courseScheduleController.semester.secondHalfName}学期课时',
                      value:
                          '${_courseScheduleController.semester.secondHalfSessionCount}',
                      unit: '节/两周',
                      backgroundColor:
                          !_courseScheduleController.firstOrSecondSemester.value
                          ? colors.primaryContainer
                          : colors.tonalTileBg,
                      valueColor:
                          !_courseScheduleController.firstOrSecondSemester.value
                          ? colors.onPrimaryContainer
                          : colors.textPrimary,
                      onTap: () {
                        _courseScheduleController.firstOrSecondSemester.value =
                            false;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _courseSchedule(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    const List<String> courseStartTime = [
      "08:00",
      "08:50",
      "10:00",
      "10:50",
      "11:40",
      "13:25",
      "14:15",
      "15:05",
      "16:15",
      "17:05",
      "18:50",
      "19:40",
      "20:30",
    ];
    const List<String> weekDays = ['一', '二', '三', '四', '五', '六', '日'];
    return AelSectionCard(
      padding: const EdgeInsets.all(AelSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(flex: 1),
              for (final dayLabel in weekDays)
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      dayLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height:
                MediaQuery.sizeOf(context).width >=
                    AelTabBarSpec.sideRailBreakpoint
                ? (MediaQuery.sizeOf(context).height * 0.68).clamp(560.0, 780.0)
                : 560,
            child: Obx(() {
              var sessionsByDayOfWeek =
                  _courseScheduleController.sessionsByDayOfWeek;
              final semName = _courseScheduleController.semester.name;
              final isFirstHalf =
                  _courseScheduleController.firstOrSecondSemester.value;
              final preferredHalfTag = isFirstHalf
                  ? (semName.contains('春夏') ? 'spring' : 'autumn')
                  : (semName.contains('春夏') ? 'summer' : 'winter');
              return Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        for (var i = 1; i <= 13; i++)
                          Expanded(
                            child: Center(
                              child: Column(
                                // mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.fitWidth,
                                    child: Text(
                                      courseStartTime[i - 1],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    i.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var i = 1; i <= 6; i++)
                    Expanded(
                      flex: 2,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            Column(
                              children: [
                                for (var j = 1; j <= 12; j++)
                                  Expanded(
                                    child: Container(
                                      // decoration: BoxDecoration(
                                      //   border: Border(
                                      //     bottom: BorderSide(
                                      //             .resolve(
                                      //                     .systemGrey4,
                                      //                 context)),
                                      //     right: BorderSide(
                                      //       color:
                                      //                   .systemGrey4,
                                      //               context),
                                      //     ),
                                      //   ),
                                      // ),
                                    ),
                                  ),
                                Expanded(
                                  child: Container(
                                    // decoration: BoxDecoration(
                                    //   border: Border(
                                    //     right: BorderSide(
                                    //       color:
                                    //               context),
                                    //     ),
                                    //   ),
                                    // ),
                                  ),
                                ),
                              ],
                            ),
                            ..._buildCourseScheduleByDayOfWeek(
                              sessionsByDayOfWeek,
                              i,
                              constraints,
                              preferredHalfTag: preferredHalfTag,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Column(
                            children: [
                              for (var j = 1; j <= 12; j++)
                                Expanded(
                                  child: Container(
                                    // decoration: BoxDecoration(
                                    //   border: Border(
                                    //     bottom: BorderSide(
                                    //       color:
                                    //               context),
                                    //     ),
                                    //   ),
                                    // ),
                                  ),
                                ),
                              Expanded(child: Container()),
                            ],
                          ),
                          ..._buildCourseScheduleByDayOfWeek(
                            sessionsByDayOfWeek,
                            7,
                            constraints,
                            preferredHalfTag: preferredHalfTag,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCourseScheduleByDayOfWeek(
    List<List<Session>> sessionsByDayOfWeek,
    int day,
    BoxConstraints constraints, {
    String? preferredHalfTag,
  }) {
    List<Tuple<int, int>> period = [];
    for (var i = 1; i <= 13; i++) {
      period.add(Tuple(i, i));
    }
    for (var s in sessionsByDayOfWeek[day]) {
      int sl = s.time.first, sr = s.time.last;
      int xl = sl, xr = sr;
      for (var i in period) {
        if (!(i.item2 < sl || sr < i.item1)) {
          xl = min(xl, i.item1);
          xr = max(xr, i.item2);
        }
      }
      period.removeWhere((x) => xl <= x.item1 && x.item2 <= xr);
      period.add(Tuple(xl, xr));
    }
    List<List<Session>> sessionList = [];
    for (var _ in period) {
      sessionList.add([]);
    }
    for (var s in sessionsByDayOfWeek[day]) {
      int sl = s.time.first, sr = s.time.last;
      for (int i = 0; i < period.length; i++) {
        if (!(period[i].item2 < sl || sr < period[i].item1)) {
          bool added = false;
          for (var t in sessionList[i]) {
            if (t.id == s.id) {
              added = true;
              Set<int> timeSet = Set.from(t.time);
              timeSet.addAll(s.time);
              t.time = List.from(timeSet);
              t.time.sort();
              break;
            }
          }
          if (!added) {
            sessionList[i].add(Session.fromJson(s.toJson()));
          }
        }
      }
    }

    List<Widget> cardList = [];
    for (int i = 0; i < period.length; i++) {
      if (sessionList[i].isNotEmpty) {
        cardList.add(
          Positioned.fromRelativeRect(
            rect: RelativeRect.fromLTRB(
              0,
              (period[i].item1 - 1) * constraints.maxHeight / 13,
              0,
              (13 - period[i].item2) * constraints.maxHeight / 13,
            ),
            child: Obx(
              () => SessionCard(
                sessionList: sessionList[i],
                hideInfomation:
                    _courseScheduleController.hideCourseInfomation.value,
                preferredHalfTag: preferredHalfTag,
              ),
            ),
          ),
        );
      }
    }

    return cardList;

    // return sessionsByDayOfWeek[day]
    //     .map((e) => Positioned.fromRelativeRect(
    //           rect: RelativeRect.fromLTRB(
    //             0,
    //             (e.time.first - 1) * constraints.maxHeight / 13,
    //             0,
    //             (13 - e.time.last) * constraints.maxHeight / 13,
    //           ),
    //           child: SessionCard(sessionList: [e]),
    //         ))
    //     .toList();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AelTheme.colorsOf(context).pageBg,
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: '课表',
            right: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AelChip(
                label: '培养方案',
                tone: AelChipTone.primary,
                leadingIcon: AelIcons.file,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    builder: (context) => const CurriculumPlanPage(),
                    title: '培养方案查看',
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AelConstrainedWidth(
              maxWidth: AelBreakpointSpec.maxWideContentWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _semesterPicker(context),
                    const SizedBox(height: 8),
                    // Container(
                    //   padding: const EdgeInsets.only(left: 16, right: 16),
                    //   child: Text(
                    //     '请前往教务网查看冲突选课课表',
                    //     style: TextStyle(
                    //         fontSize: 14),
                    //   ),
                    // ),
                    // const SizedBox(height: 8),
                    _courseSchedule(context),
                    const SizedBox(height: 20),
                    Obx(
                      () => AelSectionCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AelSpacing.lg,
                          vertical: AelSpacing.xs,
                        ),
                        child: AelSwitchTile(
                          icon: AelIcons.shield,
                          title: '隐藏课程信息',
                          value: _courseScheduleController
                              .hideCourseInfomation
                              .value,
                          onChanged: (value) async {
                            _courseScheduleController
                                    .hideCourseInfomation
                                    .value =
                                value;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
        ],
      ),
    );
  }
}
