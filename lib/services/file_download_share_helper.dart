import 'dart:io';

import 'package:celechron/design/app_notification.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SavedShareFileResult {
  final String? savedPath;
  final File? shareFile;
  final String fileName;
  final String mimeType;

  const SavedShareFileResult({
    required this.savedPath,
    required this.shareFile,
    required this.fileName,
    required this.mimeType,
  });

  bool get isSuccess => savedPath != null && savedPath!.isNotEmpty;
}

class FileDownloadShareHelper {
  FileDownloadShareHelper._();

  static String sanitizeFileName(String raw) {
    final cleaned =
        raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();
    return cleaned.isEmpty ? 'helechron_export' : cleaned;
  }

  static String inferMimeType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.txt') || lower.endsWith('.log')) {
      return 'text/plain';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.ms-powerpoint';
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/msword';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.ms-excel';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  static Future<String> resolveDefaultSaveDir() async {
    if (Get.isRegistered<Option>(tag: 'option')) {
      final custom = Get.find<Option>(tag: 'option').downloadPath.value.trim();
      if (custom.isNotEmpty) return custom;
    }
    final doc = await getApplicationDocumentsDirectory();
    return '${doc.path}/courseware';
  }

  static String formatDirShort(String dir) {
    if (dir.isEmpty) return '默认课件目录';
    if (dir.endsWith('/courseware')) return '默认课件目录 (courseware)';
    if (dir.length > 36) return '...${dir.substring(dir.length - 33)}';
    return dir;
  }

  /// 弹窗让用户选择保存路径（文件管理器自选路径 或 使用默认/当前路径）
  static Future<String?> chooseSaveDirectory(
    BuildContext context, {
    String? currentDir,
    String title = '选择保存路径并下载分享',
    String? fileLabel,
  }) async {
    final fallbackDir = (currentDir != null && currentDir.trim().isNotEmpty)
        ? currentDir.trim()
        : await resolveDefaultSaveDir();
    if (!context.mounted) return null;

    final choice = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${fileLabel != null && fileLabel.isNotEmpty ? "文件：$fileLabel\n" : ""}当前默认保存路径：\n${formatDirShort(fallbackDir)}\n\n下载完成后将自动拉起系统原生分享。',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(dialogCtx),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogCtx).pop('pick'),
            child: const Text('选择保存文件夹'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogCtx).pop('default'),
            child: const Text('使用当前目录'),
          ),
        ],
      ),
    );

    if (choice == null) return null;
    if (choice == 'pick') {
      final picked = await OhosNativeService.instance.pickDirectory();
      if (picked == null || picked.trim().isEmpty) return null;
      return picked.trim();
    }
    return fallbackDir;
  }

  static Future<Directory> _ensureShareCacheDir() async {
    final tempDir = await getTemporaryDirectory();
    final shareDir = Directory('${tempDir.path}/celechron_share');
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }
    return shareDir;
  }

  static Future<void> _pruneOldShareFiles(Directory shareDir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 12));
      await for (final entity in shareDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// 在应用沙盒缓存中准备一份标准命名副本，确保系统原生分享在各平台（含 HarmonyOS/Android SAF）均可稳定读取
  static Future<File?> prepareShareCacheFile(
    String fileName, {
    File? sourceFile,
    List<int>? bytes,
  }) async {
    try {
      final safeName = sanitizeFileName(fileName);
      final shareDir = await _ensureShareCacheDir();
      await _pruneOldShareFiles(shareDir);
      final target = File('${shareDir.path}/$safeName');
      if (sourceFile != null && await sourceFile.exists()) {
        await sourceFile.copy(target.path);
        return target;
      }
      if (bytes != null) {
        await target.writeAsBytes(bytes, flush: true);
        return target;
      }
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] prepareShareCacheFile error: $e');
    }
    return null;
  }

  static Future<File?> findShareCacheFile(String fileName) async {
    try {
      final safeName = sanitizeFileName(fileName);
      final shareDir = await _ensureShareCacheDir();
      final f = File('${shareDir.path}/$safeName');
      if (await f.exists() && await f.length() > 0) {
        return f;
      }
    } catch (_) {}
    return null;
  }

  /// 将临时文件写入目标目录，并在销毁临时文件前生成供原生分享使用的沙盒副本
  static Future<SavedShareFileResult> saveTempFileAndPrepareShare({
    required File tempFile,
    required String targetDir,
    required String fileName,
    String? mimeType,
  }) async {
    final safeName = sanitizeFileName(fileName);
    final resolvedMime = mimeType ?? inferMimeType(safeName);
    final shareFile =
        await prepareShareCacheFile(safeName, sourceFile: tempFile);

    String? savedPath;
    final canDirect = await Courses.isDirectoryDirectlyWritable(targetDir);
    if (canDirect) {
      final destDir = Directory(targetDir);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final destFile = File('${destDir.path}/$safeName');
      await tempFile.copy(destFile.path);
      savedPath = destFile.path;
    } else {
      savedPath = await OhosNativeService.instance.copyFileToDirectory(
        tempFile.path,
        targetDir,
        safeName,
        mimeType: resolvedMime,
      );
    }

    return SavedShareFileResult(
      savedPath: savedPath,
      shareFile: shareFile,
      fileName: safeName,
      mimeType: resolvedMime,
    );
  }

  /// 下载 CoursewareItem 到用户指定目录并同步产出沙盒分享副本
  static Future<SavedShareFileResult> downloadCoursewareAndPrepareShare(
    HttpClient client, {
    required CoursewareItem item,
    required String saveDir,
  }) async {
    final safeName = sanitizeFileName(item.name);
    final resolvedMime = inferMimeType(safeName);
    File? capturedShareFile;

    final savedPath = await Courses.downloadCoursewareFile(
      client,
      item: item,
      saveDir: saveDir,
      nativeCopyToDir: (sourcePath, targetDir, fileName, {mimeType}) async {
        capturedShareFile = await prepareShareCacheFile(
          fileName,
          sourceFile: File(sourcePath),
        );
        return OhosNativeService.instance.copyFileToDirectory(
          sourcePath,
          targetDir,
          fileName,
          mimeType: mimeType,
        );
      },
    );

    if (savedPath != null &&
        savedPath.isNotEmpty &&
        capturedShareFile == null &&
        !savedPath.startsWith('content://') &&
        !savedPath.startsWith('file://')) {
      final localFile = File(savedPath);
      if (await localFile.exists()) {
        capturedShareFile = await prepareShareCacheFile(
          safeName,
          sourceFile: localFile,
        );
      }
    }

    return SavedShareFileResult(
      savedPath: savedPath,
      shareFile: capturedShareFile,
      fileName: safeName,
      mimeType: resolvedMime,
    );
  }

  /// 调用系统原生分享（单文件或多文件）
  static Future<bool> shareFiles(
    List<File> files, {
    List<String>? mimeTypes,
    String? subject,
    String? text,
  }) async {
    final existing = <XFile>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (await f.exists() && await f.length() > 0) {
        final mime = (mimeTypes != null && i < mimeTypes.length)
            ? mimeTypes[i]
            : inferMimeType(f.path);
        existing.add(XFile(f.path, mimeType: mime));
      }
    }
    if (existing.isEmpty) {
      AppNotification.info('分享提示', '未能定位到可分享的本地文件，请点击“下载并分享”重试');
      return false;
    }

    try {
      await Share.shareXFiles(
        existing,
        subject: subject,
        text: text,
      );
      return true;
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] shareFiles error: $e');
      AppNotification.error('分享失败', '$e');
      return false;
    }
  }

  /// 分享已保存的文件（优先查沙盒缓存与直接路径，若遇外部只读 URI 则自动触发回调重新准备后分享）
  static Future<bool> shareSavedOrPrepare({
    required String? savedPath,
    required String fileName,
    String? mimeType,
    String? subject,
    String? text,
    Future<File?> Function()? onPrepareShareFile,
  }) async {
    File? target = await findShareCacheFile(fileName);
    if (target == null &&
        savedPath != null &&
        savedPath.isNotEmpty &&
        !savedPath.startsWith('content://') &&
        !savedPath.startsWith('file://')) {
      final f = File(savedPath);
      if (await f.exists() && await f.length() > 0) {
        target = await prepareShareCacheFile(fileName, sourceFile: f);
      }
    }
    if (target == null && onPrepareShareFile != null) {
      target = await onPrepareShareFile();
    }
    if (target == null) {
      AppNotification.info('分享提示', '未能读取该文件，请点击「下载并分享」重新获取');
      return false;
    }
    return shareFiles(
      [target],
      mimeTypes: [mimeType ?? inferMimeType(fileName)],
      subject: subject ?? fileName,
      text: text,
    );
  }
}
