import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:celechron/utils/tuple.dart';
import 'package:flutter/foundation.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/model/exams_dto.dart';
import 'package:celechron/design/captcha_input.dart';
import 'package:celechron/utils/global.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'exceptions.dart';
import 'response_utils.dart';
import 'eta.dart';

/// 培养方案与学分要求信息模型
class TrainingPlanInfo {
  final String pyfaId;
  final String planName;
  final String majorName;
  final String? grade;
  final String? collegeName;
  final double totalCredits;
  final Map<String, double> categoryCredits;
  final bool isFiveYear;

  TrainingPlanInfo({
    required this.pyfaId,
    required this.planName,
    required this.majorName,
    this.grade,
    this.collegeName,
    required this.totalCredits,
    this.categoryCredits = const {},
    this.isFiveYear = false,
  });

  Map<String, dynamic> toJson() => {
        'pyfaId': pyfaId,
        'planName': planName,
        'majorName': majorName,
        'grade': grade,
        'collegeName': collegeName,
        'totalCredits': totalCredits,
        'categoryCredits': categoryCredits,
        'isFiveYear': isFiveYear,
      };

  factory TrainingPlanInfo.fromJson(Map<String, dynamic> json) {
    return TrainingPlanInfo(
      pyfaId: json['pyfaId'] as String? ?? '',
      planName: json['planName'] as String? ?? '',
      majorName: json['majorName'] as String? ?? '',
      grade: json['grade'] as String?,
      collegeName: json['collegeName'] as String?,
      totalCredits: (json['totalCredits'] as num?)?.toDouble() ?? 160.0,
      categoryCredits: (json['categoryCredits'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ) ??
          {},
      isFiveYear: json['isFiveYear'] as bool? ?? false,
    );
  }
}

/// 本科教务网客户端；统一管理 CAS 业务会话、并发限流与按接口缓存降级。
class Zdbk {
  Cookie? _jSessionId;
  Cookie? _route;
  Cookie? _iPlanetDirectoryPro;
  String? _captcha;
  DatabaseHelper? _db;
  Future<bool>? _loginFuture;
  int _sessionGeneration = 0;
  int _activeSiteRequests = 0;
  final List<Completer<void>> _siteWaiters = [];

  set db(DatabaseHelper? db) {
    _db = db;
  }

  DateTime? get practiceScoresCacheUpdatedAt {
    final value = _db?.getCachedWebPage('zdbk_practiceScores_timestamp');
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<bool> login(HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    if (iPlanetDirectoryPro == null) {
      throw AuthenticationExpiredException("教务网：统一身份认证凭据无效");
    }
    _iPlanetDirectoryPro = iPlanetDirectoryPro;
    // 同一客户端只建立一套 JSESSIONID/route，避免并发 CAS 回调互相覆盖。
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
      HttpClient httpClient, Cookie iPlanetDirectoryPro) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    _captcha = null;
    _jSessionId = null;
    _route = null;
    // 第一步用统一认证 Cookie 换取 service 跳转；第二步访问跳转地址，
    // 业务站才会签发必须成对使用的 JSESSIONID 与 route。
    request = await httpClient
        .getUrl(Uri.parse(
            "https://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html"))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
    request.followRedirects = false;
    request.cookies.add(iPlanetDirectoryPro);
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    final firstBody = await readResponseBody(response, context: '教务网 CAS 登录');

    var stLocation = response.headers.value('location');
    if (!response.isRedirect || stLocation == null) {
      throw AuthenticationExpiredException(
          "教务网登录：统一身份认证凭据无效；HTTP ${response.statusCode}"
          "；Location ${stLocation ?? '<缺失>'}"
          "；响应摘要：${responseSummary(firstBody)}");
    } else if (stLocation.startsWith("http://")) {
      stLocation = stLocation.replaceFirst("http://", "https://");
    }
    request = await httpClient.getUrl(Uri.parse(stLocation)).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    final secondBody = await readResponseBody(response, context: '教务网登录');
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        bodyIndicatesAuthenticationFailure(secondBody)) {
      throw AuthenticationExpiredException(
          "教务网登录态失效；HTTP ${response.statusCode}"
          "；Location ${response.headers.value(HttpHeaders.locationHeader) ?? '<缺失>'}"
          "；响应摘要：${responseSummary(secondBody)}");
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw ExceptionWithMessage("教务网登录失败；HTTP ${response.statusCode}"
          "；Content-Type ${response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>'}"
          "；响应摘要：${responseSummary(secondBody)}");
    }

    if (response.cookies.any((element) => element.name == 'JSESSIONID')) {
      _jSessionId = response.cookies
          .firstWhere((element) => element.name == 'JSESSIONID');
    } else {
      throw ExceptionWithMessage(
          "教务网登录无法获取 JSESSIONID；HTTP ${response.statusCode}"
          "；响应摘要：${responseSummary(secondBody)}");
    }

    if (response.cookies.any((element) => element.name == 'route')) {
      _route =
          response.cookies.firstWhere((element) => element.name == 'route');
    } else {
      throw ExceptionWithMessage("教务网登录无法获取 route；HTTP ${response.statusCode}"
          "；响应摘要：${responseSummary(secondBody)}");
    }

    _sessionGeneration++;
    return true;
  }

  void logout() {
    _jSessionId = null;
    _route = null;
    _iPlanetDirectoryPro = null;
    _captcha = null;
  }

  void _validateResponse(HttpClientResponse response, String responseText,
      {required String context,
      required Uri requestUri,
      bool expectJson = true,
      bool relogged = false,
      bool retried = false}) {
    try {
      validateResponse(
        response: response,
        body: responseText,
        context: context,
        expectJson: expectJson,
        requestUri: requestUri,
        relogged: relogged,
        retried: retried,
      );
    } on AuthenticationExpiredException catch (error) {
      throw SessionExpiredException(
        shortErrorText(error),
        details: detailedErrorText(error),
        originalError: error,
        stackTrace: error.stackTrace,
      );
    }
  }

  Future<void> _relogin(HttpClient httpClient) async {
    final iPlanetDirectoryPro = _iPlanetDirectoryPro;
    if (iPlanetDirectoryPro == null) {
      throw LoginExpiredException("教务网会话已过期，请重新登录");
    }
    await login(httpClient, iPlanetDirectoryPro);
  }

  Future<T> _withAutoRelogin<T>(HttpClient httpClient,
      Future<T> Function(bool relogged, bool retried) requestFactory) {
    return _withSitePermit(
      () => _withAutoReloginUnlocked(httpClient, requestFactory),
    );
  }

  Future<T> _withAutoReloginUnlocked<T>(HttpClient httpClient,
      Future<T> Function(bool relogged, bool retried) requestFactory) async {
    var relogged = false;
    for (var i = 0; i < 2; i++) {
      var generation = _sessionGeneration;
      var reloginAttempted = false;
      try {
        if (_jSessionId == null || _route == null) {
          reloginAttempted = true;
          await _relogin(httpClient);
          relogged = true;
          generation = _sessionGeneration;
        }
        return await requestFactory(relogged, i > 0);
      } on AuthenticationExpiredException catch (error) {
        if (i == 1 || reloginAttempted) {
          throw LoginExpiredException(
            "教务网会话已过期，请手动重新登录",
            details: detailedErrorText(error),
            originalError: error,
          );
        }
        // 若其它并发请求已更新会话，本请求直接复用，避免重复登录。
        if (_sessionGeneration == generation) {
          await _relogin(httpClient);
          relogged = true;
        }
      }
    }
    throw LoginExpiredException("教务网会话已过期，请手动重新登录");
  }

  Future<T> _withSitePermit<T>(Future<T> Function() action) async {
    // 限制同时访问教务站的请求数，避免刷新时多个模块共同放大瞬时压力。
    if (_activeSiteRequests >= 3) {
      final waiter = Completer<void>();
      _siteWaiters.add(waiter);
      await waiter.future;
    }
    _activeSiteRequests++;
    try {
      return await action();
    } finally {
      _activeSiteRequests--;
      if (_siteWaiters.isNotEmpty) {
        _siteWaiters.removeAt(0).complete();
      }
    }
  }

  _CachedList _cachedList(String cacheKey, String context) {
    // 缓存内容必须重新走与实时响应相同的解析器；损坏缓存视为不可用。
    final cached = _db?.getCachedWebPage(cacheKey);
    if (cached == null || cached.trim().isEmpty) {
      return const _CachedList([], false);
    }
    try {
      final cachedAt = _db?.getCachedWebPage('${cacheKey}_timestamp') ?? '<未知>';
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: context,
        operation: 'readCache',
        cacheUsed: true,
        message: '使用缓存；缓存时间=$cachedAt',
      );
      return _CachedList(
        decodeJsonList(cached, context: context),
        true,
        cachedAt: cachedAt,
      );
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: context,
        operation: 'readCache',
        cacheUsed: false,
        error: error,
        stackTrace: stackTrace,
      );
      return const _CachedList([], false);
    }
  }

  void _writeCache(String cacheKey, String value) {
    unawaited(Future.wait([
      _db?.setCachedWebPage(cacheKey, value) ?? Future<void>.value(),
      _db?.setCachedWebPage(
            '${cacheKey}_timestamp',
            DateTime.now().toUtc().toIso8601String(),
          ) ??
          Future<void>.value(),
    ]));
  }

  Exception _cacheAwareException(
    Exception exception,
    _CachedList cache,
    String context,
  ) {
    // 返回缓存时仍保留实时异常，并用降级标记告知上层不要清空旧数据。
    if (!cache.used) return exception;
    return CachedDataException(
      '$context：实时请求失败，已使用缓存',
      details: [
        '缓存时间：${cache.cachedAt ?? '<未知>'}',
        detailedErrorText(exception),
      ].join('\n'),
      originalError: exception,
      stackTrace:
          exception is ExceptionWithMessage ? exception.stackTrace : null,
    );
  }

  List<Grade> _parseGrades(Object? raw, String context, {bool major = false}) {
    final items = asDynamicList(raw) ?? const [];
    final grades = <Grade>[];
    for (var index = 0; index < items.length; index++) {
      final item = asStringMap(items[index]);
      if (item == null) {
        if (kDebugMode) {
          debugPrint('$context：跳过第 ${index + 1} 条成绩，条目不是对象');
        }
        continue;
      }
      try {
        final grade = major ? Grade.fromMajor(item) : Grade(item);
        grades.add(grade);
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '$context：跳过第 ${index + 1} 条成绩：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }
    return grades;
  }

  /// 从教务网成绩/课程记录中提取用户主修专业名称
  String? _extractMajor(List<dynamic> items) {
    for (final raw in items) {
      final item = asStringMap(raw);
      if (item != null) {
        final major = asString(item['zymc']) ??
            asString(item['ZYMC']) ??
            asString(item['zyfxmc']) ??
            asString(item['ZYFXMC']) ??
            asString(item['xymc']) ??
            asString(item['XYMC']) ??
            asString(item['major']);
        if (major != null && major.trim().isNotEmpty && major != '未知') {
          return major.trim();
        }
      }
    }
    return null;
  }

  List<Session> _parseSessions(Object? raw, String context) {
    final items = asDynamicList(raw) ?? const [];
    final sessions = <Session>[];
    for (var index = 0; index < items.length; index++) {
      final item = asStringMap(items[index]);
      if (item == null ||
          item['kcb'] == null ||
          asString(item['sfyjskc']) == '1') {
        continue;
      }
      try {
        sessions.add(Session.fromZdbk(item));
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '$context：跳过第 ${index + 1} 条课程：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }
    return sessions;
  }

  List<ExamDto> _parseExams(Object? raw, String context) {
    final items = asDynamicList(raw) ?? const [];
    final exams = <ExamDto>[];
    for (var index = 0; index < items.length; index++) {
      final item = asStringMap(items[index]);
      if (item == null) continue;
      try {
        exams.add(ExamDto.fromZdbk(item));
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
              '$context：跳过第 ${index + 1} 条考试：${error.runtimeType}: $error\n$stackTrace');
        }
      }
    }
    return exams;
  }

  Future<Tuple<Exception?, Tuple<List<double>, String>>> getMajorGrade(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final uri = Uri.parse(
          "https://zdbk.zju.edu.cn/jwglxt/zycjtj/xszgkc_cxXsZgkcIndex.html?doType=query&queryModel.showCount=5000");

      try {
        request = await httpClient.postUrl(uri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.add(_jSessionId!);
        request.cookies.add(_route!);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        var responseText =
            await readResponseBody(response, context: '教务网主修成绩接口');
        const context = '教务网主修成绩接口';
        _validateResponse(response, responseText,
            context: context,
            requestUri: uri,
            relogged: relogged,
            retried: retried);
        final payload = decodeJsonMap(responseText,
            context: '$context；HTTP ${response.statusCode}');
        final items = asDynamicList(payload['items']);
        if (items == null) {
          throw ExceptionWithMessage(
              '$context：缺少 items 数组；HTTP ${response.statusCode}'
              '；响应摘要：${responseSummary(responseText)}');
        }
        final grades = _parseGrades(items, context, major: true);
        var majorGpa = GpaHelper.calculateGpa(grades);
        final major = _extractMajor(items);
        if (major != null) {
          _writeCache('zdbk_user_major', major);
        }
        _writeCache('zdbk_MajorGrade', jsonEncode(items));
        return Tuple(
            null, Tuple([majorGpa.item1[0], majorGpa.item2], responseText));
      } on Object catch (error, stackTrace) {
        if (error is AuthenticationExpiredException) rethrow;
        final exception = exceptionFrom(error,
            context: '教务网主修成绩接口',
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            stackTrace: stackTrace);
        final cachedItems = _cachedList('zdbk_MajorGrade', '教务网主修成绩缓存');
        final grades = _parseGrades(cachedItems.data, '教务网主修成绩缓存', major: true);
        var majorGpa = GpaHelper.calculateGpa(grades);
        return Tuple(
            _cacheAwareException(exception, cachedItems, '教务网主修成绩'),
            Tuple([majorGpa.item1[0], majorGpa.item2],
                '{"items":${jsonEncode(cachedItems.data)},"limit":0}'));
      }
    });
  }

  Future<Tuple<Exception?, Iterable<Grade>>> getTranscript(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final uri = Uri.parse(
          "https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000");

      try {
        request = await httpClient.postUrl(uri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.add(_jSessionId!);
        request.cookies.add(_route!);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        var responseText = await readResponseBody(response, context: '教务网成绩接口');
        const context = '教务网成绩接口';
        _validateResponse(response, responseText,
            context: context,
            requestUri: uri,
            relogged: relogged,
            retried: retried);
        final payload = decodeJsonMap(responseText,
            context: '$context；HTTP ${response.statusCode}');
        final items = asDynamicList(payload['items']);
        if (items == null) {
          throw ExceptionWithMessage(
              '$context：缺少 items 数组；HTTP ${response.statusCode}'
              '；响应摘要：${responseSummary(responseText)}');
        }
        final grades = _parseGrades(items, context);
        final major = _extractMajor(items);
        if (major != null) {
          _writeCache('zdbk_user_major', major);
        }
        _writeCache('zdbk_Transcript', jsonEncode(items));
        return Tuple(null, grades);
      } on Object catch (error, stackTrace) {
        if (error is AuthenticationExpiredException) rethrow;
        final exception = exceptionFrom(error,
            context: '教务网成绩接口',
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            stackTrace: stackTrace);
        final cached = _cachedList('zdbk_Transcript', '教务网成绩缓存');
        return Tuple(
          _cacheAwareException(exception, cached, '教务网成绩'),
          _parseGrades(cached.data, '教务网成绩缓存'),
        );
      }
    });
  }

  Future<Tuple<Exception?, Iterable<Session>>> getTimetable(
      HttpClient httpClient, String year, String semester) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final uri =
          Uri.parse("https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html");

      try {
        for (var i = 0; i < 3; i++) {
          request = await httpClient.postUrl(uri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          request.headers
            ..add("Referer",
                "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
            ..add('X-Requested-With', 'XMLHttpRequest');
          request.cookies.add(_jSessionId!);
          request.cookies.add(_route!);
          request.followRedirects = false;
          request.headers.contentType = ContentType(
              'application', 'x-www-form-urlencoded',
              charset: 'utf-8');
          request.add(
              utf8.encode('xnm=$year&xqm=$semester&captcha_value=$_captcha'));
          response = await request.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());

          var responseText =
              await readResponseBody(response, context: '教务网课表接口');
          final context = '教务网课表接口（学年 $year，学期 $semester，请求类型 课表）';
          _validateResponse(response, responseText,
              context: context,
              requestUri: uri,
              relogged: relogged,
              retried: retried);

          if (responseText.contains("captcha_error")) {
            _captcha = null;
            if (GlobalStatus.isFirstScreenReq) {
              throw ExceptionWithMessage("需要验证码");
            }
            var imageBytes = await getCaptcha(httpClient);
            var captcha = await ImageCodePortal.show(
                imageBytes: imageBytes,
                onRefresh: () async {
                  return await getCaptcha(httpClient);
                });
            if (captcha == null) {
              throw ExceptionWithMessage("验证码未填写");
            }
            _captcha = captcha.trim();
            continue;
          }

          if (responseText.trim() == "null") return Tuple(null, <Session>[]);
          final payload = decodeJsonMap(responseText,
              context: '$context；HTTP ${response.statusCode}');
          final items = asDynamicList(payload['kbList']);
          if (items == null) {
            throw ExceptionWithMessage(
                '$context：缺少 kbList 数组；HTTP ${response.statusCode}'
                '；响应摘要：${responseSummary(responseText)}');
          }
          final sessions = _parseSessions(items, context);
          _writeCache('zdbk_Timetable$year$semester', jsonEncode(items));

          final xsxx = asStringMap(payload['xsxx']);
          if (xsxx != null) {
            _writeCache('zdbk_student_info', jsonEncode(xsxx));
            final major = asString(xsxx['ZYMC']) ??
                asString(xsxx['zymc']) ??
                asString(xsxx['ZYFXMC']) ??
                asString(xsxx['zyfxmc']) ??
                asString(xsxx['XYMC']) ??
                asString(xsxx['xymc']);
            if (major != null && major.trim().isNotEmpty && major != '未知') {
              _writeCache('zdbk_user_major', major.trim());
            }
          }
          return Tuple(null, sessions);
        }
        throw ExceptionWithMessage("验证码识别失败");
      } on Object catch (error, stackTrace) {
        if (error is AuthenticationExpiredException) rethrow;
        final context = '教务网课表接口（学年 $year，学期 $semester，请求类型 课表）';
        final exception = exceptionFrom(error,
            context: context,
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            stackTrace: stackTrace);
        final cached =
            _cachedList('zdbk_Timetable$year$semester', '$context 缓存');
        return Tuple(
          _cacheAwareException(exception, cached, context),
          _parseSessions(cached.data, '$context 缓存'),
        );
      }
    });
  }

  Future<Tuple<Exception?, Iterable<ExamDto>>> getExamsDto(
      HttpClient httpClient) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final uri = Uri.parse(
          "https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html?doType=query&queryModel.showCount=5000");

      try {
        request = await httpClient.postUrl(uri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest');
        request.cookies.add(_jSessionId!);
        request.cookies.add(_route!);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        var responseText = await readResponseBody(response, context: '教务网考试接口');
        const context = '教务网考试接口（请求类型 考试）';
        _validateResponse(response, responseText,
            context: context,
            requestUri: uri,
            relogged: relogged,
            retried: retried);
        final payload = decodeJsonMap(responseText,
            context: '$context；HTTP ${response.statusCode}');
        final items = asDynamicList(payload['items']);
        if (items == null) {
          throw ExceptionWithMessage(
              '$context：缺少 items 数组；HTTP ${response.statusCode}'
              '；响应摘要：${responseSummary(responseText)}');
        }
        final exams = _parseExams(items, context);
        _writeCache('zdbk_exams', jsonEncode(items));
        return Tuple(null, exams);
      } on Object catch (error, stackTrace) {
        if (error is AuthenticationExpiredException) rethrow;
        final exception = exceptionFrom(error,
            context: '教务网考试接口（请求类型 考试）',
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            stackTrace: stackTrace);
        final cached = _cachedList('zdbk_exams', '教务网考试缓存');
        return Tuple(
          _cacheAwareException(exception, cached, '教务网考试'),
          _parseExams(cached.data, '教务网考试缓存'),
        );
      }
    });
  }

  Future<Tuple<Exception?, Map<String, double>>> getPracticeScores(
      HttpClient httpClient, String studentId) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final uri = Uri.parse(
          "https://zdbk.zju.edu.cn/jwglxt/dessktgl/dessktcx_cxDessktcxIndex.html?gnmkdm=N108001&layout=default&su=$studentId");

      try {
        request = await httpClient.getUrl(uri).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept',
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        request.cookies.add(_jSessionId!);
        request.cookies.add(_route!);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());

        var html = await readResponseBody(response, context: '教务网实践分接口');
        _validateResponse(response, html,
            context: '教务网实践分接口（学号 $studentId，请求类型 实践分）',
            requestUri: uri,
            expectJson: false,
            relogged: relogged,
            retried: retried);

        _writeCache("zdbk_practiceScores", html);

        var scores = <String, double>{
          'pt2': 0.0,
          'pt3': 0.0,
          'pt4': 0.0,
        };

        var rowPattern = RegExp(
            r'<tr>.*?<td[^>]*>.*?</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?</tr>',
            dotAll: true);
        var matches = rowPattern.allMatches(html);

        for (var match in matches) {
          var type = match.group(1)?.trim();
          var scoreStr = match.group(2)?.trim();
          if (type == null || scoreStr == null) continue;

          final score = double.tryParse(scoreStr);
          if (score == null) continue;

          if (type.contains('第二课堂')) {
            scores['pt2'] = score;
          } else if (type.contains('第三课堂')) {
            scores['pt3'] = score;
          } else if (type.contains('第四课堂')) {
            scores['pt4'] = score;
          }
        }

        if (scores['pt2'] == 0.0 &&
            scores['pt3'] == 0.0 &&
            scores['pt4'] == 0.0) {
          var altPattern = RegExp(
              r'<td[^>]*>第二课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt2Match = altPattern.firstMatch(html);
          if (pt2Match != null) {
            scores['pt2'] = double.tryParse(pt2Match.group(1) ?? '0') ?? 0.0;
          }

          altPattern = RegExp(r'<td[^>]*>第三课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt3Match = altPattern.firstMatch(html);
          if (pt3Match != null) {
            scores['pt3'] = double.tryParse(pt3Match.group(1) ?? '0') ?? 0.0;
          }

          altPattern = RegExp(r'<td[^>]*>第四课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
              dotAll: true);
          var pt4Match = altPattern.firstMatch(html);
          if (pt4Match != null) {
            scores['pt4'] = double.tryParse(pt4Match.group(1) ?? '0') ?? 0.0;
          }
        }

        return Tuple(null, scores);
      } on Object catch (error, stackTrace) {
        if (error is AuthenticationExpiredException) rethrow;

        final exception = exceptionFrom(error,
            context: '教务网实践分接口（学号 $studentId，请求类型 实践分）',
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            stackTrace: stackTrace);

        var cachedHtml = _db?.getCachedWebPage("zdbk_practiceScores");
        if (cachedHtml != null) {
          try {
            var scores = <String, double>{
              'pt2': 0.0,
              'pt3': 0.0,
              'pt4': 0.0,
            };
            var altPattern = RegExp(
                r'<td[^>]*>第二课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt2Match = altPattern.firstMatch(cachedHtml);
            if (pt2Match != null) {
              scores['pt2'] = double.tryParse(pt2Match.group(1) ?? '0') ?? 0.0;
            }

            altPattern = RegExp(r'<td[^>]*>第三课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt3Match = altPattern.firstMatch(cachedHtml);
            if (pt3Match != null) {
              scores['pt3'] = double.tryParse(pt3Match.group(1) ?? '0') ?? 0.0;
            }

            altPattern = RegExp(r'<td[^>]*>第四课堂</td>.*?<td[^>]*>([0-9.]+)</td>',
                dotAll: true);
            var pt4Match = altPattern.firstMatch(cachedHtml);
            if (pt4Match != null) {
              scores['pt4'] = double.tryParse(pt4Match.group(1) ?? '0') ?? 0.0;
            }
            final cachedException = CachedDataException(
              '教务网实践分：实时请求失败，已使用缓存',
              details: detailedErrorText(exception),
              originalError: exception,
            );
            return Tuple(cachedException, scores);
          } on Object catch (cacheError, cacheStackTrace) {
            DiagnosticLogService.instance.record(
              level: CelechronLogLevel.warning,
              module: '教务网实践分',
              operation: 'readCache',
              cacheUsed: false,
              error: cacheError,
              stackTrace: cacheStackTrace,
            );
          }
        }
        return Tuple(exception, {'pt2': 0.0, 'pt3': 0.0, 'pt4': 0.0});
      }
    });
  }

  Future<Uint8List> getCaptcha(HttpClient httpClient) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    if (_jSessionId == null || _route == null) {
      throw ExceptionWithMessage("未登录");
    }
    request = await httpClient
        .getUrl(Uri.parse(
            "https://zdbk.zju.edu.cn/jwglxt/kaptcha?time=${DateTime.now().millisecondsSinceEpoch}"))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
    request.cookies.add(_jSessionId!);
    request.cookies.add(_route!);
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    var bytes = await consolidateHttpClientResponseBytes(response);
    final contentType =
        response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>';
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (response.isRedirect ||
        response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      throw AuthenticationExpiredException(
          '教务网验证码接口：登录态已失效；HTTP ${response.statusCode}'
          '${location == null ? '' : '；Location $location'}');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !contentType.toLowerCase().startsWith('image/')) {
      final body = utf8.decode(bytes, allowMalformed: true);
      throw ExceptionWithMessage('教务网验证码接口返回异常；HTTP ${response.statusCode}'
          '；Content-Type $contentType'
          '${location == null ? '' : '；Location $location'}'
          '；响应摘要：${responseSummary(body)}');
    }
    return bytes;
  }

  /// 获取用户主修专业/大类名称（多级多源兜底：本地缓存 -> 课表学籍 -> 成绩单 -> 教务网学籍JSON -> 教务网学籍HTML -> ETA 学工系统）
  Future<Tuple<Exception?, String?>> getStudentMajor(
      HttpClient httpClient, {String? studentId}) async {
    final cached = _db?.getCachedWebPage('zdbk_user_major');
    if (cached != null && cached.trim().isNotEmpty) {
      return Tuple(null, cached.trim());
    }

    // 1. 检查学生个人信息缓存（由课表接口写入）
    final studentInfo = _db?.getCachedWebPage('zdbk_student_info');
    if (studentInfo != null && studentInfo.isNotEmpty) {
      try {
        final decoded = jsonDecode(studentInfo);
        final map = asStringMap(decoded);
        if (map != null) {
          final major = asString(map['ZYMC']) ??
              asString(map['zymc']) ??
              asString(map['ZYFXMC']) ??
              asString(map['zyfxmc']) ??
              asString(map['XYMC']) ??
              asString(map['xymc']);
          if (major != null && major.trim().isNotEmpty && major != '未知') {
            _writeCache('zdbk_user_major', major.trim());
            return Tuple(null, major.trim());
          }
        }
      } catch (_) {}
    }

    // 2. 检查成绩单与主修成绩缓存
    final transcriptCache = _cachedList('zdbk_Transcript', '教务网成绩缓存');
    final major1 = _extractMajor(transcriptCache.data);
    if (major1 != null) {
      _writeCache('zdbk_user_major', major1);
      return Tuple(null, major1);
    }
    final majorCache = _cachedList('zdbk_MajorGrade', '教务网主修成绩缓存');
    final major2 = _extractMajor(majorCache.data);
    if (major2 != null) {
      _writeCache('zdbk_user_major', major2);
      return Tuple(null, major2);
    }

    // 3. 尝试主动请求教务网学籍接口
    try {
      final zdbkMajor = await _withAutoRelogin(httpClient, (relogged, retried) async {
        // 3.1 优先请求正方标准学生个人信息 JSON 接口
        try {
          final suParam = studentId != null && studentId.isNotEmpty ? '&su=$studentId' : '';
          final jsonUri = Uri.parse(
              "https://zdbk.zju.edu.cn/jwglxt/xsxxxggl/xsxxwh_cxCkDgxsxx.html?gnmkdm=N100801$suParam");
          final jsonReq = await httpClient.getUrl(jsonUri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          jsonReq.headers
            ..add("Referer", "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('X-Requested-With', 'XMLHttpRequest')
            ..add('Accept', 'application/json, text/plain, */*');
          jsonReq.cookies.add(_jSessionId!);
          jsonReq.cookies.add(_route!);
          jsonReq.followRedirects = false;
          final jsonResp = await jsonReq.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final jsonBody = await readResponseBody(jsonResp, context: '教务网学生信息JSON接口');
          if (jsonResp.statusCode == 200 && jsonBody.isNotEmpty) {
            try {
              final decoded = jsonDecode(jsonBody);
              final map = asStringMap(decoded);
              if (map != null) {
                final major = asString(map['zymc']) ??
                    asString(map['ZYMC']) ??
                    asString(map['zyfxmc']) ??
                    asString(map['xymc']) ??
                    asString(map['jgmc']);
                if (major != null &&
                    major.trim().isNotEmpty &&
                    major != '未知' &&
                    major != '无') {
                  _writeCache('zdbk_user_major', major.trim());
                  return Tuple<Exception?, String?>(null, major.trim());
                }
              }
            } catch (_) {}
          }
        } catch (_) {}

        // 3.2 降级请求教务网学籍信息维护 HTML 页面正则匹配
        late HttpClientRequest request;
        late HttpClientResponse response;
        final uri = Uri.parse(
            "https://zdbk.zju.edu.cn/jwglxt/xsxxxggl/xsgrxxwh_cxXsgrxx.html?gnmkdm=N100801&layout=default");

        try {
          request = await httpClient.getUrl(uri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          request.headers
            ..add("Referer",
                "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept',
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
          request.cookies.add(_jSessionId!);
          request.cookies.add(_route!);
          request.followRedirects = false;
          response = await request.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());

          var responseText =
              await readResponseBody(response, context: '教务网学籍信息接口');
          _validateResponse(response, responseText,
              context: '教务网学籍信息接口',
              requestUri: uri,
              relogged: relogged,
              retried: retried,
              expectJson: false);

          final patterns = [
            RegExp('id=[\"\']col_zy(?:fx)?_id[\"\'][^>]*>\\s*<p[^>]*>([^<]+)</p>',
                caseSensitive: false),
            RegExp('name=[\"\']zy(?:mc|fxmc)?[\"\'][^>]*value=[\"\']([^\"\']+)[\"\']',
                caseSensitive: false),
            RegExp('id=[\"\']col_jg_id[\"\'][^>]*>\\s*<p[^>]*>([^<]+)</p>',
                caseSensitive: false),
            RegExp('id=[\"\']col_bh_id[\"\'][^>]*>\\s*<p[^>]*>([^<]+)</p>',
                caseSensitive: false),
          ];

          for (final p in patterns) {
            final m = p.firstMatch(responseText);
            final text = m?.group(1)?.trim();
            if (text != null &&
                text.isNotEmpty &&
                text != '未知' &&
                text != '无' &&
                !text.contains('&nbsp;')) {
              _writeCache('zdbk_user_major', text);
              return Tuple<Exception?, String?>(null, text);
            }
          }

          return Tuple<Exception?, String?>(null, null);
        } on Object catch (e) {
          if (e is AuthenticationExpiredException) rethrow;
          return Tuple<Exception?, String?>(null, null);
        }
      });

      if (zdbkMajor.item2 != null && zdbkMajor.item2!.isNotEmpty) {
        return zdbkMajor;
      }
    } catch (_) {}

    // 4. 尝试从浙大 ETA “三全育人”学生信息平台（eta.zju.edu.cn）获取专业
    try {
      final etaMajor = await Eta.getStudentMajor(httpClient, _iPlanetDirectoryPro);
      if (etaMajor != null && etaMajor.trim().isNotEmpty) {
        _writeCache('zdbk_user_major', etaMajor.trim());
        return Tuple(null, etaMajor.trim());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('从 ETA 获取专业兜底失败: $e');
      }
    }

    return Tuple(null, null);
  }

  /// 查询教务网培养方案学生查询列表（gnmkdm=N153020）
  Future<Tuple<Exception?, List<Map<String, dynamic>>>> getTrainingPlans(
      HttpClient httpClient,
      {String? studentId,
      String? majorName,
      String? grade}) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      late HttpClientRequest request;
      late HttpClientResponse response;
      final suParam = studentId != null && studentId.isNotEmpty ? '&su=$studentId' : '';
      final uri = Uri.parse(
          "https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html?doType=query&gnmkdm=N153020$suParam");

      try {
        request = await httpClient.postUrl(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout());
        request.headers
          ..add("Referer",
              "https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html?gnmkdm=N153020&layout=default$suParam")
          ..set('Connection', 'close')
          ..add('User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
          ..add('Accept', 'application/json, text/javascript, */*; q=0.01')
          ..add('X-Requested-With', 'XMLHttpRequest')
          ..set(HttpHeaders.contentTypeHeader,
              'application/x-www-form-urlencoded;charset=UTF-8');
        request.cookies.add(_jSessionId!);
        request.cookies.add(_route!);
        request.followRedirects = false;

        final queryParams = <String, String>{
          'queryModel.showCount': '5000',
          'queryModel.currentPage': '1',
          'queryModel.sortOrder': 'asc',
          '_search': 'false',
        };
        if (majorName != null && majorName.trim().isNotEmpty) {
          queryParams['zymc'] = majorName.trim();
        }
        if (grade != null && grade.trim().isNotEmpty) {
          queryParams['njdm_id'] = grade.trim();
        }

        final encodedBody = queryParams.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
        request.add(utf8.encode(encodedBody));

        response = await request.close().timeout(const Duration(seconds: 10),
            onTimeout: () => throw requestTimeout());

        var responseText =
            await readResponseBody(response, context: '教务网培养方案列表接口');
        _validateResponse(response, responseText,
            context: '教务网培养方案列表接口',
            requestUri: uri,
            relogged: relogged,
            retried: retried,
            expectJson: true);

        final decoded = jsonDecode(responseText);
        final rawItems = asDynamicList(
            decoded is Map ? decoded['items'] : decoded);
        final List<Map<String, dynamic>> items = [];
        if (rawItems != null) {
          for (final item in rawItems) {
            final m = asStringMap(item);
            if (m != null) items.add(m);
          }
        }
        _writeCache('zdbk_training_plans', responseText);
        return Tuple(null, items);
      } on Object catch (e) {
        if (e is AuthenticationExpiredException) rethrow;
        return Tuple(ExceptionWithMessage("获取培养方案列表失败: $e"), []);
      }
    });
  }

  /// 请求培养方案预览/打印页面并解析最低毕业学分及各模块要求学分
  Future<Tuple<Exception?, Map<String, dynamic>>> fetchTrainingPlanDetail(
      HttpClient httpClient, String pyfaId,
      {String? studentId}) async {
    return await _withAutoRelogin(httpClient, (relogged, retried) async {
      final suParam = studentId != null && studentId.isNotEmpty ? '&su=$studentId' : '';
      final previewUris = [
        Uri.parse(
            "https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_dyPyfaxs.html?pyfa_id=$pyfaId&gnmkdm=N153020$suParam"),
        Uri.parse(
            "https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxsView.html?pyfa_id=$pyfaId&gnmkdm=N153020$suParam"),
      ];

      double? totalCredits;
      final categoryCredits = <String, double>{};

      for (final uri in previewUris) {
        try {
          final request = await httpClient.getUrl(uri).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          request.headers
            ..add("Referer",
                "https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html?gnmkdm=N153020&layout=default$suParam")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept',
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
          request.cookies.add(_jSessionId!);
          request.cookies.add(_route!);
          request.followRedirects = false;

          final response = await request.close().timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final body =
              await readResponseBody(response, context: '教务网培养方案详情预览');

          if (response.statusCode == 200 && body.isNotEmpty) {
            // 解析总毕业学分要求
            final creditPatterns = [
              RegExp(
                  r'(?:最低毕业学分|毕业要求最低学分|毕业最低学分|最低修读学分|最低学分要求|毕业总学分|最低要求学分|修读总学分|毕业要求|总学分)[^\d\r\n]{0,25}(\d{2,3}(?:\.\d+)?)',
                  caseSensitive: false),
              RegExp(r'(\d{2,3}(?:\.\d+)?)\s*学分[^\w\r\n]{0,10}(?:毕业|最低)',
                  caseSensitive: false),
              RegExp(r'要求[^\d\r\n]{0,10}(\d{2,3}(?:\.\d+)?)\s*学分',
                  caseSensitive: false),
            ];

            for (final p in creditPatterns) {
              final m = p.firstMatch(body);
              if (m != null) {
                final parsed = double.tryParse(m.group(1) ?? '');
                if (parsed != null && parsed >= 100 && parsed <= 300) {
                  totalCredits = parsed;
                  break;
                }
              }
            }

            // 解析各模块分类学分
            final catPatterns = {
              '通识必修课': RegExp(
                  r'(?:通识必修|通识教育必修)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
              '通识选修课': RegExp(
                  r'(?:通识选修|通识核心|通识教育选修)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
              '大类基础课': RegExp(
                  r'(?:大类基础|学科基础|大类课程)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
              '专业必修课': RegExp(
                  r'(?:专业必修|专业核心)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
              '专业选修课': RegExp(
                  r'(?:专业选修|专业方向)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
              '实践与毕业设计': RegExp(
                  r'(?:实践教学|集中实践|实践与毕业设计|毕业论文|毕业设计)[^\d\r\n]{0,15}(\d{1,2}(?:\.\d+)?)'),
            };

            catPatterns.forEach((cat, reg) {
              final m = reg.firstMatch(body);
              if (m != null) {
                final val = double.tryParse(m.group(1) ?? '');
                if (val != null && val > 0 && val < 100) {
                  categoryCredits[cat] = val;
                }
              }
            });

            if (totalCredits != null) {
              break;
            }
          }
        } catch (_) {}
      }

      return Tuple(null, {
        'totalCredits': totalCredits,
        'categoryCredits': categoryCredits,
      });
    });
  }

  /// 依据专业名称查询匹配的培养方案并提取学分配置
  Future<Tuple<Exception?, TrainingPlanInfo?>> getTrainingPlanForMajor(
      HttpClient httpClient, String majorName,
      {String? studentId, String? grade}) async {
    final cleaned = majorName.trim();
    if (cleaned.isEmpty) return Tuple(null, null);

    // 检查缓存
    final cacheKey = 'zdbk_training_plan_$cleaned';
    final cachedJson = _db?.getCachedWebPage(cacheKey);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) {
          return Tuple(null, TrainingPlanInfo.fromJson(decoded));
        }
      } catch (_) {}
    }

    // 查询所有培养方案列表
    final plansRes = await getTrainingPlans(httpClient,
        studentId: studentId, majorName: cleaned, grade: grade);
    if (plansRes.item1 != null) {
      return Tuple(plansRes.item1, null);
    }

    final items = plansRes.item2;
    if (items.isEmpty) {
      // 尝试无专业过滤再查一次
      final allPlansRes = await getTrainingPlans(httpClient, studentId: studentId);
      if (allPlansRes.item2.isNotEmpty) {
        items.addAll(allPlansRes.item2);
      }
    }

    if (items.isEmpty) {
      return Tuple(null, null);
    }

    // 在列表中匹配最贴近该专业的培养方案
    Map<String, dynamic>? matchedItem;

    // 规则 1：专业全名完全匹配
    for (final it in items) {
      final zymc = asString(it['zymc']) ?? asString(it['ZYMC']) ?? '';
      if (zymc == cleaned) {
        matchedItem = it;
        break;
      }
    }

    // 规则 2：方案名称包含专业全名
    if (matchedItem == null) {
      for (final it in items) {
        final pyfamc = asString(it['pyfamc']) ?? '';
        if (pyfamc.contains(cleaned)) {
          matchedItem = it;
          break;
        }
      }
    }

    // 规则 3：核心专业名称匹配
    if (matchedItem == null) {
      final coreName = cleaned
          .replaceAll('（', '(')
          .replaceAll('）', ')')
          .replaceAll('试验班', '')
          .replaceAll('班', '')
          .trim();
      for (final it in items) {
        final zymc = asString(it['zymc']) ?? asString(it['ZYMC']) ?? '';
        final pyfamc = asString(it['pyfamc']) ?? '';
        if (zymc.contains(coreName) || pyfamc.contains(coreName)) {
          matchedItem = it;
          break;
        }
      }
    }

    // 规则 4：兜底首项
    matchedItem ??= items.first;

    final pyfaId = asString(matchedItem['pyfa_id']) ?? '';
    final planName = asString(matchedItem['pyfamc']) ?? '$cleaned培养方案';
    final zymc = asString(matchedItem['zymc']) ?? cleaned;
    final planGrade = asString(matchedItem['njdm_id']) ?? grade;
    final college = asString(matchedItem['jgmc']);

    final isFiveYear = cleaned.contains('建筑') ||
        cleaned.contains('临床') ||
        cleaned.contains('口腔') ||
        cleaned.contains('医学') ||
        cleaned.contains('规划');

    // 检查列表自带的毕业要求学分字段（如 bbyq）
    double? totalCredits;
    final bbyqStr = asString(matchedItem['bbyq']) ?? asString(matchedItem['zdbyxf']);
    if (bbyqStr != null) {
      final parsed = double.tryParse(bbyqStr);
      if (parsed != null && parsed >= 100 && parsed <= 300) {
        totalCredits = parsed;
      }
    }

    Map<String, double> categoryCredits = {};

    // 若有方案 ID，尝试进一步深入详情预览提取精准学分与各类别要求
    if (pyfaId.isNotEmpty) {
      final detailRes =
          await fetchTrainingPlanDetail(httpClient, pyfaId, studentId: studentId);
      final detailMap = detailRes.item2;
      if (detailMap['totalCredits'] != null && detailMap['totalCredits'] is double) {
        totalCredits = detailMap['totalCredits'] as double;
      }
      if (detailMap['categoryCredits'] != null &&
          detailMap['categoryCredits'] is Map) {
        categoryCredits =
            Map<String, double>.from(detailMap['categoryCredits'] as Map);
      }
    }

    totalCredits ??= isFiveYear ? 210.0 : 160.0;

    final planInfo = TrainingPlanInfo(
      pyfaId: pyfaId,
      planName: planName,
      majorName: zymc,
      grade: planGrade,
      collegeName: college,
      totalCredits: totalCredits,
      categoryCredits: categoryCredits,
      isFiveYear: isFiveYear,
    );

    try {
      _writeCache(cacheKey, jsonEncode(planInfo.toJson()));
    } catch (_) {}

    return Tuple(null, planInfo);
  }


  Future<String> solveCaptcha(HttpClient httpClient) async {
    throw UnimplementedError("验证码识别功能未开发");
  }
}

class _CachedList {
  final List<dynamic> data;
  final bool used;
  final String? cachedAt;

  const _CachedList(this.data, this.used, {this.cachedAt});
}
