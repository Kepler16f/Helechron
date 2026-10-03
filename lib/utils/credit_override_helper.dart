import 'package:hive/hive.dart';

/// 课程在学分看板内部的自定义计算覆盖规则（仅影响学分看板自身统计）
enum CourseCreditOverride {
  none,
  excludeCredit, // 不计入学分（亦不计入绩点）
  excludeGpa, // 不计入绩点（但计入学分）
}

class CreditOverrideHelper {
  static const String _boxName = 'dbOptions';
  static const String _prefix = 'credit_override_';

  static CourseCreditOverride getOverride(String courseId) {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        final box = Hive.box(_boxName);
        final val = box.get('$_prefix$courseId');
        if (val == 'excludeCredit') return CourseCreditOverride.excludeCredit;
        if (val == 'excludeGpa') return CourseCreditOverride.excludeGpa;
      }
    } catch (_) {}
    return CourseCreditOverride.none;
  }

  static Future<void> setOverride(
      String courseId, CourseCreditOverride override) async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        final box = Hive.box(_boxName);
        if (override == CourseCreditOverride.none) {
          await box.delete('$_prefix$courseId');
        } else {
          await box.put('$_prefix$courseId', override.name);
        }
      }
    } catch (_) {}
  }
}

