import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/utils.dart';

Future<void> refreshScholar() async {
  if (await RefreshCoordinator.shouldYieldBackground()) {
    DiagnosticLogService.instance.record(
      module: 'refresh',
      operation: 'backgroundYield',
      message: '后台任务启动时检测到活跃前台，已正常让行',
      origin: RefreshOrigin.background,
    );
    return;
  }

  // HarmonyOS NEXT: 后台刷新功能暂未实现
  // 后续可通过 HarmonyOS Background Tasks API 实现
  if (kDebugMode) {
    debugPrint('HarmonyOS: 后台刷新功能暂未实现');
  }
}
