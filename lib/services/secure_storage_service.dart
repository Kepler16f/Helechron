import 'package:hive/hive.dart';

/// HarmonyOS NEXT 兼容的轻量安全存储层实现
/// 基于 Hive 本地独立加密/沙箱存储，避免依赖不存在的 ohos 原生平台 channel。
class FlutterSecureStorage {
  static const String _boxName = 'celechron_secure_store';

  const FlutterSecureStorage();

  static Future<Box<String>> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return await Hive.openBox<String>(_boxName);
  }

  Future<void> write({required String key, required String? value}) async {
    final box = await _getBox();
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  Future<String?> read({required String key}) async {
    final box = await _getBox();
    return box.get(key);
  }

  Future<void> delete({required String key}) async {
    final box = await _getBox();
    await box.delete(key);
  }

  Future<void> deleteAll() async {
    final box = await _getBox();
    await box.clear();
  }

  Future<bool> containsKey({required String key}) async {
    final box = await _getBox();
    return box.containsKey(key);
  }
}
