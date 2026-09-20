import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/cupertino.dart';

import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/worker/ecard_widget_messenger.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:celechron/worker/background_app_refresh.dart';
import 'package:celechron/model/calendar_to_system.dart';
import 'package:celechron/model/calendar_to_ical.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/platform_features.dart';

class OptionController extends GetxController {
  final _option = Get.find<Option>(tag: 'option');
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _fuse = Get.find<Rx<Fuse>>(tag: 'fuse');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  late final RxInt allowTimeLength = _option.allowTime.length.obs;

  Timer? _periodicRefreshTimer;

  // 日历管理器
  late final CalendarToSystemManager _calendarManager;

  @override
  void onInit() {
    super.onInit();
    _calendarManager = CalendarToSystemManager(scholar);
    _calendarManager.reminderMode = _option.calendarReminderMode.value;

    ever(courseIdMappingList, (value) {
      _db.setCourseIdMappingList(value);
    });

    _calendarManager.checkInitialCalendarSyncStatus();

    if (PlatformFeatures.hasBackgroundRefresh) {
      if (_option.pushOnGradeChange.value || _option.pushOnDdlReminder.value) {
        _startPeriodicRefresh();
      }
    }
  }

  @override
  void onClose() {
    _periodicRefreshTimer?.cancel();
    super.onClose();
  }

  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    // 周期性触发后台刷新逻辑（15 分钟）
    _periodicRefreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => refreshScholar(),
    );
  }

  void _stopPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
  }

  void _updateBackgroundWorker() {
    final enabled = pushOnGradeChange || pushOnDdlReminder;
    if (enabled) {
      _startPeriodicRefresh();
      OhosNativeService.instance.requestNotificationPermission();
    } else {
      _stopPeriodicRefresh();
    }
  }

  Duration get workTime => _option.workTime.value;

  set workTime(Duration value) {
    _option.workTime.value = value;
    _db.setWorkTime(value);
  }

  Duration get restTime => _option.restTime.value;

  set restTime(Duration value) {
    _option.restTime.value = value;
    _db.setRestTime(value);
  }

  Map<DateTime, DateTime> get allowTime => _option.allowTime;

  set allowTime(Map<DateTime, DateTime> value) {
    _option.allowTime.value = value;
    _db.setAllowTime(value);
    allowTimeLength.value = value.length;
  }

  GpaStrategy get gpaStrategy => _option.gpaStrategy.value;

  set gpaStrategy(GpaStrategy value) {
    _option.gpaStrategy.value = value;
    _db.setGpaStrategy(value);
  }

  bool get pushOnGradeChange => _option.pushOnGradeChange.value;

  set pushOnGradeChange(bool value) {
    _option.pushOnGradeChange.value = value;
    _db.setPushOnGradeChange(value);
    _db.secureStorage.write(key: 'pushOnGradeChange', value: value.toString());
    _updateBackgroundWorker();
  }

  bool get pushOnDdlReminder => _option.pushOnDdlReminder.value;

  set pushOnDdlReminder(bool value) {
    _option.pushOnDdlReminder.value = value;
    _db.setPushOnDdlReminder(value);
    _db.secureStorage.write(key: 'pushOnDdlReminder', value: value.toString());
    _updateBackgroundWorker();
  }

  BrightnessMode get brightnessMode => _option.brightnessMode.value;

  set brightnessMode(BrightnessMode value) {
    _option.brightnessMode.value = value;
    _db.setBrightnessMode(value);
  }

  bool get bottomBarFloating => _option.bottomBarFloating.value;

  set bottomBarFloating(bool value) {
    _option.bottomBarFloating.value = value;
    _db.setBottomBarFloating(value);
    if (!value) {
      bottomBarImmersiveLight = false;
    }
    OhosNativeService.instance.setBottomBarStyle(
      floating: bottomBarFloating,
      immersiveLight: bottomBarImmersiveLight,
      materialLevel: bottomBarMaterialLevel,
    );
  }

  bool get bottomBarImmersiveLight => _option.bottomBarImmersiveLight.value;

  set bottomBarImmersiveLight(bool value) {
    _option.bottomBarImmersiveLight.value = value;
    _db.setBottomBarImmersiveLight(value);
    OhosNativeService.instance.setBottomBarStyle(
      floating: bottomBarFloating,
      immersiveLight: bottomBarImmersiveLight,
      materialLevel: bottomBarMaterialLevel,
    );
  }

  int get bottomBarMaterialLevel => _option.bottomBarMaterialLevel.value;

  set bottomBarMaterialLevel(int value) {
    _option.bottomBarMaterialLevel.value = value;
    _db.setBottomBarMaterialLevel(value);
    OhosNativeService.instance.setBottomBarStyle(
      floating: bottomBarFloating,
      immersiveLight: bottomBarImmersiveLight,
      materialLevel: bottomBarMaterialLevel,
    );
  }

  RxList<CourseIdMap> get courseIdMappingList => _option.courseIdMappingList;

  bool get hideHomeGpa => _option.hideHomeGpa.value;

  set hideHomeGpa(bool value) {
    _option.hideHomeGpa.value = value;
    _db.setHideHomeGpa(value);
  }

  bool get asyncRefresh => _option.asyncRefresh.value;

  set asyncRefresh(bool value) {
    _option.asyncRefresh.value = value;
    _db.setAsyncRefresh(value);
  }

  String get celechronVersion => _fuse.value.displayVersion;

  bool get hasNewVersion => _fuse.value.hasNewVersion;

  Future<void> logout() async {
    await scholar.value.logout();
    scholar.refresh();
    pushOnGradeChange = false;
    ECardWidgetMessenger.logout();
  }

  void showExportDialog(BuildContext context) {
    CalendarToIcal.showExportDialog(context, scholar.value);
  }

  RxBool get calendarSyncEnabled => _calendarManager.calendarSyncEnabled;

  RxBool get hasCalendarPermission => _calendarManager.hasCalendarPermission;

  CalendarReminderMode get calendarReminderMode =>
      _option.calendarReminderMode.value;

  Future<void> setCalendarReminderMode(CalendarReminderMode mode) async {
    _option.calendarReminderMode.value = mode;
    await _db.setCalendarReminderMode(mode);
    _calendarManager.reminderMode = mode;
    // 若已同步，则重新同步以应用新的提醒方式
    if (_calendarManager.calendarSyncEnabled.value) {
      await _calendarManager.syncScholarToSystemCalendar();
    }
  }

  Future<void> toggleCalendarSync(BuildContext context, bool enabled) =>
      _calendarManager.toggleCalendarSync(context, enabled);

  void showCalendarSyncDialog(BuildContext context) =>
      _calendarManager.showCalendarSyncDialog(context);

  Map<String, dynamic> getCalendarSyncStatus() {
    final stats = _calendarManager.getSyncStats();
    return {
      'enabled': calendarSyncEnabled.value,
      'hasPermission': hasCalendarPermission.value,
      'isLoggedIn': scholar.value.isLogan,
      ...stats,
    };
  }
}
