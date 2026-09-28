import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 浙大智云课堂（Zhiyun Classroom）直达服务
class ZhiyunService {
  ZhiyunService._();

  static const String _kZhiyunBaseUrl = 'https://classroom.zju.edu.cn';

  /// 提取纯净课程名称（去除（甲）、（乙）、教学班序号等，提高智云课堂检索命中率）
  static String cleanCourseName(String courseName) {
    var cleaned = courseName.trim();
    // 替换中文全角括号为半角便于统一处理
    cleaned = cleaned.replaceAll('（', '(').replaceAll('）', ')');
    // 去除末尾诸如 (01), (02) 的班级编号
    cleaned = cleaned.replaceAll(RegExp(r'\(\d+\)$'), '');
    return cleaned.trim();
  }

  /// 构建智云课堂课程关键字检索直达 URL
  static String buildSearchUrl(String courseName) {
    final keyword = cleanCourseName(courseName);
    return '$_kZhiyunBaseUrl/search?keywords=${Uri.encodeComponent(keyword)}';
  }

  /// 智云课堂首页/个人空间门户 URL
  static String buildPortalUrl() {
    return _kZhiyunBaseUrl;
  }

  /// 智云课堂 SSO 统一身份认证直达 URL
  static String buildSsoLoginUrl() {
    return 'https://zjuam.zju.edu.cn/cas/login?service=${Uri.encodeComponent(_kZhiyunBaseUrl)}';
  }

  /// 调起外部浏览器打开指定课程的智云课堂页面
  static Future<bool> openCourse(String courseName) async {
    final url = buildSearchUrl(courseName);
    try {
      return await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('打开智云课堂失败: $e');
      return false;
    }
  }

  /// 复制课程直达链接到剪贴板
  static Future<void> copyCourseLink(
      BuildContext context, String courseName) async {
    final url = buildSearchUrl(courseName);
    await Clipboard.setData(ClipboardData(text: url));
  }
}
