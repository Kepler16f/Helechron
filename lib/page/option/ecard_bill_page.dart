import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/http/zjuServices/ecard.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:celechron/worker/ecard_widget_messenger.dart';

class ECardBillPage extends StatefulWidget {
  const ECardBillPage({super.key});

  @override
  State<ECardBillPage> createState() => _ECardBillPageState();
}

class _ECardBillPageState extends State<ECardBillPage> {
  final HttpClient _httpClient = HttpClient();

  late DateTime _selectedMonth;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String? _syncWarning;
  DateTime? _cacheUpdatedAt;
  bool _monthFetchComplete = false;

  double? _balance;
  ECardMonthlySummary? _serverSummary;
  final List<ECardTransaction> _records = [];
  int _totalCount = 0;
  String _selectedCategory = '全部';

  static const List<String> _filterTabs = [
    '全部',
    '餐饮美食',
    '商超购物',
    '生活水电',
    '充值/转入',
    '其他消费',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    applyZjuNetworkDefense(_httpClient);
    _loadMonthData(reset: true);
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  DateTime get _monthEnd {
    final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1));
  }

  String _monthCacheKey(DateTime month) =>
      'ecard_bill_${month.year}_${month.month.toString().padLeft(2, '0')}';

  static const String _kBalanceCacheKey = 'ecard_balance_cache';

  DatabaseHelper? get _db => Get.isRegistered<DatabaseHelper>(tag: 'db')
      ? Get.find<DatabaseHelper>(tag: 'db')
      : null;

  ECardBillCacheSnapshot? _readMonthCache(DateTime month) {
    try {
      final raw = _db?.getCachedWebPage(_monthCacheKey(month));
      return ECardBillCacheSnapshot.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMonthCache(
      DateTime month, ECardBillCacheSnapshot snapshot) async {
    try {
      await _db?.setCachedWebPage(
          _monthCacheKey(month), snapshot.toJsonString());
    } catch (_) {}
  }

  double? _readBalanceCache() {
    try {
      final raw = _db?.getCachedWebPage(_kBalanceCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['balance'] is num) {
        return (decoded['balance'] as num).toDouble();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveBalanceCache(double balance) async {
    try {
      await _db?.setCachedWebPage(
        _kBalanceCacheKey,
        jsonEncode({
          'balance': balance,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  String _formatCacheTime(DateTime dt) {
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '今天 $hh:$mm';
    }
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<String?> _ensureAuth({bool forceRelogin = false}) async {
    const secureStorage = FlutterSecureStorage();
    if (forceRelogin) {
      await ECardWidgetMessenger.update(notifyNative: false);
    }
    var auth = await secureStorage.read(key: 'synjonesAuth');
    if (auth == null || auth.isEmpty) {
      final ok = await ECardWidgetMessenger.update(notifyNative: false);
      if (ok) {
        auth = await secureStorage.read(key: 'synjonesAuth');
      }
    }
    return auth;
  }

  Future<void> _loadMonthData({bool reset = true}) async {
    final targetMonth = _selectedMonth;
    final cachedSnapshot = _readMonthCache(targetMonth);
    final cachedBalance = _readBalanceCache();
    final hasCachedRecords =
        cachedSnapshot != null && cachedSnapshot.records.isNotEmpty;

    setState(() {
      _error = null;
      _syncWarning = null;
      if (cachedBalance != null && _balance == null) {
        _balance = cachedBalance;
      }
      if (cachedSnapshot != null) {
        _records
          ..clear()
          ..addAll(cachedSnapshot.records);
        _totalCount = cachedSnapshot.totalCount;
        _monthFetchComplete = cachedSnapshot.complete;
        _serverSummary = cachedSnapshot.summary;
        _cacheUpdatedAt = cachedSnapshot.updatedAt;
        _loading = false;
        _syncing = true;
      } else {
        _records.clear();
        _totalCount = 0;
        _monthFetchComplete = false;
        _cacheUpdatedAt = null;
        _loading = true;
        _syncing = false;
      }
    });

    try {
      var auth = await _ensureAuth();
      if (auth == null || auth.isEmpty) {
        if (!mounted || targetMonth != _selectedMonth) return;
        setState(() {
          _loading = false;
          _syncing = false;
          if (hasCachedRecords) {
            _syncWarning = '尚未重新登录校园卡，当前显示本地缓存';
          } else {
            _error = '尚未登录校园卡，请先在设置中登录学号';
          }
        });
        return;
      }

      const secureStorage = FlutterSecureStorage();
      var account = await secureStorage.read(key: 'eCardAccount');
      final timeFrom = _formatDate(targetMonth);
      final timeTo = _formatDate(_monthEnd);

      ECardMonthFetchResult fetchResult;
      try {
        fetchResult = await ECard.fetchMonthTransactions(
          _httpClient,
          auth,
          month: targetMonth,
          eCardAccount: account,
        );
      } on AuthenticationExpiredException {
        auth = await _ensureAuth(forceRelogin: true);
        if (auth == null || auth.isEmpty) rethrow;
        account = await secureStorage.read(key: 'eCardAccount');
        fetchResult = await ECard.fetchMonthTransactions(
          _httpClient,
          auth,
          month: targetMonth,
          eCardAccount: account,
        );
      }

      if (!mounted || targetMonth != _selectedMonth) return;

      // 网络波动保护：如果本月已有非空本地缓存而远端异常返回空列表，保留本地缓存并提示重试
      if (fetchResult.records.isEmpty && hasCachedRecords) {
        await _loadBalanceAndSummary(auth, account, timeFrom, timeTo,
            allowSummary: !fetchResult.complete);
        if (!mounted || targetMonth != _selectedMonth) return;
        setState(() {
          _loading = false;
          _syncing = false;
          _syncWarning = '网络波动，未拉取到最新流水，已保留本地缓存';
        });
        return;
      }

      final now = DateTime.now();
      setState(() {
        _records
          ..clear()
          ..addAll(fetchResult.records);
        _totalCount = fetchResult.records.length;
        _monthFetchComplete = fetchResult.complete;
        _cacheUpdatedAt = now;
        _loading = false;
        _syncing = false;
        _syncWarning = null;
      });

      await _loadBalanceAndSummary(
        auth,
        account,
        timeFrom,
        timeTo,
        allowSummary: !fetchResult.complete,
      );

      await _saveMonthCache(
        targetMonth,
        ECardBillCacheSnapshot(
          monthKey: _monthCacheKey(targetMonth),
          records: fetchResult.records,
          totalCount: fetchResult.records.length,
          complete: fetchResult.complete,
          updatedAt: now,
          summary: _serverSummary,
        ),
      );
    } catch (e) {
      if (!mounted || targetMonth != _selectedMonth) return;
      setState(() {
        _loading = false;
        _syncing = false;
        if (cachedSnapshot != null) {
          _syncWarning = '网络波动，当前显示本地缓存（${_formatCacheTime(cachedSnapshot.updatedAt)}）';
        } else {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _loadBalanceAndSummary(
    String auth,
    String? account,
    String timeFrom,
    String timeTo, {
    bool allowSummary = true,
  }) async {
    try {
      final bal =
          await ECard.getBalance(_httpClient, auth, eCardAccount: account);
      await _saveBalanceCache(bal);
      if (mounted) {
        setState(() {
          _balance = bal;
        });
      }
      await OhosNativeService.instance
          .setWidgetData('ecardBalance', bal.toStringAsFixed(2));
    } catch (_) {}

    if (!allowSummary) return;
    try {
      final summary = await ECard.getTurnoverCount(
        _httpClient,
        auth,
        timeFrom: timeFrom,
        timeTo: timeTo,
      );
      if (mounted &&
          summary != null &&
          (summary.expenses > 0 || summary.income > 0)) {
        setState(() {
          _serverSummary = summary;
        });
      }
    } catch (_) {}
  }

  void _changeMonth(int deltaMonths) {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + deltaMonths, 1);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month, 1))) return;
    setState(() {
      _selectedMonth = next;
      _serverSummary = null;
      _syncWarning = null;
    });
    _loadMonthData(reset: true);
  }

  double get _computedExpense {
    var sum = 0.0;
    for (final r in _records) {
      if (!r.isIncome) sum += r.amount;
    }
    if (!_monthFetchComplete &&
        _serverSummary != null &&
        _serverSummary!.expenses > sum) {
      return _serverSummary!.expenses;
    }
    return sum;
  }

  double get _computedIncome {
    var sum = 0.0;
    for (final r in _records) {
      if (r.isIncome) sum += r.amount;
    }
    if (!_monthFetchComplete &&
        _serverSummary != null &&
        _serverSummary!.income > sum) {
      return _serverSummary!.income;
    }
    return sum;
  }

  Map<String, double> get _categoryExpenses {
    final map = <String, double>{};
    for (final r in _records) {
      if (r.isIncome) continue;
      final cat = r.category;
      map[cat] = (map[cat] ?? 0.0) + r.amount;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<MapEntry<String, double>> get _topMerchants {
    final map = <String, double>{};
    for (final r in _records) {
      if (r.isIncome) continue;
      final name = r.merchant.trim();
      if (name.isEmpty) continue;
      map[name] = (map[name] ?? 0.0) + r.amount;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  List<ECardTransaction> get _filteredRecords {
    if (_selectedCategory == '全部') return _records;
    return _records.where((r) => r.category == _selectedCategory).toList();
  }

  Color _categoryColor(String category) {
    switch (category) {
      case '餐饮美食':
        return CupertinoColors.systemOrange;
      case '商超购物':
        return CupertinoColors.systemBlue;
      case '生活水电':
        return CupertinoColors.systemTeal;
      case '医疗运动':
        return CupertinoColors.systemGreen;
      case '校园出行':
        return CupertinoColors.systemIndigo;
      case '充值/转入':
        return CupertinoColors.activeGreen;
      default:
        return CupertinoColors.systemPurple;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case '餐饮美食':
        return CupertinoIcons.cart_fill;
      case '商超购物':
        return CupertinoIcons.bag_fill;
      case '生活水电':
        return CupertinoIcons.drop_fill;
      case '医疗运动':
        return CupertinoIcons.heart_fill;
      case '校园出行':
        return CupertinoIcons.bus;
      case '充值/转入':
        return CupertinoIcons.arrow_down_circle_fill;
      default:
        return CupertinoIcons.creditcard_fill;
    }
  }

  Widget _buildMonthSelector(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    return RoundRectangleCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minSize: 32,
            onPressed: () => _changeMonth(-1),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.chevron_left, size: 16),
                SizedBox(width: 2),
                Text('上月', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
          Text(
            '${_selectedMonth.year} 年 ${_selectedMonth.month} 月',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minSize: 32,
            onPressed: isCurrentMonth ? null : () => _changeMonth(1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '下月',
                  style: TextStyle(
                    fontSize: 14,
                    color: isCurrentMonth
                        ? CupertinoDynamicColor.resolve(
                            CupertinoColors.quaternaryLabel, context)
                        : null,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isCurrentMonth
                      ? CupertinoDynamicColor.resolve(
                          CupertinoColors.quaternaryLabel, context)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final expense = _computedExpense;
    final income = _computedIncome;
    final expenseCount = _records.where((r) => !r.isIncome).length;

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本月支出',
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '¥${expense.toStringAsFixed(2)}',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              if (_balance != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '卡余额 ¥${_balance!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '充值/转入 ¥${income.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '已统计消费 $expenseCount 笔（共 $_totalCount 条记录）',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ],
          ),
          if (_cacheUpdatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _syncing
                  ? '正在同步最新流水...'
                  : '缓存更新于 ${_formatCacheTime(_cacheUpdatedAt!)}',
              style: TextStyle(
                fontSize: 11.5,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiaryLabel, context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncBanner(BuildContext context) {
    if (!_syncing && _syncWarning == null) return const SizedBox.shrink();
    final isWarning = _syncWarning != null;
    final tint = isWarning
        ? CupertinoColors.systemOrange
        : CupertinoColors.activeBlue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: RoundRectangleCard(
        child: Row(
          children: [
            if (_syncing && !isWarning)
              const CupertinoActivityIndicator(radius: 8)
            else
              Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                size: 16,
                color: tint,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _syncWarning ?? '正在后台同步校园卡最新流水...',
                style: TextStyle(
                  fontSize: 12.5,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ),
            if (isWarning)
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minSize: 28,
                onPressed: () => _loadMonthData(reset: true),
                child: const Text('重试', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryStatsCard(BuildContext context) {
    final cats = _categoryExpenses;
    if (cats.isEmpty) return const SizedBox.shrink();
    final totalCatExpense =
        cats.values.fold<double>(0.0, (prev, val) => prev + val);
    if (totalCatExpense <= 0) return const SizedBox.shrink();

    final topMerchants = _topMerchants;

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分类消费统计',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          ...cats.entries.map((entry) {
            final ratio = (entry.value / totalCatExpense).clamp(0.0, 1.0);
            final color = _categoryColor(entry.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(_categoryIcon(entry.key), size: 15, color: color),
                          const SizedBox(width: 6),
                          Text(
                            entry.key,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '¥${entry.value.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemFill, context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (topMerchants.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '常去档口 / 商户 TOP ${topMerchants.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
            const SizedBox(height: 6),
            ...topMerchants.asMap().entries.map((e) {
              final idx = e.key + 1;
              final item = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: idx <= 3
                            ? CupertinoColors.systemOrange.withValues(alpha: 0.2)
                            : CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$idx',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: idx <= 3
                              ? CupertinoColors.systemOrange
                              : CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '¥${item.value.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filterTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _filterTabs[index];
          final selected = _selectedCategory == tab;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = tab;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? CupertinoColors.activeBlue
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.secondarySystemGroupedBackground,
                        context),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(
                tab,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? CupertinoColors.white
                      : CupertinoDynamicColor.resolve(
                          CupertinoColors.label, context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionTile(BuildContext context, ECardTransaction tx) {
    final color = _categoryColor(tx.category);
    final amountPrefix = tx.isIncome ? '+' : '-';
    final amountColor = tx.isIncome
        ? CupertinoColors.activeGreen
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: RoundRectangleCard(
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(_categoryIcon(tx.category), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tx.dateTimeStr} · ${tx.turnoverType}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$amountPrefix¥${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
                if (tx.balanceAfter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '余额 ¥${tx.balanceAfter!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.tertiaryLabel, context),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '校园卡账单'),
            CupertinoSliverRefreshControl(
              onRefresh: () => _loadMonthData(reset: true),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _buildMonthSelector(context),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(radius: 14),
                      SizedBox(height: 10),
                      Text('正在获取校园卡流水与统计...',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.exclamationmark_circle,
                            size: 44, color: CupertinoColors.systemRed),
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          onPressed: () => _loadMonthData(reset: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _buildSyncBanner(context),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: _buildSummaryCard(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: _buildCategoryStatsCard(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: _buildFilterChips(context),
                ),
              ),
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '暂无符合条件的流水记录',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            minSize: 32,
                            onPressed: () => _loadMonthData(reset: true),
                            child: const Text('刷新重试',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildTransactionTile(context, filtered[index]),
                    childCount: filtered.length,
                  ),
                ),
              const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
            ],
          ],
        ),
      ),
    );
  }
}
