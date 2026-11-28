import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/app_notification.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
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
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  /// 在同批次下载/打包出现重名文件时自动附加编号避免互相覆盖
  static String disambiguateFileName(
    String rawName,
    Set<String> usedLowerNames,
  ) {
    final cleaned = sanitizeFileName(rawName);
    if (usedLowerNames.add(cleaned.toLowerCase())) {
      return cleaned;
    }
    final dotIdx = cleaned.lastIndexOf('.');
    final hasExt = dotIdx > 0 && dotIdx < cleaned.length - 1;
    final stem = hasExt ? cleaned.substring(0, dotIdx) : cleaned;
    final ext = hasExt ? cleaned.substring(dotIdx) : '';
    var seq = 2;
    while (true) {
      final candidate = '$stem ($seq)$ext';
      if (usedLowerNames.add(candidate.toLowerCase())) {
        return candidate;
      }
      seq++;
    }
  }

  /// 将用户选择的保存目录持久化到全局设置，确保下次打开仍记住上次目录
  static Future<void> persistDownloadPath(String dir) async {
    final trimmed = dir.trim();
    if (trimmed.isEmpty) return;
    try {
      if (Get.isRegistered<Option>(tag: 'option')) {
        Get.find<Option>(tag: 'option').downloadPath.value = trimmed;
      }
      if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
        await Get.find<DatabaseHelper>(tag: 'db').setDownloadPath(trimmed);
      }
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] persistDownloadPath error: $e');
    }
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

    final choice = await showAelDialog<String>(
      context: context,
      title: title,
      message:
          '${fileLabel != null && fileLabel.isNotEmpty ? "文件：$fileLabel\n" : ""}当前默认保存路径：\n${formatDirShort(fallbackDir)}\n\n下载完成后将自动拉起系统原生分享。',
      actions: const [
        AelDialogAction<String>(label: '取消', variant: AelButtonVariant.tonal),
        AelDialogAction<String>(
          label: '选择保存文件夹',
          value: 'pick',
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<String>(
          label: '使用当前目录',
          value: 'default',
          variant: AelButtonVariant.primary,
        ),
      ],
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
    bool allowEmptyFileName = false,
    String? confirmHint,
  }) async {
    final fallbackDir = (currentDir != null && currentDir.trim().isNotEmpty)
        ? currentDir.trim()
        : await resolveDefaultSaveDir();
    if (!context.mounted) return null;

    final safeDefault = (allowEmptyFileName && defaultFileName.trim().isEmpty)
        ? ''
        : sanitizeFileName(defaultFileName);
    final nameCtrl = TextEditingController(text: safeDefault);

    final choice = await showAelDialog<String>(
      context: context,
      title: title,
      message:
          '${description != null && description.isNotEmpty ? "$description\n" : ""}保存路径：${formatDirShort(fallbackDir)}\n${confirmHint ?? "可自定义文件名，下载完成后自动调起原生分享："}',
      content: Builder(
        builder: (dialogCtx) {
          final colors = AelTheme.colorsOf(dialogCtx);
          return CupertinoTextField(
            controller: nameCtrl,
            autofocus: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            placeholder: fileNamePlaceholder,
            padding: const EdgeInsets.symmetric(
              horizontal: AelSpacing.md,
              vertical: AelSpacing.md,
            ),
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
            placeholderStyle: TextStyle(
              fontSize: 13.5,
              color: colors.textTertiary,
            ),
            decoration: BoxDecoration(
              color: colors.tonalTileBg,
              borderRadius: BorderRadius.circular(AelRadius.tile),
            ),
          );
        },
      ),
      actions: const [
        AelDialogAction<String>(label: '取消', variant: AelButtonVariant.tonal),
        AelDialogAction<String>(
          label: '选择保存文件夹',
          value: 'pick',
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<String>(
          label: '使用当前目录',
          value: 'default',
          variant: AelButtonVariant.primary,
        ),
      ],
    );

    final finalFileName = (allowEmptyFileName && nameCtrl.text.trim().isEmpty)
        ? ''
        : resolveFinalFileName(
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
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
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
        if (sourceFile.absolute.path == target.absolute.path) {
          return target;
        }
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

  static Map<String, dynamic>? _recordsCache;
  static String? _recordsFilePathOverride;

  /// 仅供单元测试覆盖记录文件路径并重置内存缓存
  @visibleForTesting
  static void setRecordsFilePathForTest(String? path) {
    _recordsFilePathOverride = path;
    _recordsCache = null;
  }

  static Future<File> _recordsFile() async {
    final override = _recordsFilePathOverride;
    if (override != null && override.isNotEmpty) {
      return File(override);
    }
    final doc = await getApplicationDocumentsDirectory();
    return File('${doc.path}/download_records.json');
  }

  static Future<Map<String, dynamic>> _loadRecords() async {
    if (_recordsCache != null) return _recordsCache!;
    try {
      final f = await _recordsFile();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, dynamic>) {
          _recordsCache = Map<String, dynamic>.from(decoded);
          return _recordsCache!;
        }
      }
    } catch (_) {}
    _recordsCache = <String, dynamic>{};
    return _recordsCache!;
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
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final f = await _recordsFile();
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsString(jsonEncode(records), flush: true);
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] saveDownloadRecord error: $e');
    }
  }

  static Future<bool> _isInsideAppPrivateDir(String savedPath) async {
    if (savedPath.startsWith('content://') || savedPath.startsWith('file://')) {
      return false;
    }
    try {
      final doc = await getApplicationDocumentsDirectory();
      final normSaved = savedPath.replaceAll('\\', '/');
      final normDoc = doc.path.replaceAll('\\', '/');
      return normSaved.startsWith(normDoc);
    } catch (_) {
      return false;
    }
  }

  /// 读取并校验下载记录：
  /// - 应用私有目录直接校验本地文件；
  /// - Android SAF / 鸿蒙外部公共目录受沙箱限制无法通过 dart:io File.exists() 探测，
  ///   先查沙盒缓存与原生存在性接口；仅在原生明确确认已删除（返回 false）时才判空，
  ///   避免重新进入页面后丢失已下载状态记忆。
  static Future<SavedDownloadRecord?> getDownloadRecord(String key) async {
    final records = await _loadRecords();
    final raw = records[key];
    if (raw is! Map) return null;
    final savedPath = '${raw['savedPath'] ?? ''}';
    final fileName = '${raw['fileName'] ?? ''}';
    if (savedPath.isEmpty || fileName.isEmpty) return null;

    var exists = false;
    if (!savedPath.startsWith('content://') &&
        !savedPath.startsWith('file://')) {
      try {
        final f = File(savedPath);
        exists = await f.exists() && await f.length() > 0;
      } catch (_) {}
    }
    if (!exists) {
      exists = await findShareCacheFile(fileName) != null;
    }
    if (!exists) {
      final inPrivate = await _isInsideAppPrivateDir(savedPath);
      if (inPrivate) {
        return null;
      }
      final nativeExists = await OhosNativeService.instance
          .checkSavedFileExists(savedPath);
      if (nativeExists == false) {
        return null;
      }
      // nativeExists == true，或 == null（外部目录因系统沙箱无法直接 stat，保留已下载记忆）
      exists = true;
    }
    if (!exists) return null;
    return SavedDownloadRecord(
      savedPath: savedPath,
      fileName: fileName,
      mimeType: '${raw['mimeType'] ?? inferMimeType(fileName)}',
    );
  }

  /// 尝试从沙盒分享缓存、直接路径或原生 SAF/CoreFileKit 通道恢复可分享的本地缓存文件
  static Future<File?> recoverShareFileFromSavedPath({
    required String? savedPath,
    required String fileName,
  }) async {
    final cached = await findShareCacheFile(fileName);
    if (cached != null) return cached;

    if (savedPath == null || savedPath.isEmpty) return null;
    if (!savedPath.startsWith('content://') &&
        !savedPath.startsWith('file://')) {
      try {
        final f = File(savedPath);
        if (await f.exists() && await f.length() > 0) {
          return await prepareShareCacheFile(fileName, sourceFile: f);
        }
      } catch (_) {}
    }

    try {
      final shareDir = await _ensureShareCacheDir();
      final dest = File('${shareDir.path}/${sanitizeFileName(fileName)}');
      final copied = await OhosNativeService.instance.copySavedFileToCache(
        savedPath,
        dest.path,
      );
      if (copied && await dest.exists() && await dest.length() > 0) {
        return dest;
      }
    } catch (_) {}
    return null;
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

  static Rect? _resolveShareOrigin() {
    try {
      final ctx = Get.context;
      if (ctx != null) {
        final size = MediaQuery.maybeSizeOf(ctx);
        if (size != null && size.width > 0 && size.height > 0) {
          return Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: 2,
            height: 2,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 调用系统原生分享（单文件或多文件）
  static Future<bool> shareFiles(
    List<File> files, {
    List<String>? mimeTypes,
    String? subject,
    String? text,
  }) async {
    final existingFiles = <File>[];
    final existingMimes = <String>[];
    final existing = <XFile>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (await f.exists() && await f.length() > 0) {
        final mime = (mimeTypes != null && i < mimeTypes.length)
            ? mimeTypes[i]
            : inferMimeType(f.path);
        existingFiles.add(f);
        existingMimes.add(mime);
        existing.add(XFile(f.path, mimeType: mime));
      }
    }
    if (existing.isEmpty) {
      AppNotification.info('分享提示', '未能定位到可分享的本地文件，请重新点击分享或下载重试');
      return false;
    }

    final normalizedSubject = (subject != null && subject.trim().isNotEmpty)
        ? subject.trim()
        : null;
    final normalizedText = (text != null && text.trim().isNotEmpty)
        ? text.trim()
        : null;

    // Android / HarmonyOS 优先使用原生 FileProvider+ClipData / @kit.ShareKit 分享通道，
    // 解决 share_plus 在部分机型及二进制课件 MIME 下未拉起系统分享面板的问题。
    final nativeShared = await OhosNativeService.instance.shareFiles(
      existingFiles.map((f) => f.path).toList(),
      mimeTypes: existingMimes,
      subject: normalizedSubject,
      text: normalizedText,
    );
    if (nativeShared) {
      return true;
    }

    try {
      final res = await Share.shareXFiles(
        existing,
        subject: normalizedSubject,
        text: normalizedText,
        sharePositionOrigin: _resolveShareOrigin(),
      );
      if (res.status != ShareResultStatus.unavailable) {
        return true;
      }
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] shareFiles error: $e');
      if (existingFiles.length == 1) {
        final opened = await OhosNativeService.instance.openFileWithSystem(
          existingFiles.first.path,
          mimeType: existingMimes.first,
          title: normalizedSubject ?? '选择打开或分享方式',
        );
        if (opened) return true;
      }
      AppNotification.error('分享失败', '$e');
      return false;
    }

    if (existingFiles.length == 1) {
      final opened = await OhosNativeService.instance.openFileWithSystem(
        existingFiles.first.path,
        mimeType: existingMimes.first,
        title: normalizedSubject ?? '选择打开或分享方式',
      );
      if (opened) return true;
    }
    AppNotification.info('分享提示', '当前设备暂未能拉起系统分享面板，文件已保存至本地目录');
    return false;
  }

  /// 将多个本地文件打包为单个 ZIP 压缩包（存放在沙盒分享缓存目录），
  /// 解决微信/部分安卓系统分享面板在多文件分享时仅接收最后一个文件的问题。
  static Future<File?> bundleFilesToZip(
    List<File> files, {
    required String zipBaseName,
  }) async {
    try {
      final archive = Archive();
      final usedNames = <String>{};
      var addedCount = 0;
      for (final f in files) {
        if (!await f.exists() || await f.length() <= 0) continue;
        final rawName = f.path
            .split(Platform.pathSeparator)
            .last
            .split('/')
            .last;
        final entryName = disambiguateFileName(rawName, usedNames);
        final bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
        addedCount++;
      }
      if (addedCount == 0) return null;
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes.isEmpty) return null;
      final cleanBase = sanitizeFileName(zipBaseName);
      final zipName = cleanBase.toLowerCase().endsWith('.zip')
          ? cleanBase
          : '$cleanBase.zip';
      return await prepareShareCacheFile(zipName, bytes: zipBytes);
    } catch (e) {
      debugPrint('[FileDownloadShareHelper] bundleFilesToZip error: $e');
      return null;
    }
  }

  /// 分享单个或多个文件：
  /// - 单文件直接唤起系统原生分享面板；
  /// - 多文件时弹出底部选项，提供「打包为 ZIP 分享（推荐，兼容微信/QQ 完整接收全部文件）」
  ///   与「直接多文件分享」两种方式。
  static Future<bool> shareFilesWithBatchOption(
    BuildContext context,
    List<File> files, {
    List<String>? mimeTypes,
    required String subject,
    String? text,
  }) async {
    final validFiles = <File>[];
    final validMimes = <String>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (await f.exists() && await f.length() > 0) {
        validFiles.add(f);
        validMimes.add(
          (mimeTypes != null && i < mimeTypes.length)
              ? mimeTypes[i]
              : inferMimeType(f.path),
        );
      }
    }
    if (validFiles.isEmpty) {
      AppNotification.info('分享提示', '未能定位到可分享的本地文件，请重新点击分享或下载重试');
      return false;
    }
    if (validFiles.length == 1) {
      return shareFiles(
        validFiles,
        mimeTypes: validMimes,
        subject: subject,
        text: text,
      );
    }
    if (!context.mounted) return false;
    final mode = await showAelActionSheet<String>(
      context: context,
      title: '分享 ${validFiles.length} 个文件',
      message: '微信等部分应用直接多文件分享可能仅接收最后一个文件；推荐打包为 ZIP 一次完整发送。',
      actions: [
        AelActionOption<String>(
          label: '打包为 ZIP 分享（推荐，共 ${validFiles.length} 个）',
          value: 'zip',
          isDefault: true,
        ),
        AelActionOption<String>(
          label: '直接多文件分享（${validFiles.length} 个文件）',
          value: 'multi',
        ),
      ],
    );
    if (mode == null) return false;
    if (mode == 'zip') {
      final zipFile = await bundleFilesToZip(
        validFiles,
        zipBaseName: '${subject}_${validFiles.length}个文件',
      );
      if (zipFile == null) {
        AppNotification.error('打包失败', '未能生成 ZIP 压缩包，已尝试直接多文件分享');
        return shareFiles(
          validFiles,
          mimeTypes: validMimes,
          subject: subject,
          text: text,
        );
      }
      return shareFiles(
        [zipFile],
        mimeTypes: const ['application/zip'],
        subject: zipFile.path
            .split(Platform.pathSeparator)
            .last
            .split('/')
            .last,
        text: text,
      );
    }
    return shareFiles(
      validFiles,
      mimeTypes: validMimes,
      subject: subject,
      text: text,
    );
  }

  /// 分享已保存的文件（优先查沙盒缓存与直接路径，若遇外部只读 URI 则先尝试原生复制再触发回调重新准备后分享）
  static Future<bool> shareSavedOrPrepare({
    required String? savedPath,
    required String fileName,
    String? mimeType,
    String? subject,
    String? text,
    Future<File?> Function()? onPrepareShareFile,
  }) async {
    File? target = await recoverShareFileFromSavedPath(
      savedPath: savedPath,
      fileName: fileName,
    );
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
