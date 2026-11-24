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
import 'package:celechron/model/option.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'package:celechron/design/app_notification.dart';
import 'package:celechron/services/file_download_share_helper.dart';
import 'package:celechron/services/zhiyun_service.dart';
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
          const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
        ],
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

      final authResults = await Future.wait<String?>([
        ZhiyunService.ensureValidToken().timeout(
          const Duration(seconds: 4),
          onTimeout: () => ZhiyunService.getCachedZhiyunToken(),
        ),
        ZhiyunService.ensureSsoCookieValue().timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        ),
      ]);
      final token = authResults[0] ?? ZhiyunService.getCachedZhiyunToken();
      final ssoCookie = authResults[1];

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

    // 统一架构：有 courseId 时（无论直播还是回放）均进入 ZhiyunPlayerPage；
    // 直播模式立即跳转零阻塞，在 ZhiyunPlayerPage 内直接以内嵌网页播放器打开直播间。
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
              '未获取到课程更新，请确保已登录浙大统一身份认证或稍后重试。您亦可直接输入课程ID完成绑定。',
            ),
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
              Builder(
                builder: (fieldCtx) {
                  final dialogColors = AelTheme.colorsOf(fieldCtx);
                  final colors = AelTheme.colorsOf(context);
                  return Column(
                    children: [
                      CupertinoTextField(
                        controller: textController,
                        placeholder: '85940 或 粘贴课程网页链接',
                        autofocus: true,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        style: TextStyle(color: dialogColors.textPrimary),
                        placeholderStyle: TextStyle(
                          color: dialogColors.textTertiary,
                        ),
                        decoration: BoxDecoration(
                          color: dialogColors.tonalTileBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          color: colors.tonalTileBg,
                          borderRadius: BorderRadius.circular(8),
                          minimumSize: const Size(32, 32),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AelIcons.refresh,
                                size: 14,
                                color: colors.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '从「我的课程」自动同步匹配',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          onPressed: () async {
                            Navigator.of(dialogCtx).pop();
                            await _handleSyncMyCourses(context);
                          },
                        ),
                      ),
                    ],
                  );
                },
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
                  course: widget.course,
                  semesterName: widget.semesterName,
                  preferredHalfTag: widget.preferredHalfTag,
                  targetDate: widget.period?.startTime,
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
                course: widget.course,
                semesterName: widget.semesterName,
                preferredHalfTag: widget.preferredHalfTag,
                targetDate: widget.period?.startTime,
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
                                                lastWatched['courseId']
                                                    ?.toString() ??
                                                widget.course.id,
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
            onTagTap: () => _openAndRecord(
              info.livingroomUrl,
              '实时直播',
              courseId: info.courseId,
              subId: info.subId,
              isLive: true,
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
                    title: '实时直播',
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
                onPressed: () => _openAndRecord(
                  info.livingroomUrl,
                  '实时直播',
                  courseId: info.courseId,
                  subId: info.subId,
                  isLive: true,
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

class CoursewareDownloadCard extends StatefulWidget {
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
  State<CoursewareDownloadCard> createState() => _CoursewareDownloadCardState();
}

class _CoursewareDownloadCardState extends State<CoursewareDownloadCard> {
  bool _expanded = false;
  bool _loading = false;
  bool _hasFetched = false;
  String? _error;
  final List<CoursewareItem> _items = [];
  final Map<String, String> _downloadedPaths = {};
  final Map<String, String> _downloadedNames = {};
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
        teacher: widget.course.teacher,
        course: widget.course,
        semesterName: widget.semesterName,
        preferredHalfTag: widget.preferredHalfTag,
      );
      if (zhiyunCid != null && zhiyunCid.isNotEmpty) {
        final zyFiles = await ZhiyunService.fetchZhiyunCourseware(zhiyunCid);
        for (final f in zyFiles) {
          list.add(
            CoursewareItem(
              name: f['name'] ?? '智云课件',
              sectionTitle: f['sectionTitle'] ?? '智云课堂',
              sizeBytes: 0,
              directUrl: f['url'],
              source: '智云课堂',
            ),
          );
        }
      }

      // 检查本地是否已下载（含持久化记录，兼容 SAF 目录）
      final saveDir = await _resolveSaveDir();
      final downloaded = <String, String>{};
      for (final item in list) {
        final key = _itemKey(item);
        if (!saveDir.startsWith('content://') &&
            !saveDir.startsWith('file://')) {
          final safeName = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final file = File('$saveDir/$safeName');
          try {
            if (await file.exists() && await file.length() > 0) {
              downloaded[key] = file.path;
              continue;
            }
          } catch (_) {}
        }
        final rec = await FileDownloadShareHelper.getDownloadRecord(
          'courseware|$key',
        );
        if (rec != null) {
          downloaded[key] = rec.savedPath;
          _downloadedNames[key] = rec.fileName;
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
        _hasFetched = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasFetched = true;
        _loading = false;
        _error = '$e';
      });
    } finally {
      client.close(force: true);
    }
  }

  String _itemKey(CoursewareItem item) =>
      '${item.source}_${item.uploadId}_${item.referenceId}_${item.name}';

  Future<void> _downloadItem(
    BuildContext context,
    CoursewareItem item, {
    bool share = false,
  }) async {
    final key = _itemKey(item);
    if (_downloadingKeys.contains(key)) return;

    // 分享：已下载则直接分享原文件，未下载则等同「下载并分享」
    if (share) {
      final saved = _downloadedPaths[key];
      if (saved != null) {
        await _shareCoursewareItem(item, saved);
        return;
      }
    }

    final currentDir = await _resolveSaveDir();
    if (!context.mounted) return;
    final target = await FileDownloadShareHelper.chooseSaveTarget(
      context,
      defaultFileName: _downloadedNames[key] ?? item.name,
      currentDir: currentDir,
      title: share ? '下载并分享课件' : '下载课件',
      confirmHint: share ? null : '仅下载保存，不会触发分享：',
    );
    if (target == null || !mounted) return;
    final saveDir = target.directory;

    setState(() {
      _downloadingKeys.add(key);
    });

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final result =
          await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
            client,
            item: item,
            saveDir: saveDir,
            customFileName: target.fileName,
          );
      if (!mounted) return;
      setState(() {
        _downloadingKeys.remove(key);
        if (result.isSuccess) {
          _downloadedPaths[key] = result.savedPath!;
          _downloadedNames[key] = result.fileName;
        }
      });

      if (result.isSuccess) {
        await FileDownloadShareHelper.saveDownloadRecord(
          'courseware|$key',
          savedPath: result.savedPath!,
          fileName: result.fileName,
          mimeType: result.mimeType,
        );
        AppNotification.success(
          share ? '已保存，正在分享' : '下载完成',
          '${result.fileName}\n已保存：${FileDownloadShareHelper.formatDirShort(saveDir)}',
        );
        if (result.shareFile != null && share) {
          await FileDownloadShareHelper.shareFiles(
            [result.shareFile!],
            mimeTypes: [result.mimeType],
            subject: result.fileName,
          );
        } else if (share) {
          AppNotification.info('分享提示', '文件已保存，暂未能生成系统分享副本');
        }
      } else if (context.mounted) {
        AppNotification.error('下载失败', '未能获取该课件的下载文件流，请确认已登录学在浙大');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingKeys.remove(key);
      });
      AppNotification.error('下载异常', '$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _shareCoursewareItem(
    CoursewareItem item,
    String savedPath,
  ) async {
    final effectiveName = _downloadedNames[_itemKey(item)] ?? item.name;
    await FileDownloadShareHelper.shareSavedOrPrepare(
      savedPath: savedPath,
      fileName: effectiveName,
      mimeType: FileDownloadShareHelper.inferMimeType(effectiveName),
      subject: effectiveName,
      onPrepareShareFile: () async {
        final client = HttpClient();
        applyZjuNetworkDefense(client);
        try {
          final tempDir = await getTemporaryDirectory();
          final dlDir = Directory('${tempDir.path}/celechron_share_dl');
          if (!await dlDir.exists()) {
            await dlDir.create(recursive: true);
          }
          final result =
              await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
                client,
                item: item,
                saveDir: dlDir.path,
                customFileName: effectiveName,
              );
          return result.shareFile;
        } finally {
          client.close(force: true);
        }
      },
    );
  }

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
                Row(
                  children: [
                    AelIconBadge(
                      icon: AelIcons.folder,
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
                          if (_expanded) {
                            setState(() {
                              _expanded = false;
                            });
                          } else if (_hasFetched) {
                            setState(() {
                              _expanded = true;
                            });
                          } else if (!_loading) {
                            _fetchCourseware();
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '学在浙大课件下载',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _items.isNotEmpty
                                  ? '已获取 ${_items.length} 个附件 · 点击${_expanded ? "收起" : "展开"}'
                                  : _hasFetched
                                  ? '暂无公开课件附件 · 点击${_expanded ? "收起" : "展开"}'
                                  : '支持选择保存路径、下载课件并唤起原生分享',
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
                    if (!_hasFetched && !_expanded)
                      _loading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: CupertinoActivityIndicator(radius: 8),
                            )
                          : AelChip(
                              label: '展开课件',
                              leadingIcon: AelIcons.download,
                              tone: AelChipTone.primary,
                              onTap: _fetchCourseware,
                            )
                    else
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
                              tooltip: '刷新课件列表',
                              onPressed: _fetchCourseware,
                            ),
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
                      ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Column(
                          children: [
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              '正在同步学在浙大与智云课堂课件...',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '获取课件失败：$_error',
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    )
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '暂未在学在浙大或智云课堂检索到该课程的公开课件附件。',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
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
                              AelIcons.file,
                              size: 18,
                              color: colors.primary,
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
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${item.sectionTitle} · ${item.formattedSize}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (downloading)
                              const CupertinoActivityIndicator(radius: 8)
                            else ...[
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                minimumSize: const Size(28, 28),
                                color: savedPath != null
                                    ? colors.successContainer
                                    : colors.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                                onPressed: () => _downloadItem(context, item),
                                child: Text(
                                  savedPath != null ? '已下载' : '下载',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: savedPath != null
                                        ? colors.onSuccessContainer
                                        : colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                minimumSize: const Size(28, 28),
                                color: colors.tonalTileBg,
                                borderRadius: BorderRadius.circular(999),
                                onPressed: () =>
                                    _downloadItem(context, item, share: true),
                                child: Text(
                                  '分享',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                ],

                const SizedBox(height: 12),
                Container(height: 0.5, color: colors.divider),
                const SizedBox(height: 12),

                // 智云课堂语音字幕下载
                Row(
                  children: [
                    AelIconBadge(
                      icon: AelIcons.audio,
                      size: 36,
                      iconSize: 18,
                      style: AelIconBadgeStyle.circle,
                      backgroundColor: colors.infoContainer,
                      iconColor: colors.onInfoContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showZhiyunSubtitleBatchDialog(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '智云课堂语音字幕下载',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '多选批量导出已生成的课节语音转写字幕（txt 格式）',
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
                    AelChip(
                      label: '批量管理',
                      tone: AelChipTone.primary,
                      onTap: () => _showZhiyunSubtitleBatchDialog(context),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(height: 0.5, color: colors.divider),
                const SizedBox(height: 12),

                // 智云课堂切片课件下载
                Row(
                  children: [
                    AelIconBadge(
                      icon: AelIcons.image,
                      size: 36,
                      iconSize: 18,
                      style: AelIconBadgeStyle.circle,
                      backgroundColor: colors.primaryContainer,
                      iconColor: colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showZhiyunPptBatchDialog(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '智云课堂切片课件下载',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '多选批量打包下载已生成的课堂 PPT 切片（ZIP 压缩包）',
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
                    AelChip(
                      label: '批量管理',
                      tone: AelChipTone.primary,
                      onTap: () => _showZhiyunPptBatchDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showZhiyunSubtitleBatchDialog(BuildContext context) async {
    final cid = ZhiyunService.getKnownCourseId(
      widget.course.name,
      courseCode: widget.course.id,
      teacher: widget.course.teacher,
      course: widget.course,
      semesterName: widget.semesterName,
      preferredHalfTag: widget.preferredHalfTag,
    );
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ZhiyunResourceBatchPage(
          course: widget.course,
          initialCourseId: cid,
          semesterName: widget.semesterName,
          preferredHalfTag: widget.preferredHalfTag,
          mode: ZhiyunResourceBatchMode.subtitles,
        ),
      ),
    );
  }

  Future<void> _showZhiyunPptBatchDialog(BuildContext context) async {
    final cid = ZhiyunService.getKnownCourseId(
      widget.course.name,
      courseCode: widget.course.id,
      teacher: widget.course.teacher,
      course: widget.course,
      semesterName: widget.semesterName,
      preferredHalfTag: widget.preferredHalfTag,
    );
    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ZhiyunResourceBatchPage(
          course: widget.course,
          initialCourseId: cid,
          semesterName: widget.semesterName,
          preferredHalfTag: widget.preferredHalfTag,
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
