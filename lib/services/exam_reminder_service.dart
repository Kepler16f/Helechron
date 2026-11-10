import 'dart:convert';

import 'package:get/get.dart';

import 'package:celechron/model/exam.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:celechron/utils/json_utils.dart';

class ExamReminderService {
  ExamReminderService._();

  static const String _notifiedKey = 'notifiedExamIds';
  static bool _permissionCheckedThisSession = false;
  static DateTime _lastCheckAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 检查是否有即将开始的考试（考前 1 小时内），索取通知权限并发送考前提醒通知。
  static Future<void> checkAndNotifyUpcomingExams(
    Scholar scholar, {
    bool requestPermissionIfNeeded = false,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastCheckAt) < const Duration(seconds: 45)) {
      return;
    }
    _lastCheckAt = now;

    const secureStorage = FlutterSecureStorage();
    bool enabled = true;
    if (Get.isRegistered<Option>(tag: 'option')) {
      enabled = Get.find<Option>(tag: 'option').pushOnExamReminder.value;
    } else {
      final stored = await secureStorage.read(key: 'pushOnExamReminder');
      enabled = stored != 'false';
    }
    if (!enabled) return;

    final exams = <Exam>[
      for (final semester in scholar.semesters) ...semester.exams,
    ];
    if (exams.isEmpty) return;

    // 若未来 7 天内有考试且尚未在本会话检查通知权限，主动请求通知权限
    final hasUpcomingInWeek = exams.any((e) {
      if (e.time.isEmpty) return false;
      final diff = e.time.first.difference(now);
      return !diff.isNegative && diff <= const Duration(days: 7);
    });

    if (requestPermissionIfNeeded &&
        hasUpcomingInWeek &&
        !_permissionCheckedThisSession) {
      _permissionCheckedThisSession = true;
      final granted = await OhosNativeService.instance.isNotificationEnabled();
      if (!granted) {
        await OhosNativeService.instance.requestNotificationPermission();
      }
    }

    // 读取已提醒过的考试 ID 集合
    final notifiedRaw = await secureStorage.read(key: _notifiedKey);
    final notifiedIds = <String>{};
    if (notifiedRaw != null && notifiedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(notifiedRaw);
        notifiedIds.addAll(
          (asDynamicList(decoded) ?? const [])
              .map(asString)
              .whereType<String>(),
        );
      } catch (_) {}
    }

    var notifiedChanged = false;
    var notificationId = 2000;
    for (final exam in exams) {
      if (exam.time.isEmpty) continue;
      final start = exam.time.first;
      final diffMinutes = start.difference(now).inMinutes;
      final key = '${exam.id}_${exam.type.name}_${start.millisecondsSinceEpoch}';

      // 考前 1~65 分钟内触发考前提醒
      if (diffMinutes >= 0 && diffMinutes <= 65 && !notifiedIds.contains(key)) {
        final hh = start.hour.toString().padLeft(2, '0');
        final mm = start.minute.toString().padLeft(2, '0');
        final loc = (exam.location != null && exam.location!.trim().isNotEmpty)
            ? exam.location!.trim()
            : '待定考场';
        final seat = (exam.seat != null && exam.seat!.trim().isNotEmpty)
            ? ' · 座位 ${exam.seat!.trim()}'
            : '';

        await OhosNativeService.instance.showNotification(
          id: notificationId++,
          title: '考前提醒 · ${exam.name}',
          text:
              '$hh:$mm 开考（剩余约 $diffMinutes 分钟）｜$loc$seat。请带好校园卡/学生证、身份证、2B铅笔与黑色水笔！',
        );
        notifiedIds.add(key);
        notifiedChanged = true;
      }
    }

    // 清理已过期的考试记录
    final beforeLen = notifiedIds.length;
    notifiedIds.removeWhere((k) {
      final parts = k.split('_');
      if (parts.isEmpty) return true;
      final ms = int.tryParse(parts.last);
      if (ms == null) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return now.difference(dt) > const Duration(days: 2);
    });
    if (notifiedIds.length != beforeLen) {
      notifiedChanged = true;
    }

    if (notifiedChanged) {
      await secureStorage.write(
        key: _notifiedKey,
        value: jsonEncode(notifiedIds.toList()),
      );
    }
  }
}
