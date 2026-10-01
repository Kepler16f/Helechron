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

  /// 从浙大本科生学号推算入学年级（例如 "3260101109" -> "2026"，"3240101234" -> "2024"）
  static String? inferGradeFromStudentId(String? studentId) {
    if (studentId == null || studentId.trim().isEmpty) return null;
    final trimmed = studentId.trim();
    final match = RegExp(r'^3(\d{2})').firstMatch(trimmed);
    if (match != null) {
      final yy = match.group(1)!;
      return '20$yy';
    }
    return null;
  }

  /// 标准化专业名称（清洗班级残留、统一中英括号并展开常见简称）
  static String normalizeMajorName(String name) {
    var s = name.trim().replaceAll('（', '(').replaceAll('）', ')');

    // 移除可能存在的开头部年级，如 "2026级工科试验班(信息)" -> "工科试验班(信息)"
    s = s.replaceFirst(RegExp(r'^\d{2,4}级'), '').trim();

    // 移除末尾数字班号，如 "2601班" 或 "2601"
    s = s.replaceFirst(RegExp(r'\d+班?$'), '').trim();

    if (s.endsWith('班') && !s.contains('试验班')) {
      s = s.substring(0, s.length - 1).trim();
    }

    const abbreviations = {
      '工信': '工科试验班(信息)',
      '工信大类': '工科试验班(信息)',
      '信息大类': '工科试验班(信息)',
      '工科试验班(工信)': '工科试验班(信息)',
      '工科试验班(信息)': '工科试验班(信息)',
      '工科': '工科试验班',
      '社科': '社会科学试验班',
      '人文': '人文科学试验班',
      '理试': '理科试验班',
      '信工': '信息工程',
      '信电': '信息工程',
      '计科': '计算机科学与技术',
      '计算机': '计算机科学与技术',
      '软工': '软件工程',
      '软件': '软件工程',
      '电自': '电气工程及其自动化',
      '电气': '电气工程及其自动化',
      '自动化': '自动化',
      '光电': '光电信息科学与工程',
      '微电': '微电子科学与工程',
      '机械': '机械工程',
    };
    return abbreviations[s] ?? s;
  }

  /// 从班级名称中提取主修专业或大类（例如 "信息工程2201班" -> "信息工程"，"工科试验班（信息）2601" -> "工科试验班(信息)"，"工信2601" -> "工科试验班(信息)"）
  static String? extractMajorFromClassName(String? className) {
    if (className == null) return null;
    var name = className.trim().replaceAll('&nbsp;', '');
    if (name.isEmpty || name == '未知' || name == '无') return null;

    // 清理班级末尾常见校区/学园括号标注，如 "(丹青)", "(云峰)", "(蓝田)", "(竺院)"
    name = name.replaceAll(RegExp(r'[\(（](?:丹青|云峰|蓝田|竺院)[\)）]'), '').trim();

    // 统一中英文括号
    name = name.replaceAll('（', '(').replaceAll('）', ')');

    // 移除末尾的数字班号及“班”字，例如 "工科试验班(信息)2601班" -> "工科试验班(信息)", "信息工程2201" -> "信息工程"
    name = name.replaceFirst(RegExp(r'\d+班?$'), '').trim();

    // 若依然以“班”结尾且不属于“试验班”，去除末尾“班”
    if (name.endsWith('班') && !name.contains('试验班')) {
      name = name.substring(0, name.length - 1).trim();
    }

    if (name.isNotEmpty && name.length >= 2) {
      return normalizeMajorName(name);
    }
    return null;
  }

  /// 通用 HTML 表单与表格键值对解析器（针对正方教务网 Bootstrap 与 Table 布局）
  static Map<String, String> parseHtmlFormFields(String html) {
    final result = <String, String>{};

    // 1. 匹配 <label>Key</label> ... <p class="form-control-static">Value</p>
    final labelPStaticRegex = RegExp(
      r'<label[^>]*>\s*([^<:：\s]+?)\s*[:：]?\s*</label>[\s\S]*?<p[^>]*class=["\x27][^"\x27]*form-control-static[^"\x27]*["\x27][^>]*>\s*([^<]+?)\s*</p>',
      caseSensitive: false,
    );
    for (final m in labelPStaticRegex.allMatches(html)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isNotEmpty && v.isNotEmpty && v != '&nbsp;') {
        result[k] = v;
      }
    }

    // 2. 匹配任意 <label>Key</label> ... <p>Value</p>
    final generalLabelP = RegExp(
      r'<label[^>]*>\s*([^<:：\s]+?)\s*[:：]?\s*</label>[\s\S]*?<p[^>]*>\s*([^<]+?)\s*</p>',
      caseSensitive: false,
    );
    for (final m in generalLabelP.allMatches(html)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isNotEmpty && v.isNotEmpty && v != '&nbsp;' && !result.containsKey(k)) {
        result[k] = v;
      }
    }

    // 3. 匹配表格 <th>Key</th> ... <td>Value</td>
    final thTdRegex = RegExp(
      r'<th[^>]*>\s*([^<:：\s]+?)\s*[:：]?\s*</th>[\s\S]*?<td[^>]*>\s*([^<]+?)\s*</td>',
      caseSensitive: false,
    );
    for (final m in thTdRegex.allMatches(html)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isNotEmpty && v.isNotEmpty && v != '&nbsp;' && !result.containsKey(k)) {
        result[k] = v;
      }
    }

    // 4. 匹配 <input name="k" value="v" /> 或 id="k" value="v"
    final inputRegex = RegExp(
      r'<input[^>]+(?:name|id)=["\x27]([^"\x27]+)["\x27][^>]+value=["\x27]([^"\x27]*)["\x27]|<input[^>]+value=["\x27]([^"\x27]*)["\x27][^>]+(?:name|id)=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    );
    for (final m in inputRegex.allMatches(html)) {
      final k = (m.group(1) ?? m.group(4))?.trim() ?? '';
      final v = (m.group(2) ?? m.group(3))?.trim() ?? '';
      if (k.isNotEmpty && v.isNotEmpty && v != '&nbsp;' && !result.containsKey(k)) {
        result[k] = v;
      }
    }

    return result;
  }

  /// 从 Map 键值对或 HTML 解析出的键值对中提取主修专业全称
  static String? extractMajorFromKeyValues(Map<String, dynamic> map) {
    final candidateKeys = [
      '专业名称',
      'zymc',
      'ZYMC',
      'majorName',
      'major',
      '主修专业',
      '专业',
      '大类名称',
      '大类',
      '专业（类）',
      '专业方向',
      'zyfxmc',
      'ZYFXMC',
      'evalMajor',
      'zszymc',
    ];

    for (final key in candidateKeys) {
      if (map.containsKey(key)) {
        final val = map[key];
        if (val is String) {
          final cleaned = val.trim();
          if (cleaned.isNotEmpty &&
              cleaned != '未知' &&
              cleaned != '无' &&
              !cleaned.contains('&nbsp;') &&
              !cleaned.endsWith('学院') &&
              !cleaned.endsWith('学园') &&
              !cleaned.endsWith('学部')) {
            return cleaned;
          }
        }
      }
    }

    // 尝试从班级提取
    final className = map['班级名称'] ?? map['班级'] ?? map['bjmc'] ?? map['BJMC'] ?? map['className'];
    if (className is String) {
      final fromClass = extractMajorFromClassName(className);
      if (fromClass != null) return fromClass;
    }

    return null;
  }

  /// 从教务网成绩/课程记录中提取用户主修专业名称
  String? _extractMajor(List<dynamic> items) {
    for (final raw in items) {
      final item = asStringMap(raw);
      if (item != null) {
        final major = extractMajorFromKeyValues(item);
        if (major != null) {
          return major;
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
            final major = extractMajorFromKeyValues(xsxx);
            if (major != null && major.trim().isNotEmpty) {
              _writeCache('zdbk_user_major', normalizeMajorName(major.trim()));
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

  /// 获取用户主修专业/大类名称（多级多源兜底：本地缓存 -> 课表学籍 -> 成绩单 -> 学业生涯情况 -> 学生信息/学生证补办 -> 实时课表 -> ETA 学工系统）
  Future<Tuple<Exception?, String?>> getStudentMajor(
      HttpClient httpClient, {String? studentId}) async {
    // 0. 检查本地直接缓存
    final cached = _db?.getCachedWebPage('zdbk_user_major');
    if (cached != null && cached.trim().isNotEmpty) {
      return Tuple(null, normalizeMajorName(cached.trim()));
    }

    // 1. 检查学生个人信息缓存（由课表接口写入）
    final studentInfo = _db?.getCachedWebPage('zdbk_student_info');
    if (studentInfo != null && studentInfo.isNotEmpty) {
      try {
        final decoded = jsonDecode(studentInfo);
        final map = asStringMap(decoded);
        if (map != null) {
          final major = extractMajorFromKeyValues(map);
          if (major != null && major.isNotEmpty) {
            final normalized = normalizeMajorName(major);
            _writeCache('zdbk_user_major', normalized);
            return Tuple(null, normalized);
          }
        }
      } catch (_) {}
    }

    // 2. 检查成绩单与主修成绩缓存
    final transcriptCache = _cachedList('zdbk_Transcript', '教务网成绩缓存');
    final major1 = _extractMajor(transcriptCache.data);
    if (major1 != null) {
      final normalized = normalizeMajorName(major1);
      _writeCache('zdbk_user_major', normalized);
      return Tuple(null, normalized);
    }
    final majorCache = _cachedList('zdbk_MajorGrade', '教务网主修成绩缓存');
    final major2 = _extractMajor(majorCache.data);
    if (major2 != null) {
      final normalized = normalizeMajorName(major2);
      _writeCache('zdbk_user_major', normalized);
      return Tuple(null, normalized);
    }

    // 3. 尝试主动请求教务网各个标准学籍与学业接口
    try {
      final zdbkMajor = await _withAutoRelogin(httpClient, (relogged, retried) async {
        final suParam = studentId != null && studentId.isNotEmpty ? '&su=$studentId' : '';

        // 3.1 尝试请求学业生涯情况与培养方案执行情况（Zhengfang N105515 - 最权威学业进度页面）
        try {
          final uriAcademia = Uri.parse(
              "https://zdbk.zju.edu.cn/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default$suParam");
          final req = await httpClient.getUrl(uriAcademia).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          req.headers
            ..add("Referer", "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
          req.cookies.add(_jSessionId!);
          req.cookies.add(_route!);
          req.followRedirects = false;
          final resp = await req.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final body = await readResponseBody(resp, context: '教务网学业生涯接口');
          if (resp.statusCode == 200 && body.isNotEmpty) {
            final htmlFields = parseHtmlFormFields(body);
            final major = extractMajorFromKeyValues(htmlFields);
            if (major != null) {
              final normalized = normalizeMajorName(major);
              _writeCache('zdbk_user_major', normalized);
              return Tuple<Exception?, String?>(null, normalized);
            }
            final alertPattern = RegExp(r'(?:专业|主修|大类)[：:\s]+([^\s<",]+)');
            final m = alertPattern.firstMatch(body);
            if (m != null) {
              final val = m.group(1)?.trim();
              if (val != null && val.length >= 2 && val != '未知') {
                final normalized = normalizeMajorName(val);
                _writeCache('zdbk_user_major', normalized);
                return Tuple<Exception?, String?>(null, normalized);
              }
            }
          }
        } catch (_) {}

        // 3.2 尝试请求正方教务网个人信息页面（支持同时处理 JSON 与 HTML 渲染）
        try {
          final uri1 = Uri.parse(
              "https://zdbk.zju.edu.cn/jwglxt/xsxxxggl/xsxxwh_cxCkDgxsxx.html?gnmkdm=N100801$suParam");
          final req1 = await httpClient.getUrl(uri1).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          req1.headers
            ..add("Referer", "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8');
          req1.cookies.add(_jSessionId!);
          req1.cookies.add(_route!);
          req1.followRedirects = false;
          final resp1 = await req1.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final body1 = await readResponseBody(resp1, context: '教务网学生信息接口');
          if (resp1.statusCode == 200 && body1.isNotEmpty) {
            try {
              final decoded = jsonDecode(body1);
              final map = asStringMap(decoded);
              if (map != null) {
                final major = extractMajorFromKeyValues(map);
                if (major != null) {
                  final normalized = normalizeMajorName(major);
                  _writeCache('zdbk_user_major', normalized);
                  return Tuple<Exception?, String?>(null, normalized);
                }
              }
            } catch (_) {}

            final htmlFields = parseHtmlFormFields(body1);
            final major = extractMajorFromKeyValues(htmlFields);
            if (major != null) {
              final normalized = normalizeMajorName(major);
              _writeCache('zdbk_user_major', normalized);
              return Tuple<Exception?, String?>(null, normalized);
            }
          }
        } catch (_) {}

        // 3.3 尝试请求学生证补办申请详情（Zhengfang N106005 - 必然输出 学院/专业/班级）
        try {
          final uriCard = Uri.parse(
              "https://zdbk.zju.edu.cn/jwglxt/xszbbgl/xszbbgl_cxXszbbsqIndex.html?doType=details&gnmkdm=N106005$suParam");
          final reqCard = await httpClient.postUrl(uriCard).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          reqCard.headers
            ..add("Referer", "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded;charset=UTF-8');
          reqCard.cookies.add(_jSessionId!);
          reqCard.cookies.add(_route!);
          reqCard.followRedirects = false;
          reqCard.add(utf8.encode('offDetails=1&gnmkdm=N106005&czdmKey=00'));
          final respCard = await reqCard.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final bodyCard = await readResponseBody(respCard, context: '教务网学生证补办接口');
          if (respCard.statusCode == 200 && bodyCard.isNotEmpty) {
            final htmlFields = parseHtmlFormFields(bodyCard);
            final major = extractMajorFromKeyValues(htmlFields);
            if (major != null) {
              final normalized = normalizeMajorName(major);
              _writeCache('zdbk_user_major', normalized);
              return Tuple<Exception?, String?>(null, normalized);
            }
          }
        } catch (_) {}

        // 3.4 降级请求教务网学籍信息维护页面
        try {
          final uri2 = Uri.parse(
              "https://zdbk.zju.edu.cn/jwglxt/xsxxxggl/xsgrxxwh_cxXsgrxx.html?gnmkdm=N100801&layout=default$suParam");
          final req2 = await httpClient.getUrl(uri2).timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          req2.headers
            ..add("Referer", "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html")
            ..set('Connection', 'close')
            ..add('User-Agent',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
            ..add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
          req2.cookies.add(_jSessionId!);
          req2.cookies.add(_route!);
          req2.followRedirects = false;
          final resp2 = await req2.close().timeout(const Duration(seconds: 8),
              onTimeout: () => throw requestTimeout());
          final body2 = await readResponseBody(resp2, context: '教务网学籍维护接口');
          if (resp2.statusCode == 200 && body2.isNotEmpty) {
            final htmlFields = parseHtmlFormFields(body2);
            final major = extractMajorFromKeyValues(htmlFields);
            if (major != null) {
              final normalized = normalizeMajorName(major);
              _writeCache('zdbk_user_major', normalized);
              return Tuple<Exception?, String?>(null, normalized);
            }
          }
        } catch (_) {}

        // 3.5 实时请求当前学期课表并从返回的 payload['xsxx'] 提取真实学籍班级/专业
        try {
          final now = DateTime.now();
          final curYear = (now.month >= 8) ? now.year : now.year - 1;
          final curSem = (now.month >= 8 || now.month <= 1) ? '1' : '2';
          await getTimetable(httpClient, curYear.toString(), curSem);
          final studentInfoCached = _db?.getCachedWebPage('zdbk_student_info');
          if (studentInfoCached != null && studentInfoCached.isNotEmpty) {
            final decoded = jsonDecode(studentInfoCached);
            final map = asStringMap(decoded);
            if (map != null) {
              final major = extractMajorFromKeyValues(map);
              if (major != null && major.isNotEmpty) {
                final normalized = normalizeMajorName(major);
                _writeCache('zdbk_user_major', normalized);
                return Tuple<Exception?, String?>(null, normalized);
              }
            }
          }
        } catch (_) {}

        return Tuple<Exception?, String?>(null, null);
      });

      if (zdbkMajor.item2 != null && zdbkMajor.item2!.isNotEmpty) {
        return zdbkMajor;
      }
    } catch (_) {}

    // 4. 尝试从浙大 ETA “三全育人”学生信息平台（eta.zju.edu.cn）获取专业（内网/RVPN环境可用）
    try {
      final etaMajor = await Eta.getStudentMajor(httpClient, _iPlanetDirectoryPro, studentId: studentId);
      if (etaMajor != null && etaMajor.trim().isNotEmpty) {
        final normalized = normalizeMajorName(etaMajor.trim());
        _writeCache('zdbk_user_major', normalized);
        return Tuple(null, normalized);
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
          'queryModel.sortName': 'njdm_id',
          'queryModel.sortOrder': 'desc',
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

    final targetGrade = grade ?? inferGradeFromStudentId(studentId);

    // 检查缓存
    final cacheKey = 'zdbk_training_plan_${cleaned}_${targetGrade ?? 'any'}';
    final cachedJson = _db?.getCachedWebPage(cacheKey);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) {
          return Tuple(null, TrainingPlanInfo.fromJson(decoded));
        }
      } catch (_) {}
    }

    // 尝试多层次查询方案列表
    final Set<String> triedQueries = {};
    final List<Map<String, dynamic>> items = [];

    Future<void> tryFetchPlans({String? qMajor, String? qGrade}) async {
      final key = '${qMajor ?? ""}_${qGrade ?? ""}';
      if (triedQueries.contains(key)) return;
      triedQueries.add(key);
      try {
        final res = await getTrainingPlans(httpClient,
            studentId: studentId, majorName: qMajor, grade: qGrade);
        if (res.item2.isNotEmpty) {
          items.addAll(res.item2);
        }
      } catch (_) {}
    }

    // 1. 先用精准专业名 + 年级查询
    await tryFetchPlans(qMajor: cleaned, qGrade: targetGrade);

    // 2. 若无结果，尝试括号互换变体 + 年级查询
    if (items.isEmpty && cleaned.contains('(')) {
      await tryFetchPlans(
          qMajor: cleaned.replaceAll('(', '（').replaceAll(')', '）'),
          qGrade: targetGrade);
    } else if (items.isEmpty && cleaned.contains('（')) {
      await tryFetchPlans(
          qMajor: cleaned.replaceAll('（', '(').replaceAll('）', ')'),
          qGrade: targetGrade);
    }

    // 3. 若仍无结果，尝试只用年级查询（拉取该年级所有方案）
    if (items.isEmpty && targetGrade != null && targetGrade.isNotEmpty) {
      await tryFetchPlans(qGrade: targetGrade);
    }

    // 4. 若仍无结果，尝试不限年级只查该专业
    if (items.isEmpty) {
      await tryFetchPlans(qMajor: cleaned);
    }

    // 5. 若仍无结果，全量拉取全部方案列表
    if (items.isEmpty) {
      await tryFetchPlans();
    }

    if (items.isEmpty) {
      return Tuple(null, null);
    }

    // 去重
    final uniqueItems = <String, Map<String, dynamic>>{};
    for (final it in items) {
      final id = asString(it['pyfa_id']) ?? asString(it['pyfamc']) ?? '';
      if (id.isNotEmpty) {
        uniqueItems[id] = it;
      }
    }
    final candidateList = uniqueItems.values.toList();

    // 智能多维打分匹配：专业贴合度 + 年级贴合度
    Map<String, dynamic>? bestMatch;
    double bestScore = 0;

    String norm(String s) =>
        s.trim().replaceAll('（', '(').replaceAll('）', ')').toLowerCase();

    final cleanNorm = norm(cleaned);
    final coreName = cleanNorm
        .replaceAll('试验班', '')
        .replaceAll('大类', '')
        .replaceAll('班', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .trim();

    for (final it in candidateList) {
      final zymc = norm(asString(it['zymc']) ?? asString(it['ZYMC']) ?? '');
      final pyfamc = norm(asString(it['pyfamc']) ?? '');
      final itemGrade = asString(it['njdm_id']) ?? '';

      double score = 0;

      // 1. 专业名称匹配
      if (zymc == cleanNorm) {
        score += 100;
      } else if (zymc.isNotEmpty &&
          (zymc.contains(cleanNorm) || cleanNorm.contains(zymc))) {
        score += 80;
      } else if (pyfamc.contains(cleanNorm)) {
        score += 70;
      } else if (coreName.isNotEmpty &&
          (zymc.contains(coreName) || pyfamc.contains(coreName))) {
        score += 50;
      } else {
        // 与目标专业完全无关，不参与匹配
        continue;
      }

      // 2. 年级匹配
      if (targetGrade != null && targetGrade.isNotEmpty) {
        if (itemGrade == targetGrade || pyfamc.contains(targetGrade)) {
          score += 60; // 目标年级完美匹配
        } else {
          final tYear = int.tryParse(targetGrade);
          final iYear = int.tryParse(itemGrade);
          if (tYear != null && iYear != null) {
            if (iYear < tYear) {
              // 往届培养方案：越近越优先
              final diff = tYear - iYear;
              final bonus = (30 - diff * 5).clamp(0, 30).toDouble();
              score += bonus;
            } else {
              // 未来年级方案：惩罚
              score -= 20;
            }
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = it;
      }
    }

    // 若没有找到任何匹配项（bestScore <= 0），绝不能盲目回退到 items.first
    if (bestMatch == null || bestScore <= 0) {
      return Tuple(null, null);
    }

    final pyfaId = asString(bestMatch['pyfa_id']) ?? '';
    final planName = asString(bestMatch['pyfamc']) ?? '$cleaned培养方案';
    final matchedZymc = asString(bestMatch['zymc']) ?? cleaned;
    final planGrade = asString(bestMatch['njdm_id']) ?? targetGrade;
    final college = asString(bestMatch['jgmc']);

    final isFiveYear = cleaned.contains('建筑') ||
        cleaned.contains('临床') ||
        cleaned.contains('口腔') ||
        cleaned.contains('医学') ||
        cleaned.contains('规划');

    // 检查列表自带的毕业要求学分字段（如 bbyq）
    double? totalCredits;
    final bbyqStr =
        asString(bestMatch['bbyq']) ?? asString(bestMatch['zdbyxf']);
    if (bbyqStr != null) {
      final parsed = double.tryParse(bbyqStr);
      if (parsed != null && parsed >= 100 && parsed <= 300) {
        totalCredits = parsed;
      }
    }

    Map<String, double> categoryCredits = {};

    // 若有方案 ID，尝试进一步深入详情预览提取精准学分与各类别要求
    if (pyfaId.isNotEmpty) {
      final detailRes = await fetchTrainingPlanDetail(httpClient, pyfaId,
          studentId: studentId);
      final detailMap = detailRes.item2;
      if (detailMap['totalCredits'] != null &&
          detailMap['totalCredits'] is double) {
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
      majorName: matchedZymc,
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
