import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'exceptions.dart';
import 'response_utils.dart';

/// 浙江大学“三全育人”学生综合信息平台（ETA，eta.zju.edu.cn）服务接口
/// 用于从学工系统调取学生个人信息、主修专业、学院及学籍数据
class Eta {
  static const String etaCasService = "https://eta.zju.edu.cn/";
  static const String etaBaseUrl = "https://eta.zju.edu.cn";

  /// 缓存的会话 Cookies（JSESSIONID, SESSION, route 等）
  static List<Cookie> _cachedCookies = [];
  static DateTime? _cookiesTimestamp;

  /// 清除登录凭据
  static void clearSession() {
    _cachedCookies = [];
    _cookiesTimestamp = null;
  }

  /// 使用统一身份认证凭据获取 ETA 会话 Cookies (JSESSIONID, SESSION 等)
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

    final services = [
      "https://eta.zju.edu.cn/",
      "https://eta.zju.edu.cn/zftal-xgxt-web/student/xtgl/index/check.zf",
      "http://eta.zju.edu.cn/",
    ];

    for (final srv in services) {
      try {
        final List<Cookie> cookies = [];
        final serviceUri = Uri.parse(
            "https://zjuam.zju.edu.cn/cas/login?service=${Uri.encodeComponent(srv)}");

        final request = await httpClient.getUrl(serviceUri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        request.followRedirects = false;
        request.cookies.add(iPlanetDirectoryPro);
        final response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        var stLocation = response.headers.value(HttpHeaders.locationHeader);
        if (!response.isRedirect || stLocation == null) {
          await response.drain();
          continue;
        }

        if (stLocation.startsWith("http://")) {
          stLocation = stLocation.replaceFirst("http://", "https://");
        }

        var currentUri = Uri.parse(stLocation);
        var req = await httpClient.getUrl(currentUri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        req.followRedirects = false;
        var resp = await req.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        cookies.addAll(resp.cookies);

        for (var redirectCount = 0; redirectCount < 5; redirectCount++) {
          final loc = resp.headers.value(HttpHeaders.locationHeader);
          if (resp.isRedirect && loc != null) {
            await resp.drain();
            var nextLoc = loc;
            if (nextLoc.startsWith("http://")) {
              nextLoc = nextLoc.replaceFirst("http://", "https://");
            }
            currentUri = currentUri.resolve(nextLoc);
            req = await httpClient.getUrl(currentUri).timeout(
                const Duration(seconds: 8),
                onTimeout: () => throw requestTimeout());
            req.followRedirects = false;
            req.cookies.addAll(cookies);
            resp = await req.close().timeout(const Duration(seconds: 8),
                onTimeout: () => throw requestTimeout());
            cookies.addAll(resp.cookies);
          } else {
            break;
          }
        }

        await resp.drain();

        if (cookies.isNotEmpty) {
          _cachedCookies = cookies;
          _cookiesTimestamp = DateTime.now();
          return _cachedCookies;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('尝试 ETA CAS 服务 $srv 失败: $e');
        }
      }
    }

    if (_cachedCookies.isNotEmpty) return _cachedCookies;
    throw ExceptionWithMessage("ETA 登录无法获取有效会话 Cookie");
  }

  /// 从 ETA 获取学生个人基础信息（包含主修专业、学院、学号、姓名等）
  static Future<Map<String, dynamic>?> getStudentInfo(
      HttpClient httpClient, Cookie? iPlanetDirectoryPro, {String? studentId}) async {
    try {
      final cookies = await login(httpClient, iPlanetDirectoryPro);

      final endpoints = [
        "https://eta.zju.edu.cn/api/user/info",
        "https://eta.zju.edu.cn/api/student/current",
        "https://eta.zju.edu.cn/api/student/info",
        "https://eta.zju.edu.cn/zftal-xgxt-web/xsxx/xsxxxg/firstLogin.zf",
        "https://eta.zju.edu.cn/zftal-xgxt-web/xsxx/xsxxxg/tableData.zf",
        "https://eta.zju.edu.cn/zftal-xgxt-web/student/xtgl/index/index.zf",
        "https://eta.zju.edu.cn/",
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
            ..add('Accept', 'application/json, text/html, */*');

          request.cookies.addAll(cookies);
          final response = await request.close().timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());

          final body = await readResponseBody(response, context: 'ETA 学生信息接口');
          if (response.statusCode == 200 && body.isNotEmpty) {
            try {
              final decoded = jsonDecode(body);
              if (decoded is Map<String, dynamic>) {
                Map<String, dynamic>? dataMap;
                if (decoded.containsKey('data') && decoded['data'] is Map) {
                  dataMap = decoded['data'] as Map<String, dynamic>;
                } else {
                  dataMap = decoded;
                }

                final major = _extractMajorFromMap(dataMap);
                if (major != null && major.isNotEmpty) {
                  return dataMap;
                }
              }
            } catch (_) {}

            // 若返回为 HTML，尝试从页面脚本或文本正则提取
            final majorFromHtml = _extractMajorFromText(body);
            if (majorFromHtml != null && majorFromHtml.isNotEmpty) {
              return {'majorName': majorFromHtml};
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
      HttpClient httpClient, Cookie? iPlanetDirectoryPro, {String? studentId}) async {
    try {
      final info = await getStudentInfo(httpClient, iPlanetDirectoryPro, studentId: studentId);
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

  /// 从 HTML 源码或嵌入 JSON 文本中提取专业全称
  static String? _extractMajorFromText(String text) {
    final patterns = [
      RegExp(r'"(?:majorName|major|zymc|evalMajor)":\s*"([^"]+)"', caseSensitive: false),
      RegExp(r'专业[：:]\s*([^\s<"&]+)'),
      RegExp(r'主修[：:]\s*([^\s<"&]+)'),
      RegExp(r'大类[：:]\s*([^\s<"&]+)'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      final val = m?.group(1)?.trim();
      if (val != null &&
          val.isNotEmpty &&
          val != '未知' &&
          val != '无' &&
          !val.contains('&nbsp;')) {
        return val;
      }
    }
    return null;
  }
}
