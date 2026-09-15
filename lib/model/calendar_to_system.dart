import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';

class CalendarToSystemManager {
  final Rx<Scholar> _scholarRx;

  Scholar get scholar => _scholarRx.value;

  final RxBool calendarSyncEnabled = false.obs;
  final RxBool hasCalendarPermission = false.obs;

  /// 提醒方式（通知提醒 / 闹钟提醒），默认通知提醒
  CalendarReminderMode reminderMode = CalendarReminderMode.notification;

  /// 提前提醒分钟数
  int reminderMinutes = 15;

  CalendarToSystemManager(this._scholarRx);

  Future<bool> checkPermissions() async {
    final enabled = await OhosNativeService.instance.checkCalendarPermission();
    hasCalendarPermission.value = enabled;
    return enabled;
  }

  Future<bool> requestPermissions() async {
    final granted =
        await OhosNativeService.instance.requestCalendarPermission();
    hasCalendarPermission.value = granted;
    return granted;
  }

  void _log(
    String operation, {
    CelechronLogLevel level = CelechronLogLevel.info,
    String? message,
    Object? error,
  }) {
    DiagnosticLogService.instance.record(
      level: level,
      module: '日历同步',
      operation: operation,
      message: message,
      error: error,
    );
  }

  /// 当校历配置缺失时，基于学期 session 与标准上课时间表进行保底推算
  List<Map<String, dynamic>> _generateEventsFromSessions(Semester semester) {
    final list = <Map<String, dynamic>>[];
    // 浙大标准大节次时间表 (时:分)
    const sessionTimes = [
      [], // 0 占位
      [Duration(hours: 8, minutes: 0), Duration(hours: 8, minutes: 45)], // 1
      [Duration(hours: 8, minutes: 50), Duration(hours: 9, minutes: 35)], // 2
      [Duration(hours: 10, minutes: 0), Duration(hours: 10, minutes: 45)], // 3
      [Duration(hours: 10, minutes: 50), Duration(hours: 11, minutes: 35)], // 4
      [Duration(hours: 11, minutes: 40), Duration(hours: 12, minutes: 25)], // 5
      [Duration(hours: 13, minutes: 25), Duration(hours: 14, minutes: 10)], // 6
      [Duration(hours: 14, minutes: 15), Duration(hours: 15, minutes: 0)], // 7
      [Duration(hours: 15, minutes: 5), Duration(hours: 15, minutes: 50)], // 8
      [Duration(hours: 16, minutes: 15), Duration(hours: 17, minutes: 0)], // 9
      [Duration(hours: 17, minutes: 5), Duration(hours: 17, minutes: 50)], // 10
      [
        Duration(hours: 18, minutes: 50),
        Duration(hours: 19, minutes: 35)
      ], // 11
      [
        Duration(hours: 19, minutes: 40),
        Duration(hours: 20, minutes: 25)
      ], // 12
      [
        Duration(hours: 20, minutes: 30),
        Duration(hours: 21, minutes: 15)
      ], // 13
    ];

    // 推算学期开始时间：取当前时间所在周的前几周，或以当前周周一作为基准第 1 周
    final now = DateTime.now();
    // 寻找最近的周一作为参考基准
    final baseMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    for (final session in semester.sessions) {
      if (session.time.isEmpty) continue;
      final firstSection = session.time.first;
      final lastSection = session.time.last;
      if (firstSection <= 0 || firstSection >= sessionTimes.length) continue;
      if (lastSection <= 0 || lastSection >= sessionTimes.length) continue;

      final startOffset = sessionTimes[firstSection][0];
      final endOffset = sessionTimes[lastSection][1];

      // 为学期覆盖 16 周的排课
      for (int week = 1; week <= 16; week++) {
        final isOdd = week % 2 != 0;
        if (isOdd && !session.oddWeek) continue;
        if (!isOdd && !session.evenWeek) continue;

        final isFirstHalf = week <= 8;
        if (isFirstHalf && !session.firstHalf) continue;
        if (!isFirstHalf && !session.secondHalf) continue;

        final dayOffset = (week - 1) * 7 + (session.dayOfWeek - 1);
        final classDate = baseMonday.add(Duration(days: dayOffset.toInt()));

        final startTime = classDate.add(startOffset);
        final endTime = classDate.add(endOffset);

        final mappedLocation =
            CalendarLocationMapper.mapForCalendar(session.location);

        list.add({
          'uid':
              'session_${session.id ?? session.name}_${week}_${session.dayOfWeek}_$firstSection',
          'summary': '[${semester.name}] ${session.name}',
          'description':
              '教师: ${session.teacher}\n第 $week 周 第 $firstSection-$lastSection 节',
          'location': mappedLocation,
          'startTime': startTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
        });
      }
    }
    return list;
  }

  void _showSyncFailureDialog(BuildContext context) {
    final detail = OhosNativeService.instance.lastCalendarError;
    showCupertinoDialog(
      context: context,
      builder: (BuildContext dialogContext) => CupertinoAlertDialog(
        title: const Text('同步失败'),
        content: Text(
          detail == null
              ? '请确保已授予日历权限，且课程表数据已加载。'
              : '请确保已授予日历权限，且课程表数据已加载。\n\n错误信息：\n$detail',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
    );
  }

  Future<bool> syncScholarToSystemCalendar({String? semesterName}) async {
    if (!scholar.isLogan) {
      _log('sync', level: CelechronLogLevel.warning, message: '未登录，跳过');
      return false;
    }

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        _log('sync', level: CelechronLogLevel.error, message: '日历权限被拒绝');
        return false;
      }
    }

    final semesters = semesterName != null
        ? scholar.semesters.where((s) => s.name == semesterName).toList()
        : scholar.semesters;

    if (semesters.isEmpty) {
      _log('sync', level: CelechronLogLevel.warning, message: '没有可同步的学期');
      return false;
    }

    final events = <Map<String, dynamic>>[];
    int totalCourseCount = 0;
    int totalClassSessionCount = 0;

    for (final semester in semesters) {
      // 1. 尝试从 semester.periods 获取展开的具体节次
      final periods = semester.periods;
      int classPeriodsCount = 0;
      for (final period in periods) {
        if (period.type == PeriodType.virtual) continue;
        final mappedLocation =
            CalendarLocationMapper.mapForCalendar(period.location);
        events.add({
          'uid': period.uid,
          'summary': '[${semester.name}] ${period.summary}',
          'description': period.description,
          'location': mappedLocation,
          'startTime': period.startTime.millisecondsSinceEpoch,
          'endTime': period.endTime.millisecondsSinceEpoch,
        });
        if (period.type == PeriodType.classes) {
          classPeriodsCount++;
        }
      }

      // 统计课程门数（按 unique course name 或 session name）
      final uniqueCourseNames = <String>{};
      for (final c in semester.courses.values) {
        uniqueCourseNames.add(c.name);
      }
      for (final s in semester.sessions) {
        uniqueCourseNames.add(s.name);
      }
      totalCourseCount += uniqueCourseNames.length;

      // 2. 关键防御兜底：如果 _dayOfWeekToDays 为空导致 periods 中的课程节次为 0，
      // 但 semester.sessions 实际上是有课的，直接基于 semester.sessions 生成课程节次日程！
      if (classPeriodsCount == 0 && semester.sessions.isNotEmpty) {
        _log('sync',
            level: CelechronLogLevel.warning,
            message:
                '学期 ${semester.name} 的 periods 未产生课程节次，启动基于 sessions 的保底推算');
        final fallbackEvents = _generateEventsFromSessions(semester);
        events.addAll(fallbackEvents);
        totalClassSessionCount += fallbackEvents.length;
      } else {
        totalClassSessionCount += classPeriodsCount;
      }
    }

    // 任务(DDL)：来自学在浙大的待办，按课程聚合，截止前提醒
    for (final todo in scholar.todos) {
      final end = todo.endTime;
      if (end == null || end.isBefore(DateTime.now())) continue;
      events.add({
        'uid': 'todo_${todo.id}',
        'summary': '[任务] ${todo.course}',
        'description': '${todo.name}\n课程：${todo.course}\n截止：$end',
        'location': '',
        'startTime': end
            .subtract(Duration(minutes: reminderMinutes))
            .millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      });
    }

    // 本地任务：DDL 与固定日程
    try {
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      for (final task in taskList) {
        if (task.status == TaskStatus.deleted) continue;
        if (task.type == TaskType.deadline) {
          final end = task.endTime;
          if (end.isBefore(DateTime.now())) continue;
          events.add({
            'uid': 'task_${task.uid}',
            'summary': '[DDL] ${task.summary}',
            'description': task.description,
            'location': task.location,
            'startTime': end
                .subtract(Duration(minutes: reminderMinutes))
                .millisecondsSinceEpoch,
            'endTime': end.millisecondsSinceEpoch,
          });
        } else if (task.type == TaskType.fixed) {
          if (task.endTime.isBefore(DateTime.now())) continue;
          events.add({
            'uid': 'task_${task.uid}',
            'summary': '[日程] ${task.summary}',
            'description': task.description,
            'location': task.location,
            'startTime': task.startTime.millisecondsSinceEpoch,
            'endTime': task.endTime.millisecondsSinceEpoch,
          });
        }
      }
    } catch (e) {
      _log('sync', level: CelechronLogLevel.warning, message: '读取本地任务失败：$e');
    }

    if (events.isEmpty) {
      _log('sync',
          level: CelechronLogLevel.error,
          message: '过滤后没有可同步的日程（学期数=${semesters.length}）');
      return false;
    }

    final useAlarm = reminderMode == CalendarReminderMode.alarm;
    _log('sync',
        message:
            '准备同步 ${events.length} 个日程（提醒方式=${useAlarm ? "闹钟" : "通知"}，提前$reminderMinutes分钟）');

    // 先清除旧日历（去重），再写入新事件
    await OhosNativeService.instance.clearCalendarEvents();

    final count = await OhosNativeService.instance.syncCalendarEvents(
      events,
      reminderMinutes: reminderMinutes,
      useAlarm: useAlarm,
    );
    if (count > 0) {
      calendarSyncEnabled.value = true;
      _log('sync', message: '同步成功，写入 $count 个日程');
      // 应用内弹窗或提示告知同步结果：同步了几门课共多少节
      Get.snackbar(
        '日历同步成功',
        '已同步 $totalCourseCount 门课程，共 $totalClassSessionCount 节课到系统日历',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 4),
      );
    } else {
      _log('sync',
          level: CelechronLogLevel.error,
          message: '同步失败',
          error: OhosNativeService.instance.lastCalendarError);
    }
    return count > 0;
  }

  Future<bool> clearSyncedEvents() async {
    final count = await OhosNativeService.instance.clearCalendarEvents();
    calendarSyncEnabled.value = false;
    _log('clear', message: '已清除 $count 个日历');
    return true;
  }

  List<String> getAvailableSemesters() {
    return scholar.semesters.map((semester) => semester.name).toList();
  }

  Map<String, dynamic> getSyncStats() {
    return {
      'syncedCourseCount':
          scholar.semesters.fold<int>(0, (sum, s) => sum + s.periods.length),
      'syncedEventCount':
          scholar.semesters.fold<int>(0, (sum, s) => sum + s.periods.length),
      'calendarId': null,
      'calendarName': 'Helechron课表',
    };
  }

  void showCalendarSyncDialog(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('同步到系统日历'),
        content: Text(
          calendarSyncEnabled.value
              ? '课程表已同步到系统日历。'
              : '将课程表同步到系统日历，可在日历应用中查看课程安排。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Get.back(),
          ),
          if (calendarSyncEnabled.value)
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('取消同步'),
              onPressed: () async {
                await clearSyncedEvents();
                Get.back();
              },
            ),
          if (!calendarSyncEnabled.value)
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('同步'),
              onPressed: () async {
                final success = await syncScholarToSystemCalendar();
                Get.back();
                if (!success && context.mounted) {
                  _showSyncFailureDialog(context);
                }
              },
            ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  Future<void> checkInitialCalendarSyncStatus() async {
    final hasPermission = await checkPermissions();
    hasCalendarPermission.value = hasPermission;
    // 检测系统中是否存在已同步的 Helechron 日历
    final exists = await OhosNativeService.instance.hasSyncedCalendar();
    calendarSyncEnabled.value = exists;
    _log('initialStatus',
        message: 'permission=$hasPermission, calendarExists=$exists');
  }

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) async {
    if (enabled) {
      final success = await syncScholarToSystemCalendar();
      if (!success && context.mounted) {
        _showSyncFailureDialog(context);
      }
    } else {
      await clearSyncedEvents();
    }
  }

  Map<String, dynamic> getCalendarSyncStatus() {
    return {
      'enabled': calendarSyncEnabled.value,
      'hasPermission': hasCalendarPermission.value,
      'isLoggedIn': scholar.isLogan,
      ...getSyncStats(),
    };
  }
}
