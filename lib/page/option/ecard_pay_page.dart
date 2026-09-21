import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:get/get.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/secure_storage_service.dart';

import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import '../../http/zjuServices/ecard.dart';

enum _ViewState { loading, notLoggedIn, error, showing }

class ECardPayPage extends StatefulWidget {
  const ECardPayPage({super.key});

  @override
  State<ECardPayPage> createState() => _ECardPayPageState();
}

class _ECardPayPageState extends State<ECardPayPage> {
  final HttpClient _httpClient = HttpClient();

  static const String _testAccount = '3200000000';
  static const Duration _barcodeTtl = Duration(seconds: 60);
  static const Duration _autoRefreshLead = Duration(seconds: 5);
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  static const String _cacheKeyCode = 'lastValidBarcode';
  static const String _cacheKeyTime = 'lastValidBarcodeTime';

  final _viewState = Rx<_ViewState>(_ViewState.loading);
  final _code = ''.obs;
  final _fetchedAt = Rxn<DateTime>();
  final _isCached = false.obs;
  final _errorMsg = ''.obs;
  final _secondsRemaining = 0.obs;

  Timer? _refreshTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _httpClient.close(force: true);
    super.dispose();
  }

  Future<void> _load() async {
    _viewState.value = _ViewState.loading;
    await _requestNewCode(showErrors: true);
  }

  Future<void> _requestNewCode({bool showErrors = false}) async {
    const secureStorage = FlutterSecureStorage();
    final synjonesAuth = await secureStorage.read(key: 'synjonesAuth');

    if (synjonesAuth == null || synjonesAuth == _testAccount) {
      _viewState.value = _ViewState.notLoggedIn;
      _cancelTimers();
      return;
    }

    final eCardAccount = await secureStorage.read(key: 'eCardAccount');
    final account =
        eCardAccount ?? await ECard.getAccount(_httpClient, synjonesAuth);
    if (account.isEmpty) {
      _viewState.value = _ViewState.notLoggedIn;
      _cancelTimers();
      return;
    }
    await secureStorage.write(key: 'eCardAccount', value: account);

    _httpClient.userAgent =
        "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";
    try {
      final code = await ECard.getBarcode(_httpClient, synjonesAuth, account);
      final fetchedAt = DateTime.now();
      _code.value = code;
      _fetchedAt.value = fetchedAt;
      _isCached.value = false;
      _errorMsg.value = '';
      _viewState.value = _ViewState.showing;
      await secureStorage.write(key: _cacheKeyCode, value: code);
      await secureStorage.write(
          key: _cacheKeyTime, value: fetchedAt.toIso8601String());
      _syncPaymentCode(code);
      _scheduleCountdown(fetchedAt);
    } catch (e) {
      // 失败时尝试读取缓存码
      final cached = await _readCachedBarcode(secureStorage);
      if (cached != null) {
        _code.value = cached.code;
        _fetchedAt.value = cached.fetchedAt;
        _isCached.value = true;
        _errorMsg.value = e.toString();
        _viewState.value = _ViewState.showing;
        _scheduleCountdown(cached.fetchedAt);
      } else {
        _errorMsg.value = e.toString();
        _viewState.value = _ViewState.error;
        _cancelTimers();
        if (showErrors && mounted) {
          _showErrorSnack(e.toString());
        }
      }
    }
  }

  Future<_CachedBarcode?> _readCachedBarcode(
      FlutterSecureStorage secureStorage) async {
    final code = await secureStorage.read(key: _cacheKeyCode);
    final timeStr = await secureStorage.read(key: _cacheKeyTime);
    if (code == null || code.isEmpty || timeStr == null) return null;
    final t = DateTime.tryParse(timeStr);
    if (t == null) return null;
    if (DateTime.now().difference(t) > _cacheMaxAge) return null;
    if (!_isValidBarcode(code)) return null;
    return _CachedBarcode(code, t);
  }

  static final RegExp _validBarcodePattern =
      RegExp(r'^[A-Za-z0-9+/=_\-]{14,64}$');
  static bool _isValidBarcode(String s) => _validBarcodePattern.hasMatch(s);

  void _syncPaymentCode(String code) {
    OhosNativeService.instance.updatePaymentCodeWidget(code: code);
  }

  void _scheduleCountdown(DateTime fetchedAt) {
    _cancelTimers();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _barcodeTtl.inSeconds -
          DateTime.now().difference(fetchedAt).inSeconds;
      _secondsRemaining.value = remaining > 0 ? remaining : 0;
      if (remaining <= 0) {
        _cancelTimers();
        _requestNewCode();
      }
    });
    final leadRefresh = _barcodeTtl - _autoRefreshLead;
    final delay = leadRefresh - DateTime.now().difference(fetchedAt);
    if (delay.isNegative) {
      _requestNewCode();
    } else {
      _refreshTimer = Timer(delay, _requestNewCode);
    }
  }

  void _cancelTimers() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _showErrorSnack(String message) {
    Get.snackbar(
      '付款码刷新失败',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  Widget _buildCenter(BuildContext context) {
    final state = _viewState.value;
    switch (state) {
      case _ViewState.loading:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 14),
            SizedBox(height: 12),
            Text('加载中...', style: TextStyle(fontSize: 13)),
          ],
        );
      case _ViewState.notLoggedIn:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.creditcard,
                size: 56, color: CupertinoColors.systemGrey),
            SizedBox(height: 12),
            Text('尚未登录校园卡',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            SizedBox(height: 6),
            Text('请到"设置 → 校园卡账户"完成登录后查看付款码',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
          ],
        );
      case _ViewState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle,
                size: 48, color: CupertinoColors.systemRed),
            const SizedBox(height: 12),
            const Text('获取付款码失败',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_errorMsg.value,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: CupertinoColors.systemGrey)),
            ),
          ],
        );
      case _ViewState.showing:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            QrImageView(data: _code.value, version: 3, size: 200),
          ],
        );
    }
  }

  Widget _buildSubtitle(BuildContext context) {
    final state = _viewState.value;
    switch (state) {
      case _ViewState.showing:
        if (_isCached.value) {
          final age =
              DateTime.now().difference(_fetchedAt.value ?? DateTime.now());
          return Text(
            '缓存码 · ${age.inSeconds < 60 ? '${age.inSeconds}秒前' : '${age.inMinutes}分钟前'}',
            style: const TextStyle(
                fontSize: 12, color: CupertinoColors.systemOrange),
          );
        }
        return Text(
          '剩余 ${_secondsRemaining.value}s 自动刷新',
          style: const TextStyle(fontSize: 12),
        );
      case _ViewState.error:
        return const Text('付款码获取失败', style: TextStyle(fontSize: 12));
      case _ViewState.notLoggedIn:
        return const SizedBox.shrink();
      case _ViewState.loading:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCodeValue() {
    if (_code.value.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        _code.value,
        textAlign: TextAlign.center,
        maxLines: 1,
        style: const TextStyle(
          fontSize: 18,
          fontFamily: 'monospace',
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
          color: CupertinoColors.black,
        ),
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    if (_viewState.value == _ViewState.notLoggedIn) {
      return const SizedBox.shrink();
    }
    final loading = _viewState.value == _ViewState.loading;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: CupertinoColors.activeBlue,
      borderRadius: BorderRadius.circular(20),
      onPressed: loading
          ? null
          : () {
              _viewState.value = _ViewState.loading;
              _requestNewCode(showErrors: true);
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? const CupertinoActivityIndicator(
                  color: CupertinoColors.white, radius: 8)
              : const Icon(CupertinoIcons.refresh,
                  size: 18, color: CupertinoColors.white),
          const SizedBox(width: 8),
          const Text('刷新二维码',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '付款码'),
            SliverFillRemaining(
              child: Column(
                children: [
                  const Spacer(flex: 4),
                  Obx(() => _buildCenter(context)),
                  const SizedBox(height: 16),
                  Obx(() => _buildSubtitle(context)),
                  const SizedBox(height: 12),
                  Obx(() => _buildCodeValue()),
                  const SizedBox(height: 24),
                  Obx(() => _buildRefreshButton(context)),
                  const Spacer(flex: 6),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }
}

class _CachedBarcode {
  final String code;
  final DateTime fetchedAt;
  _CachedBarcode(this.code, this.fetchedAt);
}
