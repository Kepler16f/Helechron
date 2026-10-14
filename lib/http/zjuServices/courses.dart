// This implementation is adapted from the project "login-ZJU" by 5dbwat4(https://github.com/5dbwat4/login-ZJU) under the MIT License.
// See: https://github.com/5dbwat4/login-ZJU/blob/main/src/utils/fetch-with-cookie.ts

import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/data_source_status.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/todo_task_sync.dart';
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

  static List<int> _buildMultipartPayload({
    required String boundary,
    required String fileName,
    required List<int> fileBytes,
    String parentType = 'submission_upload',
    int parentId = 0,
  }) {
    final bytes = <int>[];
    bytes.addAll(utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="parent_type"\r\n\r\n$parentType\r\n'));
    bytes.addAll(utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="parent_id"\r\n\r\n$parentId\r\n'));
    final mimeType = _lookupMimeType(fileName);
    bytes.addAll(utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$fileName"\r\nContent-Type: $mimeType\r\n\r\n'));
    bytes.addAll(fileBytes);
    bytes.addAll(utf8.encode('\r\n--$boundary--\r\n'));
    return bytes;
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
  }) async {
    try {
      final uploadUri = uploadUrlStr.startsWith('http')
          ? Uri.parse(uploadUrlStr)
          : Uri.parse('https://courses.zju.edu.cn$uploadUrlStr');

      final isExternalOss = uploadUri.host.contains('aliyuncs.com') ||
          uploadUri.host.contains('amazonaws.com') ||
          uploadUri.queryParameters.containsKey('OSSAccessKeyId') ||
          uploadUri.queryParameters.containsKey('Signature');

      if (isExternalOss) {
        final putReq = await httpClient.putUrl(uploadUri).timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw requestTimeout(),
            );
        final mime = _lookupMimeType(fileName);
        putReq.headers.set(HttpHeaders.contentTypeHeader, mime);
        putReq.contentLength = fileBytes.length;
        putReq.add(fileBytes);
        final putResp = await putReq.close();
        if (putResp.statusCode == HttpStatus.ok ||
            putResp.statusCode == HttpStatus.created ||
            putResp.statusCode == HttpStatus.noContent) {
          await _notifyUploadFinish(httpClient, session, uploadId);
          return true;
        }
      } else {
        final putReq = await httpClient.putUrl(uploadUri).timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw requestTimeout(),
            );
        putReq.cookies.add(session);
        putReq.headers
            .set(HttpHeaders.contentTypeHeader, _lookupMimeType(fileName));
        putReq.contentLength = fileBytes.length;
        putReq.add(fileBytes);
        final putResp = await putReq.close();
        if (putResp.statusCode == HttpStatus.ok ||
            putResp.statusCode == HttpStatus.created ||
            putResp.statusCode == HttpStatus.noContent) {
          await _notifyUploadFinish(httpClient, session, uploadId);
          return true;
        }

        final boundary =
            '----TronStreamBoundary${DateTime.now().millisecondsSinceEpoch}';
        final header = utf8.encode(
            '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$fileName"\r\nContent-Type: ${_lookupMimeType(fileName)}\r\n\r\n');
        final footer = utf8.encode('\r\n--$boundary--\r\n');
        final totalLength = header.length + fileBytes.length + footer.length;

        final postReq = await httpClient.postUrl(uploadUri).timeout(
              const Duration(seconds: 40),
              onTimeout: () => throw requestTimeout(),
            );
        postReq.cookies.add(session);
        postReq.headers.set(HttpHeaders.contentTypeHeader,
            'multipart/form-data; boundary=$boundary');
        postReq.contentLength = totalLength;
        postReq.add(header);
        postReq.add(fileBytes);
        postReq.add(footer);
        final postResp = await postReq.close();
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
      final payload = _buildMultipartPayload(
        boundary: boundary,
        fileName: fileName,
        fileBytes: fileBytes,
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
      req.contentLength = payload.length;
      req.add(payload);

      final resp = await req.close().timeout(
            const Duration(seconds: 35),
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
            return uploadId;
          }
          final streamed = await _streamBytesToUploadUrl(
            httpClient: httpClient,
            session: activeSession,
            uploadUrlStr: uploadUrlStr,
            fileName: fileName,
            fileBytes: fileBytes,
            uploadId: uploadId,
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
            return uploadId;
          }
          final streamed = await _streamBytesToUploadUrl(
            httpClient: httpClient,
            session: activeSession,
            uploadUrlStr: uploadUrlStr,
            fileName: fileName,
            fileBytes: fileBytes,
            uploadId: uploadId,
          );
          if (streamed) return uploadId;
        }
      }
    } catch (e) {
      debugPrint('uploadSubmissionFile Strategy 2 (ticketed) error: $e');
    }

    // 策略 3：课程级接口回退（POST /api/courses/$courseId/uploads）
    if (courseId != null && courseId.isNotEmpty) {
      try {
        final boundary =
            '----TronClassBoundary${DateTime.now().millisecondsSinceEpoch}';
        final payload = _buildMultipartPayload(
          boundary: boundary,
          fileName: fileName,
          fileBytes: fileBytes,
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
        req.contentLength = payload.length;
        req.add(payload);

        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok ||
            resp.statusCode == HttpStatus.created) {
          final body = await readResponseBody(resp, context: '课程级上传响应');
          final json = decodeJsonMap(body, context: '课程级上传响应');
          final uploadId = (json['id'] as num?)?.toInt();
          if (uploadId != null) return uploadId;
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
}

class _CachedTodos {
  final List<Todo> todos;
  final bool used;
  final String? cachedAt;

  const _CachedTodos(this.todos, this.used, {this.cachedAt});
}
