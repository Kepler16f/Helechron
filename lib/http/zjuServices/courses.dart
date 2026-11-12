// This implementation is adapted from the project "login-ZJU" by 5dbwat4(https://github.com/5dbwat4/login-ZJU) under the MIT License.
// See: https://github.com/5dbwat4/login-ZJU/blob/main/src/utils/fetch-with-cookie.ts

import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/data_source_status.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/todo_task_sync.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/model/todo.dart';
import 'package:flutter/foundation.dart';
import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:hive/hive.dart';
import 'response_utils.dart';

@visibleForTesting
Uri? coursesMetaRefreshTarget(String body, Uri source) {
  final metaTags = RegExp(r'<meta\b[^>]*>', caseSensitive: false)
      .allMatches(body)
      .map((match) => match.group(0) ?? '');
  final refreshAttribute =
      RegExp(r'''http-equiv\s*=\s*["']?refresh''', caseSensitive: false);
  final urlAttribute =
      RegExp(r'''url\s*=\s*["']?([^"' >;]+)''', caseSensitive: false);
  for (final tag in metaTags) {
    if (!refreshAttribute.hasMatch(tag)) continue;
    final rawTarget = urlAttribute.firstMatch(tag)?.group(1);
    if (rawTarget == null || rawTarget.isEmpty) continue;
    final target = source.resolve(rawTarget.replaceAll('&amp;', '&'));
    final targetHost = target.host.toLowerCase();
    final isZjuHost =
        targetHost == 'zju.edu.cn' || targetHost.endsWith('.zju.edu.cn');
    if (target.scheme == 'https' && isZjuHost) return target;
  }
  return null;
}

/// 学在浙大客户端；手动跟随 SSO 跳转并维护业务 SESSION，失败时回退作业缓存。
class Courses {
  static final Uri _todoUri = Uri.parse("https://courses.zju.edu.cn/api/todos");

  static Cookie? _cachedStaticSession;
  static Cookie? get cachedSession =>
      _cachedStaticSession ?? _readPersistedSessionCookie();

  static void _persistSessionCookie(Cookie cookie) {
    _cachedStaticSession = cookie;
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        box.put('courses_session_name', cookie.name);
        box.put('courses_session_value', cookie.value);
        box.put(
            'courses_session_domain', cookie.domain ?? 'courses.zju.edu.cn');
        box.put('courses_session_path', cookie.path ?? '/');
      }
    } catch (_) {}
  }

  static Cookie? _readPersistedSessionCookie() {
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        final name = box.get('courses_session_name')?.toString();
        final val = box.get('courses_session_value')?.toString();
        if (name != null && val != null && val.isNotEmpty) {
          final cookie = Cookie(name, val)
            ..domain = box.get('courses_session_domain')?.toString() ??
                'courses.zju.edu.cn'
            ..path = box.get('courses_session_path')?.toString() ?? '/';
          _cachedStaticSession = cookie;
          return cookie;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 查询指定课程的用户活动阅读与完成情况（用于探测作业提交与打分状态）
  static Future<Map<String, dynamic>?> fetchActivityReadsForCourse(
    HttpClient httpClient,
    String courseId, {
    Cookie? sessionCookie,
  }) async {
    if (courseId.isEmpty) return null;
    final session = sessionCookie ?? cachedSession;
    if (session == null) return null;

    final uri = Uri.parse(
        'https://courses.zju.edu.cn/api/course/$courseId/activity-reads-for-user');
    try {
      final request = await httpClient.getUrl(uri).timeout(
            const Duration(seconds: 6),
            onTimeout: () => throw requestTimeout(),
          );
      request.followRedirects = false;
      request.cookies.add(session);

      final response = await request.close().timeout(
            const Duration(seconds: 6),
            onTimeout: () => throw requestTimeout(),
          );
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await readResponseBody(
        response,
        context: '学在浙大作业提交状态接口',
      );
      final json = decodeJsonMap(body, context: '学在浙大作业提交状态');
      return json;
    } catch (e) {
      debugPrint('fetchActivityReadsForCourse error: $e');
      return null;
    }
  }

  /// 确保获取到有效的学在浙大业务 session Cookie，若失效自动利用存储的 SSO 凭据重新登录
  static Future<Cookie?> ensureSession(HttpClient httpClient) async {
    final existing = cachedSession;
    if (existing != null) return existing;
    try {
      const secureStorage = FlutterSecureStorage();
      final username = await secureStorage.read(key: 'username');
      final password = await secureStorage.read(key: 'password');
      if (username != null &&
          password != null &&
          username.isNotEmpty &&
          password.isNotEmpty) {
        final ssoCookie =
            await ZjuAm.getSsoCookie(httpClient, username, password);
        if (ssoCookie != null) {
          final courses = Courses();
          await courses.login(httpClient, ssoCookie);
          return cachedSession;
        }
      }
    } catch (e) {
      debugPrint('Courses.ensureSession error: $e');
    }
    return cachedSession;
  }

  /// 从各种不同结构/字段的活动详情 JSON 中提取作业说明与要求文本或 HTML
  static String extractDescription(Map<String, dynamic>? details) {
    if (details == null) return '';
    final candidates = [
      details['description'],
      details['content'],
      details['instructions'],
      details['instruction'],
      details['body'],
      details['requirement'],
      details['requirements'],
      details['note'],
      details['intro'],
      details['text'],
      if (details['homework'] is Map) ...[
        (details['homework'] as Map)['description'],
        (details['homework'] as Map)['content'],
        (details['homework'] as Map)['instructions'],
        (details['homework'] as Map)['requirement'],
      ],
      if (details['activity'] is Map) ...[
        (details['activity'] as Map)['description'],
        (details['activity'] as Map)['content'],
        (details['activity'] as Map)['instructions'],
      ],
      if (details['data'] is Map) ...[
        (details['data'] as Map)['description'],
        (details['data'] as Map)['content'],
        (details['data'] as Map)['instruction'],
        (details['data'] as Map)['instructions'],
      ],
    ];
    for (final c in candidates) {
      if (c != null && c.toString().trim().isNotEmpty) {
        return c.toString().trim();
      }
    }
    return '';
  }

  /// 从各种活动结构中提取教师附件列表
  static List<Map<String, dynamic>> extractUploads(
      Map<String, dynamic>? details) {
    if (details == null) return [];
    final candidates = [
      details['uploads'],
      details['attachments'],
      details['files'],
      details['reference_materials'],
      if (details['homework'] is Map) (details['homework'] as Map)['uploads'],
      if (details['activity'] is Map) (details['activity'] as Map)['uploads'],
      if (details['data'] is Map) (details['data'] as Map)['uploads'],
    ];
    for (final c in candidates) {
      if (c is List && c.isNotEmpty) {
        return c
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  /// 查询指定课程活动详情（作业标题、富文本/HTML 说明要求、截止时间、附件等）
  /// 兼容 TronClass 多租户路由：优先请求课程特定作业路由，回退通用活动路由，合并说明与附件
  static Future<Map<String, dynamic>?> fetchActivityDetails(
    HttpClient httpClient,
    String activityId, {
    String? courseId,
    Cookie? sessionCookie,
  }) async {
    if (activityId.isEmpty) return null;
    var session = sessionCookie ?? cachedSession;
    if (session == null) {
      session = await ensureSession(httpClient);
      if (session == null) return null;
    }

    final candidateUris = <Uri>[];
    if (courseId != null && courseId.isNotEmpty) {
      candidateUris.add(Uri.parse(
          'https://courses.zju.edu.cn/api/courses/$courseId/homework-activities/$activityId'));
      candidateUris.add(Uri.parse(
          'https://courses.zju.edu.cn/api/course/$courseId/homework-activities/$activityId'));
      candidateUris.add(Uri.parse(
          'https://courses.zju.edu.cn/api/courses/$courseId/activities/$activityId'));
      candidateUris.add(Uri.parse(
          'https://courses.zju.edu.cn/api/course/activities/$activityId'));
    }
    candidateUris.add(
        Uri.parse('https://courses.zju.edu.cn/api/activities/$activityId'));

    Map<String, dynamic>? bestResult;

    for (final uri in candidateUris) {
      try {
        final request = await httpClient.getUrl(uri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout(),
            );
        request.followRedirects = false;
        if (session != null) {
          request.cookies.add(session);
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');

        final response = await request.close().timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout(),
            );

        if (response.statusCode == HttpStatus.ok) {
          final body = await readResponseBody(
            response,
            context: '学在浙大作业详情接口(${uri.path})',
          );
          final json = decodeJsonMap(body, context: '学在浙大作业详情');
          if (json.isNotEmpty) {
            if (bestResult == null) {
              bestResult = Map<String, dynamic>.from(json);
            } else {
              // 深度补充字段，避免旧路由缺少说明或附件
              final target = bestResult;
              json.forEach((k, v) {
                if (v != null) {
                  final existing = target[k];
                  if (existing == null ||
                      (existing is String && existing.isEmpty) ||
                      (existing is List &&
                          existing.isEmpty &&
                          v is List &&
                          v.isNotEmpty)) {
                    target[k] = v;
                  }
                }
              });
            }

            // 若已解析出有效作业说明文本/HTML，则说明已命中最佳详情，结束后续探测
            final desc = extractDescription(bestResult);
            if (desc.isNotEmpty) {
              break;
            }
          }
        } else if (response.statusCode == HttpStatus.unauthorized ||
            response.statusCode == HttpStatus.found) {
          // 会话过期重登尝试
          final refreshed = await ensureSession(httpClient);
          if (refreshed != null && refreshed.value != session?.value) {
            session = refreshed;
          }
        }
      } catch (e) {
        debugPrint('fetchActivityDetails ($uri) error: $e');
      }
    }

    return bestResult;
  }

  /// 查询指定作业的提交记录（包含学生已上传文件、提交说明、得分及教师反馈）
  static Future<Map<String, dynamic>?> fetchActivitySubmissions(
    HttpClient httpClient,
    String activityId, {
    Cookie? sessionCookie,
  }) async {
    if (activityId.isEmpty) return null;
    final session = sessionCookie ?? cachedSession;
    if (session == null) return null;

    final uri = Uri.parse(
        'https://courses.zju.edu.cn/api/activities/$activityId/submissions');
    try {
      final request = await httpClient.getUrl(uri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout(),
          );
      request.followRedirects = false;
      request.cookies.add(session);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout(),
          );
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await readResponseBody(
        response,
        context: '学在浙大作业提交记录接口',
      );
      return decodeJsonMap(body, context: '学在浙大作业提交记录');
    } catch (e) {
      debugPrint('fetchActivitySubmissions error: $e');
      return null;
    }
  }

  static String _lookupMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.rar')) return 'application/x-rar-compressed';
    if (lower.endsWith('.7z')) return 'application/x-7z-compressed';
    if (lower.endsWith('.tar') || lower.endsWith('.gz')) {
      return 'application/gzip';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.c') ||
        lower.endsWith('.cpp') ||
        lower.endsWith('.h') ||
        lower.endsWith('.py') ||
        lower.endsWith('.java') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.html') ||
        lower.endsWith('.json') ||
        lower.endsWith('.md')) {
      return 'text/plain;charset=utf-8';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  static ({List<int> prefix, List<int> suffix}) _buildMultipartEnvelope({
    required String boundary,
    required String fileName,
    String parentType = 'submission_upload',
    int parentId = 0,
    bool includeParentFields = true,
  }) {
    final safeName = fileName.replaceAll('"', '_');
    final prefixBuffer = StringBuffer();
    if (includeParentFields) {
      prefixBuffer.write(
          '--$boundary\r\nContent-Disposition: form-data; name="parent_type"\r\n\r\n$parentType\r\n');
      prefixBuffer.write(
          '--$boundary\r\nContent-Disposition: form-data; name="parent_id"\r\n\r\n$parentId\r\n');
    }
    final mimeType = _lookupMimeType(fileName);
    prefixBuffer.write(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$safeName"\r\nContent-Type: $mimeType\r\n\r\n');
    return (
      prefix: utf8.encode(prefixBuffer.toString()),
      suffix: utf8.encode('\r\n--$boundary--\r\n'),
    );
  }

  /// 分块写入请求体并实时回调已发送字节数
  static Future<void> _writeRequestBytesWithProgress(
    HttpClientRequest req, {
    required List<int> fileBytes,
    List<int>? prefixBytes,
    List<int>? suffixBytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final totalPayloadLength = (prefixBytes?.length ?? 0) +
        fileBytes.length +
        (suffixBytes?.length ?? 0);
    req.contentLength = totalPayloadLength;
    req.bufferOutput = false;

    if (prefixBytes != null && prefixBytes.isNotEmpty) {
      req.add(prefixBytes);
    }

    final total = fileBytes.length;
    if (total == 0) {
      onProgress?.call(0, 0);
    } else {
      const chunkSize = 32 * 1024;
      final typed = fileBytes is Uint8List ? fileBytes : null;
      var offset = 0;
      onProgress?.call(0, total);
      while (offset < total) {
        final end = offset + chunkSize < total ? offset + chunkSize : total;
        final chunk = typed != null
            ? Uint8List.sublistView(typed, offset, end)
            : fileBytes.sublist(offset, end);
        req.add(chunk);
        await req.flush();
        offset = end;
        onProgress?.call(offset, total);
      }
    }

    if (suffixBytes != null && suffixBytes.isNotEmpty) {
      req.add(suffixBytes);
    }
    await req.flush();
  }

  static Future<void> _notifyUploadFinish(
    HttpClient httpClient,
    Cookie session,
    int uploadId,
  ) async {
    final endpoints = [
      Uri.parse('https://courses.zju.edu.cn/api/uploads/$uploadId/finish'),
      Uri.parse('https://courses.zju.edu.cn/api/uploads/$uploadId/success'),
    ];
    for (final uri in endpoints) {
      try {
        final req =
            await httpClient.postUrl(uri).timeout(const Duration(seconds: 6));
        req.cookies.add(session);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.contentLength = 2;
        req.write('{}');
        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok ||
            resp.statusCode == HttpStatus.noContent) {
          break;
        }
      } catch (_) {}
    }
  }

  static Future<bool> _streamBytesToUploadUrl({
    required HttpClient httpClient,
    required Cookie session,
    required String uploadUrlStr,
    required String fileName,
    required List<int> fileBytes,
    required int uploadId,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    try {
      final uploadUri = uploadUrlStr.startsWith('http')
          ? Uri.parse(uploadUrlStr)
          : Uri.parse('https://courses.zju.edu.cn$uploadUrlStr');

      final isExternalOss = uploadUri.host.contains('aliyuncs.com') ||
          uploadUri.host.contains('amazonaws.com') ||
          uploadUri.queryParameters.containsKey('OSSAccessKeyId') ||
          uploadUri.queryParameters.containsKey('Signature');

      Future<bool> sendRawPut({required bool attachSessionCookie}) async {
        final putReq = await httpClient.putUrl(uploadUri).timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw requestTimeout(),
            );
        if (attachSessionCookie) {
          putReq.cookies.add(session);
        }
        putReq.headers
            .set(HttpHeaders.contentTypeHeader, _lookupMimeType(fileName));
        await _writeRequestBytesWithProgress(
          putReq,
          fileBytes: fileBytes,
          onProgress: onProgress,
        );
        final putResp = await putReq.close().timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw requestTimeout(),
            );
        if (putResp.statusCode == HttpStatus.ok ||
            putResp.statusCode == HttpStatus.created ||
            putResp.statusCode == HttpStatus.noContent) {
          await _notifyUploadFinish(httpClient, session, uploadId);
          return true;
        }
        return false;
      }

      if (isExternalOss) {
        if (await sendRawPut(attachSessionCookie: false)) return true;
      } else {
        if (await sendRawPut(attachSessionCookie: true)) return true;

        onProgress?.call(0, fileBytes.length);
        final boundary =
            '----TronStreamBoundary${DateTime.now().millisecondsSinceEpoch}';
        final env = _buildMultipartEnvelope(
          boundary: boundary,
          fileName: fileName,
          includeParentFields: false,
        );
        final postReq = await httpClient.postUrl(uploadUri).timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw requestTimeout(),
            );
        postReq.cookies.add(session);
        postReq.headers.set(HttpHeaders.contentTypeHeader,
            'multipart/form-data; boundary=$boundary');
        await _writeRequestBytesWithProgress(
          postReq,
          fileBytes: fileBytes,
          prefixBytes: env.prefix,
          suffixBytes: env.suffix,
          onProgress: onProgress,
        );
        final postResp = await postReq.close().timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw requestTimeout(),
            );
        if (postResp.statusCode == HttpStatus.ok ||
            postResp.statusCode == HttpStatus.created ||
            postResp.statusCode == HttpStatus.noContent) {
          await _notifyUploadFinish(httpClient, session, uploadId);
          return true;
        }
      }
    } catch (e) {
      debugPrint('_streamBytesToUploadUrl error: $e');
    }
    return false;
  }

  /// 上传作业附件文件至学在浙大服务器（支持直接表单与两阶段凭据流式直传），返回 uploadId
  static Future<int?> uploadSubmissionFile(
    HttpClient httpClient, {
    required String fileName,
    required List<int> fileBytes,
    String? activityId,
    String? courseId,
    Cookie? sessionCookie,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    var currentSession = sessionCookie ?? cachedSession;
    if (currentSession == null) {
      currentSession = await ensureSession(httpClient);
      if (currentSession == null) return null;
    }
    Cookie activeSession = currentSession;

    // 策略 1：直接通过 multipart/form-data POST 上传至 /api/uploads
    try {
      final boundary =
          '----TronClassBoundary${DateTime.now().millisecondsSinceEpoch}';
      final env = _buildMultipartEnvelope(
        boundary: boundary,
        fileName: fileName,
      );

      final uploadUri = Uri.parse('https://courses.zju.edu.cn/api/uploads');
      final req = await httpClient.postUrl(uploadUri).timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw requestTimeout(),
          );
      req.followRedirects = false;
      req.cookies.add(activeSession);
      req.headers.set(HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      await _writeRequestBytesWithProgress(
        req,
        fileBytes: fileBytes,
        prefixBytes: env.prefix,
        suffixBytes: env.suffix,
        onProgress: onProgress,
      );

      final resp = await req.close().timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw requestTimeout(),
          );

      if (resp.statusCode == HttpStatus.ok ||
          resp.statusCode == HttpStatus.created) {
        final body = await readResponseBody(resp, context: '学在浙大直接上传接口');
        final json = decodeJsonMap(body, context: '学在浙大上传响应');
        final uploadId = (json['id'] as num?)?.toInt();
        final uploadUrlStr = json['upload_url']?.toString();

        if (uploadId != null) {
          if (uploadUrlStr == null || uploadUrlStr.isEmpty) {
            onProgress?.call(fileBytes.length, fileBytes.length);
            return uploadId;
          }
          onProgress?.call(0, fileBytes.length);
          final streamed = await _streamBytesToUploadUrl(
            httpClient: httpClient,
            session: activeSession,
            uploadUrlStr: uploadUrlStr,
            fileName: fileName,
            fileBytes: fileBytes,
            uploadId: uploadId,
            onProgress: onProgress,
          );
          if (streamed) return uploadId;
        }
      } else if (resp.statusCode == HttpStatus.unauthorized ||
          resp.statusCode == HttpStatus.found) {
        final refreshed = await ensureSession(httpClient);
        if (refreshed != null) activeSession = refreshed;
      }
    } catch (e) {
      debugPrint(
          'uploadSubmissionFile Strategy 1 (direct multipart) error: $e');
    }

    // 策略 2：两阶段凭据上传（POST /api/uploads 申请凭据 JSON -> 写入目标地址）
    onProgress?.call(0, fileBytes.length);
    try {
      final ticketUri = Uri.parse('https://courses.zju.edu.cn/api/uploads');
      final ticketReq = await httpClient.postUrl(ticketUri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw requestTimeout(),
          );
      ticketReq.cookies.add(activeSession);
      ticketReq.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json;charset=utf-8');
      ticketReq.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final ticketPayload = jsonEncode({
        'name': fileName,
        'size': fileBytes.length,
        'parent_type': 'submission_upload',
        'parent_id': 0,
      });
      ticketReq.contentLength = utf8.encode(ticketPayload).length;
      ticketReq.write(ticketPayload);

      final ticketResp = await ticketReq.close();
      if (ticketResp.statusCode == HttpStatus.ok ||
          ticketResp.statusCode == HttpStatus.created) {
        final ticketBody =
            await readResponseBody(ticketResp, context: '学在浙大上传凭据接口');
        final ticketJson = decodeJsonMap(ticketBody, context: '学在浙大上传凭据');
        final uploadId = (ticketJson['id'] as num?)?.toInt();
        final uploadUrlStr = ticketJson['upload_url']?.toString();

        if (uploadId != null) {
          if (uploadUrlStr == null || uploadUrlStr.isEmpty) {
            onProgress?.call(fileBytes.length, fileBytes.length);
            return uploadId;
          }
          final streamed = await _streamBytesToUploadUrl(
            httpClient: httpClient,
            session: activeSession,
            uploadUrlStr: uploadUrlStr,
            fileName: fileName,
            fileBytes: fileBytes,
            uploadId: uploadId,
            onProgress: onProgress,
          );
          if (streamed) return uploadId;
        }
      }
    } catch (e) {
      debugPrint('uploadSubmissionFile Strategy 2 (ticketed) error: $e');
    }

    // 策略 3：课程级接口回退（POST /api/courses/$courseId/uploads）
    if (courseId != null && courseId.isNotEmpty) {
      onProgress?.call(0, fileBytes.length);
      try {
        final boundary =
            '----TronClassBoundary${DateTime.now().millisecondsSinceEpoch}';
        final env = _buildMultipartEnvelope(
          boundary: boundary,
          fileName: fileName,
          parentType: 'submission',
        );

        final courseUploadUri = Uri.parse(
            'https://courses.zju.edu.cn/api/courses/$courseId/uploads');
        final req = await httpClient.postUrl(courseUploadUri).timeout(
              const Duration(seconds: 35),
              onTimeout: () => throw requestTimeout(),
            );
        req.cookies.add(activeSession);
        req.headers.set(HttpHeaders.contentTypeHeader,
            'multipart/form-data; boundary=$boundary');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        await _writeRequestBytesWithProgress(
          req,
          fileBytes: fileBytes,
          prefixBytes: env.prefix,
          suffixBytes: env.suffix,
          onProgress: onProgress,
        );

        final resp = await req.close().timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw requestTimeout(),
            );
        if (resp.statusCode == HttpStatus.ok ||
            resp.statusCode == HttpStatus.created) {
          final body = await readResponseBody(resp, context: '课程级上传响应');
          final json = decodeJsonMap(body, context: '课程级上传响应');
          final uploadId = (json['id'] as num?)?.toInt();
          if (uploadId != null) {
            onProgress?.call(fileBytes.length, fileBytes.length);
            return uploadId;
          }
        }
      } catch (e) {
        debugPrint(
            'uploadSubmissionFile Strategy 3 (course uploads) error: $e');
      }
    }

    return null;
  }

  /// 提交作业（指定活动 ID、已上传附件 ID 列表、留言与文本内容）
  static Future<bool> submitHomework(
    HttpClient httpClient, {
    required String activityId,
    required List<int> uploadIds,
    String? courseId,
    String? comment,
    String? content,
    Cookie? sessionCookie,
  }) async {
    var session = sessionCookie ?? cachedSession;
    if (session == null) {
      session = await ensureSession(httpClient);
      if (session == null) return false;
    }

    final candidateUris = <Uri>[
      Uri.parse(
          'https://courses.zju.edu.cn/api/course/activities/$activityId/submissions'),
      Uri.parse(
          'https://courses.zju.edu.cn/api/activities/$activityId/submissions'),
    ];
    if (courseId != null && courseId.isNotEmpty) {
      candidateUris.insert(
          0,
          Uri.parse(
              'https://courses.zju.edu.cn/api/courses/$courseId/homework-activities/$activityId/submissions'));
      candidateUris.insert(
          1,
          Uri.parse(
              'https://courses.zju.edu.cn/api/course/$courseId/homework-activities/$activityId/submissions'));
    }

    for (final uri in candidateUris) {
      try {
        final request = await httpClient.postUrl(uri).timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw requestTimeout(),
            );
        request.cookies.add(session);
        request.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json;charset=utf-8');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');

        final payload = jsonEncode({
          'uploads': uploadIds,
          'comment': comment ?? '',
          'is_draft': false,
          'content': content ?? '',
        });
        request.contentLength = utf8.encode(payload).length;
        request.write(payload);

        final response = await request.close().timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw requestTimeout(),
            );

        if (response.statusCode == HttpStatus.ok ||
            response.statusCode == HttpStatus.created ||
            response.statusCode == HttpStatus.noContent) {
          return true;
        }
      } catch (e) {
        debugPrint('submitHomework ($uri) error: $e');
      }
    }

    return false;
  }

  /// 撤回作业提交
  static Future<bool> retractHomework(
    HttpClient httpClient, {
    required String submissionId,
    String? activityId,
    Cookie? sessionCookie,
  }) async {
    final session = sessionCookie ?? cachedSession;
    if (session == null) return false;

    try {
      final uri = Uri.parse(
          'https://courses.zju.edu.cn/api/submissions/$submissionId/retract');
      final request = await httpClient.putUrl(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout(),
          );
      request.cookies.add(session);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout(),
          );

      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.noContent) {
        return true;
      }

      if (activityId != null && activityId.isNotEmpty) {
        final altUri = Uri.parse(
            'https://courses.zju.edu.cn/api/course/activities/$activityId/submissions/retract');
        final altReq = await httpClient.putUrl(altUri).timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw requestTimeout(),
            );
        altReq.cookies.add(session);
        final altResp = await altReq.close();
        if (altResp.statusCode == HttpStatus.ok ||
            altResp.statusCode == HttpStatus.noContent) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('retractHomework error: $e');
      return false;
    }
  }

  Future<void> _probeActivitiesCompleteness(
    HttpClient httpClient,
    Set<String> courseIds,
    List<Todo> todos,
  ) async {
    try {
      final futures = courseIds.map((cid) async {
        final res = await fetchActivityReadsForCourse(
          httpClient,
          cid,
          sessionCookie: _session,
        );
        return MapEntry(cid, res);
      });
      final results = await Future.wait(futures);

      for (final entry in results) {
        final data = entry.value;
        if (data == null) continue;
        final rawReads = asDynamicList(data['activity_reads']);
        if (rawReads == null) continue;

        for (final item in rawReads) {
          final m = asStringMap(item);
          if (m == null) continue;
          final aid = m['activity_id']?.toString() ?? '';
          if (aid.isEmpty) continue;
          final completeness = asString(m['completeness']) ?? '';
          final subData = asStringMap(m['data']);
          final score = (subData?['score'] as num?)?.toDouble();
          final submittedAtStr = asString(subData?['submitted_at']);
          final submittedAt = DateTime.tryParse(submittedAtStr ?? '');
          final isDraft = asBool(subData?['is_draft']) ?? false;

          final isSubmitted =
              (score != null) || (completeness == 'full' && !isDraft);

          for (final todo in todos) {
            if (todo.id == aid) {
              todo.completeness = completeness;
              todo.score = score;
              todo.submittedAt = isSubmitted ? submittedAt : null;
              if (score != null) {
                todo.submissionStatus = HomeworkSubmissionStatus.graded;
              } else if (completeness == 'full' && !isDraft) {
                todo.submissionStatus = HomeworkSubmissionStatus.submitted;
              } else {
                todo.submissionStatus = HomeworkSubmissionStatus.unsubmitted;
              }
            }
          }

          TodoTaskSync.recordHomeworkStatus(
            aid,
            completeness: completeness,
            score: score,
            submittedAt: isSubmitted ? submittedAt : null,
            clearIfIncomplete: !isSubmitted,
          );
        }
      }
    } catch (e) {
      debugPrint('_probeActivitiesCompleteness error: $e');
    }
  }

  DatabaseHelper? _db;
  Cookie? _session;
  Cookie? _iPlanetDirectoryPro;
  Future<bool>? _loginFuture;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  Future<Tuple3<Exception?, List<Todo>, DataSourceStatus>> getTodo(
      HttpClient httpClient) async {
    // 认证失败只允许重建一次业务 SESSION；网络或解析失败直接进入缓存降级。
    try {
      var relogged = false;
      if (_session == null) {
        if (_iPlanetDirectoryPro != null) {
          await login(httpClient, _iPlanetDirectoryPro);
          relogged = true;
        } else {
          throw AuthenticationExpiredException("学在浙大：未登录");
        }
      }
      Map<String, dynamic> data;
      final attemptedSession = _session;
      try {
        data = await _fetchTodo(httpClient, relogged: relogged);
      } on AuthenticationExpiredException catch (firstError) {
        if (_iPlanetDirectoryPro == null || relogged) {
          throw LoginExpiredException(
            "学在浙大：登录态已失效，请手动重新登录",
            details: detailedErrorText(firstError),
          );
        }
        try {
          if (identical(_session, attemptedSession)) {
            _session = null;
            await login(httpClient, _iPlanetDirectoryPro);
          }
          data = await _fetchTodo(
            httpClient,
            relogged: true,
            retried: true,
          );
        } on AuthenticationExpiredException catch (secondError) {
          throw LoginExpiredException(
            "学在浙大：自动重登失败，请手动重新登录",
            details: detailedErrorText(secondError),
            originalError: secondError,
          );
        }
      }
      final body = jsonEncode(data);
      await Future.wait([
        _db?.setCachedWebPage("courses_todo", body) ?? Future<void>.value(),
        _db?.setCachedWebPage(
              "courses_todo_timestamp",
              DateTime.now().toUtc().toIso8601String(),
            ) ??
            Future<void>.value(),
      ]);
      final todos = Todo.getAllFromCourses(data);
      if (todos.isNotEmpty && _session != null) {
        final courseIds = todos
            .map((t) => t.resolvedCourseId)
            .where((cid) => cid.isNotEmpty)
            .toSet();
        if (courseIds.isNotEmpty) {
          await _probeActivitiesCompleteness(httpClient, courseIds, todos);
        }
      }
      DiagnosticLogService.instance.record(
        module: '学在浙大作业',
        operation: 'fetchTodo',
        requestUri: _todoUri,
        message: '实时成功，${todos.length} 条',
      );
      return Tuple3(null, todos, DataSourceStatus.live);
    } on Object catch (error, stackTrace) {
      final exception = exceptionFrom(
        error,
        context: '学在浙大作业',
        requestUri: _todoUri,
        stackTrace: stackTrace,
      );
      final cached = _readCachedTodos();
      final status =
          cached.used ? DataSourceStatus.cache : DataSourceStatus.unavailable;
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '学在浙大作业',
        operation: 'fetchTodo',
        requestUri: _todoUri,
        cacheUsed: cached.used,
        message: cached.used
            ? '实时请求失败，使用缓存，${cached.todos.length} 条；'
                '缓存时间=${cached.cachedAt ?? '<未知>'}'
            : '实时请求失败，且没有可用缓存',
        error: error,
        stackTrace: stackTrace,
      );
      return Tuple3(exception, cached.todos, status);
    }
  }

  Future<Map<String, dynamic>> _fetchTodo(
    HttpClient httpClient, {
    bool relogged = false,
    bool retried = false,
  }) async {
    final request = await _createTodoRequest(httpClient);
    final response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    final body = await readResponseText(
      response,
      context: '学在浙大作业接口',
      expectJson: true,
      requestUri: _todoUri,
      relogged: relogged,
      retried: retried,
    );
    final data =
        decodeJsonMap(body, context: '学在浙大作业接口；HTTP ${response.statusCode}');
    if (jsonIndicatesAuthenticationFailure(data)) {
      throw AuthenticationExpiredException(
          '学在浙大作业接口：登录态已失效；HTTP ${response.statusCode}'
          '；响应摘要：${responseSummary(body)}');
    }
    return data;
  }

  Future<HttpClientRequest> _createTodoRequest(HttpClient httpClient) async {
    final request = await httpClient.getUrl(_todoUri).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    request.followRedirects = false;
    request.cookies.add(_session!);
    return request;
  }

  _CachedTodos _readCachedTodos() {
    final cached = _db?.getCachedWebPage("courses_todo");
    if (cached == null || cached.trim().isEmpty) {
      return const _CachedTodos([], false);
    }
    try {
      final todos = Todo.getAllFromCourses(
        decodeJsonMap(cached, context: '学在浙大作业缓存'),
      );
      for (final todo in todos) {
        final recorded = TodoTaskSync.getHomeworkStatus(todo.id);
        if (recorded != null) {
          todo.completeness = asString(recorded['completeness']);
          todo.score = (recorded['score'] as num?)?.toDouble();
          if (todo.score != null) {
            todo.submissionStatus = HomeworkSubmissionStatus.graded;
          } else if (todo.completeness == 'full') {
            todo.submissionStatus = HomeworkSubmissionStatus.submitted;
          }
        }
      }
      return _CachedTodos(
        todos,
        true,
        cachedAt: _db?.getCachedWebPage("courses_todo_timestamp"),
      );
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '学在浙大作业',
        operation: 'readCache',
        cacheUsed: false,
        error: error,
        stackTrace: stackTrace,
      );
      return const _CachedTodos([], false);
    }
  }

  Future<bool> login(HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    if (iPlanetDirectoryPro == null) {
      throw AuthenticationExpiredException("学在浙大：统一身份认证凭据无效");
    }
    _iPlanetDirectoryPro = iPlanetDirectoryPro;

    final pending = _loginFuture;
    if (pending != null) return await pending;
    final login = _doLogin(httpClient, iPlanetDirectoryPro);
    _loginFuture = login;
    try {
      return await login;
    } finally {
      if (identical(_loginFuture, login)) _loginFuture = null;
    }
  }

  Future<bool> _doLogin(
    HttpClient httpClient,
    Cookie iPlanetDirectoryPro,
  ) async {
    _session = null;

    // 简单 CookieJar。
    // 相同 name + domain + path 的 Cookie 会被新值覆盖，
    // 避免重复发送旧 session。
    final cookieJar = <String, Cookie>{};
    final redirectTrace = <String>[];

    bool isExpiredCookie(Cookie cookie) {
      if (cookie.maxAge != null && cookie.maxAge! <= 0) {
        return true;
      }

      final expires = cookie.expires;
      return expires != null && expires.isBefore(DateTime.now());
    }

    String normalizedDomain(Cookie cookie, Uri source) {
      final rawDomain = cookie.domain;

      if (rawDomain == null || rawDomain.trim().isEmpty) {
        // Set-Cookie 没有 Domain 时，将其视为当前响应主机的 Cookie。
        return source.host.toLowerCase();
      }

      return rawDomain.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    }

    String normalizedPath(Cookie cookie) {
      final path = cookie.path;
      if (path == null || path.trim().isEmpty) {
        return '/';
      }
      return path;
    }

    String cookieKey(Cookie cookie, Uri source) {
      return '${cookie.name}|'
          '${normalizedDomain(cookie, source)}|'
          '${normalizedPath(cookie)}';
    }

    void storeCookie(Cookie cookie, Uri source) {
      final key = cookieKey(cookie, source);

      if (isExpiredCookie(cookie)) {
        cookieJar.remove(key);
        return;
      }

      // 保存 Cookie 来源范围，便于后续按照域名和路径筛选。
      if (cookie.domain == null || cookie.domain!.trim().isEmpty) {
        cookie.domain = source.host.toLowerCase();
      }

      if (cookie.path == null || cookie.path!.trim().isEmpty) {
        cookie.path = '/';
      }

      cookieJar[key] = cookie;
    }

    bool cookieMatchesUri(Cookie cookie, Uri uri) {
      if (isExpiredCookie(cookie)) {
        return false;
      }

      if (cookie.secure && uri.scheme != 'https') {
        return false;
      }

      final rawDomain = cookie.domain;
      if (rawDomain == null || rawDomain.trim().isEmpty) {
        return false;
      }

      final domain =
          rawDomain.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

      final host = uri.host.toLowerCase();

      final domainMatches = host == domain || host.endsWith('.$domain');

      if (!domainMatches) {
        return false;
      }

      final path =
          cookie.path == null || cookie.path!.isEmpty ? '/' : cookie.path!;

      return uri.path.startsWith(path);
    }

    List<Cookie> cookiesFor(Uri uri) {
      return cookieJar.values
          .where((cookie) => cookieMatchesUri(cookie, uri))
          .toList();
    }

    String cookieNames(Iterable<Cookie> cookies) {
      final names = cookies.map((cookie) => cookie.name).toSet().toList()
        ..sort();

      return names.isEmpty ? '<无>' : names.join(', ');
    }

    // iPlanetDirectoryPro 的 domain 通常是 zju.edu.cn，
    // 因此可用于 identity、zjuam、courses 等子域。
    final trustedSsoCookie =
        Cookie(iPlanetDirectoryPro.name, iPlanetDirectoryPro.value)
          ..domain = 'zju.edu.cn'
          ..path = '/'
          ..secure = iPlanetDirectoryPro.secure;
    storeCookie(trustedSsoCookie, Uri.parse('https://zjuam.zju.edu.cn/'));

    var current = Uri.parse(
      'https://courses.zju.edu.cn/user/index',
    );

    // Keycloak/CAS 可能经过多次跳转，略微提高上限。
    for (var redirectCount = 0; redirectCount < 15; redirectCount++) {
      final outgoingCookies = cookiesFor(current);

      if (kDebugMode) {
        debugPrint(
          '[Courses.login] '
          'hop=$redirectCount, '
          'request=${sanitizedRequestUri(current)}, '
          '发送Cookie名称=${cookieNames(outgoingCookies)}',
        );
      }
      DiagnosticLogService.instance.record(
        module: '学在浙大登录',
        operation: 'redirectHop',
        requestUri: current,
        message:
            'hop=$redirectCount；发送Cookie名称=${cookieNames(outgoingCookies)}',
      );

      final request = await httpClient.getUrl(current).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout(),
          );

      request.followRedirects = false;
      request.cookies.addAll(outgoingCookies);

      final response = await request.close().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout(),
          );

      final responseCookies = List<Cookie>.from(response.cookies);

      // 必须在 current 更新前处理当前响应的 Cookie。
      for (final cookie in responseCookies) {
        storeCookie(cookie, current);

        // 只接受 courses.zju.edu.cn 返回的 session，
        // 避免把其他域名的同名 Cookie 当作业务会话。
        if (current.host == 'courses.zju.edu.cn' && cookie.name == 'session') {
          _session = isExpiredCookie(cookie) ? null : cookie;
          if (_session != null) {
            _persistSessionCookie(_session!);
          }
        }
      }

      final body = await readResponseBody(
        response,
        context: '学在浙大登录',
      );

      final location = response.headers.value(HttpHeaders.locationHeader);

      final redirectTarget =
          location == null ? null : current.resolve(location);

      final traceLine = [
        'hop=$redirectCount',
        '请求=${sanitizedRequestUri(current)}',
        'HTTP=${response.statusCode}',
        'Location=${redirectTarget == null ? '<无>' : sanitizedRequestUri(redirectTarget)}',
        '响应Cookie=${cookieNames(responseCookies)}',
        '已取得session=${_session != null ? '是' : '否'}',
      ].join('；');

      redirectTrace.add(traceLine);

      if (kDebugMode) {
        debugPrint('[Courses.login] $traceLine');
      }
      DiagnosticLogService.instance.record(
        level: isHttpRedirectStatus(response.statusCode)
            ? CelechronLogLevel.debug
            : CelechronLogLevel.info,
        module: '学在浙大登录',
        operation: 'redirectHop',
        requestUri: current,
        statusCode: response.statusCode,
        contentType:
            response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>',
        location: location,
        message:
            'hop=$redirectCount；响应Cookie名称=${cookieNames(responseCookies)}；'
            '已取得session=${_session != null ? '是' : '否'}',
      );

      // 先处理重定向。
      // 关键：必须真正访问 redirectTarget，不能看到下一跳回到 courses
      // 就提前返回登录成功。
      if (isHttpRedirectStatus(response.statusCode)) {
        if (location == null || location.trim().isEmpty) {
          throw ExceptionWithMessage(
            '学在浙大登录：HTTP ${response.statusCode} 跳转但缺少 Location',
            details: redirectTrace.join('\n'),
          );
        }

        current = redirectTarget!;
        continue;
      }

      final successStatus = response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices;

      // Courses 现网登录链会返回 HTTP 200 meta-refresh，它仍是中间跳转。
      final metaRefresh =
          successStatus ? coursesMetaRefreshTarget(body, current) : null;
      if (metaRefresh != null) {
        redirectTrace.add(
          'hop=$redirectCount；HTTP 200 meta-refresh='
          '${sanitizedRequestUri(metaRefresh)}',
        );
        current = metaRefresh;
        continue;
      }

      final sessionCanAccessTodo =
          cookiesFor(_todoUri).any((cookie) => cookie.name == 'session');

      // 只有真正完成所有重定向，并成功访问 courses 页面后，
      // 才认定业务登录成功。
      if (successStatus &&
          current.host == 'courses.zju.edu.cn' &&
          _session != null &&
          sessionCanAccessTodo) {
        return true;
      }

      final terminalIsAuthenticationPage =
          (current.host == 'zjuam.zju.edu.cn' &&
                  current.path.startsWith('/cas/login')) ||
              current.host == 'identity.zju.edu.cn';
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden ||
          (successStatus && terminalIsAuthenticationPage)) {
        throw AuthenticationExpiredException(
          '学在浙大登录态失效；HTTP ${response.statusCode}',
          details: [
            ...redirectTrace,
            '响应摘要：${responseSummary(body)}',
          ].join('\n'),
        );
      }

      throw ExceptionWithMessage(
        '学在浙大登录失败；HTTP ${response.statusCode}',
        details: [
          ...redirectTrace,
          'Content-Type：'
              '${response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>'}',
          '响应摘要：${responseSummary(body)}',
        ].join('\n'),
      );
    }

    throw ExceptionWithMessage(
      '学在浙大登录失败：重定向次数过多',
      details: redirectTrace.join('\n'),
    );
  }

  void logout() {
    _session = null;
    _iPlanetDirectoryPro = null;
  }

  /// 查询某门课程在“学在浙大”(courses.zju.edu.cn) 上的所有课件与作业附件列表
  ///
  /// 参考开源项目：
  /// - PeiPei233/zju-learning-assistant
  /// - 8eoyw/zju-learning-cli
  /// - iamNCJ/ZJU-Tronclass-Courseware-Downloader
  static Future<List<CoursewareItem>> fetchCoursewareList(
    HttpClient httpClient, {
    required String courseName,
    String? courseCode,
  }) async {
    final session = await ensureSession(httpClient);
    if (session == null) {
      return const [];
    }

    final tcCourseIds = await _resolveTronClassCourseIds(
      httpClient,
      session,
      courseName: courseName,
      courseCode: courseCode,
    );
    if (tcCourseIds.isEmpty) {
      return const [];
    }

    final results = <CoursewareItem>[];
    final seenKeys = <String>{};

    for (final tcId in tcCourseIds) {
      final endpoints = [
        Uri.parse('https://courses.zju.edu.cn/api/courses/$tcId/activities'),
        Uri.parse(
            'https://courses.zju.edu.cn/api/courses/$tcId/homework-activities?page=1&page_size=50&reloadPage=false'),
      ];
      for (final uri in endpoints) {
        try {
          final req = await httpClient.getUrl(uri).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw requestTimeout(),
              );
          req.cookies.add(session);
          req.headers.set(HttpHeaders.acceptHeader, 'application/json');
          final resp = await req.close().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw requestTimeout(),
              );
          if (resp.statusCode != HttpStatus.ok) continue;
          final body = await readResponseBody(resp, context: '学在浙大课件列表');
          final json = decodeJsonMap(body, context: '学在浙大课件列表');
          final actList = asDynamicList(json['activities']) ??
              asDynamicList(json['homework_activities']) ??
              const [];
          for (final rawAct in actList) {
            final act = asStringMap(rawAct);
            if (act == null) continue;
            final actTitle = asString(act['title']) ?? '课程资料';
            final uploads = asDynamicList(act['uploads']) ?? const [];
            for (final rawUp in uploads) {
              final up = asStringMap(rawUp);
              if (up == null) continue;
              final uploadId = (asDouble(up['id']) ?? 0).toInt();
              final refId = (asDouble(up['reference_id']) ?? 0).toInt();
              final name = asString(up['name']) ?? '';
              final size = (asDouble(up['size']) ?? 0).toInt();
              if (name.isEmpty || (uploadId <= 0 && refId <= 0)) continue;
              final key = '${uploadId}_${refId}_$name';
              if (seenKeys.add(key)) {
                results.add(CoursewareItem(
                  name: name,
                  sectionTitle: actTitle,
                  sizeBytes: size,
                  uploadId: uploadId,
                  referenceId: refId,
                  source: '学在浙大',
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('fetchCoursewareList ($uri) error: $e');
        }
      }
    }

    return results;
  }

  static Future<List<int>> _resolveTronClassCourseIds(
    HttpClient httpClient,
    Cookie session, {
    required String courseName,
    String? courseCode,
  }) async {
    Future<List<int>> queryCoursesWithKeyword(String keyword) async {
      final uri = Uri.parse('https://courses.zju.edu.cn/api/my-courses');
      final req = await httpClient.postUrl(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout(),
          );
      req.cookies.add(session);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final payload = jsonEncode({
        'fields':
            'id,name,course_code,department(id,name),start_date,end_date,is_started,is_closed,academic_year_id,semester_id,credit,display_name,instructors(id,name)',
        'page': 1,
        'page_size': 100,
        'conditions': {
          'status': ['ongoing', 'notStarted', 'closed'],
          'keyword': keyword,
          'classify_type': 'recently_started',
          'display_studio_list': false,
        },
        'showScorePassedStatus': false,
      });
      final payloadBytes = utf8.encode(payload);
      req.contentLength = payloadBytes.length;
      req.add(payloadBytes);

      final resp = await req.close().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout(),
          );
      if (resp.statusCode != HttpStatus.ok) return const [];
      final body = await readResponseBody(resp, context: '学在浙大我的课程');
      final json = decodeJsonMap(body, context: '学在浙大我的课程');
      final courses = asDynamicList(json['courses']) ?? const [];

      final codeMatches = <int>[];
      final nameMatches = <int>[];
      final normalizedTargetCode =
          (courseCode ?? '').replaceAll(RegExp(r'\s+'), '').toLowerCase();

      for (final raw in courses) {
        final c = asStringMap(raw);
        if (c == null) continue;
        final id = (asDouble(c['id']) ?? 0).toInt();
        if (id <= 0) continue;
        final cCode =
            (asString(c['course_code']) ?? '').replaceAll(RegExp(r'\s+'), '').toLowerCase();
        final cName = asString(c['name']) ?? asString(c['display_name']) ?? '';

        if (normalizedTargetCode.isNotEmpty &&
            cCode.isNotEmpty &&
            (cCode == normalizedTargetCode ||
                cCode.contains(normalizedTargetCode) ||
                normalizedTargetCode.contains(cCode))) {
          codeMatches.add(id);
          continue;
        }
        if (courseName.trim().isNotEmpty &&
            cName.trim().isNotEmpty &&
            ZhiyunService.matchesCourseName(courseName, cName)) {
          nameMatches.add(id);
        }
      }
      return codeMatches.isNotEmpty ? codeMatches : nameMatches;
    }

    try {
      var matchedIds = await queryCoursesWithKeyword('');
      if (matchedIds.isEmpty && courseName.trim().isNotEmpty) {
        matchedIds = await queryCoursesWithKeyword(courseName.trim());
      }
      return matchedIds;
    } catch (e) {
      debugPrint('_resolveTronClassCourseIds error: $e');
      return const [];
    }
  }

  static const Set<String> _homeworkOrQuizTypes = {
    'homework',
    'homework_activity',
    'quiz',
    'exam',
    'assessment',
    'test',
  };

  /// 从单页课程活动 / 作业列表 JSON 解析标准化 [Todo] 列表
  @visibleForTesting
  static List<Todo> parseCourseHomeworkActivities(
    Map<String, dynamic> json, {
    required String tcCourseId,
    required String courseName,
  }) {
    final result = <Todo>[];
    final seenIds = <String>{};

    void absorbList(List<dynamic> rawList, {required bool fromHomeworkApi}) {
      for (final raw in rawList) {
        final act = asStringMap(raw);
        if (act == null) continue;
        final aid = (act['id']?.toString() ?? '').trim();
        if (aid.isEmpty || !seenIds.add(aid)) continue;

        final rawType =
            (asString(act['type']) ?? asString(act['activity_type']) ?? '')
                .toLowerCase();
        final resolvedType =
            rawType.isEmpty && fromHomeworkApi ? 'homework' : rawType;
        if (!fromHomeworkApi && !_homeworkOrQuizTypes.contains(resolvedType)) {
          continue;
        }

        final title = asString(act['title'])?.trim();
        if (title == null || title.isEmpty) continue;

        final rawData = asStringMap(act['data']);
        final endTime = asString(act['end_time']) ??
            asString(act['deadline']) ??
            asString(rawData?['end_time']);
        final completeness =
            asString(act['completeness']) ?? asString(rawData?['completeness']);
        final scoreNum = (act['score'] as num?) ?? (rawData?['score'] as num?);
        final submittedAtStr = asString(act['submitted_at']) ??
            asString(rawData?['submitted_at']);
        final isSubmittedFlag = asBool(act['submitted']) == true ||
            asBool(act['is_submitted']) == true ||
            ((asDouble(act['submission_count']) ?? 0) > 0);

        result.add(Todo.fromJson({
          'id': aid,
          'title': title,
          'course_name': asString(act['course_name']) ?? courseName,
          'course_id': asString(act['course_id']) ?? tcCourseId,
          'end_time': endTime,
          'type': resolvedType.isEmpty ? 'homework' : resolvedType,
          'score': scoreNum,
          'completeness':
              completeness ?? (isSubmittedFlag ? 'full' : null),
          'submitted_at': submittedAtStr,
        }));
      }
    }

    absorbList(
      asDynamicList(json['homework_activities']) ?? const [],
      fromHomeworkApi: true,
    );
    absorbList(
      asDynamicList(json['activities']) ?? const [],
      fromHomeworkApi: false,
    );
    return result;
  }

  /// 合并多来源作业状态与阅读完成度，并按待完成置顶（DDL 升序）→ 逾期 → 已完成置底（DDL 降序）排序
  static List<Todo> mergeAndSortCourseHomeworks(
    Iterable<Todo> items, {
    Map<String, dynamic>? activityReadsJson,
    bool readLocalStatus = true,
  }) {
    final byId = <String, Todo>{};

    void absorbTodo(Todo source) {
      if (source.id.isEmpty) return;
      final existing = byId[source.id];
      if (existing == null) {
        byId[source.id] = source;
        return;
      }
      if ((existing.name.isEmpty || existing.name == '未命名作业') &&
          source.name.isNotEmpty) {
        existing.name = source.name;
      }
      existing.endTime ??= source.endTime;
      if (existing.courseId.isEmpty && source.courseId.isNotEmpty) {
        existing.courseId = source.courseId;
      }
      if ((existing.type == null || existing.type!.isEmpty) &&
          source.type != null &&
          source.type!.isNotEmpty) {
        existing.type = source.type;
      }
      existing.score ??= source.score;
      existing.submittedAt ??= source.submittedAt;
      if (source.completeness == 'full' || !existing.isSubmitted) {
        if (source.completeness != null && source.completeness!.isNotEmpty) {
          existing.completeness = source.completeness;
        }
        if (source.isSubmitted) {
          existing.submissionStatus = source.submissionStatus;
        }
      }
    }

    for (final item in items) {
      absorbTodo(item);
    }

    // 应用 activity-reads-for-user 中的真实提交/评分数据
    final rawReads = asDynamicList(activityReadsJson?['activity_reads']);
    if (rawReads != null) {
      for (final item in rawReads) {
        final m = asStringMap(item);
        if (m == null) continue;
        final aid = (m['activity_id']?.toString() ?? '').trim();
        final target = byId[aid];
        if (target == null) continue;

        final completeness = asString(m['completeness']) ?? '';
        final subData = asStringMap(m['data']);
        final score = (subData?['score'] as num?)?.toDouble();
        final submittedAt =
            DateTime.tryParse(asString(subData?['submitted_at']) ?? '');
        final isDraft = asBool(subData?['is_draft']) ?? false;
        final isSubmitted =
            (score != null) || (completeness == 'full' && !isDraft);

        target.completeness = isSubmitted
            ? 'full'
            : (completeness == 'full' ? 'incomplete' : completeness);
        if (score != null) target.score = score;
        if (submittedAt != null && isSubmitted) {
          target.submittedAt = submittedAt;
        }
        if (score != null) {
          target.submissionStatus = HomeworkSubmissionStatus.graded;
        } else if (isSubmitted) {
          target.submissionStatus = HomeworkSubmissionStatus.submitted;
        } else {
          target.submissionStatus = HomeworkSubmissionStatus.unsubmitted;
        }

        if (readLocalStatus) {
          TodoTaskSync.recordHomeworkStatus(
            aid,
            completeness: target.completeness,
            score: score,
            submittedAt: isSubmitted ? submittedAt : null,
            clearIfIncomplete: !isSubmitted,
            isQuiz: target.isQuiz ? true : null,
          );
        }
      }
    }

    // 与本地实时提交记录合并
    if (readLocalStatus) {
      for (final target in byId.values) {
        final recorded = TodoTaskSync.getHomeworkStatus(target.id);
        if (recorded == null) continue;
        final recScore = (recorded['score'] as num?)?.toDouble();
        final recComp = recorded['completeness']?.toString();
        final recTime =
            DateTime.tryParse(recorded['submitted_at']?.toString() ?? '');
        if (recScore != null) {
          target.score = recScore;
          target.submissionStatus = HomeworkSubmissionStatus.graded;
        } else if (recComp == 'full') {
          target.completeness = 'full';
          target.submissionStatus = HomeworkSubmissionStatus.submitted;
          if (recTime != null) target.submittedAt ??= recTime;
        } else if (recComp != null && recComp.isNotEmpty) {
          target.completeness = recComp;
          if (!target.isGraded) {
            target.submissionStatus = HomeworkSubmissionStatus.unsubmitted;
          }
        }
      }
    }

    final sorted = byId.values.toList();
    sorted.sort((a, b) {
      int bucket(Todo t) {
        switch (t.effectiveStatus) {
          case HomeworkSubmissionStatus.unsubmitted:
            return 0; // 待提交且未截止优先
          case HomeworkSubmissionStatus.overdue:
            return 1; // 逾期未提交次之
          case HomeworkSubmissionStatus.submitted:
          case HomeworkSubmissionStatus.graded:
            return 2; // 已提交/已批改置后
        }
      }

      final ba = bucket(a);
      final bb = bucket(b);
      if (ba != bb) return ba.compareTo(bb);

      final ea = a.endTime;
      final eb = b.endTime;
      if (ea != null && eb != null) {
        // 未提交的按截止时间升序（最紧迫在最前）；已提交/逾期按时间倒序（最近在最前）
        return ba == 0 ? ea.compareTo(eb) : eb.compareTo(ea);
      }
      if (ea != null) return -1;
      if (eb != null) return 1;
      return b.id.compareTo(a.id);
    });

    return sorted;
  }

  /// 查询指定课程在“学在浙大”中的**全部作业与测验**（涵盖待提交、已提交、已批改与历史已截止活动）
  static Future<List<Todo>> fetchCourseHomeworks(
    HttpClient httpClient, {
    required String courseName,
    String? courseCode,
  }) async {
    final session = await ensureSession(httpClient);
    if (session == null) {
      return const [];
    }

    final tcCourseIds = await _resolveTronClassCourseIds(
      httpClient,
      session,
      courseName: courseName,
      courseCode: courseCode,
    );
    if (tcCourseIds.isEmpty) {
      return const [];
    }

    final collected = <Todo>[];
    final combinedReads = <dynamic>[];

    for (final tcId in tcCourseIds) {
      final cidStr = tcId.toString();

      // 1. 分页抓取 /homework-activities（包含历史及已完成作业）
      for (int page = 1; page <= 5; page++) {
        try {
          final uri = Uri.parse(
              'https://courses.zju.edu.cn/api/courses/$tcId/homework-activities?page=$page&page_size=100&reloadPage=false');
          final req = await httpClient.getUrl(uri).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw requestTimeout(),
              );
          req.cookies.add(session);
          req.headers.set(HttpHeaders.acceptHeader, 'application/json');
          final resp = await req.close().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw requestTimeout(),
              );
          if (resp.statusCode != HttpStatus.ok) break;
          final body = await readResponseBody(resp, context: '课程作业列表接口');
          final json = decodeJsonMap(body, context: '课程作业列表');
          final parsed = parseCourseHomeworkActivities(
            json,
            tcCourseId: cidStr,
            courseName: courseName,
          );
          collected.addAll(parsed);
          final totalPages = (asDouble(json['pages']) ?? 1).toInt();
          if (page >= totalPages || parsed.isEmpty) break;
        } catch (e) {
          debugPrint('fetchCourseHomeworks homework-activities page=$page error: $e');
          break;
        }
      }

      // 2. 补充抓取 /activities（涵盖在线小测、测验等活动）
      try {
        final actUri = Uri.parse(
            'https://courses.zju.edu.cn/api/courses/$tcId/activities');
        final req = await httpClient.getUrl(actUri).timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw requestTimeout(),
            );
        req.cookies.add(session);
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final resp = await req.close().timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw requestTimeout(),
            );
        if (resp.statusCode == HttpStatus.ok) {
          final body = await readResponseBody(resp, context: '课程活动列表接口');
          final json = decodeJsonMap(body, context: '课程活动列表');
          collected.addAll(parseCourseHomeworkActivities(
            json,
            tcCourseId: cidStr,
            courseName: courseName,
          ));
        }
      } catch (e) {
        debugPrint('fetchCourseHomeworks activities error: $e');
      }

      // 3. 拉取完成度与打分详情
      final reads = await fetchActivityReadsForCourse(
        httpClient,
        cidStr,
        sessionCookie: session,
      );
      final readList = asDynamicList(reads?['activity_reads']);
      if (readList != null) {
        combinedReads.addAll(readList);
      }
    }

    return mergeAndSortCourseHomeworks(
      collected,
      activityReadsJson: {'activity_reads': combinedReads},
      readLocalStatus: true,
    );
  }

  /// 检查目录路径是否允许直接通过 POSIX File API 创建与写入（排除 content:// / file:// 及无权限目录）
  static Future<bool> isDirectoryDirectlyWritable(String saveDir) async {
    final trimmed = saveDir.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('content://') ||
        trimmed.startsWith('file://')) {
      return false;
    }
    try {
      final dir = Directory(trimmed);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(
          '${dir.path}/.celechron_probe_${DateTime.now().microsecondsSinceEpoch}');
      await probe.writeAsBytes(const [], flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 将 HTTP 响应流保存到目标目录；当目标为原生选择器返回的 URI 或受限目录时自动通过临时文件中转原生拷贝
  static Future<String?> saveHttpResponseToDirectory(
    Stream<List<int>> resp, {
    required String saveDir,
    required String fileName,
    String? mimeType,
    bool? directWritable,
    Future<String?> Function(
      String sourcePath,
      String targetDir,
      String fileName, {
      String? mimeType,
    })? nativeCopyToDir,
  }) async {
    final canWriteDirect =
        directWritable ?? await isDirectoryDirectlyWritable(saveDir);
    if (canWriteDirect) {
      final dir = Directory(saveDir);
      final targetFile = File('${dir.path}/$fileName');
      final sink = targetFile.openWrite();
      await resp.pipe(sink);
      await sink.flush();
      await sink.close();
      if (await targetFile.exists() && await targetFile.length() > 0) {
        return targetFile.path;
      }
      return null;
    }

    if (nativeCopyToDir == null) {
      await resp.drain();
      return null;
    }

    final tempFile = File(
        '${Directory.systemTemp.path}/celechron_dl_${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      final sink = tempFile.openWrite();
      await resp.pipe(sink);
      await sink.flush();
      await sink.close();
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        return null;
      }
      return await nativeCopyToDir(
        tempFile.path,
        saveDir,
        fileName,
        mimeType: mimeType,
      );
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// 下载课件或附件到本地指定目录（包含 4 级回退下载链，支持仅预览 PDF 课件提取直链下载）
  static Future<String?> downloadCoursewareFile(
    HttpClient httpClient, {
    required CoursewareItem item,
    required String saveDir,
    Future<String?> Function(
      String sourcePath,
      String targetDir,
      String fileName, {
      String? mimeType,
    })? nativeCopyToDir,
  }) async {
    final session = await ensureSession(httpClient);
    final candidateUrls = <String>[];

    if (item.directUrl != null && item.directUrl!.isNotEmpty) {
      candidateUrls.add(item.directUrl!);
    }
    if (item.referenceId > 0) {
      candidateUrls.add(
          'https://courses.zju.edu.cn/api/uploads/reference/${item.referenceId}/blob');
    }
    if (item.uploadId > 0) {
      candidateUrls
          .add('https://courses.zju.edu.cn/api/uploads/${item.uploadId}/blob');
    }

    // 针对禁止直接下载但允许预览的 PDF/Office 课件，通过 preview=true 接口获取签名直链
    if (item.referenceId > 0 && session != null) {
      try {
        final previewUri = Uri.parse(
            'https://courses.zju.edu.cn/api/uploads/reference/document/${item.referenceId}/url?preview=true');
        final req = await httpClient
            .getUrl(previewUri)
            .timeout(const Duration(seconds: 8));
        req.cookies.add(session);
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final resp = await req.close().timeout(const Duration(seconds: 8));
        if (resp.statusCode == HttpStatus.ok) {
          final body = await readResponseBody(resp, context: '学在浙大课件预览链接');
          final json = decodeJsonMap(body, context: '学在浙大课件预览链接');
          final signedUrl = asString(json['url']);
          if (signedUrl != null && signedUrl.isNotEmpty) {
            candidateUrls.add(signedUrl);
          }
        }
      } catch (_) {}
    }

    final safeName = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final directWritable = await isDirectoryDirectlyWritable(saveDir);
    if (!directWritable && nativeCopyToDir == null) {
      return null;
    }

    for (final urlStr in candidateUrls) {
      try {
        var currentUri = Uri.parse(urlStr);
        for (int hop = 0; hop < 6; hop++) {
          final req = await httpClient
              .getUrl(currentUri)
              .timeout(const Duration(seconds: 15));
          req.followRedirects = false;
          if (session != null && currentUri.host.contains('zju.edu.cn')) {
            req.cookies.add(session);
          }
          final resp = await req.close().timeout(const Duration(seconds: 30));
          if (resp.isRedirect ||
              resp.statusCode == HttpStatus.movedPermanently ||
              resp.statusCode == HttpStatus.found ||
              resp.statusCode == HttpStatus.seeOther ||
              resp.statusCode == HttpStatus.temporaryRedirect) {
            final loc = resp.headers.value(HttpHeaders.locationHeader);
            await resp.drain();
            if (loc != null && loc.isNotEmpty) {
              currentUri = currentUri.resolve(loc);
              continue;
            }
            break;
          }
          if (resp.statusCode == HttpStatus.ok) {
            final contentType =
                resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
            if (contentType.contains('text/html')) {
              await resp.drain();
              break;
            }
            final saved = await saveHttpResponseToDirectory(
              resp,
              saveDir: saveDir,
              fileName: safeName,
              mimeType: contentType.split(';').first.trim(),
              directWritable: directWritable,
              nativeCopyToDir: nativeCopyToDir,
            );
            if (saved != null && saved.isNotEmpty) {
              return saved;
            }
          } else {
            await resp.drain();
          }
          break;
        }
      } catch (e) {
        debugPrint('downloadCoursewareFile candidate ($urlStr) failed: $e');
      }
    }
    return null;
  }
}

class CoursewareItem {
  final String name;
  final String sectionTitle;
  final int sizeBytes;
  final int uploadId;
  final int referenceId;
  final String? directUrl;
  final String source;

  const CoursewareItem({
    required this.name,
    required this.sectionTitle,
    required this.sizeBytes,
    this.uploadId = 0,
    this.referenceId = 0,
    this.directUrl,
    this.source = '学在浙大',
  });

  String get formattedSize {
    if (sizeBytes <= 0) return source;
    if (sizeBytes < 1024) return '$sizeBytes B · $source';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB · $source';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB · $source';
  }
}

class _CachedTodos {
  final List<Todo> todos;
  final bool used;
  final String? cachedAt;

  const _CachedTodos(this.todos, this.used, {this.cachedAt});
}
