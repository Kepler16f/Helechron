import 'dart:io';

import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
import 'courseware_batch_page.dart';
import 'zhiyun_player_page.dart';
import 'zhiyun_resource_batch_page.dart';

class CourseDetailPage extends StatelessWidget {
  final Course? course;
  final Period? period;
  final bool showZhiyun;
  final String? semesterName;
  final String? preferredHalfTag;

  factory CourseDetailPage({
    required String? courseId,
    Period? period,
    bool showZhiyun = true,
    String? semesterName,
    String? preferredHalfTag,
    Key? key,
  }) {
    final resolved = _findCourseWithSemester(courseId);
    return CourseDetailPage._(
      course: resolved.$1,
      period: period,
      showZhiyun: showZhiyun,
      semesterName: semesterName ?? resolved.$2,
      preferredHalfTag: preferredHalfTag,
      key: key,
    );
  }

  const CourseDetailPage._({
    required this.course,
    this.period,
    required this.showZhiyun,
    this.semesterName,
    this.preferredHalfTag,
    super.key,
  });

  /// 依据不同来源的标识定位课程及其所属学期名称。
  ///
  /// 本科课程由 ZDBK 课表创建时没有课号（[Course.id] 为 null），只有成绩
  /// 补全后才会带上选课课号，因此不能只用 [Course.id] 匹配：
  /// - 课程表 / 日历：传入 [Session.id]（可能为 null）
  /// - 成绩卡片：传入 [Grade.id]（选课课号，对应 [Course.grade])
  /// - 课程列表：传入 [Course.id]
  static (Course?, String?) _findCourseWithSemester(String? courseId) {
    if (courseId == null || courseId.isEmpty) {
      return (null, null);
    }
    try {
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
      for (final semester in scholar.value.semesters) {
        final byKey = semester.courses[courseId];
        if (byKey != null) {
          return (byKey, semester.name);
        }
        for (final candidate in semester.courses.values) {
          if (candidate.id == courseId) {
            return (candidate, semester.name);
          }
          if (candidate.grade?.id == courseId) {
            return (candidate, semester.name);
          }
          for (final session in candidate.sessions) {
            if (session.id != null && session.id == courseId) {
              return (candidate, semester.name);
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
    return (null, null);
  }

  Widget createSessionCard(BuildContext context, List<Session> sessions) {
    sessions.sort((a, b) => a.time.first.compareTo(b.time.first));
    final colors = AelTheme.colorsOf(context);
    return Column(
      children: [
        SubSubtitleRow(subtitle: '课时'),
        AelSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < sessions.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 24,
                    thickness: 1,
                    indent: 0,
                    endIndent: 0,
                    color: colors.divider,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: BoxDecoration(
                            color: TimeColors.colorFromClass(
                              sessions[i].time.first,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            sessions[i].chineseTime,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    Row(
                      children: [
                        Icon(
                          AelIcons.location,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        Expanded(
                          child: Text(
                            ' 地点：${sessions[i].location ?? '未知'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: colors.textSecondary,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget createExamCard(BuildContext context, List<Exam> exams) {
    final colors = AelTheme.colorsOf(context);
    return Column(
      children: [
        SubSubtitleRow(subtitle: '考试'),
        AelSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < exams.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 16,
                    thickness: 1,
                    indent: 0,
                    endIndent: 0,
                    color: colors.divider,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: BoxDecoration(
                            color: exams[i].type == ExamType.midterm
                                ? colors.warning
                                : colors.error,
                            shape: exams[i].type == ExamType.midterm
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            exams[i].chineseTime,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    Row(
                      children: [
                        Icon(
                          AelIcons.location,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        Expanded(
                          child: Text(
                            ' 地点：${exams[i].location ?? '未知'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: colors.textSecondary,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(
                          AelIcons.location,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        Expanded(
                          child: Text(
                            ' 座位：${exams[i].seat ?? '未知'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: colors.textSecondary,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (exams[i].type == ExamType.midterm)
                      Row(
                        children: [
                          Icon(
                            AelIcons.file,
                            size: 14,
                            color: colors.textTertiary,
                          ),
                          Expanded(
                            child: Text(
                              ' 类型：期中',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: colors.textSecondary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
        final coursePeriods = scholar.periods.where(
          (p) =>
              p.type == PeriodType.classes &&
              (p.fromUid == c.id ||
                  p.summary == c.name ||
                  c.sessions.any((s) => s.id != null && s.id == p.fromUid)),
        );

        if (coursePeriods.isNotEmpty) {
          final hasStartedAny = coursePeriods.any(
            (p) => !now.isBefore(p.startTime),
          );
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
    return ZhiyunCard(
      course: c,
      period: period,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final c = course;
    if (c == null) {
      return CupertinoPageScaffold(
        backgroundColor: colors.pageBg,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '课程详情'),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '未找到该课程的信息',
                  style: TextStyle(color: colors.textSecondary, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = AelResponsive.isWideBody(constraints.maxWidth);
          return CustomScrollView(
            slivers: [
              const CelechronSliverTextHeader(subtitle: '课程详情'),
              if (isWide)
                SliverToBoxAdapter(
                  child: AelConstrainedWidth(
                    maxWidth: AelBreakpointSpec.maxWideContentWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SubSubtitleRow(subtitle: '基本信息'),
                                CourseBriefCard(course: c),
                                if (_shouldShowZhiyun(c)) ...[
                                  const SizedBox(height: 8),
                                  createZhiyunCard(context, c),
                                ],
                                if (c.sessions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  createSessionCard(context, c.sessions),
                                ],
                                if (c.exams.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  createExamCard(context, c.exams),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                CoursewareDownloadCard(
                                  course: c,
                                  semesterName: semesterName,
                                  preferredHalfTag: preferredHalfTag,
                                ),
                                CourseHomeworkCard(course: c),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.only(
                      bottom: 5,
                      left: 16,
                      right: 16,
                    ),
                    child: Column(
                      children: [
                        SubSubtitleRow(subtitle: '基本信息'),
                        CourseBriefCard(course: c),
                      ],
                    ),
                  ),
                ),
                if (_shouldShowZhiyun(c))
                  SliverToBoxAdapter(child: createZhiyunCard(context, c)),
                SliverToBoxAdapter(
                  child: CoursewareDownloadCard(
                    course: c,
                    semesterName: semesterName,
                    preferredHalfTag: preferredHalfTag,
                  ),
                ),
                SliverToBoxAdapter(child: CourseHomeworkCard(course: c)),
                if (c.sessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: createSessionCard(context, c.sessions),
                    ),
                  ),
                if (c.exams.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: createExamCard(context, c.exams),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
            ],
          );
        },
      ),
    );
  }
}

class ZhiyunCard extends StatefulWidget {
  final Course course;
  final Period? period;
  final String? semesterName;
  final String? preferredHalfTag;

  const ZhiyunCard({
    super.key,
    required this.course,
    this.period,
    this.semesterName,
    this.preferredHalfTag,
  });

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
        oldWidget.period?.startTime != widget.period?.startTime ||
        oldWidget.semesterName != widget.semesterName ||
        oldWidget.preferredHalfTag != widget.preferredHalfTag) {
      _load();
    }
  }

  String? get _semesterScopeKey => ZhiyunService.inferSemesterHint(
    course: widget.course,
    semesterName: widget.semesterName,
    preferredHalfTag: widget.preferredHalfTag,
    targetDate: widget.period?.startTime,
  ).scopeKey;

  void _load() {
    _future = ZhiyunService.getLessonReplay(
      course: widget.course,
      period: widget.period,
      semesterName: widget.semesterName,
      preferredHalfTag: widget.preferredHalfTag,
    );
  }

  Future<String?> _resolveLiveSubId(
    String courseId,
    String? initialSubId,
  ) async {
    if (initialSubId != null && initialSubId.isNotEmpty) {
      return initialSubId;
    }
    final now = DateTime.now();
    try {
      final active = await ZhiyunService.fetchActiveSubIdForDate(
        courseId,
        now,
        period: widget.period,
      ).timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (active != null && active.isNotEmpty) return active;
    } catch (_) {}

    try {
      final cat = await ZhiyunService.fetchCourseCatalogue(
        courseId,
        forceRefresh: true,
      ).timeout(const Duration(seconds: 5), onTimeout: () => const []);
      final liveItem =
          cat.firstWhereOrNull(
            (item) =>
                ZhiyunService.checkIsLive(item: item) &&
                (item['sub_id']?.toString().isNotEmpty == true ||
                    item['id']?.toString().isNotEmpty == true),
          ) ??
          ZhiyunService.findBestMatchingCatalogueItem(
            catalogue: cat,
            targetDate: now,
            course: widget.course,
            period: widget.period,
          );
      final sid =
          liveItem?['sub_id']?.toString() ?? liveItem?['id']?.toString();
      if (sid != null && sid.isNotEmpty) return sid;
    } catch (_) {}

    return null;
  }

  Future<void> _openAndRecord(
    String url,
    String title, {
    String? courseId,
    String? subId,
    bool isLive = false,
  }) async {
    try {
      await ZhiyunService.saveLastWatchedReplay(
        courseName: widget.course.name,
        lessonTitle: title,
        livingroomUrl: url,
        courseId: courseId,
        subId: subId,
        courseCode: widget.course.id,
        scopeKey: _semesterScopeKey,
      );
      if (mounted) {
        setState(() {});
      }

      String? targetSubId = subId;
      if (isLive &&
          (targetSubId == null || targetSubId.isEmpty) &&
          courseId != null &&
          courseId.isNotEmpty) {
        targetSubId = await _resolveLiveSubId(courseId, subId);
      }

      final token =
          await ZhiyunService.ensureValidToken() ??
          ZhiyunService.getCachedZhiyunToken();
      final ssoCookie = await ZhiyunService.ensureSsoCookieValue();

      var effectiveLivingroom = url;
      if (courseId != null && courseId.isNotEmpty) {
        effectiveLivingroom = ZhiyunService.buildCourseLivingroomUrl(
          courseId,
          subId: targetSubId,
        );
      }
      effectiveLivingroom = ZhiyunService.appendTokenToUrl(
        effectiveLivingroom,
        token,
      );

      final ok = await OhosNativeService.instance.openInAppVideoPlayer(
        url: effectiveLivingroom,
        title: '${widget.course.name} · $title',
        streams: const [],
        livingroomUrl: effectiveLivingroom,
        token: token,
        ssoCookie: ssoCookie,
        isLive: isLive,
        preferWeb: true,
      );
      if (!ok) {
        await ZhiyunService.openUrl(effectiveLivingroom);
      }
    } catch (_) {
      await ZhiyunService.openUrl(url);
    }
  }

  Future<void> _openExternalBrowser(
    String url,
    String title, {
    String? courseId,
    String? subId,
  }) async {
    try {
      await ZhiyunService.saveLastWatchedReplay(
        courseName: widget.course.name,
        lessonTitle: title,
        livingroomUrl: url,
        courseId: courseId,
        subId: subId,
        courseCode: widget.course.id,
        scopeKey: _semesterScopeKey,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
    var target = url;
    if (courseId != null && courseId.isNotEmpty) {
      target = ZhiyunService.buildCourseLivingroomUrl(courseId, subId: subId);
    }
    target = ZhiyunService.appendTokenToUrl(
      target,
      ZhiyunService.getCachedZhiyunToken(),
    );
    await ZhiyunService.openUrl(target);
  }

  Future<void> _openInAppPlayer(
    BuildContext context, {
    required String url,
    required String title,
    String? courseId,
    String? subId,
    bool preferLive = false,
  }) async {
    try {
      await ZhiyunService.saveLastWatchedReplay(
        courseName: widget.course.name,
        lessonTitle: title,
        livingroomUrl: url,
        courseId: courseId,
        subId: subId,
        courseCode: widget.course.id,
        scopeKey: _semesterScopeKey,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}

    // 统一架构：有 courseId 时（无论直播还是回放）均进入 ZhiyunPlayerPage，
    // 对齐回放与 0.1.8 解析直连视频流并拉起原生播放器（直播首次进入自动开播）。
    if (courseId != null && courseId.isNotEmpty) {
      final replayList = <ZhiyunReplayInfo>[];
      if (!preferLive) {
        try {
          final rawCat = await ZhiyunService.fetchCourseCatalogue(
            courseId,
            forceRefresh: false,
          ).timeout(const Duration(seconds: 6), onTimeout: () => const []);
          for (final item in rawCat) {
            final sid =
                item['sub_id']?.toString() ?? item['id']?.toString() ?? '';
            if (sid.isEmpty) continue;
            final t =
                item['title']?.toString() ??
                item['sub_title']?.toString() ??
                '课节 $sid';
            final isLive = ZhiyunService.checkIsLive(item: item);
            final hasReplay =
                !isLive && ZhiyunService.checkHasReplay(item: item);
            final lessonDt = ZhiyunService.parseZhiyunTimestamp(
              item['start_at'] ?? item['class_begin'] ?? item['course_begin'],
            );
            replayList.add(
              ZhiyunReplayInfo(
                courseId: courseId,
                subId: sid,
                courseName: widget.course.name,
                lessonTitle: t,
                lessonDate: lessonDt,
                hasReplay: hasReplay,
                isLive: isLive,
                isLessonSpecific: true,
                livingroomUrl: ZhiyunService.buildCourseLivingroomUrl(
                  courseId,
                  subId: sid,
                ),
              ),
            );
          }
        } catch (_) {}
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
            course: widget.course,
            period: widget.period,
          ),
        ),
      );
      return;
    }

    await _openAndRecord(
      url,
      title,
      courseId: courseId,
      subId: subId,
      isLive: preferLive,
    );
  }

  Future<void> _handleSyncMyCourses(BuildContext context) async {
    final count = await ZhiyunService.syncFromMyCourses();
    if (context.mounted) {
      if (count > 0) {
        showAelAlertDialog(
          context: context,
          title: '同步完成',
          message: '已从智云课堂「我的课程」成功同步并智能匹配了 $count 门专属课程。',
          confirmLabel: '好',
        );
        setState(() {
          _load();
        });
      } else {
        showAelAlertDialog(
          context: context,
          title: '同步提示',
          message: '未获取到课程更新，请确保已登录浙大统一身份认证或稍后重试。您亦可直接输入课程ID完成绑定。',
          confirmLabel: '好',
        );
      }
    }
  }

  void _showBindDialog(BuildContext context, String currentId) {
    final textController = TextEditingController(text: currentId);
    showAelDialog<void>(
      context: context,
      title: '绑定智云课堂 ID',
      message: '在浏览器打开智云课堂对应课程后，复制网页链接或直接输入课程 ID（例如 85940）：',
      content: Builder(
        builder: (dialogCtx) {
          final colors = AelTheme.colorsOf(dialogCtx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoTextField(
                controller: textController,
                placeholder: '85940 或 粘贴课程网页链接',
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.md,
                  vertical: AelSpacing.md,
                ),
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                placeholderStyle: TextStyle(color: colors.textTertiary),
                decoration: BoxDecoration(
                  color: colors.tonalTileBg,
                  borderRadius: BorderRadius.circular(AelRadius.tile),
                ),
              ),
              const SizedBox(height: AelSpacing.md),
              AelButton(
                label: '从「我的课程」自动同步匹配',
                icon: AelIcons.refresh,
                variant: AelButtonVariant.tonal,
                expanded: true,
                onPressed: () async {
                  Navigator.of(dialogCtx).pop();
                  await _handleSyncMyCourses(context);
                },
              ),
            ],
          );
        },
      ),
      actions: [
        if (currentId.isNotEmpty)
          AelDialogAction<void>(
            label: '解绑',
            isDestructive: true,
            onPressed: () async {
              await ZhiyunService.deleteCourseId(
                widget.course.name,
                courseCode: widget.course.id,
                courseId: currentId,
                course: widget.course,
                semesterName: widget.semesterName,
                preferredHalfTag: widget.preferredHalfTag,
                targetDate: widget.period?.startTime,
              );
              if (mounted) {
                setState(() {
                  _load();
                });
              }
            },
          ),
        const AelDialogAction<void>(
          label: '取消',
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<void>(
          label: '确认',
          variant: AelButtonVariant.primary,
          onPressed: () async {
            final raw = textController.text.trim();
            final cid = ZhiyunService.extractCourseId(raw);
            if (cid == null || cid.isEmpty) {
              return;
            }
            await ZhiyunService.saveCourseId(
              widget.course.name,
              cid,
              courseCode: widget.course.id,
              course: widget.course,
              semesterName: widget.semesterName,
              preferredHalfTag: widget.preferredHalfTag,
              targetDate: widget.period?.startTime,
            );
            if (mounted) {
              setState(() {
                _load();
              });
            }
          },
        ),
      ],
    ).then((_) => textController.dispose());
  }

  Widget _buildCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    Color? iconForeground,
    required String title,
    required String tag,
    VoidCallback? onTagTap,
    required String subtitle,
    required List<Widget> buttons,
  }) {
    final colors = AelTheme.colorsOf(context);
    final effectiveIconFg = iconForeground ?? colors.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '智云课堂'),
          AelSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AelIconBadge(
                      icon: icon,
                      size: 36,
                      iconSize: 18,
                      style: AelIconBadgeStyle.cookie,
                      backgroundColor: iconColor,
                      iconColor: effectiveIconFg,
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
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: onTagTap,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.tonalTileBg,
                                    borderRadius: BorderRadius.circular(
                                      AelRadius.pill,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
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
                              color: colors.textSecondary,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final lastWatched =
                                  ZhiyunService.getLastWatchedReplay(
                                    courseName: widget.course.name,
                                    courseCode: widget.course.id,
                                    scopeKey: _semesterScopeKey,
                                  );
                              if (lastWatched != null &&
                                  lastWatched['lessonTitle'] != null) {
                                final title = lastWatched['lessonTitle']
                                    .toString();
                                final url = lastWatched['livingroomUrl']
                                    ?.toString();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: GestureDetector(
                                    onTap: url != null && url.isNotEmpty
                                        ? () => _openInAppPlayer(
                                            context,
                                            url: url,
                                            title: title,
                                            courseId:
                                                ZhiyunService.extractCourseId(
                                                  lastWatched['courseId']
                                                          ?.toString() ??
                                                      '',
                                                ),
                                            subId: lastWatched['subId']
                                                ?.toString(),
                                          )
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.tonalTileBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            AelIcons.tabFlow,
                                            size: 11,
                                            color: colors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '上次播放: $title',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colors.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            AelIcons.chevronRight,
                                            size: 10,
                                            color: colors.textTertiary,
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
                Row(children: buttons),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final colors = AelTheme.colorsOf(context);
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
          return const SizedBox.shrink();
        }

        final info = snapshot.data;
        if (info == null || (!info.isLive && !info.hasReplay)) {
          return const SizedBox.shrink();
        }

        // 状态零：当前课程或课节正在进行实时直播 (isLive)
        if (info.isLive) {
          return _buildCard(
            context: context,
            icon: AelIcons.radio,
            iconColor: colors.error,
            title: '智云实时直播',
            tag: '● 正在直播',
            onTagTap: () => _openInAppPlayer(
              context,
              url: info.livingroomUrl,
              title: info.lessonTitle.isNotEmpty ? info.lessonTitle : '实时直播',
              courseId: info.courseId,
              subId: info.subId,
              preferLive: true,
            ),
            subtitle: '该课程当前正在智云课堂进行实时直播，点击可直达直播间观看',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: colors.error,
                  borderRadius: BorderRadius.circular(AelRadius.pill),
                  minimumSize: const Size(36, 36),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AelIcons.video, size: 16, color: colors.onPrimary),
                        const SizedBox(width: 6),
                        Text(
                          '观看直播',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onPressed: () => _openInAppPlayer(
                    context,
                    url: info.livingroomUrl,
                    title: info.lessonTitle.isNotEmpty
                        ? info.lessonTitle
                        : '实时直播',
                    courseId: info.courseId,
                    subId: info.subId,
                    preferLive: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AelCircleIconButton(
                icon: AelIcons.compass,
                size: 36,
                iconSize: 16,
                backgroundColor: colors.tonalTileBg,
                iconColor: colors.textPrimary,
                elevated: false,
                tooltip: '外部浏览器打开',
                onPressed: () => _openExternalBrowser(
                  info.livingroomUrl,
                  info.lessonTitle.isNotEmpty ? info.lessonTitle : '实时直播',
                  courseId: info.courseId,
                  subId: info.subId,
                ),
              ),
              if (info.courseId != null) ...[
                const SizedBox(width: 8),
                AelCircleIconButton(
                  icon: AelIcons.edit,
                  size: 36,
                  iconSize: 16,
                  backgroundColor: colors.tonalTileBg,
                  iconColor: colors.textPrimary,
                  elevated: false,
                  tooltip: '修改智云课程绑定',
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
            icon: AelIcons.video,
            iconColor: colors.primary,
            iconForeground: colors.onPrimary,
            title: '本节录播回放',
            tag: info.lessonTitle,
            onTagTap: info.courseId != null
                ? () => _showBindDialog(context, info.courseId!)
                : null,
            subtitle: '本节录播已就绪，点击可直接进入回放房间观看',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AelRadius.pill),
                  minimumSize: const Size(36, 36),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AelIcons.video, size: 16, color: colors.onPrimary),
                        const SizedBox(width: 6),
                        Text(
                          '观看回放',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onPrimary,
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
              AelCircleIconButton(
                icon: AelIcons.compass,
                size: 36,
                iconSize: 16,
                backgroundColor: colors.tonalTileBg,
                iconColor: colors.textPrimary,
                elevated: false,
                tooltip: '外部浏览器打开',
                onPressed: () => _openAndRecord(
                  info.livingroomUrl,
                  info.lessonTitle,
                  courseId: info.courseId,
                  subId: info.subId,
                ),
              ),
              if (info.courseId != null) ...[
                const SizedBox(width: 8),
                AelCircleIconButton(
                  icon: AelIcons.edit,
                  size: 36,
                  iconSize: 16,
                  backgroundColor: colors.tonalTileBg,
                  iconColor: colors.textPrimary,
                  elevated: false,
                  tooltip: '修改智云课程绑定',
                  onPressed: () => _showBindDialog(context, info.courseId!),
                ),
              ],
            ],
          );
        }

        // 状态二：整门课程智云房间直达（已确认有回放，且非单节模式）
        if (info.courseId != null && info.hasReplay) {
          return _buildCard(
            context: context,
            icon: AelIcons.video,
            iconColor: colors.primary,
            iconForeground: colors.onPrimary,
            title: '智云课堂房间',
            tag: 'ID: ${info.courseId}',
            onTagTap: () => _showBindDialog(context, info.courseId!),
            subtitle: '点击进入该课程专属房间，查看所有课节与回放',
            buttons: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AelRadius.pill),
                  minimumSize: const Size(36, 36),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          AelIcons.externalLink,
                          size: 16,
                          color: colors.onPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '进入课堂',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onPrimary,
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
              AelCircleIconButton(
                icon: AelIcons.compass,
                size: 36,
                iconSize: 16,
                backgroundColor: colors.tonalTileBg,
                iconColor: colors.textPrimary,
                elevated: false,
                tooltip: '外部浏览器打开',
                onPressed: () => _openAndRecord(
                  info.livingroomUrl,
                  '课程房间',
                  courseId: info.courseId,
                ),
              ),
              const SizedBox(width: 8),
              AelCircleIconButton(
                icon: AelIcons.edit,
                size: 36,
                iconSize: 16,
                backgroundColor: colors.tonalTileBg,
                iconColor: colors.textPrimary,
                elevated: false,
                tooltip: '修改智云课程绑定',
                onPressed: () => _showBindDialog(context, info.courseId!),
              ),
            ],
          );
        }

        // 无直播且无回放时彻底隐藏智云课堂卡片
        return const SizedBox.shrink();
      },
    );
  }
}

class CoursewareDownloadCard extends StatelessWidget {
  final Course course;
  final String? semesterName;
  final String? preferredHalfTag;

  const CoursewareDownloadCard({
    super.key,
    required this.course,
    this.semesterName,
    this.preferredHalfTag,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '资源'),
          AelSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 学在浙大 / 智云课程课件批量管理与下载
                _buildBatchResourceRow(
                  context,
                  colors: colors,
                  icon: AelIcons.folder,
                  iconBg: colors.primaryContainer,
                  iconFg: colors.onPrimaryContainer,
                  title: '学在浙大课件下载',
                  subtitle: '多选批量下载与分享课程课件附件（学在浙大 / 智云）',
                  onTap: () => _openCoursewareBatchPage(context),
                ),

                const SizedBox(height: 12),
                Container(height: 0.5, color: colors.divider),
                const SizedBox(height: 12),

                // 智云课堂语音字幕下载
                _buildBatchResourceRow(
                  context,
                  colors: colors,
                  icon: AelIcons.audio,
                  iconBg: colors.infoContainer,
                  iconFg: colors.onInfoContainer,
                  title: '智云课堂语音字幕下载',
                  subtitle: '多选批量导出已生成的课节语音转写字幕（txt 格式）',
                  onTap: () => _showZhiyunSubtitleBatchDialog(context),
                ),

                const SizedBox(height: 12),
                Container(height: 0.5, color: colors.divider),
                const SizedBox(height: 12),

                // 智云课堂切片课件下载
                _buildBatchResourceRow(
                  context,
                  colors: colors,
                  icon: AelIcons.image,
                  iconBg: colors.primaryContainer,
                  iconFg: colors.onPrimaryContainer,
                  title: '智云课堂切片课件下载',
                  subtitle: '多选批量打包下载已生成的课堂 PPT 切片（ZIP 压缩包）',
                  onTap: () => _showZhiyunPptBatchDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchResourceRow(
    BuildContext context, {
    required AelColorTokens colors,
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        AelIconBadge(
          icon: icon,
          size: 36,
          iconSize: 18,
          style: AelIconBadgeStyle.circle,
          backgroundColor: iconBg,
          iconColor: iconFg,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        AelChip(label: '批量管理', tone: AelChipTone.primary, onTap: onTap),
      ],
    );
  }

  Future<void> _openCoursewareBatchPage(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => CoursewareBatchPage(
          course: course,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
        ),
      ),
    );
  }

  Future<void> _showZhiyunSubtitleBatchDialog(BuildContext context) async {
    final cid = ZhiyunService.getKnownCourseId(
      course.name,
      courseCode: course.id,
      teacher: course.teacher,
      course: course,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
    );
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ZhiyunResourceBatchPage(
          course: course,
          initialCourseId: cid,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
          mode: ZhiyunResourceBatchMode.subtitles,
        ),
      ),
    );
  }

  Future<void> _showZhiyunPptBatchDialog(BuildContext context) async {
    final cid = ZhiyunService.getKnownCourseId(
      course.name,
      courseCode: course.id,
      teacher: course.teacher,
      course: course,
      semesterName: semesterName,
      preferredHalfTag: preferredHalfTag,
    );
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ZhiyunResourceBatchPage(
          course: course,
          initialCourseId: cid,
          semesterName: semesterName,
          preferredHalfTag: preferredHalfTag,
          mode: ZhiyunResourceBatchMode.pptSlides,
        ),
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
  bool _expanded = false;
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
      widget.course.name,
      candidateCourseName,
    );
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
        final urlMatch = RegExp(
          r'/course[s]?/(\d+)/',
        ).firstMatch(t.description);
        if (urlMatch != null) {
          cidFromUrl = urlMatch.group(1);
        }
        if (!_matchesThisCourse(taskCourse, candidateCid: cidFromUrl)) {
          continue;
        }

        final aid =
            (t.fromUid != null && t.fromUid!.startsWith('courses-todo:'))
            ? t.fromUid!.substring('courses-todo:'.length)
            : 'task:${t.uid}';
        taskMap[aid] = t;

        final cleanTitle = t.summary
            .replaceFirst(RegExp(r'^(作业|小测)：'), '')
            .trim();
        localItems.add(
          Todo.fromJson({
            'id': aid,
            'title': cleanTitle.isNotEmpty ? cleanTitle : t.summary,
            'course_name': taskCourse.isNotEmpty
                ? taskCourse
                : widget.course.name,
            'course_id': cidFromUrl ?? '',
            'end_time': t.endTime.toIso8601String(),
            'type': t.isQuiz ? 'quiz' : 'homework',
            'completeness': t.status == TaskStatus.completed
                ? 'full'
                : 'incomplete',
          }),
        );
      }
    }

    if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
      final scholarTodos = Get.find<Rx<Scholar>>(tag: 'scholar').value.todos;
      for (final todo in scholarTodos) {
        if (!_matchesThisCourse(
          todo.course,
          candidateCid: todo.resolvedCourseId,
        )) {
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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 10),
    );
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
    if (_error != null && _items.isEmpty) {
      return '获取作业失败，点击展开查看详情或重试';
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
    final colors = AelTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          SubSubtitleRow(subtitle: '作业'),
          AelSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AelIconBadge(
                      icon: AelIcons.homework,
                      size: 36,
                      iconSize: 18,
                      style: AelIconBadgeStyle.cookie,
                      backgroundColor: colors.primaryContainer,
                      iconColor: colors.onPrimaryContainer,
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
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _summarySubtitle(),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
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
                        if (_loading)
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: Center(
                              child: CupertinoActivityIndicator(radius: 7),
                            ),
                          )
                        else
                          AelCircleIconButton(
                            icon: AelIcons.refresh,
                            size: 32,
                            iconSize: 14,
                            backgroundColor: colors.tonalTileBg,
                            iconColor: colors.textPrimary,
                            elevated: false,
                            tooltip: '刷新课程作业',
                            onPressed: _fetchHomeworks,
                          ),
                        if (_items.isNotEmpty || _error != null) ...[
                          const SizedBox(width: 6),
                          AelChip(
                            label: _expanded ? '收起' : '展开',
                            leadingIcon: _expanded
                                ? AelIcons.chevronUp
                                : AelIcons.chevronDown,
                            tone: _expanded
                                ? AelChipTone.neutral
                                : AelChipTone.primary,
                            onTap: () {
                              setState(() {
                                _expanded = !_expanded;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (_expanded) ...[
                  if (_loading && _items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Column(
                          children: [
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              '正在同步该课程的全部作业与成绩状态...',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
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
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    )
                  else if (_items.isEmpty && _fetchedOnce)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        '学在浙大暂无该课程的已发布作业或测验。',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  else if (_items.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, thickness: 1, color: colors.divider),
                    for (int i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 16,
                          thickness: 1,
                          color: colors.divider,
                        ),
                      Builder(
                        builder: (context) {
                          final todo = _items[i];
                          final matchingTask = _taskByActivityId[todo.id];
                          final uidKey =
                              matchingTask?.uid ?? 'courses-todo:${todo.id}';
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
                          final canSubmitInApp =
                              !todo.id.startsWith('task:') ||
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
                                horizontal: 4,
                                vertical: 8,
                              ),
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
                        },
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
