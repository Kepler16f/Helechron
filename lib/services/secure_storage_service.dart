import 'package:hive/hive.dart';

/// HarmonyOS NEXT 兼容的轻量安全存储层实现
/// 基于 Hive 本地沙箱存储，避免依赖不存在的 ohos 原生平台 channel。
///
/// 说明：手机端应用沙箱本身即为私有目录，配合 Hive 独立 box 存储敏感数据。
/// 若后续需要强加密，可在此接入 HarmonyOS Crypto Architecture Kit。
class FlutterSecureStorage {
  static const String _boxName = 'celechron_secure_store';

  static final Map<String, String> _mockStore = <String, String>{};
  static bool _useMock = false;

  const FlutterSecureStorage();

  /// 测试辅助方法，模拟原始插件 API。
  static void setMockInitialValues(Map<String, String> values) {
    _useMock = true;
    _mockStore
      ..clear()
      ..addAll(values);
  }

  static Future<Box<String>> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return await Hive.openBox<String>(_boxName);
  }

  Future<void> write({required String key, required String? value}) async {
    if (_useMock) {
      if (value == null) {
        _mockStore.remove(key);
      } else {
        _mockStore[key] = value;
      }
      return;
    }
    final box = await _getBox();
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  Future<String?> read({required String key}) async {
    if (_useMock) {
      return _mockStore[key];
    }
    final box = await _getBox();
    return box.get(key);
  }

  Future<Map<String, String>> readAll() async {
    if (_useMock) {
      return Map<String, String>.from(_mockStore);
    }
    final box = await _getBox();
    return box
        .toMap()
        .map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  Future<void> delete({required String key}) async {
    if (_useMock) {
      _mockStore.remove(key);
      return;
    }
    final box = await _getBox();
    await box.delete(key);
  }

  Future<void> deleteAll() async {
    if (_useMock) {
      _mockStore.clear();
      return;
    }
    final box = await _getBox();
    await box.clear();
  }

  Future<bool> containsKey({required String key}) async {
    if (_useMock) {
      return _mockStore.containsKey(key);
    }
    final box = await _getBox();
    return box.containsKey(key);
  }
}
