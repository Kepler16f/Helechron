import 'package:hive/hive.dart';

/// 素拓/第二课堂目标分数的轻量持久化工具（存入已开启的 dbOptions Hive Box）
class PracticeTargetHelper {
  static const String _boxName = 'dbOptions';
  static const String _keyPrefix = 'practice_target_cat_';

  static double getTarget(int categoryId) {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        final box = Hive.box(_boxName);
        final val = box.get('$_keyPrefix$categoryId');
        if (val is num) return val.toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  static Future<void> setTarget(int categoryId, double target) async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        final box = Hive.box(_boxName);
        await box.put('$_keyPrefix$categoryId', target);
      }
    } catch (_) {}
  }
}

