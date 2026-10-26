import 'package:hive/hive.dart';

import 'package:celechron/utils/legal_links.dart';

/// 记录用户对隐私政策的同意状态。
///
/// 使用独立 box，保证在数据库初始化之前即可读取，任何网络请求或
/// 学校账号数据读取都必须发生在本类返回 true 之后。
class ConsentStore {
  static const String _boxName = 'consent';
  static const String _agreedVersionKey = 'agreed_policy_version';

  static Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  static Future<bool> hasAgreed() async {
    final box = await _box();
    final agreedVersion = box.get(_agreedVersionKey);
    return agreedVersion is int && agreedVersion >= privacyPolicyVersion;
  }

  static Future<void> agree() async {
    final box = await _box();
    await box.put(_agreedVersionKey, privacyPolicyVersion);
  }

  static Future<void> withdraw() async {
    final box = await _box();
    await box.delete(_agreedVersionKey);
  }
}
