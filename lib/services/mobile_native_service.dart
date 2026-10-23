import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Android / iOS 上的原生能力实现（基于 Flutter 插件）。
///
/// 接口形态与 [OhosNativeService] 中对应方法保持一致，
/// 由 OhosNativeService 在非鸿蒙平台自动转发到这里。
class MobileNativeService {
  MobileNativeService._();
  static final MobileNativeService instance = MobileNativeService._();

  static const String calendarName = 'Aelechron课表';
  static const String _notificationChannelId = 'aelechron_default';
  static const String _notificationChannelName = '成绩与 DDL 提醒';

  String? lastCalendarError;
  String? lastFilePickError;

  // ==================== Calendar ====================

  final DeviceCalendarPlugin _calendar = DeviceCalendarPlugin();

  Future<bool> checkCalendarPermission() async {
    try {
      final r = await _calendar.hasPermissions();
      return r.isSuccess && (r.data ?? false);
    } catch (e) {
      debugPrint('checkCalendarPermission failed: $e');
      return false;
    }
  }

  Future<bool> requestCalendarPermission() async {
    try {
      final r = await _calendar.requestPermissions();
      return r.isSuccess && (r.data ?? false);
    } catch (e) {
      debugPrint('requestCalendarPermission failed: $e');
      return false;
    }
  }

  Future<Calendar?> _findCalendar() async {
    final r = await _calendar.retrieveCalendars();
    if (!r.isSuccess) return null;
    for (final c in r.data ?? const <Calendar>[]) {
      if (c.name == calendarName) return c;
    }
    return null;
  }

  Future<String?> _getOrCreateCalendarId() async {
    final existing = await _findCalendar();
    if (existing?.id != null) return existing!.id;
    final created = await _calendar.createCalendar(
      calendarName,
      localAccountName: 'Aelechron',
    );
    if (created.isSuccess && created.data != null) return created.data;
    // 创建失败时回退到任意可写日历
    final all = await _calendar.retrieveCalendars();
    for (final c in all.data ?? const <Calendar>[]) {
      if (c.isReadOnly == false && c.id != null) return c.id;
    }
    lastCalendarError = created.errors.map((e) => e.errorMessage).join('; ');
    return null;
  }

  Future<int> syncCalendarEvents(
    List<Map<String, dynamic>> events, {
    int reminderMinutes = 15,
    bool useAlarm = false,
  }) async {
    try {
      lastCalendarError = null;
      if (!await checkCalendarPermission() &&
          !await requestCalendarPermission()) {
        lastCalendarError = '未授予日历权限';
        return 0;
      }
      // 先清掉旧的，避免重复
      await clearCalendarEvents();
      final calendarId = await _getOrCreateCalendarId();
      if (calendarId == null) {
        lastCalendarError ??= '无法创建或找到可写日历';
        return 0;
      }
      var added = 0;
      for (final e in events) {
        final start = tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.UTC, (e['startTime'] as num).toInt());
        final end = tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.UTC, (e['endTime'] as num).toInt());
        final event = Event(
          calendarId,
          title: e['summary']?.toString(),
          description: e['description']?.toString(),
          location: e['location']?.toString(),
          start: start,
          end: end,
          reminders: [Reminder(minutes: reminderMinutes)],
        );
        final r = await _calendar.createOrUpdateEvent(event);
        if (r?.isSuccess ?? false) {
          added++;
        } else {
          lastCalendarError ??=
              r?.errors.map((x) => x.errorMessage).join('; ') ?? '写入失败';
        }
      }
      return added;
    } catch (e) {
      lastCalendarError = '$e';
      debugPrint('syncCalendarEvents failed: $e');
      return 0;
    }
  }

  Future<int> clearCalendarEvents() async {
    try {
      var count = 0;
      while (true) {
        final c = await _findCalendar();
        if (c?.id == null) break;
        final r = await _calendar.deleteCalendar(c!.id!);
        if (!(r.isSuccess && (r.data ?? false))) break;
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('clearCalendarEvents failed: $e');
      return 0;
    }
  }

  Future<bool> hasSyncedCalendar() async {
    try {
      return (await _findCalendar()) != null;
    } catch (_) {
      return false;
    }
  }

  Future<String> calendarDiagnostics() async {
    try {
      final r = await _calendar.retrieveCalendars();
      final list = r.data ?? const <Calendar>[];
      final mine = list.where((c) => c.name == calendarName).length;
      return '日历总数=${list.length}，Aelechron 日历=$mine';
    } catch (e) {
      return 'diagnostics failed: $e';
    }
  }

  Future<String> calendarSelfTest() async {
    final perm = await checkCalendarPermission();
    return 'permission=$perm, ${await calendarDiagnostics()}';
  }

  // ==================== Notifications ====================

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _notificationsInitialized = true;
  }

  Future<bool> requestNotificationPermission() async {
    try {
      await _ensureNotificationsInitialized();
      if (Platform.isAndroid) {
        final impl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.requestNotificationsPermission() ?? false;
      }
      final impl = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await impl?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    } catch (e) {
      debugPrint('requestNotificationPermission failed: $e');
      return false;
    }
  }

  Future<bool> isNotificationEnabled() async {
    try {
      await _ensureNotificationsInitialized();
      if (Platform.isAndroid) {
        final impl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.areNotificationsEnabled() ?? false;
      }
      final impl = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final p = await impl?.checkPermissions();
      return p?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showNotification({
    required int id,
    required String title,
    required String text,
    String? additionalText,
  }) async {
    try {
      await _ensureNotificationsInitialized();
      await _notifications.show(
        id,
        title,
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            _notificationChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('showNotification failed: $e');
      return false;
    }
  }

  Future<bool> cancelNotification(int id) async {
    try {
      await _ensureNotificationsInitialized();
      await _notifications.cancel(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelAllNotifications() async {
    try {
      await _ensureNotificationsInitialized();
      await _notifications.cancelAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==================== File Picker ====================

  Future<Map<String, String>?> pickTextFile() async {
    try {
      lastFilePickError = null;
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return null;
      final f = files.first;
      final path = f.path;
      if (path == null) return null;
      final content = await File(path).readAsString();
      if (content.isEmpty) return null;
      return {'name': f.name, 'content': content};
    } catch (e) {
      lastFilePickError = '$e';
      debugPrint('pickTextFile failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> pickAnyFiles({int maxCount = 10}) async {
    try {
      lastFilePickError = null;
      final files = await FilePicker.pickFiles(type: FileType.any);
      final list = <Map<String, dynamic>>[];
      for (final f in files.take(maxCount)) {
        final path = f.path;
        if (path == null) continue;
        final Uint8List bytes = await File(path).readAsBytes();
        if (bytes.isEmpty) continue;
        list.add({'name': f.name, 'size': bytes.length, 'bytes': bytes});
      }
      return list;
    } catch (e) {
      lastFilePickError = '$e';
      debugPrint('pickAnyFiles failed: $e');
      return [];
    }
  }
}

