import 'dart:io';

import 'package:flutter/services.dart';
import 'package:celechron/services/secure_storage_service.dart';

import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/ecard.dart';

class ECardWidgetMessenger {
  static const _platform = MethodChannel('top.celechron.celechron/ecardWidget');

  static void installNativeHandler() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'refreshCredential') {
        return await update(notifyNative: false);
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

      return true;
    } catch (e) {
      return false;
    } finally {
      httpClient.close(force: true);
    }
  }

  static Future<void> logout() async {
    var secureStorage = const FlutterSecureStorage();
    await secureStorage.delete(key: 'synjonesAuth');
    await secureStorage.delete(key: 'eCardAccount');
  }
}
