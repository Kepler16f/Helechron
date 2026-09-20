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

  /// 向原生写入小组件数据（通用键值）
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
  Future<void> updatePaymentCodeWidget({
    required String code,
    String displayName = '浙大校园卡付款码',
  }) async {
    try {
      await _channel.invokeMethod('updatePaymentCodeWidget', {
        'paymentCode': code,
        'displayName': displayName,
      });
    } on PlatformException catch (e) {
      debugPrint('updatePaymentCodeWidget failed: $e');
    } on MissingPluginException {
      // Not on HarmonyOS
    }
  }

  /// 将校园卡鉴权凭据写入小组件本地存储，
  /// 供桌面小组件的「刷新」按钮在原生侧直接重新取码（无需拉起应用）。
  Future<void> setPaymentCredentials({
    required String synjonesAuth,
    required String eCardAccount,
  }) async {
    try {
      await _channel.invokeMethod('setPaymentCredentials', {
        'synjonesAuth': synjonesAuth,
        'eCardAccount': eCardAccount,
      });
    } on PlatformException catch (e) {
      debugPrint('setPaymentCredentials failed: $e');
    } on MissingPluginException {
      // Not on HarmonyOS
    }
  }

  /// 更新课程小组件数据。
  ///
  /// [coursesJson] 为后续若干节课的紧凑 JSON 数组，字段：
  /// `s` 开始时间戳(ms)、`e` 结束时间戳(ms)、`n` 课程名、`t` 时间区间、
  /// `l` 地点、`c` 教师。状态/倒计时/进度/当前课程选择均由原生侧依据
  /// 当前时间计算，因此系统级刷新（定时、下次刷新）无需 Dart 参与，
  /// 应用被杀后也能正确切换课程。
  Future<void> updateCourseWidget({
    required String coursesJson,
    required int leadWindowMinutes,
  }) async {
    try {
      await _channel.invokeMethod('updateCourseWidget', {
        'coursesJson': coursesJson,
        'leadWindowMinutes': leadWindowMinutes,
      });
    } on PlatformException catch (e) {
      debugPrint('updateCourseWidget failed: $e');
    } on MissingPluginException {
      // Not on HarmonyOS
    }
  }

  /// 清除课程小组件（无课或已全部结课）
  Future<void> clearCourseWidget() async {
    await updateCourseWidget(coursesJson: '[]', leadWindowMinutes: 120);
  }

  /// 设置底部 Tab 栏样式（鸿蒙原生 ArkTS 接口）
  /// [materialLevel] 沉浸光感强度档位：10=跟随系统 0=精致 1=柔和 2=流畅
  Future<void> setBottomBarStyle({
    required bool floating,
    required bool immersiveLight,
    int materialLevel = 10,
  }) async {
    try {
      await _channel.invokeMethod('setBottomBarStyle', {
        'floating': floating,
        'immersiveLight': immersiveLight,
        'materialLevel': materialLevel,
      });
    } on PlatformException catch (e) {
      debugPrint('setBottomBarStyle failed: $e');
    } on MissingPluginException {}
  }

  /// 通知原生侧当前选中 Tab
  Future<void> setCurrentTab(int index) async {
    try {
      await _channel.invokeMethod('setCurrentTab', {'index': index});
    } on PlatformException catch (e) {
      debugPrint('setCurrentTab failed: $e');
    } on MissingPluginException {}
  }

  /// 显示/隐藏原生底栏（弹出 Flutter 模态窗口时隐藏，避免遮挡弹窗）
  Future<void> setBottomBarVisible(bool visible) async {
    try {
      await _channel.invokeMethod('setBottomBarVisible', {'visible': visible});
    } on PlatformException catch (e) {
      debugPrint('setBottomBarVisible failed: $e');
    } on MissingPluginException {}
  }

  // ==================== Widget Routes & Native Tab ====================

  static void Function(String target)? _widgetRouteHandler;
  static void Function(int index)? _nativeTabHandler;
  static bool _routeHandlerInstalled = false;

  /// 注册小组件点击跳转回调（原生 -> Dart）。
  void installWidgetRouteHandler(void Function(String target) handler) {
    _widgetRouteHandler = handler;
    _ensureIncomingHandlerInstalled();
  }

  /// 注册原生底栏 Tab 切换回调（原生 -> Dart）。
  void installNativeTabHandler(void Function(int index) handler) {
    _nativeTabHandler = handler;
    _ensureIncomingHandlerInstalled();
  }

  static void _ensureIncomingHandlerInstalled() {
    if (_routeHandlerInstalled) return;
    _routeHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWidgetRoute':
          final args = call.arguments;
          if (args is Map && args['target'] is String) {
            _widgetRouteHandler?.call(args['target'] as String);
          }
          return null;
        case 'onNativeTabChanged':
          final args = call.arguments;
          if (args is Map && args['index'] is int) {
            _nativeTabHandler?.call(args['index'] as int);
          }
          return null;
        default:
          throw MissingPluginException(
              'Unsupported native method: ${call.method}');
      }
    });
  }

  /// 领取冷启动时由小组件传入的待处理路由。
  Future<String?> consumePendingRoute() async {
    try {
      final route = await _channel.invokeMethod<String>('consumePendingRoute');
      if (route != null && route.isNotEmpty) {
        return route;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('consumePendingRoute failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
