import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OhosNativeService {
  OhosNativeService._();
  static final OhosNativeService instance = OhosNativeService._();

  static const MethodChannel _channel =
      MethodChannel('top.celechron.helechron/native');

  /// 最近一次日历同步失败的原生错误信息，用于诊断与向用户展示
  String? lastCalendarError;

  // ==================== Calendar ====================

  /// 检查日历权限
  Future<bool> checkCalendarPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('checkCalendarPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('checkCalendarPermission failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 请求日历权限
  Future<bool> requestCalendarPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('requestCalendarPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('requestCalendarPermission failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 同步课程事件到系统日历
  /// [reminderMinutes] 提前提醒分钟数
  /// [useAlarm] true 使用闹钟代理提醒，false 使用系统日历通知提醒
  /// 返回成功插入的事件数
  Future<int> syncCalendarEvents(
    List<Map<String, dynamic>> events, {
    int reminderMinutes = 15,
    bool useAlarm = false,
  }) async {
    try {
      lastCalendarError = null;
      final result = await _channel.invokeMethod<int>(
        'syncCalendarEvents',
        {
          'events': events,
          'reminderMinutes': reminderMinutes,
          'useAlarm': useAlarm,
        },
      );
      return result ?? 0;
    } on PlatformException catch (e) {
      lastCalendarError = '${e.code}: ${e.message} ${e.details ?? ''}';
      debugPrint('syncCalendarEvents failed: $lastCalendarError');
      return 0;
    } on MissingPluginException {
      lastCalendarError = '原生通道不可用 (MissingPluginException)';
      debugPrint('syncCalendarEvents failed: $lastCalendarError');
      return 0;
    }
  }

  /// 清除已同步的日历事件
  Future<int> clearCalendarEvents() async {
    try {
      final result = await _channel.invokeMethod<int>('clearCalendarEvents');
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('clearCalendarEvents failed: $e');
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// 检查是否存在已同步的 Helechron 日历
  Future<bool> hasSyncedCalendar() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasSyncedCalendar');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('hasSyncedCalendar failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 获取系统日历写入诊断信息（账户、事件总数、本应用事件数）
  Future<String> calendarDiagnostics() async {
    try {
      final result = await _channel.invokeMethod<String>('calendarDiagnostics');
      return result ?? '';
    } on PlatformException catch (e) {
      return 'diagnostics failed: $e';
    } on MissingPluginException {
      return 'native channel unavailable';
    }
  }

  /// 自测：逐步测试日历 API 各环节（权限→获取日历→添加测试事件→回读→清理）
  Future<String> calendarSelfTest() async {
    try {
      final result = await _channel.invokeMethod<String>('calendarSelfTest');
      return result ?? '';
    } on PlatformException catch (e) {
      return 'selfTest platform error: $e';
    } on MissingPluginException {
      return 'selfTest: native channel unavailable';
    }
  }

  // ==================== Notifications ====================

  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('requestNotificationPermission failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('OhosNativeService not available on this platform');
      return false;
    }
  }

  /// 检查是否拥有通知权限
  Future<bool> isNotificationEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isNotificationEnabled');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('isNotificationEnabled failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 发送本地通知
  Future<bool> showNotification({
    required int id,
    required String title,
    required String text,
    String? additionalText,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('showNotification', {
        'id': id,
        'title': title,
        'text': text,
        'additionalText': additionalText ?? '',
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('showNotification failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('showNotification: platform channel not available');
      return false;
    }
  }

  /// 取消特定通知
  Future<bool> cancelNotification(int id) async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelNotification', {
        'id': id,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('cancelNotification failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 取消所有通知
  Future<bool> cancelAllNotifications() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('cancelAllNotifications');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('cancelAllNotifications failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // ==================== Widgets ====================

  /// 向原生 AppStorage 写入小组件数据
  Future<void> setWidgetData(String key, String value) async {
    try {
      await _channel.invokeMethod('setWidgetData', {
        'key': key,
        'value': value,
      });
    } on PlatformException catch (e) {
      debugPrint('setWidgetData failed: $e');
    } on MissingPluginException {
      // Not on HarmonyOS
    }
  }

  /// 更新付款码小组件数据
  Future<void> updatePaymentCodeWidget(String code, String name) async {
    await setWidgetData('paymentCode', code);
    await setWidgetData('displayName', name);
  }

  /// 更新课程小组件数据（下一节课信息）
  /// 格式: "课程名|周几|开始时间戳|结束时间|地点|教师"
  Future<void> updateCourseWidget({
    required String courseName,
    required int weekday,
    required DateTime startTime,
    required DateTime endTime,
    String location = '',
    String teacher = '',
  }) async {
    final data =
        '$courseName|$weekday|${startTime.millisecondsSinceEpoch}|${endTime.millisecondsSinceEpoch}|$location|$teacher';
    await setWidgetData('nextCourse', data);
  }

  /// 清除课程小组件（无课时调用）
  Future<void> clearCourseWidget() async {
    await setWidgetData('nextCourse', '');
  }
}
