import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/services/mobile_native_service.dart';
import 'package:celechron/worker/fuse.dart';

/// 远程 Release 信息模型
class ReleaseInfo {
  final String tagName;
  final String cleanVersion;
  final int buildNumber;
  final String title;
  final String body;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final String? ipaDownloadUrl;
  final String? hapDownloadUrl;
  final int? apkSize;
  final String? publishedAt;
  final bool isPrerelease;
  final bool hasUpdate;

  ReleaseInfo({
    required this.tagName,
    required this.cleanVersion,
    required this.buildNumber,
    required this.title,
    required this.body,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.ipaDownloadUrl,
    this.hapDownloadUrl,
    this.apkSize,
    this.publishedAt,
    this.isPrerelease = false,
    required this.hasUpdate,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  static const String _kAutoCheckUpdateKey = 'option_auto_check_update';

  bool get autoCheckUpdate {
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      final val = db.optionsBox.get(_kAutoCheckUpdateKey);
      if (val is bool) return val;
      return true; // 默认开启
    } catch (_) {
      return true;
    }
  }

  set autoCheckUpdate(bool val) {
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      db.optionsBox.put(_kAutoCheckUpdateKey, val);
    } catch (_) {}
  }

  /// 检查 GitHub 最新 Release
  Future<ReleaseInfo?> checkUpdate({bool force = false}) async {
    try {
      final fuse = Fuse();
      const apiUrl =
          'https://api.github.com/repos/Kepler16f/Helechron/releases/latest';

      final request = await _httpClient.getUrl(Uri.parse(apiUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Helechron');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final text = await response.transform(utf8.decoder).join();
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['draft'] == true) return null;

      final tagName = data['tag_name']?.toString() ?? '';
      final title = data['name']?.toString() ?? tagName;
      final body = data['body']?.toString() ?? '暂无更新日志说明';
      final htmlUrl = data['html_url']?.toString() ??
          'https://github.com/Kepler16f/Helechron/releases';
      final publishedAt = data['published_at']?.toString();
      final isPrerelease = data['prerelease'] == true;

      // 解析版本与构建号，例如 v0.1.8+102 或 0.1.8_dev2
      final tagMatch =
          RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[+_](?:dev)?(\d+))?').firstMatch(tagName);
      List<int> remoteVer = [0, 0, 0];
      int remoteBuild = 0;
      if (tagMatch != null) {
        remoteVer = [
          int.tryParse(tagMatch.group(1) ?? '0') ?? 0,
          int.tryParse(tagMatch.group(2) ?? '0') ?? 0,
          int.tryParse(tagMatch.group(3) ?? '0') ?? 0,
        ];
        remoteBuild = int.tryParse(tagMatch.group(4) ?? '0') ?? 0;
      }

      // 解析资源下载链接
      String? apkUrl;
      String? ipaUrl;
      String? hapUrl;
      int? apkSize;

      final assets = data['assets'] as List? ?? [];
      for (final a in assets) {
        if (a is Map) {
          final name = (a['name']?.toString() ?? '').toLowerCase();
          final downloadUrl = a['browser_download_url']?.toString();
          if (name.endsWith('.apk')) {
            apkUrl = downloadUrl;
            apkSize = a['size'] as int?;
          } else if (name.endsWith('.ipa')) {
            ipaUrl = downloadUrl;
          } else if (name.endsWith('.hap')) {
            hapUrl = downloadUrl;
          }
        }
      }

      final hasUpdate = _isRemoteNewer(
        localVersion: fuse.version,
        localBuild: fuse.build,
        remoteVersion: remoteVer,
        remoteBuild: remoteBuild,
        currentDisplayVersion: fuse.displayVersion,
        remoteTag: tagName,
      );

      final cleanVer = tagName.replaceFirst(RegExp(r'^v'), '');

      return ReleaseInfo(
        tagName: tagName,
        cleanVersion: cleanVer,
        buildNumber: remoteBuild,
        title: title,
        body: body,
        htmlUrl: htmlUrl,
        apkDownloadUrl: apkUrl,
        ipaDownloadUrl: ipaUrl,
        hapDownloadUrl: hapUrl,
        apkSize: apkSize,
        publishedAt: publishedAt,
        isPrerelease: isPrerelease,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('UpdateService checkUpdate failed: $e');
      return null;
    }
  }

  bool _isRemoteNewer({
    required List<int> localVersion,
    required int localBuild,
    required List<int> remoteVersion,
    required int remoteBuild,
    required String currentDisplayVersion,
    required String remoteTag,
  }) {
    // 优先主次修订版本号比较
    for (var i = 0; i < 3; i++) {
      if (remoteVersion[i] > localVersion[i]) return true;
      if (remoteVersion[i] < localVersion[i]) return false;
    }
    // 主版本相同，比较 build 号
    if (remoteBuild > localBuild) return true;
    if (remoteBuild < localBuild) return false;

    // 若版本相同但 tag 包含 dev 且不相等
    final cleanTag = remoteTag.replaceFirst(RegExp(r'^v'), '').trim();
    if (cleanTag != currentDisplayVersion.trim() && cleanTag.isNotEmpty) {
      return true;
    }
    return false;
  }

  /// 下载 APK 文件至应用临时缓存区
  Future<File?> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/Helechron_update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'Helechron');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final total = response.contentLength;
      var received = 0;

      final sink = apkFile.openWrite();
      await response.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received, total);
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      return apkFile;
    } catch (e) {
      debugPrint('下载 APK 失败: $e');
      return null;
    }
  }

  /// 调用 Android 系统包安装器执行 APK 安装
  Future<bool> installApk(String filePath) async {
    return await MobileNativeService.instance.installApk(filePath);
  }

  /// 检查更新交互流程（弹窗提示并引导更新）
  Future<void> performCheckUpdateFlow(
    BuildContext context, {
    bool showLoading = true,
    bool silentIfNoUpdate = false,
  }) async {
    if (showLoading) {
      showCupertinoDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CupertinoAlertDialog(
          title: Text('检查更新'),
          content: Padding(
            padding: EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 12),
                Text('正在获取最新版本信息...'),
              ],
            ),
          ),
        ),
      );
    }

    final release = await checkUpdate(force: true);

    if (showLoading && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    if (release == null) {
      if (!silentIfNoUpdate) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('检查更新'),
            content: const Text('检查更新失败，请确保网络通畅后重试。'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (!release.hasUpdate) {
      if (!silentIfNoUpdate) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('检查更新'),
            content: Text('当前已是最新版本 (${Fuse().displayVersion})'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 发现新版本：弹窗展示版本号、更新日志及更新操作
    _showUpdateDialog(context, release);
  }

  void _showUpdateDialog(BuildContext context, ReleaseInfo release) {
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: Text('发现新版本 ${release.cleanVersion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              '当前版本：${Fuse().displayVersion}',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  release.body.trim().isEmpty ? '性能优化与问题修复' : release.body.trim(),
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('稍后'),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          if (Platform.isAndroid && release.apkDownloadUrl != null)
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('立即更新'),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _startDownloadAndInstall(context, release);
              },
            )
          else
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('前往下载'),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                launchUrl(Uri.parse(release.htmlUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }

  void _startDownloadAndInstall(BuildContext context, ReleaseInfo release) {
    final apkUrl = release.apkDownloadUrl;
    if (apkUrl == null) return;

    final receivedBytes = 0.obs;
    final totalBytes = (release.apkSize ?? 0).obs;
    final isDone = false.obs;

    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progCtx) => Obx(() {
        final rec = receivedBytes.value;
        final tot = totalBytes.value;
        final progress = tot > 0 ? (rec / tot).clamp(0.0, 1.0) : 0.0;
        final recMb = (rec / (1024 * 1024)).toStringAsFixed(1);
        final totMb = tot > 0
            ? (tot / (1024 * 1024)).toStringAsFixed(1)
            : '未知';

        return CupertinoAlertDialog(
          title: Text(isDone.value ? '下载完成' : '正在下载更新包...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: tot > 0 ? progress : null,
                backgroundColor: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill, context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  CupertinoDynamicColor.resolve(
                      CustomCupertinoDynamicColors.sakura, context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tot > 0
                    ? '$recMb MB / $totMb MB (${(progress * 100).toStringAsFixed(0)}%)'
                    : '$recMb MB',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
              if (isDone.value) ...[
                const SizedBox(height: 8),
                const Text('正在启动系统安装程序，请按提示完成安装...'),
              ],
            ],
          ),
          actions: [
            if (!isDone.value)
              CupertinoDialogAction(
                child: const Text('取消'),
                onPressed: () => Navigator.of(progCtx).pop(),
              ),
          ],
        );
      }),
    );

    downloadApk(
      apkUrl,
      onProgress: (received, total) {
        receivedBytes.value = received;
        totalBytes.value = total;
      },
    ).then((apkFile) async {
      isDone.value = true;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (apkFile != null && await apkFile.exists()) {
        final ok = await installApk(apkFile.path);
        if (!ok && context.mounted) {
          // 若直接安装调起失败，提示手动打开或通过系统打开方式安装
          showCupertinoDialog<void>(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('安装提示'),
              content: Text(
                  '更新包已下载至：\n${apkFile.path}\n如果未自动弹出安装界面，请在文件管理器中点击该安装包进行安装。'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('选择打开方式'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    MobileNativeService.instance.openFileWithSystem(
                      apkFile.path,
                      mimeType: 'application/vnd.android.package-archive',
                      title: '安装更新',
                    );
                  },
                ),
                CupertinoDialogAction(
                  child: const Text('确定'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          );
        }
      } else if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('下载失败'),
            content: const Text('下载更新包时遇到问题，您可选择前往 GitHub 页面手动下载。'),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('前往 GitHub'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  launchUrl(Uri.parse(release.htmlUrl),
                      mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        );
      }
    });
  }
}
