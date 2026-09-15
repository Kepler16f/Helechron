import 'dart:convert';

import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:celechron/utils/json_utils.dart';
import 'package:flutter/foundation.dart';

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

  final nativeService = OhosNativeService.instance;
  final scholar = Scholar();
  const secureStorage = FlutterSecureStorage();

  final username = await secureStorage.read(key: 'username');
  final password = await secureStorage.read(key: 'password');
  scholar.username = username;
  scholar.password = password;

  final oldGpa = await secureStorage.read(key: 'gpa') ?? '0.0';
  final gradedCourseCount =
      await secureStorage.read(key: 'gradedCourseCount') ?? '0';
  final pushOnGradeChangeFuse =
      await secureStorage.read(key: 'pushOnGradeChangeFuse');
  final pushOnGradeChange = await secureStorage.read(key: 'pushOnGradeChange');
  final pushOnDdlReminder = await secureStorage.read(key: 'pushOnDdlReminder');
  final notifiedDdlIdsStr = await secureStorage.read(key: 'notifiedDdlIds');

  try {
    var backgroundYielded = false;
    final refreshErrors = await scholar.refresh(
      origin: RefreshOrigin.background,
      onBackgroundYield: () => backgroundYielded = true,
    );
    if (backgroundYielded) return;

    if (refreshErrors.whereType<String>().any((error) =>
        isDegradedRefreshText(error) && shortErrorText(error).contains('刷新'))) {
      return;
    }

    bool failed(String interfaceName) => refreshErrors
        .whereType<String>()
        .any((error) => shortErrorText(error).contains(interfaceName));

    // 成绩变动通知
    if (pushOnGradeChange != 'false' && !failed('成绩')) {
      if (pushOnGradeChangeFuse == null) {
        await nativeService.showNotification(
          id: 100,
          title: '首次成绩推送',
          text: '若有新出分的课程，Helechron 将会通知您。若不需要此功能，可在设置中关闭。',
        );
        await secureStorage.write(
          key: 'pushOnGradeChangeFuse',
          value: '1',
        );
      } else if (scholar.gpa[0] != double.tryParse(oldGpa) ||
          scholar.gradedCourseCount != int.tryParse(gradedCourseCount)) {
        await nativeService.showNotification(
          id: 101,
          title: '成绩变动提醒',
          text: '有新出分的课程，可在 Helechron 的学业页面中刷新查看。',
        );
      }
      await secureStorage.write(
        key: 'gpa',
        value: scholar.gpa[0].toString(),
      );
      await secureStorage.write(
        key: 'gradedCourseCount',
        value: scholar.gradedCourseCount.toString(),
      );
    }

    // DDL 截止提醒
    if (pushOnDdlReminder != 'false' && !failed('作业')) {
      Set<String> notifiedDdlIds = {};
      if (notifiedDdlIdsStr != null && notifiedDdlIdsStr.isNotEmpty) {
        final decoded = jsonDecode(notifiedDdlIdsStr);
        notifiedDdlIds = (asDynamicList(decoded) ?? const [])
            .map(asString)
            .whereType<String>()
            .toSet();
      }

      final now = DateTime.now();
      final upcomingTodos = scholar.todos.where((todo) {
        if (todo.endTime == null) return false;
        final timeLeft = todo.endTime!.difference(now);
        return timeLeft.inHours >= 0 &&
            timeLeft.inHours <= 24 &&
            !notifiedDdlIds.contains(todo.id);
      }).toList();

      if (upcomingTodos.isNotEmpty) {
        var notificationId = 1000;
        for (final todo in upcomingTodos) {
          final hoursLeft = todo.endTime!.difference(now).inHours;
          final timeDesc = hoursLeft > 0 ? '$hoursLeft 小时后' : '即将';
          await nativeService.showNotification(
            id: notificationId++,
            title: '作业截止提醒',
            text: '「${todo.course}」的作业「${todo.name}」将于$timeDesc截止',
          );
          notifiedDdlIds.add(todo.id);
        }
      }

      notifiedDdlIds.removeWhere((id) {
        final todo = scholar.todos.where((t) => t.id == id);
        if (todo.isEmpty) return true;
        return todo.first.endTime != null && todo.first.endTime!.isBefore(now);
      });

      await secureStorage.write(
        key: 'notifiedDdlIds',
        value: jsonEncode(notifiedDdlIds.toList()),
      );
    }
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('后台学业刷新失败：${error.runtimeType}: $error\n$stackTrace');
    }
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.warning,
      module: '后台刷新',
      operation: 'refreshScholar',
      message: '后台学业刷新遇到未捕获异常',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
