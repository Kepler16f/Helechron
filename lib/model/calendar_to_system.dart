import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';

class CalendarToSystemManager {
  final Scholar scholar;

  final RxBool _calendarSyncEnabled = false.obs;
  final RxBool _hasCalendarPermission = false.obs;

  bool get calendarSyncEnabled => _calendarSyncEnabled.value;
  bool get hasCalendarPermission => _hasCalendarPermission.value;

  CalendarToSystemManager(this.scholar);

  Future<bool> checkPermissions() async {
    final enabled = await OhosNativeService.instance.checkCalendarPermission();
    _hasCalendarPermission.value = enabled;
    return enabled;
  }

  Future<bool> requestPermissions() async {
    final granted =
        await OhosNativeService.instance.requestCalendarPermission();
    _hasCalendarPermission.value = granted;
    return granted;
  }

  Future<bool> syncScholarToSystemCalendar({String? semesterName}) async {
    if (!scholar.isLogan) return false;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) return false;
    }

    final semesters = semesterName != null
        ? scholar.semesters.where((s) => s.name == semesterName).toList()
        : scholar.semesters;

    if (semesters.isEmpty) return false;

    final events = <Map<String, dynamic>>[];
    for (final semester in semesters) {
      for (final period in semester.periods) {
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

    if (events.isEmpty) return false;

    final count = await OhosNativeService.instance.syncCalendarEvents(events);
    if (count > 0) {
      _calendarSyncEnabled.value = true;
    }
    return count > 0;
  }

  Future<bool> clearSyncedEvents() async {
    final count = await OhosNativeService.instance.clearCalendarEvents();
    if (count > 0) {
      _calendarSyncEnabled.value = false;
    }
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
          _calendarSyncEnabled.value
              ? '课程表已同步到系统日历。'
              : '将课程表同步到系统日历，可在日历应用中查看课程安排。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Get.back(),
          ),
          if (_calendarSyncEnabled.value)
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('取消同步'),
              onPressed: () async {
                await clearSyncedEvents();
                Get.back();
              },
            ),
          if (!_calendarSyncEnabled.value)
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
    _hasCalendarPermission.value = hasPermission;
    _calendarSyncEnabled.value = false;
  }

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) async {
    if (enabled) {
      showCalendarSyncDialog(context);
    } else {
      await clearSyncedEvents();
    }
  }

  Map<String, dynamic> getCalendarSyncStatus() {
    return {
      'enabled': calendarSyncEnabled,
      'hasPermission': hasCalendarPermission,
      'isLoggedIn': scholar.isLogan,
      ...getSyncStats(),
    };
  }
}
