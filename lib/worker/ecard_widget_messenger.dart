import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/secure_storage_service.dart';
import 'package:celechron/services/ohos_native_service.dart';

import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/ecard.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';

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
    if ((username == null ||
            username.isEmpty ||
            password == null ||
            password.isEmpty) &&
        Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
      if (scholar.username != null &&
          scholar.username!.isNotEmpty &&
          scholar.password != null &&
          scholar.password!.isNotEmpty) {
        username = scholar.username;
        password = scholar.password;
        await secureStorage.write(key: 'username', value: username);
        await secureStorage.write(key: 'password', value: password);
      }
    }
    if (username == null || password == null) return false;

    // 即使后续网络请求尚未完成或暂时超时，也先把学号密码同步给原生，
    // 确保桌面小组件放大页在应用被杀/墓碑后台时能独立完成 CAS SSO 重登。
    await _pushCredentials();

    if (username == "3200000000") {
      await secureStorage.write(key: 'synjonesAuth', value: "3200000000");
      await secureStorage.write(key: 'eCardAccount', value: "3200000000");
      await _pushCredentials();
      return true;
    }

    var httpClient = HttpClient();
    httpClient.userAgent =
        "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";
    applyZjuNetworkDefense(httpClient);

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

  /// 将鉴权凭据（含学号与密码）同步给原生，供小组件刷新按钮与放大页在原生侧直接取码及过期自动重登。
  static Future<void> syncCredentialsToNative() => _pushCredentials();

  static Future<void> _pushCredentials() async {
    try {
      const secureStorage = FlutterSecureStorage();
      final synjonesAuth = await secureStorage.read(key: 'synjonesAuth');
      final eCardAccount = await secureStorage.read(key: 'eCardAccount');
      var username = await secureStorage.read(key: 'username');
      var password = await secureStorage.read(key: 'password');
      if ((username == null ||
              username.isEmpty ||
              password == null ||
              password.isEmpty) &&
          Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
        final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
        if (scholar.username != null && scholar.username!.isNotEmpty) {
          username = scholar.username;
        }
        if (scholar.password != null && scholar.password!.isNotEmpty) {
          password = scholar.password;
        }
      }
      if ((synjonesAuth == null || synjonesAuth.isEmpty) &&
          (username == null || username.isEmpty)) {
        return;
      }
      await OhosNativeService.instance.setPaymentCredentials(
        synjonesAuth: synjonesAuth ?? '',
        eCardAccount: eCardAccount ?? '',
        username: username,
        password: password,
      );
    } catch (_) {}
  }

  static Future<void> logout() async {
    var secureStorage = const FlutterSecureStorage();
    await secureStorage.delete(key: 'synjonesAuth');
    await secureStorage.delete(key: 'eCardAccount');
    await OhosNativeService.instance.setPaymentCredentials(
      synjonesAuth: '',
      eCardAccount: '',
      clear: true,
    );
  }

  /// 拉取当前付款码并同步到桌面小组件。
  /// 未登录时静默跳过，失败时保留上一次的付款码。
  static Future<void> updatePaymentCode() async {
    try {
      const secureStorage = FlutterSecureStorage();
      var synjonesAuth = await secureStorage.read(key: 'synjonesAuth');
      var eCardAccount = await secureStorage.read(key: 'eCardAccount');

      // 让原生侧也持有凭据（含学号密码），支持小组件“刷新”按钮与放大页直接取码/重登
      await _pushCredentials();

      if (synjonesAuth == null || synjonesAuth.isEmpty) {
        final reloginOk = await update(notifyNative: false);
        if (!reloginOk) {
          return;
        }
        synjonesAuth = await secureStorage.read(key: 'synjonesAuth');
        eCardAccount = await secureStorage.read(key: 'eCardAccount');
        if (synjonesAuth == null || synjonesAuth.isEmpty) {
          return;
        }
      }

      // 未登录 / 测试账号：不推送任何码，让小组件显示"点击打开付款码"占位
      if (synjonesAuth == "3200000000" || eCardAccount == "3200000000") {
        await OhosNativeService.instance.updatePaymentCodeWidget(code: '');
        return;
      }

      final httpClient = HttpClient();
      httpClient.userAgent =
          "E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)";
      applyZjuNetworkDefense(httpClient);
      try {
        String? account = eCardAccount;
        if (account == null || account.isEmpty) {
          try {
            account = await ECard.getAccount(httpClient, synjonesAuth);
            await secureStorage.write(key: 'eCardAccount', value: account);
          } catch (_) {
            account = null;
          }
        }
        try {
          if (account == null || account.isEmpty) {
            throw Exception('Missing eCardAccount');
          }
          final code =
              await ECard.getBarcode(httpClient, synjonesAuth, account);
          await OhosNativeService.instance.updatePaymentCodeWidget(code: code);
        } catch (_) {
          // 付款码接口失败通常是 synjones-auth 过期：重新登录一次再取，
          // 避免小组件长期停留在过期/空白的付款码。
          final reloginOk = await update(notifyNative: false);
          if (!reloginOk) {
            return;
          }
          final freshAuth = await secureStorage.read(key: 'synjonesAuth');
          final freshAccount = await secureStorage.read(key: 'eCardAccount');
          if (freshAuth == null || freshAuth.isEmpty) {
            return;
          }
          final targetAccount = freshAccount ?? account ?? '';
          if (targetAccount.isEmpty) {
            return;
          }
          final code =
              await ECard.getBarcode(httpClient, freshAuth, targetAccount);
          await OhosNativeService.instance.updatePaymentCodeWidget(code: code);
        }
      } finally {
        httpClient.close(force: true);
      }
    } catch (_) {
      // 网络或鉴权失败：保留上一次的付款码，不覆盖为空
    }
  }
}
