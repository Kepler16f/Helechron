import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/model/scholar.dart';

/// HarmonyOS NEXT: 系统日历同步功能暂未实现
/// 后续可通过 HarmonyOS Calendar Kit 实现
class CalendarToSystemManager {
  final Scholar scholar;

  final RxBool _calendarSyncEnabled = false.obs;
  final RxBool _hasCalendarPermission = false.obs;

  bool get calendarSyncEnabled => false;
  bool get hasCalendarPermission => false;

  CalendarToSystemManager(this.scholar);

  Future<bool> checkPermissions() async {
    return false;
  }

  Future<bool> requestPermissions() async {
    return false;
  }

  Future<bool> syncScholarToSystemCalendar() async {
    return false;
  }

  Future<bool> clearSyncedEvents() async {
    return true;
  }

  List<String> getAvailableSemesters() {
    return scholar.semesters.map((semester) => semester.name).toList();
  }

  Map<String, dynamic> getSyncStats() {
    return {
      'syncedCourseCount': 0,
      'syncedEventCount': 0,
      'calendarId': null,
      'calendarName': 'Celechron课表',
    };
  }

  void showCalendarSyncDialog(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('暂不支持'),
        content: const Text('HarmonyOS NEXT 系统日历同步功能将在后续版本中实现'),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  Future<void> checkInitialCalendarSyncStatus() async {
    _calendarSyncEnabled.value = false;
    _hasCalendarPermission.value = false;
  }

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) async {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('暂不支持'),
        content: const Text('HarmonyOS NEXT 系统日历同步功能将在后续版本中实现'),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  Map<String, dynamic> getCalendarSyncStatus() {
    return {
      'enabled': false,
      'hasPermission': false,
      'isLoggedIn': scholar.isLogan,
    };
  }
}
