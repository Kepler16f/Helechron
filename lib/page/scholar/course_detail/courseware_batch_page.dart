import 'dart:io';

import 'package:celechron/design/app_notification.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/file_download_share_helper.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

enum _CoursewareDownloadStatus { idle, downloading, done, error }

class _ManagedCoursewareEntry {
  final CoursewareItem item;
  final String key;
  final int originalIndex;
  String? localFilePath;
  String? customFileName;
  _CoursewareDownloadStatus status = _CoursewareDownloadStatus.idle;
  String? errorMessage;

  _ManagedCoursewareEntry({
    required this.item,
    required this.key,
    required this.originalIndex,
  });
}

/// 学在浙大 / 智云课程课件批量管理与多选下载页面
///
/// 页面结构与交互同 [ZhiyunResourceBatchPage] 保持完全一致：
/// - 顶部返回/标题/刷新栏 + 课程概览与全选/选未下载/反选/正倒序工具栏
/// - 多选列表卡片：单选勾选、章节/大小/来源/已下载标签、单条下载与分享胶囊按钮
/// - 底部固定操作栏：自定义保存目录、批量下载进度与停止控制、「仅下载 / 分享」双操作按钮
class CoursewareBatchPage extends StatefulWidget {
  final Course course;
  final String? semesterName;
  final String? preferredHalfTag;

  /// 测试用自定义加载器；未传入时默认拉取学在浙大与智云课堂课件。
  final Future<List<CoursewareItem>> Function()? itemsLoader;

  const CoursewareBatchPage({
    super.key,
    required this.course,
    this.semesterName,
    this.preferredHalfTag,
    this.itemsLoader,
  });

  @override
  State<CoursewareBatchPage> createState() => _CoursewareBatchPageState();
}

class _CoursewareBatchPageState extends State<CoursewareBatchPage> {
  bool _loading = true;
  String? _fatalError;

  final List<_ManagedCoursewareEntry> _entries = [];
  final Set<String> _selectedKeys = {};
  bool _ascending = true;

  String _saveDir = '';
  bool _isCustomSaveDir = false;

  bool _isBatchProcessing = false;
  bool _cancelRequested = false;
  int _batchCompleted = 0;
  int _batchTotal = 0;
  String _batchCurrentLabel = '';

  int _loadGeneration = 0;

  static String _itemKey(CoursewareItem item) =>
      '${item.source}_${item.uploadId}_${item.referenceId}_${item.name}';

  static String _recordKey(String key) => 'courseware|$key';

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    final gen = ++_loadGeneration;
    await _initSaveDir();
    if (!mounted || gen != _loadGeneration) return;
    await _fetchCoursewareList(gen: gen);
  }

  Future<void> _initSaveDir() async {
    if (_isCustomSaveDir && _saveDir.isNotEmpty) return;
    var dir = '';
    if (Get.isRegistered<Option>(tag: 'option')) {
      dir = Get.find<Option>(tag: 'option').downloadPath.value.trim();
    }
    if (dir.isEmpty && widget.itemsLoader == null) {
      try {
        final doc = await getApplicationDocumentsDirectory().timeout(
          const Duration(seconds: 2),
        );
        dir = '${doc.path}/courseware';
      } catch (_) {
        dir = '';
      }
    }
    if (mounted) {
      setState(() {
        _saveDir = dir;
      });
    }
  }

  Future<String?> _findLocalFile(_ManagedCoursewareEntry entry) async {
    if (_saveDir.isNotEmpty &&
        !_saveDir.startsWith('content://') &&
        !_saveDir.startsWith('file://')) {
      final safeName = entry.item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('$_saveDir/$safeName');
      try {
        if (await file.exists() && await file.length() > 0) {
          return file.path;
        }
      } catch (_) {}
    }
    if (widget.itemsLoader != null && _saveDir.isEmpty) {
      return null;
    }
    try {
      final rec = await FileDownloadShareHelper.getDownloadRecord(
        _recordKey(entry.key),
      );
      if (rec != null) {
        entry.customFileName = rec.fileName;
        return rec.savedPath;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _refreshLocalStatuses() async {
    for (final entry in _entries) {
      entry.localFilePath = await _findLocalFile(entry);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _sortEntriesInPlace() {
    _entries.sort((a, b) {
      return _ascending
          ? a.originalIndex.compareTo(b.originalIndex)
          : b.originalIndex.compareTo(a.originalIndex);
    });
  }

  Future<void> _fetchCoursewareList({required int gen}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _fatalError = null;
        _entries.clear();
        _selectedKeys.clear();
      });
    }

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final list = <CoursewareItem>[];
      if (widget.itemsLoader != null) {
        list.addAll(await widget.itemsLoader!());
      } else {
        final tronItems = await Courses.fetchCoursewareList(
          client,
          courseName: widget.course.name,
          courseCode: widget.course.id,
        );
        list.addAll(tronItems);

        final zhiyunCid = ZhiyunService.getKnownCourseId(
          widget.course.name,
          courseCode: widget.course.id,
          teacher: widget.course.teacher,
          course: widget.course,
          semesterName: widget.semesterName,
          preferredHalfTag: widget.preferredHalfTag,
        );
        if (zhiyunCid != null && zhiyunCid.isNotEmpty) {
          final zyFiles = await ZhiyunService.fetchZhiyunCourseware(zhiyunCid);
          for (final f in zyFiles) {
            list.add(
              CoursewareItem(
                name: f['name'] ?? '智云课件',
                sectionTitle: f['sectionTitle'] ?? '智云课堂',
                sizeBytes: 0,
                directUrl: f['url'],
                source: '智云课堂',
              ),
            );
          }
        }
      }

      if (!mounted || gen != _loadGeneration) return;

      final built = <_ManagedCoursewareEntry>[];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        final entry = _ManagedCoursewareEntry(
          item: item,
          key: _itemKey(item),
          originalIndex: i,
        );
        entry.localFilePath = await _findLocalFile(entry);
        built.add(entry);
      }

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(built);
        _sortEntriesInPlace();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loading = false;
        _fatalError = '获取课件失败：$e';
      });
    } finally {
      client.close(force: true);
    }
  }

  void _toggleSelection(String key) {
    if (_isBatchProcessing) return;
    setState(() {
      if (!_selectedKeys.remove(key)) {
        _selectedKeys.add(key);
      }
    });
  }

  void _toggleSelectAll() {
    if (_isBatchProcessing || _entries.isEmpty) return;
    setState(() {
      if (_selectedKeys.length == _entries.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(_entries.map((e) => e.key));
      }
    });
  }

  void _selectUndownloadedOrInvert() {
    if (_isBatchProcessing || _entries.isEmpty) return;
    final hasDownloaded = _entries.any((e) => e.localFilePath != null);
    final undownloaded = _entries
        .where((e) => e.localFilePath == null)
        .map((e) => e.key);
    setState(() {
      if (hasDownloaded && undownloaded.isNotEmpty) {
        _selectedKeys
          ..clear()
          ..addAll(undownloaded);
      } else {
        final next = <String>{};
        for (final entry in _entries) {
          if (!_selectedKeys.contains(entry.key)) {
            next.add(entry.key);
          }
        }
        _selectedKeys
          ..clear()
          ..addAll(next);
      }
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _ascending = !_ascending;
      _sortEntriesInPlace();
    });
  }

  Future<void> _pickSaveDirectory() async {
    if (_isBatchProcessing) return;
    final picked = await OhosNativeService.instance.pickDirectory();
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _saveDir = picked;
      _isCustomSaveDir = true;
    });
    await _refreshLocalStatuses();
    AppNotification.success('目录已更新', '保存路径：$picked');
  }

  Future<SavedShareFileResult?> _downloadSingleEntry(
    _ManagedCoursewareEntry entry, {
    required String targetDir,
    String? customFileName,
    bool showToast = true,
  }) async {
    if (!mounted) return null;
    setState(() {
      entry.status = _CoursewareDownloadStatus.downloading;
      entry.errorMessage = null;
    });

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      var effectiveDir = targetDir;
      if (effectiveDir.isEmpty) {
        await _initSaveDir();
        effectiveDir = _saveDir;
      }
      final result =
          await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
            client,
            item: entry.item,
            saveDir: effectiveDir,
            customFileName: customFileName ?? entry.item.name,
          );
      if (!mounted) return result;

      if (result.isSuccess) {
        await FileDownloadShareHelper.saveDownloadRecord(
          _recordKey(entry.key),
          savedPath: result.savedPath!,
          fileName: result.fileName,
          mimeType: result.mimeType,
        );
        setState(() {
          entry.status = _CoursewareDownloadStatus.done;
          entry.localFilePath = result.savedPath;
          entry.customFileName = result.fileName;
        });
        if (showToast) {
          AppNotification.success(
            '下载完成',
            '${result.fileName}\n已保存：${FileDownloadShareHelper.formatDirShort(effectiveDir)}',
          );
        }
        return result;
      } else {
        setState(() {
          entry.status = _CoursewareDownloadStatus.error;
          entry.errorMessage = '未能获取下载文件流';
        });
        if (showToast) {
          AppNotification.error(
            '下载失败',
            '未能获取「${entry.item.name}」的下载文件流，请确认已登录学在浙大',
          );
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          entry.status = _CoursewareDownloadStatus.error;
          entry.errorMessage = '$e';
        });
      }
      if (showToast) {
        AppNotification.error('下载失败', '「${entry.item.name}」：$e');
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File?> _resolveExistingShareFile(_ManagedCoursewareEntry entry) async {
    final fileName = entry.customFileName ?? entry.item.name;
    final cached = await FileDownloadShareHelper.findShareCacheFile(fileName);
    if (cached != null) return cached;
    final path = entry.localFilePath;
    if (path != null &&
        path.isNotEmpty &&
        !path.startsWith('content://') &&
        !path.startsWith('file://')) {
      final f = File(path);
      if (await f.exists() && await f.length() > 0) {
        return FileDownloadShareHelper.prepareShareCacheFile(
          fileName,
          sourceFile: f,
        );
      }
    }
    return null;
  }

  Future<void> _handleShareAlreadyDownloaded(
    _ManagedCoursewareEntry entry,
  ) async {
    final effectiveName = entry.customFileName ?? entry.item.name;
    await FileDownloadShareHelper.shareSavedOrPrepare(
      savedPath: entry.localFilePath,
      fileName: effectiveName,
      mimeType: FileDownloadShareHelper.inferMimeType(effectiveName),
      subject: effectiveName,
      onPrepareShareFile: () async {
        final client = HttpClient();
        applyZjuNetworkDefense(client);
        try {
          final tempDir = await getTemporaryDirectory();
          final dlDir = Directory('${tempDir.path}/celechron_share_dl');
          if (!await dlDir.exists()) {
            await dlDir.create(recursive: true);
          }
          final result =
              await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
                client,
                item: entry.item,
                saveDir: dlDir.path,
                customFileName: effectiveName,
              );
          return result.shareFile;
        } finally {
          client.close(force: true);
        }
      },
    );
  }

  Future<void> _handleSingleDownloadOrShare(
    _ManagedCoursewareEntry entry, {
    required bool share,
  }) async {
    if (_isBatchProcessing ||
        entry.status == _CoursewareDownloadStatus.downloading) {
      return;
    }
    if (share && entry.localFilePath != null) {
      await _handleShareAlreadyDownloaded(entry);
      return;
    }
    if (share) {
      final rec = await FileDownloadShareHelper.getDownloadRecord(
        _recordKey(entry.key),
      );
      if (rec != null) {
        entry.localFilePath = rec.savedPath;
        entry.customFileName = rec.fileName;
        await _handleShareAlreadyDownloaded(entry);
        return;
      }
    }

    if (_saveDir.isEmpty) {
      await _initSaveDir();
    }
    if (!mounted) return;
    final target = await FileDownloadShareHelper.chooseSaveTarget(
      context,
      defaultFileName: entry.customFileName ?? entry.item.name,
      currentDir: _saveDir,
      title: share ? '下载并分享课件' : '下载课件',
      confirmHint: share ? null : '仅下载保存，不会触发分享：',
    );
    if (target == null || !mounted) return;
    final pickedDir = target.directory;
    if (pickedDir != _saveDir) {
      setState(() {
        _saveDir = pickedDir;
        _isCustomSaveDir = true;
      });
    }

    final result = await _downloadSingleEntry(
      entry,
      targetDir: pickedDir,
      customFileName: target.fileName,
      showToast: !share,
    );
    if (!mounted || result == null || !result.isSuccess) return;

    if (share) {
      File? shareTarget = result.shareFile;
      shareTarget ??= await _resolveExistingShareFile(entry);
      if (shareTarget != null) {
        await FileDownloadShareHelper.shareFiles(
          [shareTarget],
          mimeTypes: [result.mimeType],
          subject: result.fileName,
        );
      } else {
        AppNotification.info('分享提示', '文件已保存，暂未能生成系统分享副本');
      }
    }
  }

  String _prefixedFileName(String originalName, String prefix) {
    final cleanPrefix = FileDownloadShareHelper.sanitizeFileName(prefix);
    final cleanName = FileDownloadShareHelper.sanitizeFileName(originalName);
    if (cleanPrefix.isEmpty || cleanName.startsWith(cleanPrefix)) {
      return cleanName;
    }
    return '${cleanPrefix}_$cleanName';
  }

  Future<void> _downloadSelectedEntries({required bool shareAfter}) async {
    if (_isBatchProcessing || _selectedKeys.isEmpty) return;

    final targets = _entries
        .where((e) => _selectedKeys.contains(e.key))
        .toList();
    if (targets.isEmpty) return;

    final shareFiles = <File>[];
    final shareMimes = <String>[];
    final pendingDownload = <_ManagedCoursewareEntry>[];

    if (shareAfter) {
      for (final entry in targets) {
        final existing = await _resolveExistingShareFile(entry);
        if (existing != null) {
          final fileName = entry.customFileName ?? entry.item.name;
          shareFiles.add(existing);
          shareMimes.add(FileDownloadShareHelper.inferMimeType(fileName));
        } else {
          pendingDownload.add(entry);
        }
      }
      if (pendingDownload.isEmpty) {
        await FileDownloadShareHelper.shareFiles(
          shareFiles,
          mimeTypes: shareMimes,
          subject: '${widget.course.name}_课程课件',
        );
        return;
      }
    } else {
      pendingDownload.addAll(targets);
    }

    if (_saveDir.isEmpty) {
      await _initSaveDir();
    }
    if (!mounted) return;
    final isSingleTarget = pendingDownload.length == 1;
    final saveChoice = await FileDownloadShareHelper.chooseSaveTarget(
      context,
      defaultFileName: isSingleTarget
          ? (pendingDownload.first.customFileName ??
                pendingDownload.first.item.name)
          : '',
      currentDir: _saveDir,
      title: isSingleTarget
          ? (shareAfter ? '下载并分享课件' : '下载课件')
          : (shareAfter
                ? '下载并分享（${pendingDownload.length} 个课件）'
                : '批量下载（${pendingDownload.length} 个课件）'),
      description: isSingleTarget
          ? null
          : '待下载 ${pendingDownload.length} 个课件附件，留空保留原文件名，或输入统一前缀',
      fileNamePlaceholder: isSingleTarget ? '请输入文件名' : '留空保留原文件名（可选前缀）',
      preserveExtension: isSingleTarget,
      allowEmptyFileName: !isSingleTarget,
      confirmHint: shareAfter ? null : '仅下载保存，不会触发分享：',
    );
    if (saveChoice == null || !mounted) return;
    final targetDir = saveChoice.directory;
    if (targetDir != _saveDir) {
      setState(() {
        _saveDir = targetDir;
        _isCustomSaveDir = true;
      });
    }

    setState(() {
      _isBatchProcessing = true;
      _cancelRequested = false;
      _batchCompleted = 0;
      _batchTotal = pendingDownload.length;
      _batchCurrentLabel = pendingDownload.first.item.name;
    });

    var successCount = 0;
    var failedCount = 0;

    try {
      for (final entry in pendingDownload) {
        if (_cancelRequested || !mounted) break;
        setState(() {
          _batchCurrentLabel = entry.item.name;
        });
        final customName = isSingleTarget
            ? saveChoice.fileName
            : (saveChoice.fileName.trim().isEmpty
                  ? entry.item.name
                  : _prefixedFileName(entry.item.name, saveChoice.fileName));
        final result = await _downloadSingleEntry(
          entry,
          targetDir: targetDir,
          customFileName: customName,
          showToast: false,
        );
        if (result != null && result.isSuccess) {
          successCount++;
          File? shareTarget = result.shareFile;
          if (shareAfter && shareTarget == null) {
            shareTarget = await _resolveExistingShareFile(entry);
          }
          if (shareTarget != null) {
            shareFiles.add(shareTarget);
            shareMimes.add(result.mimeType);
          }
          if (mounted) {
            setState(() {
              _selectedKeys.remove(entry.key);
            });
          }
        } else if (!_cancelRequested) {
          failedCount++;
        }
        if (mounted) {
          setState(() {
            _batchCompleted++;
          });
        }
      }

      if (!mounted) return;
      if (_cancelRequested) {
        AppNotification.info('批量下载已停止', '已完成 $successCount 个，其余任务已取消');
      } else if (!shareAfter) {
        if (failedCount == 0) {
          AppNotification.success('批量下载完成', '成功保存 $successCount 个课件附件');
        } else {
          AppNotification.info(
            '批量下载结束',
            '成功 $successCount 个，失败 $failedCount 个',
          );
        }
      } else if (failedCount > 0 && shareFiles.isEmpty) {
        AppNotification.error('下载失败', '所选课件下载失败（$failedCount 个），未能发起分享');
      }

      if (shareAfter) {
        if (shareFiles.isNotEmpty) {
          await FileDownloadShareHelper.shareFiles(
            shareFiles,
            mimeTypes: shareMimes,
            subject: '${widget.course.name}_课程课件',
          );
        } else if (!_cancelRequested && failedCount == 0) {
          AppNotification.info('分享提示', '课件已保存，但未能准备系统分享副本，请点击单条「分享」重试');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBatchProcessing = false;
          _cancelRequested = false;
        });
      }
    }
  }

  String _formatSaveDirShort() {
    if (_saveDir.isEmpty) return '默认课件目录';
    if (!_isCustomSaveDir && _saveDir.endsWith('/courseware')) {
      return '默认课件目录 (courseware)';
    }
    if (_saveDir.length > 34) {
      return '...${_saveDir.substring(_saveDir.length - 31)}';
    }
    return _saveDir;
  }

  String _buildSummaryText() {
    if (_loading) {
      return '正在同步学在浙大与智云课堂课件...';
    }
    if (_entries.isEmpty) {
      return '当前暂无公开课件附件';
    }
    final downloadedCount = _entries
        .where((e) => e.localFilePath != null)
        .length;
    if (downloadedCount > 0) {
      return '当前共 ${_entries.length} 个课件附件 · 已下载 $downloadedCount 个';
    }
    return '当前可下载 ${_entries.length} 个课件附件';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final accent = colors.primary;
    final allSelected =
        _entries.isNotEmpty && _selectedKeys.length == _entries.length;
    final partialSelected =
        _selectedKeys.isNotEmpty && _selectedKeys.length < _entries.length;
    final hasDownloaded = _entries.any((e) => e.localFilePath != null);
    final hasUndownloaded = _entries.any((e) => e.localFilePath == null);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部 Ael 标题栏（与 ZhiyunResourceBatchPage 一致）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  AelCircleIconButton(
                    icon: AelIcons.back,
                    size: 36,
                    iconSize: 18,
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '学在浙大课件下载',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_loading)
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: CupertinoActivityIndicator(radius: 9),
                      ),
                    )
                  else
                    AelCircleIconButton(
                      icon: AelIcons.refresh,
                      size: 36,
                      iconSize: 17,
                      tooltip: '刷新',
                      onPressed: _isBatchProcessing ? null : _initAndLoad,
                    ),
                ],
              ),
            ),

            // 顶部课程概览与多选操作工具栏
            AelConstrainedWidth(
              maxWidth: AelBreakpointSpec.maxDetailWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: AelSectionCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AelIconBadge(
                            icon: AelIcons.folder,
                            size: 34,
                            iconSize: 17,
                            style: AelIconBadgeStyle.cookie,
                            backgroundColor: accent,
                            iconColor: colors.onPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.course.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _buildSummaryText(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_entries.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(height: 0.5, color: colors.divider),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _isBatchProcessing
                                  ? null
                                  : _toggleSelectAll,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    allSelected
                                        ? AelIcons.success
                                        : partialSelected
                                        ? LucideIcons.circleMinus
                                        : LucideIcons.circle,
                                    size: 18,
                                    color: (allSelected || partialSelected)
                                        ? colors.primary
                                        : colors.textTertiary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    allSelected ? '取消全选' : '全选',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AelChip(
                              label: (hasDownloaded && hasUndownloaded)
                                  ? '选未下载'
                                  : '反选',
                              tone: AelChipTone.neutral,
                              onTap: _isBatchProcessing
                                  ? null
                                  : _selectUndownloadedOrInvert,
                            ),
                            const SizedBox(width: 6),
                            AelChip(
                              label: _ascending ? '正序' : '倒序',
                              leadingIcon: LucideIcons.arrowUpDown,
                              tone: AelChipTone.neutral,
                              onTap: _toggleSortOrder,
                            ),
                            const Spacer(),
                            Text(
                              '已选 ${_selectedKeys.length}/${_entries.length}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedKeys.isNotEmpty
                                    ? colors.primary
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 主列表区域
            Expanded(child: _buildBody(context, colors)),

            // 底部固定操作栏
            _buildBottomBar(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AelColorTokens colors) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 13),
            const SizedBox(height: 12),
            Text(
              '正在同步学在浙大与智云课堂课件...',
              style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_fatalError != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AelEmptyState(
            icon: AelIcons.warning,
            title: '加载失败',
            subtitle: _fatalError!,
            actionLabel: '重试',
            onAction: _initAndLoad,
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AelEmptyState(
            icon: AelIcons.folder,
            title: '暂无公开课件附件',
            subtitle: '暂未在学在浙大或智云课堂检索到该课程的公开课件附件，可稍后刷新重试。',
            actionLabel: '重新获取',
            onAction: _initAndLoad,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final entry = _entries[idx];
        final item = entry.item;
        final isSelected = _selectedKeys.contains(entry.key);
        final isBusy = entry.status == _CoursewareDownloadStatus.downloading;
        final isDownloaded = entry.localFilePath != null;

        return AelConstrainedWidth(
          maxWidth: AelBreakpointSpec.maxDetailWidth,
          child: AelSectionCard(
            onTap: () => _toggleSelection(entry.key),
            cornerRadius: AelRadius.tile,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            backgroundColor: isSelected
                ? colors.primaryContainer.withValues(alpha: 0.35)
                : colors.cardBg,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected ? AelIcons.success : LucideIcons.circle,
                    size: 21,
                    color: isSelected ? colors.primary : colors.textTertiary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (item.sectionTitle.isNotEmpty)
                            Text(
                              item.sectionTitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          if (item.formattedSize.isNotEmpty)
                            _buildTag(item.formattedSize, colors.primary),
                          if (item.source.isNotEmpty)
                            _buildTag(
                              item.source,
                              item.source == '智云课堂'
                                  ? colors.info
                                  : colors.textSecondary,
                            ),
                          if (isBusy)
                            _buildTag('下载中...', colors.primary)
                          else if (entry.status ==
                              _CoursewareDownloadStatus.error)
                            _buildTag('下载失败', colors.error)
                          else if (isDownloaded)
                            _buildTag('已下载', colors.success),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: CupertinoActivityIndicator(radius: 8),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _actionPill(
                        icon: isDownloaded ? AelIcons.check : AelIcons.download,
                        label: isDownloaded ? '已下载' : '下载',
                        bg: isDownloaded
                            ? colors.successContainer
                            : colors.primaryContainer,
                        fg: isDownloaded
                            ? colors.onSuccessContainer
                            : colors.onPrimaryContainer,
                        onTap: _isBatchProcessing
                            ? null
                            : () => _handleSingleDownloadOrShare(
                                entry,
                                share: false,
                              ),
                      ),
                      const SizedBox(height: 5),
                      _actionPill(
                        icon: AelIcons.share,
                        label: '分享',
                        bg: colors.tonalTileBg,
                        fg: colors.textPrimary,
                        onTap: _isBatchProcessing
                            ? null
                            : () => _handleSingleDownloadOrShare(
                                entry,
                                share: true,
                              ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, AelColorTokens colors) {
    final selectedCount = _selectedKeys.length;
    final canDownload = !_isBatchProcessing && !_loading && selectedCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: AelConstrainedWidth(
          maxWidth: AelBreakpointSpec.maxDetailWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      AelIcons.folder,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '保存至：${_formatSaveDirShort()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    AelChip(
                      label: '更改目录',
                      tone: AelChipTone.primary,
                      onTap: _isBatchProcessing ? null : _pickSaveDirectory,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isBatchProcessing) ...[
                  Row(
                    children: [
                      const CupertinoActivityIndicator(radius: 8),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '正在处理 $_batchCompleted/$_batchTotal：$_batchCurrentLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: SizedBox(
                                height: 4,
                                child: Stack(
                                  children: [
                                    Container(color: colors.tonalTileBg),
                                    FractionallySizedBox(
                                      widthFactor: _batchTotal > 0
                                          ? (_batchCompleted / _batchTotal)
                                                .clamp(0, 1)
                                          : 0,
                                      child: Container(color: colors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AelButton(
                        variant: AelButtonVariant.destructive,
                        label: '停止',
                        onPressed: () {
                          setState(() {
                            _cancelRequested = true;
                          });
                        },
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: AelButton(
                          variant: AelButtonVariant.tonal,
                          icon: AelIcons.download,
                          label: selectedCount == 0
                              ? '仅下载'
                              : '仅下载 ($selectedCount)',
                          onPressed: canDownload
                              ? () =>
                                    _downloadSelectedEntries(shareAfter: false)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AelButton(
                          variant: AelButtonVariant.primary,
                          icon: AelIcons.share,
                          label: selectedCount == 0
                              ? '分享'
                              : '分享 ($selectedCount)',
                          onPressed: canDownload
                              ? () => _downloadSelectedEntries(shareAfter: true)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
