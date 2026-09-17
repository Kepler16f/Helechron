import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:celechron/services/ohos_native_service.dart';

import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/ecard.dart';

class ECardWidgetMessenger {
  static const _platform = MethodChannel('top.celechron.celechron/ecardWidget');

  static void installNativeHandler() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'refreshCredential') {
        final ok = await update(notifyNative: false);
        await updatePaymentCode();
        return ok;
      }
      throw MissingPluginException('Unsupported ECard method: ${call.method}');
    });
  }

  static Future<bool> update({bool notifyNative = true}) async {
    var secureStorage = const FlutterSecureStorage();
    var username = await secureStorage.read(key: 'username');
    var password = await secureStorage.read(key: 'password');
    if (username == null || password == null) return false;

    if (username == "3200000000") {
      await secureStorage.write(key: 'synjonesAuth', value: "3200000000");
      await secureStorage.write(key: 'eCardAccount', value: "3200000000");
      await _pushCredentials();
      return true;
    }

    var httpClient = HttpClient();
    httpClient.userAgent =
        "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";

    try {
      var iPlanetDirectoryPro =
          await ZjuAm.getSsoCookie(httpClient, username, password)
              .catchError((e) => null);
      var synjonesAuth =
          await ECard.getSynjonesAuth(httpClient, iPlanetDirectoryPro);
      var eCardAccount = await ECard.getAccount(httpClient, synjonesAuth);
      await secureStorage.write(key: 'synjonesAuth', value: synjonesAuth);
      await secureStorage.write(key: 'eCardAccount', value: eCardAccount);
      await _pushCredentials();

      return true;
    } catch (e) {
      return false;
    } finally {
      httpClient.close(force: true);
    }
  }

  /// 将鉴权凭据同步给原生，供小组件刷新按钮在原生侧直接取码。
  static Future<void> _pushCredentials() async {
    try {
      final secureStorage = const FlutterSecureStorage();
      final synjonesAuth = await secureStorage.read(key: 'synjonesAuth');
      final eCardAccount = await secureStorage.read(key: 'eCardAccount');
      if (synjonesAuth == null || synjonesAuth.isEmpty) {
        return;
      }
      await OhosNativeService.instance.setPaymentCredentials(
        synjonesAuth: synjonesAuth,
        eCardAccount: eCardAccount ?? '',
      );
    } catch (_) {}
  }

  static Future<void> logout() async {
    var secureStorage = const FlutterSecureStorage();
    await secureStorage.delete(key: 'synjonesAuth');
    await secureStorage.delete(key: 'eCardAccount');
  }

  /// 拉取当前付款码并同步到桌面小组件。
  /// 未登录时静默跳过，失败时保留上一次的付款码。
  static Future<void> updatePaymentCode() async {
    try {
      final secureStorage = const FlutterSecureStorage();
      final synjonesAuth = await secureStorage.read(key: 'synjonesAuth');
      var eCardAccount = await secureStorage.read(key: 'eCardAccount');

      if (synjonesAuth == null || synjonesAuth.isEmpty) {
        return;
      }

      // 让原生侧也持有凭据，支持小组件“刷新”按钮直接取码
      await _pushCredentials();

      // 测试账号：生成模拟付款码，便于本地预览
      if (synjonesAuth == "3200000000" || eCardAccount == "3200000000") {
        final code =
            List.generate(16, (_) => Random().nextInt(10).toString()).join();
        await OhosNativeService.instance.updatePaymentCodeWidget(code: code);
        return;
      }

      final httpClient = HttpClient();
      httpClient.userAgent =
          "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";
      try {
        final account =
            eCardAccount ?? await ECard.getAccount(httpClient, synjonesAuth);
        await secureStorage.write(key: 'eCardAccount', value: account);
        final code = await ECard.getBarcode(httpClient, synjonesAuth, account);
        await OhosNativeService.instance.updatePaymentCodeWidget(code: code);
      } finally {
        httpClient.close(force: true);
      }
    } catch (_) {
      // 网络或鉴权失败：保留上一次的付款码，不覆盖为空
    }
  }
}
