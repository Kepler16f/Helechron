import 'dart:io';

import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';

import 'package:celechron/model/exam.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/scholar/todo/todo_card.dart';
import 'package:celechron/page/task/homework_submission_page.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'zhiyun_player_page.dart';

class CourseDetailPage extends StatelessWidget {
  final Course? course;
  final Period? period;
  final bool showZhiyun;

  CourseDetailPage({
    required String? courseId,
    this.period,
    this.showZhiyun = true,
    super.key,
  }) : course = _findCourse(courseId);

  /// 依据不同来源的标识定位课程。
  ///
  /// 本科课程由 ZDBK 课表创建时没有课号（[Course.id] 为 null），只有成绩
  /// 补全后才会带上选课课号，因此不能只用 [Course.id] 匹配：
  /// - 课程表 / 日历：传入 [Session.id]（可能为 null）
  /// - 成绩卡片：传入 [Grade.id]（选课课号，对应 [Course.grade])
  /// - 课程列表：传入 [Course.id]
  static Course? _findCourse(String? courseId) {
    if (courseId == null || courseId.isEmpty) {
      return null;
    }
    try {
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
      for (final semester in scholar.value.semesters) {
        final byKey = semester.courses[courseId];
        if (byKey != null) {
          return byKey;
        }
        for (final candidate in semester.courses.values) {
          if (candidate.id == courseId) {
            return candidate;
          }
          if (candidate.grade?.id == courseId) {
            return candidate;
          }
          for (final session in candidate.sessions) {
            if (session.id != null && session.id == courseId) {
              return candidate;
            }
          }
        }
      }
    } catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.error,
        module: 'course',
        operation: 'findCourse',
        message: 'courseId=$courseId',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  Widget createSessionCard(context, List<Session> sessions) {
    sessions.sort((a, b) => a.time.first.compareTo(b.time.first));
    return Column(
      children: [
        SubSubtitleRow(subtitle: '课时'),
        RoundRectangleCard(
            child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: Column(children: [
            Row(
              children: [
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12.0,
                              height: 12.0,
                              decoration: BoxDecoration(
                                color: TimeColors.colorFromClass(
                                    sessions[0].time.first),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                                child: Text(sessions[0].chineseTime,
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .copyWith(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          overflow: TextOverflow.ellipsis,
                                        ))),
                          ],
                        ),
                        const SizedBox(height: 4.0),
                        Row(children: [
                          Icon(
                            CupertinoIcons.location_solid,
                            size: 14,
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.5),
                          ),
                          Expanded(
                              child: Text(' 地点：${sessions[0].location ?? '未知'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .color!
                                        .withValues(alpha: 0.75),
                                    overflow: TextOverflow.ellipsis,
                                  )))
                        ]),
                      ],
                    ),
                    for (var i = 1; i < sessions.length; i++)
                      Column(
                        children: [
                          Divider(
                            height: 24,
                            thickness: 1,
                            indent: 0,
                            endIndent: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 12.0,
                                height: 12.0,
                                decoration: BoxDecoration(
                                  color: TimeColors.colorFromClass(
                                      sessions[i].time.first),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Expanded(
                                  child: Text(sessions[i].chineseTime,
                                      style: CupertinoTheme.of(context)
                                          .textTheme
                                          .textStyle
                                          .copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            overflow: TextOverflow.ellipsis,
                                          ))),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          Row(children: [
                            Icon(
                              CupertinoIcons.location_solid,
                              size: 14,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.5),
                            ),
                            Expanded(
                                child:
                                    Text(' 地点：${sessions[i].location ?? '未知'}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: CupertinoTheme.of(context)
                                              .textTheme
                                              .textStyle
                                              .color!
                                              .withValues(alpha: 0.75),
                                          overflow: TextOverflow.ellipsis,
                                        )))
                          ]),
                        ],
                      )
                  ],
                )),
              ],
            ),
          ]),
        ))
      ],
    );
  }

  Widget createExamCard(context, List<Exam> exams) {
    return Column(
      children: [
        SubSubtitleRow(subtitle: '考试'),
        RoundRectangleCard(
            child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: Column(children: [
            Row(
              children: [
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12.0,
                              height: 12.0,
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemPink,
                                shape: exams[0].type == ExamType.midterm
                                    ? BoxShape.circle
                                    : BoxShape.rectangle,
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                                child: Text(exams[0].chineseTime,
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .copyWith(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          overflow: TextOverflow.ellipsis,
                                        ))),
                          ],
                        ),
                        const SizedBox(height: 4.0),
                        Row(children: [
                          Icon(
                            CupertinoIcons.location_solid,
                            size: 14,
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.5),
                          ),
                          Expanded(
                              child: Text(' 地点：${exams[0].location ?? '未知'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .color!
                                        .withValues(alpha: 0.75),
                                    overflow: TextOverflow.ellipsis,
                                  )))
                        ]),
                        Row(children: [
                          Icon(
                            CupertinoIcons.map_pin_ellipse,
                            size: 14,
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.5),
                          ),
                          Expanded(
                              child: Text(' 座位：${exams[0].seat ?? '未知'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .color!
                                        .withValues(alpha: 0.75),
                                    overflow: TextOverflow.ellipsis,
                                  )))
                        ]),
                        if (exams[0].type == ExamType.midterm)
                          Row(children: [
                            Icon(
                              CupertinoIcons.doc_text,
                              size: 14,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.5),
                            ),
                            Expanded(
                                child: Text(' 类型：期中',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: CupertinoTheme.of(context)
                                          .textTheme
                                          .textStyle
                                          .color!
                                          .withValues(alpha: 0.75),
                                      overflow: TextOverflow.ellipsis,
                                    )))
                          ]),
                      ],
                    ),
                    for (var i = 1; i < exams.length; i++)
                      Column(
                        children: [
                          Divider(
                            height: 16,
                            thickness: 1,
                            indent: 0,
                            endIndent: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 12.0,
                                height: 12.0,
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemPink,
                                  shape: exams[i].type == ExamType.midterm
                                      ? BoxShape.circle
                                      : BoxShape.rectangle,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Expanded(
                                  child: Text(exams[i].chineseTime,
                                      style: CupertinoTheme.of(context)
                                          .textTheme
                                          .textStyle
                                          .copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            overflow: TextOverflow.ellipsis,
                                          ))),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          Row(children: [
                            Icon(
                              CupertinoIcons.location_solid,
                              size: 14,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.5),
                            ),
                            Expanded(
                                child: Text(' 地点：${exams[i].location ?? '未知'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: CupertinoTheme.of(context)
                                          .textTheme
                                          .textStyle
                                          .color!
                                          .withValues(alpha: 0.75),
                                      overflow: TextOverflow.ellipsis,
                                    )))
                          ]),
                          Row(children: [
                            Icon(
                              CupertinoIcons.map_pin_ellipse,
                              size: 14,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.5),
                            ),
                            Expanded(
                                child: Text(' 座位：${exams[i].seat ?? '未知'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: CupertinoTheme.of(context)
                                          .textTheme
                                          .textStyle
                                          .color!
                                          .withValues(alpha: 0.75),
                                      overflow: TextOverflow.ellipsis,
                                    )))
                          ]),
                          if (exams[i].type == ExamType.midterm)
                            Row(children: [
                              Icon(
                                CupertinoIcons.doc_text,
                                size: 14,
                                color: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .color!
                                    .withValues(alpha: 0.5),
                              ),
                              Expanded(
                                  child: Text(' 类型：期中',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                        color: CupertinoTheme.of(context)
                                            .textTheme
                                            .textStyle
                                            .color!
                                            .withValues(alpha: 0.75),
                                        overflow: TextOverflow.ellipsis,
                                      )))
                            ]),
                        ],
                      ),
                  ],
                )),
              ],
            ),
          ]),
        ))
      ],
    );
  }

  bool _shouldShowZhiyun(Course c) {
    if (!showZhiyun) return false;
    final now = DateTime.now();

    // 1. 若当前页面传入了具体的课程节次 (period)，则判断该节次是否已经到了上课时间
    if (period != null) {
      if (now.isBefore(period!.startTime)) {
        return false;
      }
      return true;
    }

    // 2. 若未传入具体节次（如从课程表网格/课程列表进入）：
    // 检查该课程是否有任何已经到达上课时间（或已经上过）的节次；
    // 如果该课程的所有节次都在未来（还没到上课时间），则隐藏智云课堂卡片。
    try {
      if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
        final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
        final coursePeriods = scholar.periods.where((p) =>
            p.type == PeriodType.classes &&
            (p.fromUid == c.id ||
                p.summary == c.name ||
                c.sessions.any((s) => s.id != null && s.id == p.fromUid)));

        if (coursePeriods.isNotEmpty) {
          final hasStartedAny =
              coursePeriods.any((p) => !now.isBefore(p.startTime));
          if (!hasStartedAny) {
            return false;
          }
        }
      }
    } catch (e) {
      debugPrint('CourseDetailPage._shouldShowZhiyun error: $e');
    }

    return true;
  }

  Widget createZhiyunCard(BuildContext context, Course c) {
    return ZhiyunCard(course: c, period: period);
  }

  @override
  Widget build(BuildContext context) {
    final c = course;
    if (c == null) {
      return CupertinoPageScaffold(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '课程详情'),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '未找到该课程的信息',
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          const CelechronSliverTextHeader(subtitle: '课程详情'),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(bottom: 5, left: 16, right: 16),
              child: Column(
                children: [
                  SubSubtitleRow(subtitle: '基本信息'),
                  CourseBriefCard(course: c),
                ],
              ),
            ),
          ),
          if (_shouldShowZhiyun(c))
            SliverToBoxAdapter(
              child: createZhiyunCard(context, c),
            ),
          SliverToBoxAdapter(
            child: CoursewareDownloadCard(course: c),
          ),
          SliverToBoxAdapter(
            child: CourseHomeworkCard(course: c),
          ),
          if (c.sessions.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: createSessionCard(context, c.sessions),
              ),
            ),
          if (c.exams.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: createExamCard(context, c.exams),
              ),
            ),
          const SliverToBoxAdapter(
            child: NativeBottomBarSpacer(),
          ),
        ],
      ),
    );
  }
}

class ZhiyunCard extends StatefulWidget {
  final Course course;
  final Period? period;

  const ZhiyunCard({super.key, required this.course, this.period});

  @override
  State<ZhiyunCard> createState() => _ZhiyunCardState();
}

class _ZhiyunCardState extends State<ZhiyunCard> {
  late Future<ZhiyunReplayInfo?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ZhiyunCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.name != widget.course.name ||
        oldWidget.period?.startTime != widget.period?.startTime) {
      _load();
    }
  }

  void _load() {
    _future = ZhiyunService.getLessonReplay(
      course: widget.course,
      period: widget.period,
    );
  }

  void _openAndRecord(String url, String title,
      {String? courseId, String? subId}) {
    ZhiyunService.saveLastWatchedReplay(
      courseName: widget.course.name,
      lessonTitle: title,
      livingroomUrl: url,
      courseId: courseId,
      subId: subId,
    );
    ZhiyunService.openUrl(url);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openInAppPlayer(
    BuildContext context, {
    required String url,
    required String title,
    String? courseId,
    String? subId,
    bool preferLive = false,
  }) async {
    await ZhiyunService.saveLastWatchedReplay(
      courseName: widget.course.name,
      lessonTitle: title,
      livingroomUrl: url,
      courseId: courseId,
      subId: subId,
    );
    if (mounted) {
      setState(() {});
    }

    if (courseId != null && courseId.isNotEmpty) {
      final rawCat = await ZhiyunService.fetchCourseCatalogue(
        courseId,
        forceRefresh: preferLive,
      );
      final replayList = <ZhiyunReplayInfo>[];
      for (final item in rawCat) {
        final sid =
            item['sub_id']?.toString() ?? item['id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final t = item['title']?.toString() ??
            item['sub_title']?.toString() ??
            '课节 $sid';
        final isLive = ZhiyunService.checkIsLive(item: item);
        final hasReplay = !isLive && ZhiyunService.checkHasReplay(item: item);
        replayList.add(ZhiyunReplayInfo(
          courseId: courseId,
          subId: sid,
          courseName: widget.course.name,
          lessonTitle: t,
          hasReplay: hasReplay,
          isLive: isLive,
          isLessonSpecific: true,
          livingroomUrl:
              ZhiyunService.buildCourseLivingroomUrl(courseId, subId: sid),
        ));
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => ZhiyunPlayerPage(
            courseName: widget.course.name,
            courseId: courseId,
            initialSubId: subId,
            initialTitle: title,
            livingroomUrl: url,
            replays: replayList,
            preferLive: preferLive,
          ),
        ),
      );
      return;
    }

    await OhosNativeService.instance.openInAppVideoPlayer(
      url: url,
      title: '${widget.course.name} · $title',
      livingroomUrl: url,
      token: ZhiyunService.getCachedZhiyunToken(),
    );
  }

  Future<void> _handleSyncMyCourses(BuildContext context) async {
    final count = await ZhiyunService.syncFromMyCourses();
    if (context.mounted) {
      if (count > 0) {
        showCupertinoDialog(
          context: context,
          builder: (dialogCtx) => CupertinoAlertDialog(
            title: const Text('同步完成'),
            content: Text('已从智云课堂「我的课程」成功同步并智能匹配了 $count 门专属课程。'),
            actions: [
              CupertinoDialogAction(
                child: const Text('好'),
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        );
        setState(() {
          _load();
        });
      } else {
        showCupertinoDialog(
          context: context,
          builder: (dialogCtx) => CupertinoAlertDialog(
            title: const Text('同步提示'),
            content:
                const Text('未获取到课程更新，请确保已登录浙大统一身份认证或稍后重试。您亦可直接输入课程ID完成绑定。'),
            actions: [
              CupertinoDialogAction(
                child: const Text('好'),
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showBindDialog(BuildContext context, String currentId) {
    final textController = TextEditingController(text: currentId);
    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('绑定智云课堂ID'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '在浏览器打开智云课堂对应课程后，复制网页链接或直接输入课程ID（例如 85940）：',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: textController,
                placeholder: '85940 或 粘贴课程网页链接',
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
              const SizedBox(height: 12),
              Center(
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 32,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_2_circlepath, size: 14),
                      SizedBox(width: 4),
                      Text('从「我的课程」自动同步匹配', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  onPressed: () async {
                    Navigator.of(dialogCtx).pop();
                    await _handleSyncMyCourses(context);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (currentId.isNotEmpty)
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('解绑'),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await ZhiyunService.deleteCourseId(
                  widget.course.name,
                  courseCode: widget.course.id,
                  courseId: currentId,
                );
                setState(() {
                  _load();
                });
              },
            ),
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('确认'),
            onPressed: () async {
              final raw = textController.text.trim();
              final cid = ZhiyunService.extractCourseId(raw);
              if (cid == null || cid.isEmpty) {
                return;
              }
              Navigator.of(dialogCtx).pop();
              await ZhiyunService.saveCourseId(
                widget.course.name,
                cid,
                courseCode: widget.course.id,
              );
              setState(() {
                _load();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    Color iconForeground = CupertinoColors.white,
    required String title,
    required String tag,
    VoidCallback? onTagTap,
    required String subtitle,
    required List<Widget> buttons,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '智云课堂'),
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              CupertinoDynamicColor.resolve(iconColor, context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: CupertinoDynamicColor.resolve(
                              iconForeground, context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: CupertinoDynamicColor.resolve(
                                        CupertinoColors.label, context),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: onTagTap,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.tertiarySystemFill,
                                          context),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.secondaryLabel,
                                            context),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final lastWatched =
                                    ZhiyunService.getLastWatchedReplay(
                                  courseName: widget.course.name,
                                  courseId: widget.course.id,
                                );
                                if (lastWatched != null &&
                                    lastWatched['lessonTitle'] != null) {
                                  final title =
                                      lastWatched['lessonTitle'].toString();
                                  final url =
                                      lastWatched['livingroomUrl']?.toString();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: GestureDetector(
                                      onTap: url != null && url.isNotEmpty
                                          ? () => _openInAppPlayer(
                                                context,
                                                url: url,
                                                title: title,
                                                courseId: lastWatched['courseId']
                                                        ?.toString() ??
                                                    widget.course.id,
                                                subId: lastWatched['subId']
                                                    ?.toString(),
                                              )
                                          : null,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: CupertinoDynamicColor.resolve(
                                              CupertinoColors
                                                  .tertiarySystemFill,
                                              context),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CupertinoIcons.clock_fill,
                                              size: 11,
                                              color:
                                                  CupertinoDynamicColor.resolve(
                                                      CustomCupertinoDynamicColors
                                                          .sakuraInk,
                                                      context),
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '上次播放: $title',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: CupertinoDynamicColor
                                                      .resolve(
                                                          CupertinoColors
                                                              .secondaryLabel,
                                                          context),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(
                                              CupertinoIcons.chevron_right,
                                              size: 10,
                                              color: CupertinoColors
                                                  .secondaryLabel,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: buttons,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCoursesButton(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemFill, context),
      borderRadius: BorderRadius.circular(8),
      minSize: 36,
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.person_crop_square, size: 16),
            SizedBox(width: 4),
            Text('我的课程', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      onPressed: () => ZhiyunService.openUrl(ZhiyunService.buildMyCoursesUrl()),
    );
  }

  static const _sakuraForeground = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF7A1C59),
    darkColor: Color(0xFF28061E),
  );

  Widget _buildLoadingCard(BuildContext context) {
    return _buildCard(
      context: context,
      icon: CupertinoIcons.play_rectangle,
      iconColor: CustomCupertinoDynamicColors.sakura,
      iconForeground: _sakuraForeground,
      title: '智云课堂',
      tag: '正在匹配',
      subtitle: '正在从智云课堂动态匹配课程房间与节次回放...',
      buttons: [
        const Expanded(
          child: SizedBox(
            height: 36,
            child: Center(
              child: CupertinoActivityIndicator(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    return FutureBuilder<ZhiyunReplayInfo?>(
      future: _future,
      builder: (context, snapshot) {
        if (!ZhiyunService.isRecordableCourse(c.name, courseCode: c.id)) {
          return const SizedBox.shrink();
        }

        if (widget.period != null &&
            DateTime.now().isBefore(widget.period!.startTime)) {
          return const SizedBox.shrink();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard(context);
        }

        final info = snapshot.data;
        if (info == null) {
          return const SizedBox.shrink();
        }

        // 状态零：当前课程或课节正在进行实时直播 (isLive)
        if (info.isLive) {
          return _buildCard(
            context: context,
            icon: CupertinoIcons.dot_radiowaves_left_right,
            iconColor: CupertinoColors.systemRed,
            title: '智云实时直播',
            tag: '● 正在直播',
            onTagTap: () => ZhiyunService.openUrl(info.livingroomUrl),
            subtitle: '该课程当前正在智云课堂进行实时直播，点击可直达直播间观看',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  color: CupertinoColors.systemRed,
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.play_arrow_solid,
                            size: 16, color: CupertinoColors.white),
                        SizedBox(width: 6),
                        Text(
                          '观看直播',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => _openInAppPlayer(
                    context,
                    url: info.livingroomUrl,
                    title: '实时直播',
                    courseId: info.courseId,
                    subId: info.subId,
                    preferLive: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const Icon(CupertinoIcons.compass, size: 16),
                onPressed: () => _openAndRecord(info.livingroomUrl, '实时直播',
                    courseId: info.courseId, subId: info.subId),
              ),
              if (info.courseId != null) ...[
                const SizedBox(width: 8),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: const Icon(CupertinoIcons.pencil, size: 16),
                  onPressed: () => _showBindDialog(context, info.courseId!),
                ),
              ],
            ],
          );
        }

        // 状态一：本节课录播已就绪 (hasReplay && isLessonSpecific)
        if (info.isLessonSpecific && info.hasReplay) {
          final sakuraFg =
              CupertinoDynamicColor.resolve(_sakuraForeground, context);
          return _buildCard(
            context: context,
            icon: CupertinoIcons.play_rectangle_fill,
            iconColor: CustomCupertinoDynamicColors.sakura,
            iconForeground: _sakuraForeground,
            title: '本节录播回放',
            tag: info.lessonTitle,
            onTagTap: info.courseId != null
                ? () => _showBindDialog(context, info.courseId!)
                : null,
            subtitle: '本节录播已就绪，点击可直接进入回放房间观看',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.play_arrow_solid,
                            size: 16, color: sakuraFg),
                        const SizedBox(width: 6),
                        Text(
                          '观看回放',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sakuraFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => _openInAppPlayer(
                    context,
                    url: info.livingroomUrl,
                    title: info.lessonTitle,
                    courseId: info.courseId,
                    subId: info.subId,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const Icon(CupertinoIcons.compass, size: 16),
                onPressed: () => _openAndRecord(
                    info.livingroomUrl, info.lessonTitle,
                    courseId: info.courseId, subId: info.subId),
              ),
              if (info.courseId != null) ...[
                const SizedBox(width: 8),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: const Icon(CupertinoIcons.pencil, size: 16),
                  onPressed: () => _showBindDialog(context, info.courseId!),
                ),
              ],
            ],
          );
        }

        // 状态二：本节课未生成录播（未上课、转码中或无需录播）
        if (info.isLessonSpecific && !info.hasReplay) {
          return _buildCard(
            context: context,
            icon: CupertinoIcons.play_rectangle,
            iconColor: CupertinoColors.secondaryLabel,
            title: '本节录播回放',
            tag: '未生成回放',
            onTagTap: info.courseId != null
                ? () => _showBindDialog(context, info.courseId!)
                : null,
            subtitle: '该节课录播尚未转码生成，或未到录播时间',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.tv,
                            size: 16,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context)),
                        const SizedBox(width: 6),
                        Text(
                          '进入课程房间',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => _openAndRecord(info.livingroomUrl, '课程房间',
                      courseId: info.courseId),
                ),
              ),
              const SizedBox(width: 8),
              _buildMyCoursesButton(context),
              if (info.courseId != null) ...[
                const SizedBox(width: 8),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: const Icon(CupertinoIcons.pencil, size: 16),
                  onPressed: () => _showBindDialog(context, info.courseId!),
                ),
              ],
            ],
          );
        }

        // 状态三：整门课程智云房间直达（已绑定 ID）
        if (info.courseId != null) {
          final hasReplay = info.hasReplay;
          final sakuraFg =
              CupertinoDynamicColor.resolve(_sakuraForeground, context);
          return _buildCard(
            context: context,
            icon: hasReplay
                ? CupertinoIcons.play_rectangle_fill
                : CupertinoIcons.play_rectangle,
            iconColor: hasReplay
                ? CustomCupertinoDynamicColors.sakura
                : CupertinoColors.secondaryLabel,
            iconForeground:
                hasReplay ? _sakuraForeground : CupertinoColors.white,
            title: '智云课堂房间',
            tag: hasReplay ? 'ID: ${info.courseId}' : '未生成回放',
            onTagTap: () => _showBindDialog(context, info.courseId!),
            subtitle: hasReplay
                ? '点击进入该课程专属房间，查看所有课节与回放'
                : '该课程未在智云课堂生成录播回放或无需录播，点击仍可进入房间',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  color: CupertinoDynamicColor.resolve(
                      hasReplay
                          ? CustomCupertinoDynamicColors.sakura
                          : CupertinoColors.secondarySystemFill,
                      context),
                  borderRadius: BorderRadius.circular(8),
                  minSize: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_up_right_square,
                          size: 16,
                          color: hasReplay
                              ? sakuraFg
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '进入课堂',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: hasReplay
                                ? sakuraFg
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => _openInAppPlayer(
                    context,
                    url: info.livingroomUrl,
                    title: '课程房间',
                    courseId: info.courseId,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const Icon(CupertinoIcons.compass, size: 16),
                onPressed: () => _openAndRecord(info.livingroomUrl, '课程房间',
                    courseId: info.courseId),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const Icon(CupertinoIcons.pencil, size: 16),
                onPressed: () => _showBindDialog(context, info.courseId!),
              ),
            ],
          );
        }

        // 状态四：未绑定课程 ID（提供检索、我的课程与一键绑定）
        // 采用比例分配按钮宽度，避免在窄屏或大字号下溢出粉色框
        final searchSakuraFg =
            CupertinoDynamicColor.resolve(_sakuraForeground, context);
        return _buildCard(
          context: context,
          icon: CupertinoIcons.compass,
          iconColor: CustomCupertinoDynamicColors.sakura,
          iconForeground: _sakuraForeground,
          title: '智云课堂',
          tag: '未绑定',
          onTagTap: () => _showBindDialog(context, ''),
          subtitle: '点击前往智云课堂检索或进入我的课程，亦可一键绑定课程ID',
          buttons: [
            Expanded(
              flex: 5,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CustomCupertinoDynamicColors.sakura, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.search,
                          size: 15, color: searchSakuraFg),
                      const SizedBox(width: 4),
                      Text(
                        '智云搜索',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: searchSakuraFg,
                        ),
                      ),
                    ],
                  ),
                ),
                onPressed: () => ZhiyunService.openUrl(
                    ZhiyunService.buildSearchContentUrl(c.name)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 5,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.person_crop_square, size: 15),
                      SizedBox(width: 4),
                      Text(
                        '我的课程',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                onPressed: () =>
                    ZhiyunService.openUrl(ZhiyunService.buildMyCoursesUrl()),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 4,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.link, size: 15),
                      SizedBox(width: 3),
                      Text('绑定ID', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                onPressed: () => _showBindDialog(context, ''),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CoursewareDownloadCard extends StatefulWidget {
  final Course course;

  const CoursewareDownloadCard({super.key, required this.course});

  @override
  State<CoursewareDownloadCard> createState() => _CoursewareDownloadCardState();
}

class _CoursewareDownloadCardState extends State<CoursewareDownloadCard> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  final List<CoursewareItem> _items = [];
  final Map<String, String> _downloadedPaths = {};
  final Set<String> _downloadingKeys = {};

  Future<String> _resolveSaveDir() async {
    if (Get.isRegistered<Option>(tag: 'option')) {
      final custom = Get.find<Option>(tag: 'option').downloadPath.value.trim();
      if (custom.isNotEmpty) {
        return custom;
      }
    }
    final doc = await getApplicationDocumentsDirectory();
    return '${doc.path}/courseware';
  }

  Future<void> _fetchCourseware() async {
    setState(() {
      _expanded = true;
      _loading = true;
      _error = null;
    });

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final list = <CoursewareItem>[];
      final tronItems = await Courses.fetchCoursewareList(
        client,
        courseName: widget.course.name,
        courseCode: widget.course.id,
      );
      list.addAll(tronItems);

      final zhiyunCid = ZhiyunService.getKnownCourseId(
        widget.course.name,
        courseCode: widget.course.id,
      );
      if (zhiyunCid != null && zhiyunCid.isNotEmpty) {
        final zyFiles = await ZhiyunService.fetchZhiyunCourseware(zhiyunCid);
        for (final f in zyFiles) {
          list.add(CoursewareItem(
            name: f['name'] ?? '智云课件',
            sectionTitle: f['sectionTitle'] ?? '智云课堂',
            sizeBytes: 0,
            directUrl: f['url'],
            source: '智云课堂',
          ));
        }
      }

      // 检查本地是否已下载
      final saveDir = await _resolveSaveDir();
      final downloaded = <String, String>{};
      for (final item in list) {
        final safeName = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File('$saveDir/$safeName');
        if (await file.exists() && await file.length() > 0) {
          downloaded[_itemKey(item)] = file.path;
        }
      }

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _downloadedPaths
          ..clear()
          ..addAll(downloaded);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    } finally {
      client.close(force: true);
    }
  }

  String _itemKey(CoursewareItem item) =>
      '${item.source}_${item.uploadId}_${item.referenceId}_${item.name}';

  Future<void> _downloadItem(BuildContext context, CoursewareItem item) async {
    final key = _itemKey(item);
    if (_downloadingKeys.contains(key)) return;
    setState(() {
      _downloadingKeys.add(key);
    });

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final saveDir = await _resolveSaveDir();
      final savedPath = await Courses.downloadCoursewareFile(
        client,
        item: item,
        saveDir: saveDir,
      );
      if (!mounted) return;
      setState(() {
        _downloadingKeys.remove(key);
        if (savedPath != null) {
          _downloadedPaths[key] = savedPath;
        }
      });

      if (savedPath != null && context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogCtx) => CupertinoAlertDialog(
            title: const Text('课件下载完成'),
            content: Text('文件已保存至：\n$savedPath'),
            actions: [
              CupertinoDialogAction(
                child: const Text('稍后查看'),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('打开'),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  OhosNativeService.instance.openFileWithSystem(
                    savedPath,
                    title: '打开文件',
                  );
                },
              ),
            ],
          ),
        );
      } else if (context.mounted) {
        Get.snackbar('下载失败', '未能获取该课件的下载文件流，请确认已登录学在浙大',
            snackPosition: SnackPosition.TOP);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingKeys.remove(key);
      });
      Get.snackbar('下载异常', '$e', snackPosition: SnackPosition.TOP);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '课程课件与附件'),
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: CupertinoColors.activeBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          CupertinoIcons.folder_fill_badge_person_crop,
                          size: 18,
                          color: CupertinoColors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_items.isEmpty) {
                              if (!_loading) _fetchCourseware();
                            } else {
                              setState(() {
                                _expanded = !_expanded;
                              });
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '学在浙大 / 智云课堂课件下载',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _items.isNotEmpty
                                    ? '已获取 ${_items.length} 个附件 · 点击${_expanded ? "收起" : "展开"}'
                                    : '支持一键下载课程讲义、作业附件并唤起系统打开',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondaryLabel, context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_items.isEmpty)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minSize: 32,
                          color: CupertinoColors.activeBlue,
                          borderRadius: BorderRadius.circular(8),
                          onPressed: _loading ? null : _fetchCourseware,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_loading)
                                const CupertinoActivityIndicator(
                                    radius: 7, color: CupertinoColors.white)
                              else ...[
                                const Icon(
                                    CupertinoIcons.arrow_down_circle_fill,
                                    size: 15,
                                    color: CupertinoColors.white),
                                const SizedBox(width: 4),
                                const Text(
                                  '展开课件',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              minSize: 32,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondarySystemFill, context),
                              borderRadius: BorderRadius.circular(8),
                              onPressed: _loading ? null : _fetchCourseware,
                              child: _loading
                                  ? const CupertinoActivityIndicator(radius: 7)
                                  : const Icon(CupertinoIcons.arrow_clockwise,
                                      size: 14),
                            ),
                            const SizedBox(width: 6),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              minSize: 32,
                              color: _expanded
                                  ? CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondarySystemFill,
                                      context)
                                  : CupertinoColors.activeBlue,
                              borderRadius: BorderRadius.circular(8),
                              onPressed: () {
                                setState(() {
                                  _expanded = !_expanded;
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _expanded
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.chevron_down,
                                    size: 13,
                                    color: _expanded
                                        ? CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context)
                                        : CupertinoColors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _expanded ? '收起' : '展开',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _expanded
                                          ? CupertinoDynamicColor.resolve(
                                              CupertinoColors.label, context)
                                          : CupertinoColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              CupertinoActivityIndicator(),
                              SizedBox(height: 6),
                              Text('正在同步学在浙大与智云课堂课件...',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '获取课件失败：$_error',
                          style: const TextStyle(
                              fontSize: 12, color: CupertinoColors.systemRed),
                        ),
                      )
                    else if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '暂未在学在浙大或智云课堂检索到该课程的公开课件附件。',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel, context),
                          ),
                        ),
                      )
                    else
                      ..._items.map((item) {
                        final key = _itemKey(item);
                        final downloading = _downloadingKeys.contains(key);
                        final savedPath = _downloadedPaths[key];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.doc_on_doc_fill,
                                size: 18,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.activeBlue, context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${item.sectionTitle} · ${item.formattedSize}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.secondaryLabel,
                                            context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (savedPath != null) ...[
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  minSize: 28,
                                  color: CupertinoColors.activeGreen
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  onPressed: () {
                                    OhosNativeService.instance
                                        .openFileWithSystem(
                                      savedPath,
                                      title: '选择打开方式',
                                    );
                                  },
                                  child: const Text(
                                    '打开',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: CupertinoColors.activeGreen,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                minSize: 28,
                                color: CupertinoColors.activeBlue
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                                onPressed: downloading
                                    ? null
                                    : () => _downloadItem(context, item),
                                child: downloading
                                    ? const CupertinoActivityIndicator(
                                        radius: 7)
                                    : Text(
                                        savedPath != null ? '重新下载' : '下载',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: CupertinoColors.activeBlue,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CourseHomeworkCard extends StatefulWidget {
  final Course course;

  const CourseHomeworkCard({super.key, required this.course});

  @override
  State<CourseHomeworkCard> createState() => _CourseHomeworkCardState();
}

class _CourseHomeworkCardState extends State<CourseHomeworkCard> {
  bool _expanded = true;
  bool _loading = false;
  bool _fetchedOnce = false;
  String? _error;
  List<Todo> _items = [];
  Map<String, Task> _taskByActivityId = {};

  String? get _effectiveCourseCode {
    if (widget.course.id != null && widget.course.id!.trim().isNotEmpty) {
      return widget.course.id!.trim();
    }
    if (widget.course.grade?.id != null &&
        widget.course.grade!.id.trim().isNotEmpty) {
      return widget.course.grade!.id.trim();
    }
    for (final s in widget.course.sessions) {
      if (s.id != null && s.id!.trim().isNotEmpty) {
        return s.id!.trim();
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final local = _collectLocalHomeworks();
    _items = Courses.mergeAndSortCourseHomeworks(local);
    _fetchHomeworks();
  }

  bool _matchesThisCourse(String candidateCourseName, {String? candidateCid}) {
    final code = _effectiveCourseCode;
    if (code != null &&
        candidateCid != null &&
        candidateCid.isNotEmpty &&
        code == candidateCid) {
      return true;
    }
    if (candidateCourseName.trim().isEmpty ||
        widget.course.name.trim().isEmpty) {
      return false;
    }
    return ZhiyunService.matchesCourseName(
        widget.course.name, candidateCourseName);
  }

  List<Todo> _collectLocalHomeworks() {
    final localItems = <Todo>[];
    final taskMap = <String, Task>{};

    if (Get.isRegistered<RxList<Task>>(tag: 'taskList')) {
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      for (final t in taskList) {
        if (t.type != TaskType.homework || t.status == TaskStatus.deleted) {
          continue;
        }
        var taskCourse = '';
        for (final line in t.description.split('\n')) {
          if (line.startsWith('课程：')) {
            taskCourse = line.substring(3).trim();
            break;
          }
        }
        String? cidFromUrl;
        final urlMatch =
            RegExp(r'/course[s]?/(\d+)/').firstMatch(t.description);
        if (urlMatch != null) {
          cidFromUrl = urlMatch.group(1);
        }
        if (!_matchesThisCourse(taskCourse, candidateCid: cidFromUrl)) {
          continue;
        }

        final aid = (t.fromUid != null && t.fromUid!.startsWith('courses-todo:'))
            ? t.fromUid!.substring('courses-todo:'.length)
            : 'task:${t.uid}';
        taskMap[aid] = t;

        final cleanTitle =
            t.summary.replaceFirst(RegExp(r'^(作业|小测)：'), '').trim();
        localItems.add(Todo.fromJson({
          'id': aid,
          'title': cleanTitle.isNotEmpty ? cleanTitle : t.summary,
          'course_name':
              taskCourse.isNotEmpty ? taskCourse : widget.course.name,
          'course_id': cidFromUrl ?? '',
          'end_time': t.endTime.toIso8601String(),
          'type': t.isQuiz ? 'quiz' : 'homework',
          'completeness':
              t.status == TaskStatus.completed ? 'full' : 'incomplete',
        }));
      }
    }

    if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
      final scholarTodos = Get.find<Rx<Scholar>>(tag: 'scholar').value.todos;
      for (final todo in scholarTodos) {
        if (!_matchesThisCourse(todo.course,
            candidateCid: todo.resolvedCourseId)) {
          continue;
        }
        localItems.add(Todo.fromJson(todo.toJson()));
      }
    }

    _taskByActivityId = taskMap;
    return localItems;
  }

  void _syncLocalStatusesAndRebuild() {
    final local = _collectLocalHomeworks();
    if (!mounted) return;
    setState(() {
      _items = Courses.mergeAndSortCourseHomeworks([..._items, ...local]);
    });
  }

  Future<void> _fetchHomeworks() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    applyZjuNetworkDefense(client,
        connectionTimeout: const Duration(seconds: 10));
    try {
      final remote = await Courses.fetchCourseHomeworks(
        client,
        courseName: widget.course.name,
        courseCode: _effectiveCourseCode,
      );
      final local = _collectLocalHomeworks();
      final merged = Courses.mergeAndSortCourseHomeworks([...remote, ...local]);
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
        _fetchedOnce = true;
      });
    } catch (e) {
      final local = _collectLocalHomeworks();
      final merged = Courses.mergeAndSortCourseHomeworks([..._items, ...local]);
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
        _fetchedOnce = true;
        if (_items.isEmpty) {
          _error = '$e';
        }
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openSubmissionPage(BuildContext context, Todo todo) async {
    final matchingTask = _taskByActivityId[todo.id];
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (context) => HomeworkSubmissionPage(
          todo: todo.id.startsWith('task:') ? null : todo,
          task: matchingTask,
        ),
      ),
    );
    _syncLocalStatusesAndRebuild();
  }

  String _summarySubtitle() {
    if (_loading && _items.isEmpty) {
      return '正在从学在浙大同步全部作业与小测...';
    }
    if (_items.isEmpty) {
      return _fetchedOnce ? '暂未检索到该课程的作业记录' : '点击同步该课程全部作业与提交状态';
    }
    final pendingCount = _items
        .where((e) => !e.isSubmitted && !e.isGraded)
        .length;
    if (pendingCount > 0) {
      return '共 ${_items.length} 项作业 · 待完成 $pendingCount 项';
    }
    return '共 ${_items.length} 项作业 · 已全部完成';
  }

  @override
  Widget build(BuildContext context) {
    final badgeAccent = CupertinoDynamicColor.resolve(
        CustomCupertinoDynamicColors.magenta, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '作业'),
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: badgeAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          CupertinoIcons.checkmark_alt_circle_fill,
                          size: 18,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label, context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _expanded = !_expanded;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '课程作业',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _summarySubtitle(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondaryLabel, context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            minSize: 32,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondarySystemFill, context),
                            borderRadius: BorderRadius.circular(8),
                            onPressed: _loading ? null : _fetchHomeworks,
                            child: _loading
                                ? const CupertinoActivityIndicator(radius: 7)
                                : const Icon(CupertinoIcons.arrow_clockwise,
                                    size: 14),
                          ),
                          if (_items.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              minSize: 32,
                              color: _expanded
                                  ? CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondarySystemFill,
                                      context)
                                  : CupertinoColors.activeBlue,
                              borderRadius: BorderRadius.circular(8),
                              onPressed: () {
                                setState(() {
                                  _expanded = !_expanded;
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _expanded
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.chevron_down,
                                    size: 13,
                                    color: _expanded
                                        ? CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context)
                                        : CupertinoColors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _expanded ? '收起' : '展开',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _expanded
                                          ? CupertinoDynamicColor.resolve(
                                              CupertinoColors.label, context)
                                          : CupertinoColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    if (_loading && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              CupertinoActivityIndicator(),
                              SizedBox(height: 6),
                              Text(
                                '正在同步该课程的全部作业与成绩状态...',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_error != null && _items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          '获取作业失败：$_error\n请先确保已登录学在浙大后点击刷新。',
                          style: const TextStyle(
                              fontSize: 12, color: CupertinoColors.systemRed),
                        ),
                      )
                    else if (_items.isEmpty && _fetchedOnce)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          '学在浙大暂无该课程的已发布作业或测验。',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel, context),
                          ),
                        ),
                      )
                    else if (_items.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemFill, context),
                      ),
                      for (int i = 0; i < _items.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 16,
                            thickness: 1,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                          ),
                        Builder(builder: (context) {
                          final todo = _items[i];
                          final matchingTask = _taskByActivityId[todo.id];
                          final uidKey = matchingTask?.uid ??
                              'courses-todo:${todo.id}';
                          final indicatorColor = UidColors.colorFromUid(uidKey);
                          final cleanTitle = todo.name
                              .replaceFirst(RegExp(r'^(作业|小测)：'), '')
                              .trim();
                          final displayTitle = todo.isQuiz
                              ? '小测：${cleanTitle.isEmpty ? todo.name : cleanTitle}'
                              : '作业：${cleanTitle.isEmpty ? todo.name : cleanTitle}';
                          final displayCourse = todo.course.trim().isNotEmpty
                              ? todo.course.trim()
                              : widget.course.name;
                          final canSubmitInApp = !todo.id.startsWith('task:') ||
                              (matchingTask != null &&
                                  extractCoursesUrl(matchingTask.description) !=
                                      null);

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: canSubmitInApp
                                ? () => _openSubmissionPage(context, todo)
                                : null,
                            onLongPress: !todo.id.startsWith('task:')
                                ? () => showTodoSubmitSheet(
                                      context,
                                      todo.submitUrl,
                                      title: '$displayCourse · $cleanTitle',
                                      courseId: todo.resolvedCourseId,
                                      activityId: todo.id,
                                    )
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              child: HomeworkTaskItemContent(
                                indicatorColor: indicatorColor,
                                title: displayTitle,
                                courseName: displayCourse,
                                endTime: todo.endTime,
                                isQuiz: todo.isQuiz,
                                isSubmitted: todo.isSubmitted,
                                isGraded: todo.isGraded,
                                score: todo.score,
                                titleFontSize: 16,
                                onOpenSubmission: canSubmitInApp
                                    ? () => _openSubmissionPage(context, todo)
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
