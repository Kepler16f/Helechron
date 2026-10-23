import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/worker/background_app_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

const String _taskName = 'top.celechron.aelechron.backgroundScholarFetch';

/// workmanager 后台入口（Android WorkManager / iOS BGTaskScheduler）。
@pragma('vm:entry-point')
void mobileBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Hive.initFlutter();
      await refreshScholar();
      return true;
    } catch (e) {
      debugPrint('background refresh failed: $e');
      return false;
    }
  });
}

/// 注册 Android / iOS 的 15 分钟周期后台刷新（用于成绩变动与 DDL 提醒）。
Future<void> registerMobileBackgroundRefresh() async {
  if (!PlatformFeatures.usesFlutterPlugins) return;
  try {
    await Workmanager().initialize(mobileBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint('registerMobileBackgroundRefresh failed: $e');
  }
}

