import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';

import 'package:celechron/model/exam.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/zhiyun_service.dart';

class CourseDetailPage extends StatelessWidget {
  final Course? course;
  final Period? period;

  CourseDetailPage({required String? courseId, this.period, super.key})
      : course = _findCourse(courseId);

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
          SliverToBoxAdapter(
            child: createZhiyunCard(context, c),
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
            content: const Text(
                '未获取到课程更新，请确保已登录浙大统一身份认证或稍后重试。您亦可直接输入课程ID完成绑定。'),
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
                          color: CupertinoDynamicColor.resolve(
                              iconColor, context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: CupertinoColors.white,
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

  Widget _buildCopyButton(BuildContext context, String url, String courseName,
      String detailName) {
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
            Icon(CupertinoIcons.link, size: 16),
            SizedBox(width: 4),
            Text('复制链接', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (dialogCtx) => CupertinoAlertDialog(
              title: const Text('已复制链接'),
              content: Text('课程「$courseName」($detailName) 的智云课堂直达链接已复制到剪贴板。'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('好'),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
          );
        }
      },
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

  Widget _buildLoadingCard(BuildContext context) {
    return _buildCard(
      context: context,
      icon: CupertinoIcons.play_rectangle,
      iconColor: CustomCupertinoDynamicColors.sakura,
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
        if (!ZhiyunService.isRecordableCourse(c.name)) {
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
                          '进入实时直播',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => ZhiyunService.openUrl(info.livingroomUrl),
                ),
              ),
              const SizedBox(width: 8),
              _buildCopyButton(
                  context, info.livingroomUrl, c.name, '实时直播'),
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
          return _buildCard(
            context: context,
            icon: CupertinoIcons.play_rectangle_fill,
            iconColor: CustomCupertinoDynamicColors.sakura,
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
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.play_arrow_solid, size: 16),
                        SizedBox(width: 6),
                        Text(
                          '直达本节录播',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => ZhiyunService.openUrl(info.livingroomUrl),
                ),
              ),
              const SizedBox(width: 8),
              _buildCopyButton(
                  context, info.livingroomUrl, c.name, info.lessonTitle),
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
                  onPressed: () => ZhiyunService.openUrl(info.livingroomUrl),
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
          return _buildCard(
            context: context,
            icon: hasReplay
                ? CupertinoIcons.play_rectangle_fill
                : CupertinoIcons.play_rectangle,
            iconColor: hasReplay
                ? CustomCupertinoDynamicColors.sakura
                : CupertinoColors.secondaryLabel,
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
                              ? CupertinoColors.white
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '进入课程房间',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: hasReplay
                                ? CupertinoColors.white
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => ZhiyunService.openUrl(info.livingroomUrl),
                ),
              ),
              const SizedBox(width: 8),
              _buildCopyButton(
                  context, info.livingroomUrl, c.name, '课程主页'),
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
          );
        }

        // 状态四：未绑定课程 ID（提供检索、我的课程与一键绑定）
        // 采用比例分配按钮宽度，避免在窄屏或大字号下溢出粉色框
        return _buildCard(
          context: context,
          icon: CupertinoIcons.compass,
          iconColor: CustomCupertinoDynamicColors.sakura,
          title: '智云课堂',
          tag: '未绑定',
          onTagTap: () => _showBindDialog(context, ''),
          subtitle: '点击前往智云课堂检索或进入我的课程，亦可一键绑定课程ID',
          buttons: [
            Expanded(
              flex: 5,
              child: CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                color: CupertinoDynamicColor.resolve(
                    CustomCupertinoDynamicColors.sakura, context),
                borderRadius: BorderRadius.circular(8),
                minSize: 36,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.search, size: 15),
                      SizedBox(width: 4),
                      Text(
                        '智云搜索',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
