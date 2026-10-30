import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';

class Fuse {
  late DateTime lastUpdateTime;

  final bool isBeta = false;
  final version = [0, 1, 7];
  final build = 100;
  List<int>? remoteVersion;
  int? remoteBuild;
  bool hasNewVersion = false;

  final HttpClient _httpClient = HttpClient();
  final DatabaseHelper _db = Get.find<DatabaseHelper>(tag: 'db');

  String get displayVersion => '0.1.7';

  Fuse() {
    lastUpdateTime = DateTime(2001, 1, 1);
  }

  Future<String?> checkUpdate() async {
    try {
      if (lastUpdateTime
          .isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
        return null;
      }

      // 仅检查本移植项目的发布版本，不能把上游版本当作 Helechron 更新。
      const checkUpdateUrl =
          'https://api.github.com/repos/Kepler16f/Helechron/releases/latest';

      var request = await _httpClient
          .getUrl(Uri.parse(checkUpdateUrl))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'Helechron');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      var response = await request.close().timeout(const Duration(seconds: 8));
      var html = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return null;
      final release = jsonDecode(html) as Map<String, dynamic>;
      final tag = release['tag_name']?.toString() ?? '';
      final match =
          RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(tag);
      if (match == null || release['draft'] == true) return null;
      remoteVersion = [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
      remoteBuild = int.tryParse(match.group(4) ?? '') ?? 0;

      hasNewVersion = _compareVersion(release['prerelease'] == true);
      lastUpdateTime = DateTime.now();
      await _db.setFuse(this);

      if (hasNewVersion) {
        return "有新版本可用";
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  bool _compareVersion(bool remoteIsBeta) {
    if (remoteVersion == null || remoteBuild == null) {
      return false;
    }
    if (remoteVersion![0] > version[0]) {
      return true;
    } else if (remoteVersion![0] == version[0]) {
      if (remoteVersion![1] > version[1]) {
        return true;
      } else if (remoteVersion![1] == version[1]) {
        if (remoteVersion![2] > version[2]) {
          return true;
        } else if (remoteVersion![2] == version[2]) {
          if (remoteBuild! > build) {
            return true;
          } else if (remoteBuild == build) {
            if (isBeta && !remoteIsBeta) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'lastUpdateTime': lastUpdateTime.toIso8601String(),
      };

  Fuse.fromJson(Map<String, dynamic> json) {
    lastUpdateTime = DateTime.parse(json['lastUpdateTime']);
  }
}
