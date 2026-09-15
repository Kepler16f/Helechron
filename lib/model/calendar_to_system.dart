import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';

class CalendarToSystemManager {
  final Rx<Scholar> _scholarRx;

  Scholar get scholar => _scholarRx.value;

  final RxBool calendarSyncEnabled = false.obs;
  final RxBool hasCalendarPermission = false.obs;

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
    for (final semester in semesters) {
      final periods = semester.periods;
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
      }
    }

    if (events.isEmpty) {
      _log('sync',
          level: CelechronLogLevel.error,
          message: '过滤后没有可同步的日程（学期数=${semesters.length}）');
      return false;
    }

    _log('sync', message: '准备同步 ${events.length} 个日程');

    // 先清除旧日历（去重），再写入新事件
    await OhosNativeService.instance.clearCalendarEvents();

    final count = await OhosNativeService.instance.syncCalendarEvents(events);
    if (count > 0) {
      calendarSyncEnabled.value = true;
      _log('sync', message: '同步成功，写入 $count 个日程');
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
