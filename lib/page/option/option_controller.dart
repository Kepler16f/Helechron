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
import 'package:celechron/services/backup_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/scholar_widget_sync.dart';
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

    // 允许提醒时段变化（含备份恢复）时同步维护入口计数
    ever(_option.allowTime, (value) {
      allowTimeLength.value = value.length;
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

  bool get liveViewEnabled => _option.liveViewEnabled.value;

  set liveViewEnabled(bool value) {
    _option.liveViewEnabled.value = value;
    _db.setLiveViewEnabled(value);
    if (value) {
      if (PlatformFeatures.isOhos) {
        OhosNativeService.instance.requestNotificationPermission();
      }
      ScholarWidgetSync.sync();
    } else {
      OhosNativeService.instance.stopLiveView();
    }
  }

  /// 发送测试实况窗（5分钟倒计时），用于验证系统实况窗支持并在系统设置中激活本应用
  Future<void> sendTestLiveView(BuildContext context) async {
    final granted =
        await OhosNativeService.instance.requestNotificationPermission();
    if (!granted) {
      final hasPerm =
          await OhosNativeService.instance.isNotificationEnabled();
      if (!hasPerm) {
        _showAlertDialog(
          context,
          '提示',
          '未授予通知权限。实况窗底层依赖通知服务体系，请在系统设置中允许 Helechron 发送通知。',
        );
        return;
      }
    }

    final target = DateTime.now().add(const Duration(minutes: 5));
    final ok = await OhosNativeService.instance.updateLiveView(
      phase: 'ongoing',
      title: 'Helechron 课表实况窗测试',
      subtitle: '紫金港西区教学楼 · 5分钟后下课',
      targetTimestamp: target.millisecondsSinceEpoch,
    );

    if (!context.mounted) return;

    if (ok) {
      _showAlertDialog(
        context,
        '测试成功',
        '测试实况窗已发送！\n\n'
        '1. 请查看手机顶部状态栏是否已出现胶囊图标，以及锁屏界面是否出现倒计时。\n\n'
        '2. 成功发送后，系统已将 Helechron 注册至「设置 → 通知和状态栏 → 实况窗」，你现在即可在系统设置中找到并管理本应用。',
      );
    } else {
      final err = OhosNativeService.instance.lastLiveViewError ?? '未知错误';
      String explanation = '实况窗发送失败：\n$err\n\n';
      if (err.contains('401')) {
        explanation +=
            '原因诊断：\nLive View Kit 是华为受限开放能力。需要在华为开发者联盟 (AppGallery Connect) 后台为应用包名 (top.celechron.helechron) 申请「实况窗服务」权益证书。\n当前调试安装包若未关联该权益证书，系统底层会直接返回 401 权限拦截。';
      } else if (err.contains('isLiveViewEnabled=false')) {
        explanation +=
            '原因诊断：\n当前设备的实况窗总开关处于关闭状态，请前往「设置 → 通知和状态栏 → 实况窗」开启系统总开关。';
      } else {
        explanation +=
            '请检查设备是否支持实况窗，以及通知权限是否已开启。';
      }
      _showAlertDialog(context, '实况窗未生效', explanation);
    }
  }

  void _showAlertDialog(BuildContext context, String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
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

  // ==================== 备份与恢复 / iCal 导入 ====================

  final RxInt icsImportKey = 0.obs;
  final RxInt backupActionKey = 0.obs;

  bool _isExportingBackup = false;
  Future<void> exportBackup() async {
    if (_isExportingBackup) return;
    _isExportingBackup = true;
    try {
      await BackupService.exportBackup();
    } finally {
      _isExportingBackup = false;
      backupActionKey.value++;
    }
  }

  bool _isImportingBackup = false;
  Future<void> importBackup() async {
    if (_isImportingBackup) return;
    _isImportingBackup = true;
    try {
      await BackupService.importBackup();
    } finally {
      _isImportingBackup = false;
      backupActionKey.value++;
    }
  }

  bool _isImportingIcs = false;
  Future<void> importIcs() async {
    if (_isImportingIcs) return;
    _isImportingIcs = true;
    try {
      await BackupService.importIcs();
    } finally {
      _isImportingIcs = false;
      icsImportKey.value++;
    }
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
