import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OhosNativeService {
  OhosNativeService._();
  static final OhosNativeService instance = OhosNativeService._();

  static const MethodChannel _channel =
      MethodChannel('top.celechron.helechron/native');

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
}
