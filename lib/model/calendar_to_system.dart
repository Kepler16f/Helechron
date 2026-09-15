import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
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

  Future<bool> syncScholarToSystemCalendar({String? semesterName}) async {
    if (!scholar.isLogan) {
      debugPrint('[CalendarSync] not logged in, skip');
      return false;
    }

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      debugPrint('[CalendarSync] no permission, requesting...');
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('[CalendarSync] permission denied');
        return false;
      }
    }

    final semesters = semesterName != null
        ? scholar.semesters.where((s) => s.name == semesterName).toList()
        : scholar.semesters;

    if (semesters.isEmpty) {
      debugPrint('[CalendarSync] no semesters to sync');
      return false;
    }

    debugPrint(
        '[CalendarSync] building events from ${semesters.length} semesters');
    final events = <Map<String, dynamic>>[];
    for (final semester in semesters) {
      final periods = semester.periods;
      debugPrint(
          '[CalendarSync] semester ${semester.name}: ${periods.length} periods');
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
      debugPrint('[CalendarSync] no events to sync after filtering');
      return false;
    }

    debugPrint('[CalendarSync] syncing ${events.length} events to calendar');

    // 先清除旧日历（去重），再写入新事件
    await OhosNativeService.instance.clearCalendarEvents();

    final count = await OhosNativeService.instance.syncCalendarEvents(events);
    debugPrint('[CalendarSync] sync result: $count events');
    if (count > 0) {
      calendarSyncEnabled.value = true;
    }
    return count > 0;
  }

  Future<bool> clearSyncedEvents() async {
    final count = await OhosNativeService.instance.clearCalendarEvents();
    calendarSyncEnabled.value = false;
    debugPrint('[CalendarSync] cleared $count calendars');
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
                  showCupertinoDialog(
                    context: context,
                    builder: (BuildContext dialogContext) =>
                        CupertinoAlertDialog(
                      title: const Text('同步失败'),
                      content: const Text('请确保已授予日历权限，且课程表数据已加载。'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('确定'),
                          onPressed: () => Get.back(),
                        ),
                      ],
                    ),
                  );
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
    debugPrint(
        '[CalendarSync] initial status: permission=$hasPermission, calendarExists=$exists');
  }

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) async {
    if (enabled) {
      final success = await syncScholarToSystemCalendar();
      if (!success && context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (BuildContext dialogContext) => CupertinoAlertDialog(
            title: const Text('同步失败'),
            content: const Text('请确保已授予日历权限，且课程表数据已加载。'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Get.back(),
              ),
            ],
          ),
        );
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
