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
    return FutureBuilder<ZhiyunReplayInfo?>(
      future: ZhiyunService.getLessonReplay(course: c, period: period),
      builder: (context, snapshot) {
        final info = snapshot.data;
        // 如果未上课、未生成录播回放、或为体育/身体素质等非录播课程，自动隐藏该入口
        if (info == null || !info.hasReplay) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Column(
            children: [
              SubSubtitleRow(subtitle: '智云课堂'),
              RoundRectangleCard(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  CustomCupertinoDynamicColors.sakura, context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              CupertinoIcons.play_rectangle_fill,
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
                                      '本节录播回放',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.tertiarySystemFill,
                                            context),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        info.lessonTitle,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: CupertinoDynamicColor.resolve(
                                              CupertinoColors.secondaryLabel,
                                              context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '本节录播已就绪，点击可直接进入回放房间观看',
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
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: CupertinoDynamicColor.resolve(
                                  CustomCupertinoDynamicColors.sakura, context),
                              borderRadius: BorderRadius.circular(8),
                              minSize: 36,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.play_arrow_solid, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    '直达本节录播',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              onPressed: () =>
                                  ZhiyunService.openUrl(info.livingroomUrl),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondarySystemFill, context),
                            borderRadius: BorderRadius.circular(8),
                            minSize: 36,
                            child: const Row(
                              children: [
                                Icon(CupertinoIcons.link, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '复制链接',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: info.livingroomUrl));
                              if (context.mounted) {
                                showCupertinoDialog(
                                  context: context,
                                  builder: (dialogCtx) => CupertinoAlertDialog(
                                    title: const Text('已复制回放链接'),
                                    content: Text(
                                        '课程「${c.name}」(${info.lessonTitle}) 的智云课堂回放直达链接已复制到剪贴板。'),
                                    actions: [
                                      CupertinoDialogAction(
                                        child: const Text('好'),
                                        onPressed: () =>
                                            Navigator.of(dialogCtx).pop(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
