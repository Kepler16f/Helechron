import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/design/app_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppNotification 深浅色自适应与通知样式测试', () {
    test('isDark 在测试环境下能够安全返回布尔值而不抛出异常', () {
      expect(AppNotification.isDark, isA<bool>());
    });
  });
}
