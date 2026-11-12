import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'exceptions.dart';
import 'response_utils.dart';

class ECard {
  static Future<T> _withTransientRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 2,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on AuthenticationExpiredException {
        rethrow;
      } catch (e) {
        lastError = e;
        final isTransient = e is TimeoutException ||
            e is SocketException ||
            e is HttpException ||
            e is HandshakeException ||
            e is ExceptionWithMessage;
        if (!isTransient || attempt >= maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw lastError!;
  }
  static Future<String> getSynjonesAuth(
      HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    List<Cookie> cookies = [];
    if (iPlanetDirectoryPro == null) {
      throw AuthenticationExpiredException("校园卡：统一身份认证凭据无效");
    }
    request = await httpClient
        .getUrl(Uri.parse(
            "https://elife.zju.edu.cn/berserker-auth/cas/oauth2?resultUrl=https://elife.zju.edu.cn/plat-pc"))
        .timeout(const Duration(seconds: 12),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));
    request.followRedirects = false;
    cookies.add(iPlanetDirectoryPro);
    request.cookies.addAll(cookies);
    response = await request.close().timeout(const Duration(seconds: 12),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));

    // synjones-auth 可能出现在任意一跳 Location 中；每跳必须先收集
    // 当前响应 Cookie，再访问相对地址解析后的下一跳。
    var current = Uri.parse(
        "https://elife.zju.edu.cn/berserker-auth/cas/oauth2?resultUrl=https://elife.zju.edu.cn/plat-pc");
    for (var redirectCount = 0; redirectCount < 10; redirectCount++) {
      if (response.statusCode != 301 && response.statusCode != 302) {
        final body = await readResponseBody(response, context: '校园卡登录');
        throw AuthenticationExpiredException(
            "校园卡登录失败；HTTP ${response.statusCode}"
            "；Content-Type ${response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>'}"
            "；响应摘要：${responseSummary(body)}");
      }

      var location = response.headers.value('location');
      if (location == null) {
        await response.drain();
        throw AuthenticationExpiredException(
            "校园卡登录失败；HTTP ${response.statusCode}；Location 缺失");
      }
      var synjonesAuth =
          RegExp(r'synjones-auth=(.*?)(?:&|$)').firstMatch(location)?.group(1);
      if (synjonesAuth != null) {
        await response.drain();
        return synjonesAuth;
      }

      await response.drain();
      current = current.resolve(location);
      request = await httpClient.getUrl(current).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw ExceptionWithMessage("请求超时"));
      request.followRedirects = false;
      cookies.addAll(response.cookies);
      request.cookies.addAll(cookies);
      response = await request.close().timeout(const Duration(seconds: 12),
          onTimeout: () => throw ExceptionWithMessage("请求超时"));
    }
    throw ExceptionWithMessage("校园卡登录失败：重定向次数过多");
  }

  static Future<String> getAccount(
      HttpClient httpClient, String synjonesAuth) async {
    late HttpClientRequest request;
    late HttpClientResponse response;

    request = await httpClient
        .getUrl(Uri.parse(
            "https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards"))
        .timeout(const Duration(seconds: 10),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));
    request.headers.add("Synjones-Auth", "Bearer $synjonesAuth");
    request.headers.add(
        "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
    request.headers.add("Accept", "application/json, text/plain, */*");
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 10),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));

    var accountJson =
        await readResponseText(response, context: '校园卡账户接口', expectJson: true);
    final payload = decodeJsonMap(accountJson,
        context: '校园卡账户接口；HTTP ${response.statusCode}');
    if (jsonIndicatesAuthenticationFailure(payload)) {
      throw AuthenticationExpiredException('校园卡账户接口：登录态已失效');
    }
    final data = asStringMap(payload['data']);
    final cardList = asDynamicList(data?['card']) ?? const [];
    // Card list is a List<Map<String, dynamic>> object, which may contain multiple cards.
    // Select the card which has the highest balance.
    // The account number is stored in the 'account' field.
    // The balance is stored in the 'db_balance' field.
    final cards = cardList
        .map(asStringMap)
        .whereType<Map<String, dynamic>>()
        .where((card) => asString(card['account'])?.isNotEmpty == true)
        .toList();
    if (cards.isEmpty) {
      throw ExceptionWithMessage(
          '校园卡账户接口：未返回有效卡片；响应摘要：${responseSummary(accountJson)}');
    }
    cards.sort((a, b) => (asDouble(b['db_balance']) ?? 0.0)
        .compareTo(asDouble(a['db_balance']) ?? 0.0));
    return asString(cards.first['account'])!;
  }

  /// 查询指定账户（缺省取余额最高的卡）的现金余额，单位：元。
  ///
  /// `getCampusCards` 返回的 `db_balance` 以「分」为单位。
  static Future<double> getBalance(
      HttpClient httpClient, String synjonesAuth,
      {String? eCardAccount}) async {
    return _withTransientRetry(() async {
      final request = await httpClient
          .getUrl(Uri.parse(
              "https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards"))
          .timeout(const Duration(seconds: 10),
              onTimeout: () => throw ExceptionWithMessage("请求超时"));
      request.headers.add("Synjones-Auth", "Bearer $synjonesAuth");
      request.headers.add(
          "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
      request.headers.add("Accept", "application/json, text/plain, */*");
      request.followRedirects = false;
      final response = await request.close().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw ExceptionWithMessage("请求超时"));
      final body = await readResponseText(response,
          context: '校园卡余额接口', expectJson: true);
      final payload =
          decodeJsonMap(body, context: '校园卡余额接口；HTTP ${response.statusCode}');
      if (jsonIndicatesAuthenticationFailure(payload)) {
        throw AuthenticationExpiredException('校园卡余额接口：登录态已失效');
      }
      final cards = (asDynamicList(asStringMap(payload['data'])?['card']) ??
              const [])
          .map(asStringMap)
          .whereType<Map<String, dynamic>>()
          .where((card) => asString(card['account'])?.isNotEmpty == true)
          .toList();
      if (cards.isEmpty) {
        throw ExceptionWithMessage(
            '校园卡余额接口：未返回有效卡片；响应摘要：${responseSummary(body)}');
      }
      cards.sort((a, b) => (asDouble(b['db_balance']) ?? 0.0)
          .compareTo(asDouble(a['db_balance']) ?? 0.0));
      final card = cards.firstWhere(
          (c) => eCardAccount != null && asString(c['account']) == eCardAccount,
          orElse: () => cards.first);
      final cents =
          asDouble(card['db_balance']) ?? asDouble(card['unsettle_amount']);
      if (cents == null) {
        throw ExceptionWithMessage('校园卡余额接口：缺少余额字段');
      }
      return cents / 100.0;
    });
  }

  static Future<String> getBarcode(
      HttpClient httpClient, String synjonesAuth, String eCardAccount) async {
    Object? lastError;
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final request = await httpClient
            .getUrl(Uri.parse(
                "https://elife.zju.edu.cn/berserker-app/ykt/tsm/batchGetBarCodeGet?account=$eCardAccount&payacc=%23%23%23&paytype=1&synAccessSource=app"))
            .timeout(const Duration(seconds: 10),
                onTimeout: () => throw ExceptionWithMessage("请求超时"));
        request.headers.add("synjones-auth", "bearer $synjonesAuth");
        request.headers.add("User-Agent",
            "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
        request.headers.add("Accept", "application/json, text/plain, */*");
        request.followRedirects = false;
        final response = await request.close().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw ExceptionWithMessage("请求超时"));

        var barcodeJson = await readResponseText(response,
            context: '校园卡付款码接口', expectJson: true);
        final payload = decodeJsonMap(barcodeJson,
            context: '校园卡付款码接口；HTTP ${response.statusCode}');
        if (jsonIndicatesAuthenticationFailure(payload)) {
          throw AuthenticationExpiredException('校园卡付款码接口：登录态已失效');
        }
        final data = asStringMap(payload['data']);
        final barcodes = asDynamicList(data?['barcode']) ?? const [];
        final barcode = barcodes.isEmpty ? null : asString(barcodes.first);
        if (barcode == null || barcode.isEmpty) {
          throw ExceptionWithMessage(
              '校园卡付款码接口：未返回有效付款码；响应摘要：${responseSummary(barcodeJson)}');
        }
        // 捕获降级码：返回内容长度/字符集异常时通常是鉴权失败或接口降级
        // 返回的"假"码看上去是字符串，但扫码会被 POS 拒绝。
        // 这种情况应触发上层自动重登，而非继续展示无效码。
        if (!_isValidBarcode(barcode)) {
          throw AuthenticationExpiredException(
              '校园卡付款码接口：返回内容疑似降级码（长度=${barcode.length}）；响应摘要：${responseSummary(barcodeJson)}');
        }
        return barcode;
      } catch (e) {
        lastError = e;
        if (e is AuthenticationExpiredException) {
          rethrow;
        }
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw ExceptionWithMessage("获取付款码失败");
  }

  /// 合法付款码：长度 14-64，字符集限定为字母数字 + base64/QR 常见符号。
  /// 此规则能拦截 HTML/JSON 残留、空响应包装等明显垃圾；
  /// 同时兼容老版本纯数字 18 位与未来可能的新版编码格式。
  static final RegExp _validBarcodePattern =
      RegExp(r'^[A-Za-z0-9+/=_\-]{14,64}$');
  static bool _isValidBarcode(String s) => _validBarcodePattern.hasMatch(s);

  /// 解析校园卡流水接口返回的 JSON 负载（兼容多种分页/列表字段形态）
  static ECardTransactionPage parseTransactionPage(
    Map<String, dynamic> payload, {
    int currentPage = 1,
  }) {
    if (jsonIndicatesAuthenticationFailure(payload)) {
      throw AuthenticationExpiredException('校园卡账单接口：登录态已失效');
    }
    final code = asInt(payload['code']);
    final success = payload['success'];
    final rawData = payload['data'];
    final hasAnyListShape = rawData is List ||
        payload['rows'] is List ||
        payload['records'] is List ||
        asStringMap(rawData) != null;
    if (!hasAnyListShape &&
        (success == false || (code != null && code != 200 && code != 0))) {
      final msg = asString(payload['msg']) ??
          asString(payload['message']) ??
          '服务返回异常状态 ${code ?? ''}';
      throw ExceptionWithMessage('校园卡账单接口：$msg');
    }

    final dataMap = asStringMap(rawData) ?? const <String, dynamic>{};
    final recordsRaw = asDynamicList(dataMap['records']) ??
        asDynamicList(dataMap['rows']) ??
        asDynamicList(dataMap['list']) ??
        asDynamicList(dataMap['turnovers']) ??
        asDynamicList(rawData) ??
        asDynamicList(payload['rows']) ??
        asDynamicList(payload['records']) ??
        const <dynamic>[];
    final records = recordsRaw
        .map(asStringMap)
        .whereType<Map<String, dynamic>>()
        .map(ECardTransaction.fromJson)
        .toList();
    final total =
        (asDouble(dataMap['total']) ?? records.length.toDouble()).toInt();
    final pages =
        (asDouble(dataMap['pages']) ?? 1.0).toInt().clamp(1, 9999);

    return ECardTransactionPage(
      records: records,
      total: total < records.length ? records.length : total,
      pages: pages,
      currentPage: currentPage,
    );
  }

  /// 查询校园卡流水账单（新中新 Berserker Search 接口）
  ///
  /// 参考开源项目：
  /// - OpenAHU/AHUTong-Android (`berserker-search/search/personal/turnover`)
  /// - Mercury000/HUEL-yktwx (`berserker-search/search/personal/turnover`)
  /// - Chiu-xaH/HFUT-Schedule (`berserker-search/search/personal/turnover`)
  /// - Inonvation/JUWPHub（兼容无时间参数全量拉取并在客户端按月切片）
  static Future<ECardTransactionPage> getTransactions(
    HttpClient httpClient,
    String synjonesAuth, {
    int page = 1,
    int size = 30,
    String? timeFrom,
    String? timeTo,
    String? eCardAccount,
    bool filterByAccount = false,
    String synAccessSource = 'h5',
  }) async {
    return _withTransientRetry(() async {
      final queryParams = <String, String>{
        'size': '$size',
        'current': '$page',
        'synAccessSource': synAccessSource,
      };
      if (timeFrom != null && timeFrom.isNotEmpty) {
        queryParams['timeFrom'] = timeFrom;
      }
      if (timeTo != null && timeTo.isNotEmpty) {
        queryParams['timeTo'] = timeTo;
      }
      if (filterByAccount &&
          eCardAccount != null &&
          eCardAccount.isNotEmpty) {
        queryParams['fromAccount'] = eCardAccount;
      }

      final uri = Uri.https(
        'elife.zju.edu.cn',
        '/berserker-search/search/personal/turnover',
        queryParams,
      );
      final request = await httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 12),
              onTimeout: () => throw ExceptionWithMessage("账单查询请求超时"));
      request.headers.add("Synjones-Auth", "bearer $synjonesAuth");
      request.headers.add("synAccessSource", synAccessSource);
      request.headers.add(
          "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
      request.headers.add("Accept", "application/json, text/plain, */*");
      request.followRedirects = false;

      final response = await request.close().timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw ExceptionWithMessage("账单查询响应超时"));
      final body = await readResponseText(response,
          context: '校园卡账单接口', expectJson: true);
      final payload = decodeJsonMap(body,
          context: '校园卡账单接口；HTTP ${response.statusCode}');
      return parseTransactionPage(payload, currentPage: page);
    });
  }

  static String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 自适应拉取指定月份的完整校园卡流水：
  /// 1. 优先不传 `fromAccount`、使用 `[timeFrom, timeTo]` 请求当月；
  /// 2. 若部分新中新后端带时间参数或 `synAccessSource=h5` 返回空列表，
  ///    自动回退至不带 `timeFrom/timeTo` 并轮询 `h5/app/pc` 按月客户端切片；
  /// 3. 所有分支仍空时，最后尝试带 `fromAccount` 兜底。
  static Future<ECardMonthFetchResult> fetchMonthTransactions(
    HttpClient httpClient,
    String synjonesAuth, {
    required DateTime month,
    String? eCardAccount,
    DateTime? now,
    Future<ECardTransactionPage> Function({
      required int page,
      required int size,
      String? timeFrom,
      String? timeTo,
      String? eCardAccount,
      required bool filterByAccount,
      required String synAccessSource,
    })? pageLoader,
  }) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final nextMonthStart = DateTime(month.year, month.month + 1, 1);
    final rawMonthEnd = nextMonthStart.subtract(const Duration(days: 1));
    final refNow = now ?? DateTime.now();
    final todayPlusOne =
        DateTime(refNow.year, refNow.month, refNow.day).add(const Duration(days: 1));
    final clampedEnd = (month.year == refNow.year &&
            month.month == refNow.month &&
            rawMonthEnd.isAfter(todayPlusOne))
        ? todayPlusOne
        : rawMonthEnd;

    final loader = pageLoader ??
        ({
          required int page,
          required int size,
          String? timeFrom,
          String? timeTo,
          String? eCardAccount,
          required bool filterByAccount,
          required String synAccessSource,
        }) =>
            getTransactions(
              httpClient,
              synjonesAuth,
              page: page,
              size: size,
              timeFrom: timeFrom,
              timeTo: timeTo,
              eCardAccount: eCardAccount,
              filterByAccount: filterByAccount,
              synAccessSource: synAccessSource,
            );

    Future<ECardMonthFetchResult> collect({
      required String source,
      String? timeFrom,
      String? timeTo,
      bool filterByAccount = false,
      int pageSize = 50,
      int maxPages = 10,
    }) async {
      final collected = <ECardTransaction>[];
      final seenKeys = <String>{};
      var sawRaw = false;
      var reachedBeforeMonth = false;
      var lastPage = 1;
      var serverPages = 1;
      var reachedEnd = false;

      for (int page = 1; page <= maxPages; page++) {
        final pageData = await loader(
          page: page,
          size: pageSize,
          timeFrom: timeFrom,
          timeTo: timeTo,
          eCardAccount: eCardAccount,
          filterByAccount: filterByAccount,
          synAccessSource: source,
        );
        if (pageData.records.isEmpty) {
          if (page == 1) {
            return const ECardMonthFetchResult(
              records: [],
              totalCount: 0,
              currentPage: 1,
              totalPages: 1,
              complete: false,
              sawRawRecords: false,
            );
          }
          reachedEnd = true;
          break;
        }
        sawRaw = true;
        lastPage = page;
        if (pageData.pages > serverPages) {
          serverPages = pageData.pages;
        }

        DateTime? oldestOnPage;
        for (final tx in pageData.records) {
          final dt = tx.dateTime;
          if (dt != null && (oldestOnPage == null || dt.isBefore(oldestOnPage))) {
            oldestOnPage = dt;
          }
          final inMonth = dt == null
              ? (timeFrom != null)
              : (!dt.isBefore(monthStart) && dt.isBefore(nextMonthStart));
          if (!inMonth) continue;

          final key = tx.dedupeKey;
          if (seenKeys.add(key)) {
            collected.add(tx);
          }
        }

        if (oldestOnPage != null && oldestOnPage.isBefore(monthStart)) {
          reachedBeforeMonth = true;
          break;
        }
        if (page >= pageData.pages) {
          reachedEnd = true;
          break;
        }
      }

      return ECardMonthFetchResult(
        records: collected,
        totalCount: collected.length,
        currentPage: lastPage,
        totalPages: serverPages,
        complete: sawRaw && (reachedBeforeMonth || reachedEnd),
        sawRawRecords: sawRaw,
      );
    }

    // 1. 首选：带年月范围、不传 fromAccount（避免多卡/虚拟卡子账户被过滤空）
    final primary = await collect(
      source: 'h5',
      timeFrom: _fmtYmd(monthStart),
      timeTo: _fmtYmd(clampedEnd),
      filterByAccount: false,
      pageSize: 50,
      maxPages: 10,
    );
    if (primary.records.isNotEmpty || (primary.sawRawRecords && primary.complete)) {
      return primary;
    }

    // 2. 回退：去掉 timeFrom/timeTo 并轮询 synAccessSource，无参全量拉取后客户端按月切片
    for (final src in const ['h5', 'app', 'pc']) {
      final res = await collect(
        source: src,
        timeFrom: null,
        timeTo: null,
        filterByAccount: false,
        pageSize: 100,
        maxPages: 12,
      );
      if (res.sawRawRecords && (res.records.isNotEmpty || res.complete)) {
        return res;
      }
    }

    // 3. 最终兜底：仅当未拿到任何记录且存在卡号时，尝试带 fromAccount
    if (eCardAccount != null && eCardAccount.isNotEmpty) {
      final byAcc = await collect(
        source: 'h5',
        timeFrom: null,
        timeTo: null,
        filterByAccount: true,
        pageSize: 100,
        maxPages: 8,
      );
      if (byAcc.sawRawRecords) {
        return byAcc;
      }
    }

    return primary;
  }

  /// 查询指定日期区间的校园卡总收支统计（单位：元）
  static Future<ECardMonthlySummary?> getTurnoverCount(
    HttpClient httpClient,
    String synjonesAuth, {
    required String timeFrom,
    required String timeTo,
  }) async {
    try {
      final uri = Uri.https(
        'elife.zju.edu.cn',
        '/berserker-search/statistics/turnover/count',
        {
          'timeFrom': timeFrom,
          'timeTo': timeTo,
          'synAccessSource': 'h5',
        },
      );
      final request = await httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 10),
              onTimeout: () => throw ExceptionWithMessage("统计查询超时"));
      request.headers.add("Synjones-Auth", "bearer $synjonesAuth");
      request.headers.add("synAccessSource", "h5");
      request.headers.add(
          "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
      request.headers.add("Accept", "application/json, text/plain, */*");
      request.followRedirects = false;
      final response = await request.close().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw ExceptionWithMessage("统计响应超时"));
      final body = await readResponseText(response,
          context: '校园卡收支统计接口', expectJson: true);
      final payload = decodeJsonMap(body,
          context: '校园卡收支统计接口；HTTP ${response.statusCode}');
      final data = asStringMap(payload['data']);
      if (data == null) return null;
      final expensesCents = asDouble(data['expenses']) ?? 0.0;
      final incomeCents = asDouble(data['income']) ?? 0.0;
      return ECardMonthlySummary(
        expenses: expensesCents / 100.0,
        income: incomeCents / 100.0,
      );
    } catch (_) {
      return null;
    }
  }
}

class ECardMonthlySummary {
  final double expenses;
  final double income;

  const ECardMonthlySummary({
    required this.expenses,
    required this.income,
  });
}

class ECardTransactionPage {
  final List<ECardTransaction> records;
  final int total;
  final int pages;
  final int currentPage;

  const ECardTransactionPage({
    required this.records,
    required this.total,
    required this.pages,
    required this.currentPage,
  });
}

class ECardMonthFetchResult {
  final List<ECardTransaction> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool complete;
  final bool sawRawRecords;

  const ECardMonthFetchResult({
    required this.records,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    required this.complete,
    required this.sawRawRecords,
  });
}

class ECardBillCacheSnapshot {
  final String monthKey;
  final List<ECardTransaction> records;
  final int totalCount;
  final bool complete;
  final DateTime updatedAt;
  final ECardMonthlySummary? summary;

  const ECardBillCacheSnapshot({
    required this.monthKey,
    required this.records,
    required this.totalCount,
    required this.complete,
    required this.updatedAt,
    this.summary,
  });

  String toJsonString() => jsonEncode({
        'month': monthKey,
        'totalCount': totalCount,
        'complete': complete,
        'updatedAt': updatedAt.toIso8601String(),
        if (summary != null)
          'summary': {
            'expenses': summary!.expenses,
            'income': summary!.income,
          },
        'records': records.map((r) => r.toJson()).toList(),
      });

  static ECardBillCacheSnapshot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final map = asStringMap(decoded);
      if (map == null) return null;
      final monthKey = asString(map['month']) ?? '';
      final updatedAtStr = asString(map['updatedAt']) ?? '';
      final updatedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();
      final recordsRaw = asDynamicList(map['records']) ?? const [];
      final records = recordsRaw
          .map(asStringMap)
          .whereType<Map<String, dynamic>>()
          .map(ECardTransaction.fromJson)
          .toList();
      final summaryMap = asStringMap(map['summary']);
      final summary = summaryMap == null
          ? null
          : ECardMonthlySummary(
              expenses: asDouble(summaryMap['expenses']) ?? 0.0,
              income: asDouble(summaryMap['income']) ?? 0.0,
            );
      return ECardBillCacheSnapshot(
        monthKey: monthKey,
        records: records,
        totalCount: asInt(map['totalCount']) ?? records.length,
        complete: asBool(map['complete']) ?? true,
        updatedAt: updatedAt,
        summary: summary,
      );
    } catch (_) {
      return null;
    }
  }
}

class ECardTransaction {
  final String orderId;
  final double amount;
  final bool isIncome;
  final String turnoverType;
  final String merchant;
  final String summary;
  final String dateTimeStr;
  final DateTime? dateTime;
  final double? balanceAfter;

  const ECardTransaction({
    required this.orderId,
    required this.amount,
    required this.isIncome,
    required this.turnoverType,
    required this.merchant,
    required this.summary,
    required this.dateTimeStr,
    this.dateTime,
    this.balanceAfter,
  });

  String get dedupeKey => orderId.isNotEmpty
      ? orderId
      : '${dateTimeStr}_${merchant}_${amount.toStringAsFixed(2)}_${balanceAfter?.toStringAsFixed(2) ?? ''}';

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'amountYuan': amount,
        'isIncome': isIncome,
        'turnoverType': turnoverType,
        'toMerchant': merchant,
        'resume': summary,
        'effectdateStr': dateTimeStr,
        if (balanceAfter != null) 'balanceAfterYuan': balanceAfter,
      };

  static double? _parseNumericField(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final cleaned = raw.toString().replaceAll(',', '').replaceAll('¥', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static double _parseAmountYuan(Map<String, dynamic> json) {
    final explicitYuan = _parseNumericField(json['amountYuan']);
    if (explicitYuan != null) return explicitYuan.abs();

    const centKeys = [
      'tranamt',
      'transAmt',
      'tranAmt',
      'txamt',
      'txAmt',
      'opfare',
      'consumeAmt',
      'tradeAmt',
    ];
    for (final key in centKeys) {
      final v = _parseNumericField(json[key]);
      if (v != null && v != 0) return v.abs() / 100.0;
    }
    final fallbackCents =
        _parseNumericField(json['amt']) ?? _parseNumericField(json['amount']);
    if (fallbackCents != null) return fallbackCents.abs() / 100.0;
    return 0.0;
  }

  static (DateTime?, String) _parseDateTime(Map<String, dynamic> json) {
    for (final key in const [
      'effectdateStr',
      'jndatetimeStr',
      'opdtStr',
      'txdateStr',
      'dateTimeStr',
    ]) {
      final raw = asString(json[key])?.trim() ?? '';
      if (raw.isEmpty) continue;
      final normalized = raw.replaceAll('/', '-').replaceFirst(' ', 'T');
      var parsed = DateTime.tryParse(normalized);
      if (parsed == null && RegExp(r'^\d{14}$').hasMatch(raw)) {
        parsed = DateTime.tryParse(
          '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}'
          'T${raw.substring(8, 10)}:${raw.substring(10, 12)}:${raw.substring(12, 14)}',
        );
      }
      if (parsed != null) {
        if (parsed.isUtc) parsed = parsed.toLocal();
        return (parsed, raw);
      }
    }

    for (final key in const [
      'effectdate',
      'jndatetime',
      'tranDate',
      'createTime',
    ]) {
      final val = json[key];
      if (val is num) {
        final ms = val > 100000000000 ? val.toInt() : (val.toInt() * 1000);
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        final str =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
        return (dt, str);
      }
      final raw = asString(val)?.trim() ?? '';
      if (raw.isEmpty) continue;
      var parsed = DateTime.tryParse(raw.replaceAll('/', '-'));
      if (parsed != null) {
        if (parsed.isUtc) parsed = parsed.toLocal();
        final str =
            '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
            '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}:${parsed.second.toString().padLeft(2, '0')}';
        return (parsed, str);
      }
    }
    return (null, '');
  }

  factory ECardTransaction.fromJson(Map<String, dynamic> json) {
    final amountYuan = _parseAmountYuan(json);
    final typeFrom = asString(json['typeFrom'])?.trim() ??
        asString(json['type'])?.trim() ??
        '';
    final turnoverType = asString(json['turnoverType']) ??
        asString(json['consumeTypeName']) ??
        '消费';
    final resume = asString(json['resume']) ?? asString(json['remark']) ?? '';
    final merchant = asString(json['toMerchant']) ??
        asString(json['merchantName']) ??
        asString(json['mername']) ??
        asString(json['shopname']) ??
        (resume.isNotEmpty ? resume.split('-').first.trim() : turnoverType);
    final (dt, dtStr) = _parseDateTime(json);

    final explicitBalYuan = _parseNumericField(json['balanceAfterYuan']);
    final balCents = _parseNumericField(json['cardBalance']) ??
        _parseNumericField(json['ebagamt']);
    final balanceAfter =
        explicitBalYuan ?? (balCents != null ? balCents / 100.0 : null);

    final explicitIsIncome = json['isIncome'] is bool ? json['isIncome'] as bool : null;
    final isInc = explicitIsIncome ??
        (typeFrom == '1' ||
            turnoverType.contains('充值') ||
            turnoverType.contains('圈存') ||
            turnoverType.contains('补助') ||
            turnoverType.contains('退款') ||
            resume.contains('充值') ||
            resume.contains('补助') ||
            resume.contains('退款'));

    final rawOrderId = asString(json['orderId'])?.trim() ?? '';
    return ECardTransaction(
      orderId: rawOrderId.isNotEmpty
          ? rawOrderId
          : '$dtStr-$merchant-${amountYuan.toStringAsFixed(2)}',
      amount: amountYuan,
      isIncome: isInc,
      turnoverType: turnoverType,
      merchant: merchant.isEmpty ? turnoverType : merchant,
      summary: resume.isEmpty ? turnoverType : resume,
      dateTimeStr: dtStr,
      dateTime: dt,
      balanceAfter: balanceAfter,
    );
  }

  String get category {
    if (isIncome) return '充值/转入';
    final text = '$merchant $summary $turnoverType';
    if (RegExp(r'餐|食堂|美食|面|饭|茶|咖啡|烘焙|糕|小吃|风味|麦当劳|肯德基|玉湖|临湖|银泉|休闲|食天|东区|西区|澄月|留食|清真|麦香|早点|夜宵|包子|粉|粥|烧腊|铁板|麻辣|香锅|烤')
        .hasMatch(text)) {
      return '餐饮美食';
    }
    if (RegExp(r'超市|商贸|便利|购|文印|打印|书店|启真|教育超市|全家|罗森|百货|水果')
        .hasMatch(text)) {
      return '商超购物';
    }
    if (RegExp(r'洗浴|水控|热水|淋浴|洗衣|吹风|开水|直饮水|电控|电费|水费|能耗')
        .hasMatch(text)) {
      return '生活水电';
    }
    if (RegExp(r'校医院|医疗|门诊|药|体测|体育|游泳|羽毛球|网球|健身|球馆')
        .hasMatch(text)) {
      return '医疗运动';
    }
    if (RegExp(r'校车|班车|通行|巴士|观光车|小白车|停车')
        .hasMatch(text)) {
      return '校园出行';
    }
    return '其他消费';
  }
}
