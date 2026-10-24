// HarmonyOS 构建用桩实现：鸿蒙端的原生能力由 ArkTS 通道提供，
// 构建时由 CI 覆盖 lib/services/mobile_native_service.dart，避免引入 Android/iOS 专用插件。
class MobileNativeService {
  MobileNativeService._();
  static final MobileNativeService instance = MobileNativeService._();

  String? lastCalendarError;
  String? lastFilePickError;

  Future<bool> checkCalendarPermission() async => false;
  Future<bool> requestCalendarPermission() async => false;
  Future<int> syncCalendarEvents(
    List<Map<String, dynamic>> events, {
    int reminderMinutes = 15,
    bool useAlarm = false,
  }) async =>
      0;
  Future<int> clearCalendarEvents() async => 0;
  Future<bool> hasSyncedCalendar() async => false;
  Future<String> calendarDiagnostics() async => '';
  Future<String> calendarSelfTest() async => '';
  Future<bool> requestNotificationPermission() async => false;
  Future<bool> isNotificationEnabled() async => false;
  Future<bool> showNotification({
    required int id,
    required String title,
    required String text,
    String? additionalText,
  }) async =>
      false;
  Future<bool> cancelNotification(int id) async => false;
  Future<bool> cancelAllNotifications() async => false;
  Future<Map<String, String>?> pickTextFile() async => null;
  Future<List<Map<String, dynamic>>> pickAnyFiles({int maxCount = 10}) async =>
      [];

  void ensureWidgetHandler(void Function(String target) handler) {}
  Future<void> updateCourseWidget({
    required String coursesJson,
    required int leadWindowMinutes,
  }) async {}
  Future<void> updatePaymentCodeWidget({
    required String code,
    String displayName = '付款码',
  }) async {}
  Future<void> setWidgetData(String key, String value) async {}
  Future<String?> consumePendingRoute() async => null;
}
