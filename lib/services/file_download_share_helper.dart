import 'dart:convert';
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

class SavedDownloadRecord {
  final String savedPath;
  final String fileName;
  final String mimeType;

  const SavedDownloadRecord({
    required this.savedPath,
    required this.fileName,
    required this.mimeType,
  });
}

class SaveTargetChoice {
  final String directory;
  final String fileName;

  const SaveTargetChoice({required this.directory, required this.fileName});
}

class FileDownloadShareHelper {
  FileDownloadShareHelper._();

  static String sanitizeFileName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_')
        .trim();
    return cleaned.isEmpty ? 'helechron_export' : cleaned;
  }

  /// 根据用户输入和默认文件名生成安全文件名，若用户去掉了后缀且未输入新后缀则自动补回原后缀
  static String resolveFinalFileName(
    String userInput, {
    required String defaultFileName,
    bool preserveExtension = true,
  }) {
    final fallback = sanitizeFileName(defaultFileName);
    final trimmedInput = userInput.trim();
    if (trimmedInput.isEmpty) return fallback;
    final cleaned = sanitizeFileName(trimmedInput);
    if (!preserveExtension) return cleaned;
    final dotIdx = fallback.lastIndexOf('.');
    if (dotIdx > 0 && dotIdx < fallback.length - 1) {
      final defaultExt = fallback.substring(dotIdx);
      if (!cleaned.toLowerCase().endsWith(defaultExt.toLowerCase()) &&
          !cleaned.contains('.')) {
        return '$cleaned$defaultExt';
      }
    }
    return cleaned;
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

  /// 弹窗让用户在下载前自定义文件名并选择保存路径（文件管理器自选路径 或 使用当前目录）
  static Future<SaveTargetChoice?> chooseSaveTarget(
    BuildContext context, {
    required String defaultFileName,
    String? currentDir,
    String title = '下载并分享',
    String? description,
    String fileNamePlaceholder = '请输入文件名',
    bool preserveExtension = true,
    String? confirmHint,
  }) async {
    final fallbackDir = (currentDir != null && currentDir.trim().isNotEmpty)
        ? currentDir.trim()
        : await resolveDefaultSaveDir();
    if (!context.mounted) return null;

    final safeDefault = sanitizeFileName(defaultFileName);
    final nameCtrl = TextEditingController(text: safeDefault);

    final choice = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${description != null && description.isNotEmpty ? "$description\n" : ""}保存路径：${formatDirShort(fallbackDir)}\n${confirmHint ?? "可自定义文件名，下载完成后自动调起原生分享："}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: CupertinoColors.secondaryLabel.resolveFrom(dialogCtx),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: nameCtrl,
                autofocus: true,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: fileNamePlaceholder,
                style: TextStyle(
                  fontSize: 13.5,
                  color: CupertinoColors.label.resolveFrom(dialogCtx),
                ),
                placeholderStyle: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.placeholderText.resolveFrom(dialogCtx),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(
                    dialogCtx,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
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

    final finalFileName = resolveFinalFileName(
      nameCtrl.text,
      defaultFileName: safeDefault,
      preserveExtension: preserveExtension,
    );
    Future<void>.delayed(const Duration(milliseconds: 400), nameCtrl.dispose);

    if (choice == null) return null;
    if (choice == 'pick') {
      final picked = await OhosNativeService.instance.pickDirectory();
      if (picked == null || picked.trim().isEmpty) return null;
      return SaveTargetChoice(
        directory: picked.trim(),
        fileName: finalFileName,
      );
    }
    return SaveTargetChoice(directory: fallbackDir, fileName: finalFileName);
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
    final shareFile = await prepareShareCacheFile(
      safeName,
      sourceFile: tempFile,
    );

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
    String? customFileName,
  }) async {
    final safeName =
        (customFileName != null && customFileName.trim().isNotEmpty)
        ? resolveFinalFileName(customFileName, defaultFileName: item.name)
        : sanitizeFileName(item.name);
    final effectiveItem = safeName == item.name
        ? item
        : CoursewareItem(
            name: safeName,
            sectionTitle: item.sectionTitle,
            sizeBytes: item.sizeBytes,
            uploadId: item.uploadId,
            referenceId: item.referenceId,
            directUrl: item.directUrl,
            source: item.source,
          );
    final resolvedMime = inferMimeType(safeName);
    File? capturedShareFile;

    final savedPath = await Courses.downloadCoursewareFile(
      client,
      item: effectiveItem,
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

  // ───────────── 下载记录（下载与分享解耦） ─────────────

  static Future<File> _recordsFile() async {
    final doc = await getApplicationDocumentsDirectory();
    return File('${doc.path}/download_records.json');
  }

  static Future<Map<String, dynamic>> _loadRecords() async {
    try {
      final f = await _recordsFile();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// 记录一次成功下载（key 为业务唯一键，如 课程+课节+类型）
  static Future<void> saveDownloadRecord(
    String key, {
    required String savedPath,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      final records = await _loadRecords();
      records[key] = {
        'savedPath': savedPath,
        'fileName': fileName,
        'mimeType': mimeType ?? inferMimeType(fileName),
      };
      final f = await _recordsFile();
      await f.writeAsString(jsonEncode(records), flush: true);
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] saveDownloadRecord error: $e');
    }
  }

  /// 读取并校验下载记录；文件已被删除则返回 null
  static Future<SavedDownloadRecord?> getDownloadRecord(String key) async {
    final records = await _loadRecords();
    final raw = records[key];
    if (raw is! Map) return null;
    final savedPath = '${raw['savedPath'] ?? ''}';
    final fileName = '${raw['fileName'] ?? ''}';
    if (savedPath.isEmpty || fileName.isEmpty) return null;
    var exists = false;
    if (savedPath.startsWith('content://') || savedPath.startsWith('file://')) {
      exists = await findShareCacheFile(fileName) != null;
    } else {
      try {
        final f = File(savedPath);
        exists = await f.exists() && await f.length() > 0;
      } catch (_) {}
      if (!exists) exists = await findShareCacheFile(fileName) != null;
    }
    if (!exists) return null;
    return SavedDownloadRecord(
      savedPath: savedPath,
      fileName: fileName,
      mimeType: '${raw['mimeType'] ?? inferMimeType(fileName)}',
    );
  }

  /// 统一的「仅下载 / 分享」流程。
  /// - [share]=false：弹出命名/路径选择 → 生成文件 → 保存并登记，不分享。
  /// - [share]=true：已下载过则直接分享原文件；未下载则等同「下载并分享」。
  /// [writeTemp] 负责把内容写入给定临时文件，返回是否成功。
  static Future<bool> exportFile(
    BuildContext context, {
    required String recordKey,
    required String defaultFileName,
    required String mimeType,
    required Future<bool> Function(File tempFile) writeTemp,
    required bool share,
    String? description,
    String? title,
  }) async {
    if (share) {
      final record = await getDownloadRecord(recordKey);
      if (record != null) {
        return shareSavedOrPrepare(
          savedPath: record.savedPath,
          fileName: record.fileName,
          mimeType: record.mimeType,
          subject: record.fileName,
        );
      }
    }
    if (!context.mounted) return false;
    final target = await chooseSaveTarget(
      context,
      defaultFileName: defaultFileName,
      title: title ?? (share ? '下载并分享' : '下载'),
      description: description,
      confirmHint: share ? '下载完成后将自动调起系统分享：' : '仅下载保存，不会触发分享：',
    );
    if (target == null) return false;

    final tempFile = File(
      '${Directory.systemTemp.path}/temp_export_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      final ok = await writeTemp(tempFile);
      if (!ok) return false;
      final res = await saveTempFileAndPrepareShare(
        tempFile: tempFile,
        targetDir: target.directory,
        fileName: target.fileName,
        mimeType: mimeType,
      );
      if (!res.isSuccess) {
        AppNotification.error('保存失败', '未能写入目标目录');
        return false;
      }
      await saveDownloadRecord(
        recordKey,
        savedPath: res.savedPath!,
        fileName: res.fileName,
        mimeType: res.mimeType,
      );
      AppNotification.success(
        share ? '已保存，正在分享' : '下载完成',
        '${res.fileName}\n已保存：${formatDirShort(target.directory)}',
      );
      if (share && res.shareFile != null) {
        await shareFiles(
          [res.shareFile!],
          mimeTypes: [res.mimeType],
          subject: res.fileName,
        );
      }
      return true;
    } catch (e) {
      AppNotification.error('操作失败', '$e');
      return false;
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
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
      AppNotification.info('分享提示', '未能定位到可分享的本地文件，请重新点击分享或下载重试');
      return false;
    }

    try {
      await Share.shareXFiles(existing, subject: subject, text: text);
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
      AppNotification.info('分享提示', '未能读取该文件，请重新下载后分享');
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
