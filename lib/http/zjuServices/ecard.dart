import 'dart:io';

import 'exceptions.dart';
import 'response_utils.dart';

class ECard {
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
    final response = await request.close().timeout(const Duration(seconds: 10),
        onTimeout: () => throw ExceptionWithMessage("请求超时"));
    final body =
        await readResponseText(response, context: '校园卡余额接口', expectJson: true);
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
    final cents = asDouble(card['db_balance']);
    if (cents == null) {
      throw ExceptionWithMessage('校园卡余额接口：缺少余额字段');
    }
    return cents / 100.0;
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

  /// 查询校园卡流水账单（新中新 Berserker Search 接口）
  ///
  /// 参考开源项目：
  /// - OpenAHU/AHUTong-Android (`berserker-search/search/personal/turnover`)
  /// - Mercury000/HUEL-yktwx (`berserker-search/search/personal/turnover`)
  /// - Chiu-xaH/HFUT-Schedule (`berserker-search/search/personal/turnover`)
  static Future<ECardTransactionPage> getTransactions(
    HttpClient httpClient,
    String synjonesAuth, {
    int page = 1,
    int size = 30,
    String? timeFrom,
    String? timeTo,
    String? eCardAccount,
  }) async {
    final queryParams = <String, String>{
      'size': '$size',
      'current': '$page',
      'synAccessSource': 'h5',
    };
    if (timeFrom != null && timeFrom.isNotEmpty) {
      queryParams['timeFrom'] = timeFrom;
    }
    if (timeTo != null && timeTo.isNotEmpty) {
      queryParams['timeTo'] = timeTo;
    }
    if (eCardAccount != null && eCardAccount.isNotEmpty) {
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
    request.headers.add(
        "User-Agent", "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)");
    request.headers.add("Accept", "application/json, text/plain, */*");
    request.followRedirects = false;

    final response = await request.close().timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw ExceptionWithMessage("账单查询响应超时"));
    final body =
        await readResponseText(response, context: '校园卡账单接口', expectJson: true);
    final payload =
        decodeJsonMap(body, context: '校园卡账单接口；HTTP ${response.statusCode}');
    if (jsonIndicatesAuthenticationFailure(payload)) {
      throw AuthenticationExpiredException('校园卡账单接口：登录态已失效');
    }

    final data = asStringMap(payload['data']) ?? const {};
    final recordsRaw = asDynamicList(data['records']) ?? const [];
    final records = recordsRaw
        .map(asStringMap)
        .whereType<Map<String, dynamic>>()
        .map(ECardTransaction.fromJson)
        .toList();
    final total = (asDouble(data['total']) ?? records.length.toDouble()).toInt();
    final pages = (asDouble(data['pages']) ?? 1.0).toInt();

    return ECardTransactionPage(
      records: records,
      total: total,
      pages: pages,
      currentPage: page,
    );
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

  factory ECardTransaction.fromJson(Map<String, dynamic> json) {
    final cents = asDouble(json['tranamt']) ??
        asDouble(json['amount']) ??
        0.0;
    final typeFrom = asString(json['typeFrom']) ?? '';
    final turnoverType = asString(json['turnoverType']) ??
        asString(json['consumeTypeName']) ??
        '消费';
    final resume = asString(json['resume']) ?? '';
    final merchant = asString(json['toMerchant']) ??
        asString(json['merchantName']) ??
        (resume.isNotEmpty ? resume.split('-').first.trim() : turnoverType);
    final dtStr = asString(json['effectdateStr']) ??
        asString(json['jndatetimeStr']) ??
        '';
    final dt = dtStr.isNotEmpty
        ? DateTime.tryParse(dtStr.replaceFirst(' ', 'T'))
        : null;
    final balCents = asDouble(json['cardBalance']);
    final isInc = typeFrom == '1' ||
        turnoverType.contains('充值') ||
        turnoverType.contains('圈存') ||
        turnoverType.contains('补助') ||
        turnoverType.contains('退款') ||
        resume.contains('充值') ||
        resume.contains('补助');

    return ECardTransaction(
      orderId: asString(json['orderId']) ?? '$dtStr-$cents',
      amount: (cents.abs()) / 100.0,
      isIncome: isInc,
      turnoverType: turnoverType,
      merchant: merchant.isEmpty ? turnoverType : merchant,
      summary: resume.isEmpty ? turnoverType : resume,
      dateTimeStr: dtStr,
      dateTime: dt,
      balanceAfter: balCents != null ? balCents / 100.0 : null,
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
