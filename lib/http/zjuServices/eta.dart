import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'exceptions.dart';
import 'response_utils.dart';

/// 浙江大学“三全育人”学生综合信息平台（ETA，eta.zju.edu.cn）服务接口
/// 用于从学工系统（ZFTAL-XGXT）调取学生个人信息、主修专业、学院及学籍数据
class Eta {
  static const String etaCasService =
      "https://eta.zju.edu.cn/zftal-xgxt-web/teacher/xtgl/index/check.zf";
  static const String etaBaseUrl = "https://eta.zju.edu.cn";

  /// 缓存的会话 Cookies（JSESSIONID, route 等）
  static List<Cookie> _cachedCookies = [];
  static DateTime? _cookiesTimestamp;

  /// 清除登录凭据
  static void clearSession() {
    _cachedCookies = [];
    _cookiesTimestamp = null;
  }

  /// 使用统一身份认证凭据获取 ETA 会话 Cookies (JSESSIONID 等)
  static Future<List<Cookie>> login(
      HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    if (iPlanetDirectoryPro == null) {
      throw AuthenticationExpiredException("ETA 平台：统一身份认证凭据无效");
    }

    // 检查缓存的 Session 是否在 5 分钟内且有效
    if (_cachedCookies.isNotEmpty &&
        _cookiesTimestamp != null &&
        DateTime.now().difference(_cookiesTimestamp!).inMinutes < 5) {
      return _cachedCookies;
    }

    late HttpClientRequest request;
    late HttpClientResponse response;

    final List<Cookie> cookies = [];
    final serviceUri = Uri.parse(
        "https://zjuam.zju.edu.cn/cas/login?service=${Uri.encodeComponent(etaCasService)}");

    try {
      request = await httpClient.getUrl(serviceUri).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());
      request.followRedirects = false;
      request.cookies.add(iPlanetDirectoryPro);
      response = await request.close().timeout(const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());

      final firstBody = await readResponseBody(response, context: 'ETA CAS 登录');

      var stLocation = response.headers.value(HttpHeaders.locationHeader);
      if (!response.isRedirect || stLocation == null) {
        throw AuthenticationExpiredException(
            "ETA 登录：统一身份认证未重定向；HTTP ${response.statusCode}；Location: ${stLocation ?? '<缺失>'}；响应摘要：${responseSummary(firstBody)}");
      }

      // 如果重定向地址为 http，转换为 https
      if (stLocation.startsWith("http://")) {
        stLocation = stLocation.replaceFirst("http://", "https://");
      }

      // 访问重定向的 service 回调地址以获取 ETA 会话 Cookie
      var currentUri = Uri.parse(stLocation);
      request = await httpClient.getUrl(currentUri).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());
      request.followRedirects = false;
      response = await request.close().timeout(const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());

      cookies.addAll(response.cookies);

      // 处理多跳重定向直到拿到 200 或进入首页
      for (var redirectCount = 0; redirectCount < 5; redirectCount++) {
        final loc = response.headers.value(HttpHeaders.locationHeader);
        if (response.isRedirect && loc != null) {
          await response.drain();
          var nextLoc = loc;
          if (nextLoc.startsWith("http://")) {
            nextLoc = nextLoc.replaceFirst("http://", "https://");
          }
          currentUri = currentUri.resolve(nextLoc);
          request = await httpClient.getUrl(currentUri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          request.followRedirects = false;
          request.cookies.addAll(cookies);
          response = await request.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          cookies.addAll(response.cookies);
        } else {
          break;
        }
      }

      await response.drain();

      if (cookies.isEmpty) {
        throw ExceptionWithMessage("ETA 登录无法获取会话 Cookie");
      }

      _cachedCookies = cookies;
      _cookiesTimestamp = DateTime.now();
      return _cachedCookies;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ETA 登录失败: $e');
      }
      rethrow;
    }
  }

  /// 从 ETA 获取学生个人基础信息（包含主修专业、学院、学号、姓名等）
  static Future<Map<String, dynamic>?> getStudentInfo(
      HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    try {
      final cookies = await login(httpClient, iPlanetDirectoryPro);

      // 依次尝试 ETA 的两个主要用户信息接口
      final endpoints = [
        "https://eta.zju.edu.cn/zftal-xgxt-web/teacher/xtgl/login/getCurrentUser.zf",
        "https://eta.zju.edu.cn/zftal-xgxt-web/xsxx/xsxxxg/firstLogin.zf",
        "https://eta.zju.edu.cn/zftal-xgxt-web/xsxx/xsxxxg/tableData.zf",
      ];

      for (final endpoint in endpoints) {
        try {
          final uri = Uri.parse(endpoint);
          final request = await httpClient.getUrl(uri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          request.headers
            ..add("Referer", "https://eta.zju.edu.cn/")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('X-Requested-With', 'XMLHttpRequest')
            ..add('Accept', 'application/json, text/plain, */*');

          request.cookies.addAll(cookies);
          final response = await request.close().timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());

          final body = await readResponseBody(response, context: 'ETA 学生信息接口');
          if (response.statusCode == 200 && body.isNotEmpty) {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) {
              // 检查返回的数据节点
              Map<String, dynamic>? dataMap;
              if (decoded.containsKey('data') && decoded['data'] is Map) {
                dataMap = decoded['data'] as Map<String, dynamic>;
              } else {
                dataMap = decoded;
              }

              // 尝试从中提取专业名称
              final major = _extractMajorFromMap(dataMap);
              if (major != null && major.isNotEmpty) {
                return dataMap;
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('尝试 ETA 接口 $endpoint 失败: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ETA 获取学生信息流程失败: $e');
      }
    }
    return null;
  }

  /// 从 ETA 获取主修专业名称
  static Future<String?> getStudentMajor(
      HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    try {
      final info = await getStudentInfo(httpClient, iPlanetDirectoryPro);
      if (info != null) {
        return _extractMajorFromMap(info);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ETA 获取主修专业失败: $e');
      }
    }
    return null;
  }

  /// 从 Map 数据中解析专业名称
  static String? _extractMajorFromMap(Map<String, dynamic> map) {
    final candidateKeys = [
      'zymc',
      'ZYMC',
      'majorName',
      'major',
      'zyfxmc',
      'ZYFXMC',
      'evalMajor',
      'bmmc',
      'xymc',
      'XYMC',
      'collegeName',
    ];

    for (final key in candidateKeys) {
      if (map.containsKey(key)) {
        final val = map[key];
        if (val is String &&
            val.trim().isNotEmpty &&
            val.trim() != '未知' &&
            val.trim() != '无') {
          return val.trim();
        }
      }
    }
    return null;
  }
}
