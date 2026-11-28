import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:celechron/design/app_notification.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
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

enum ZhiyunResourceBatchMode { subtitles, pptSlides }

enum _LessonDownloadStatus { idle, downloading, done, error }

class _GeneratedLessonResource {
  final String subId;
  final String title;
  final DateTime? lessonDate;
  final List<ZhiyunTranscriptSegment>? transcript;
  final List<ZhiyunPptSlide>? slides;
  final int charCount;
  String? localFilePath;
  String? customFileName;
  _LessonDownloadStatus status = _LessonDownloadStatus.idle;
  String? progressText;
  String? errorMessage;

  _GeneratedLessonResource({
    required this.subId,
    required this.title,
    required this.lessonDate,
    this.transcript,
    this.slides,
    this.charCount = 0,
  });

  int get itemCount => transcript?.length ?? slides?.length ?? 0;

  String get dateLabel {
    final dt = lessonDate;
    if (dt == null) return '';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dt.hour == 0 && dt.minute == 0) {
      return '$y-$m-$d';
    }
    return '$y-$m-$d $hh:$mm';
  }

  String get dateCompact {
    final dt = lessonDate;
    if (dt == null) return subId;
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String get charCountLabel {
    if (charCount >= 10000) {
      return '约 ${(charCount / 10000).toStringAsFixed(1)} 万字';
    }
    return '$charCount 字';
  }
}

/// 智云课堂语音字幕 / 切片课件批量管理与多选下载页面
///
/// 仅展示当前**实际已生成**字幕或 PPT 切片的课节，支持：
/// - 单选 / 多选 / 全选 / 选未下载 / 反选 / 正倒序切换
/// - 单个下载 / 勾选批量下载 / 进度实时展示与中途停止
/// - 自定义保存目录与本地已下载状态识别（一键打开）
class ZhiyunResourceBatchPage extends StatefulWidget {
  final Course course;
  final String? initialCourseId;
  final String? semesterName;
  final String? preferredHalfTag;
  final ZhiyunResourceBatchMode mode;

  const ZhiyunResourceBatchPage({
    super.key,
    required this.course,
    this.initialCourseId,
    this.semesterName,
    this.preferredHalfTag,
    required this.mode,
  });

  @override
  State<ZhiyunResourceBatchPage> createState() =>
      _ZhiyunResourceBatchPageState();
}

class _ZhiyunResourceBatchPageState extends State<ZhiyunResourceBatchPage> {
  String? _resolvedCourseId;
  bool _loadingCatalogue = true;
  bool _probing = false;
  int _probedCount = 0;
  int _totalCandidates = 0;
  int _probeErrorCount = 0;
  String? _fatalError;

  final List<_GeneratedLessonResource> _lessons = [];
  final Set<String> _selectedSubIds = {};
  bool _ascending = true;

  String _saveDir = '';
  bool _isCustomSaveDir = false;

  bool _isBatchProcessing = false;
  bool _cancelRequested = false;
  int _batchCompleted = 0;
  int _batchTotal = 0;
  String _batchCurrentLabel = '';

  int _loadGeneration = 0;

  bool get _isSubtitleMode => widget.mode == ZhiyunResourceBatchMode.subtitles;

  Color _accentColor(AelColorTokens colors) =>
      _isSubtitleMode ? colors.primary : colors.info;

  String _recordKey(_GeneratedLessonResource lesson) =>
      'batch|${_resolvedCourseId ?? widget.course.name}|${_isSubtitleMode ? 'txt' : 'zip'}|${lesson.subId}';

  @override
  void initState() {
    super.initState();
    _resolvedCourseId = widget.initialCourseId?.trim();
    _initAndLoad(forceRefresh: false);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _initAndLoad({required bool forceRefresh}) async {
    final gen = ++_loadGeneration;
    await _initSaveDir();
    if (!mounted || gen != _loadGeneration) return;
    await _loadGeneratedLessons(forceRefresh: forceRefresh, gen: gen);
  }

  Future<void> _initSaveDir() async {
    if (_isCustomSaveDir && _saveDir.isNotEmpty) return;
    var dir = '';
    if (Get.isRegistered<Option>(tag: 'option')) {
      dir = Get.find<Option>(tag: 'option').downloadPath.value.trim();
    }
    if (dir.isEmpty) {
      final doc = await getApplicationDocumentsDirectory();
      dir = '${doc.path}/courseware';
    }
    if (mounted) {
      setState(() {
        _saveDir = dir;
      });
    }
  }

  String _buildFileName(
    _GeneratedLessonResource lesson, {
    String? customPrefix,
  }) {
    final safeCourse =
        (customPrefix != null && customPrefix.trim().isNotEmpty
                ? customPrefix
                : widget.course.name)
            .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_')
            .trim();
    final safeTitle = lesson.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_')
        .trim();
    final dateTag = lesson.dateCompact;
    final includeDate = dateTag.isNotEmpty && !safeTitle.contains(dateTag);
    final baseName = includeDate
        ? '${safeCourse}_${dateTag}_$safeTitle'
        : '${safeCourse}_$safeTitle';
    return _isSubtitleMode ? '${baseName}_语音字幕.txt' : '${baseName}_切片课件.zip';
  }

  Future<String?> _findLocalFile(_GeneratedLessonResource lesson) async {
    try {
      final rec = await FileDownloadShareHelper.getDownloadRecord(
        _recordKey(lesson),
      );
      if (rec != null) {
        lesson.customFileName = rec.fileName;
        return rec.savedPath;
      }
    } catch (_) {}
    if (_saveDir.isNotEmpty &&
        !_saveDir.startsWith('content://') &&
        !_saveDir.startsWith('file://')) {
      try {
        final file = File('$_saveDir/${_buildFileName(lesson)}');
        if (await file.exists() && await file.length() > 0) {
          return file.path;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _refreshLocalStatuses() async {
    for (final lesson in _lessons) {
      lesson.localFilePath = await _findLocalFile(lesson);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _sortLessonsInPlace() {
    _lessons.sort((a, b) {
      final da = a.lessonDate;
      final db = b.lessonDate;
      if (da == null && db == null) return a.subId.compareTo(b.subId);
      if (da == null) return 1;
      if (db == null) return -1;
      return _ascending ? da.compareTo(db) : db.compareTo(da);
    });
  }

  Future<String?> _ensureCourseId() async {
    if (_resolvedCourseId != null && _resolvedCourseId!.isNotEmpty) {
      return _resolvedCourseId;
    }
    final known = ZhiyunService.getKnownCourseId(
      widget.course.name,
      courseCode: widget.course.id,
      teacher: widget.course.teacher,
      course: widget.course,
      semesterName: widget.semesterName,
      preferredHalfTag: widget.preferredHalfTag,
    );
    if (known != null && known.isNotEmpty) {
      _resolvedCourseId = known;
      return known;
    }
    final resolved = await ZhiyunService.getLessonReplay(
      course: widget.course,
      semesterName: widget.semesterName,
      preferredHalfTag: widget.preferredHalfTag,
    );
    final resolvedCid = resolved?.courseId;
    if (resolvedCid != null && resolvedCid.isNotEmpty) {
      _resolvedCourseId = resolvedCid;
      return resolvedCid;
    }
    return null;
  }

  Future<void> _loadGeneratedLessons({
    required bool forceRefresh,
    required int gen,
  }) async {
    if (mounted) {
      setState(() {
        _loadingCatalogue = true;
        _probing = false;
        _probedCount = 0;
        _totalCandidates = 0;
        _probeErrorCount = 0;
        _fatalError = null;
        _lessons.clear();
        _selectedSubIds.clear();
      });
    }

    try {
      await ZhiyunService.ensureValidToken();
      if (!mounted || gen != _loadGeneration) return;

      final cid = await _ensureCourseId();
      if (!mounted || gen != _loadGeneration) return;
      if (cid == null || cid.isEmpty) {
        setState(() {
          _loadingCatalogue = false;
          _fatalError = '未检索到该课程的智云课堂 ID，请先返回课程详情并在上方智云课堂卡片完成同步或绑定。';
        });
        return;
      }

      final rawCat = await ZhiyunService.fetchCourseCatalogue(
        cid,
        forceRefresh: forceRefresh,
      );
      if (!mounted || gen != _loadGeneration) return;

      final candidates = ZhiyunService.filterGeneratedResourceCandidates(
        rawCat,
      );

      if (candidates.isEmpty) {
        setState(() {
          _loadingCatalogue = false;
          _probing = false;
        });
        return;
      }

      setState(() {
        _loadingCatalogue = false;
        _probing = true;
        _totalCandidates = candidates.length;
        _probedCount = 0;
      });

      const poolSize = 4;
      for (var i = 0; i < candidates.length; i += poolSize) {
        if (!mounted || gen != _loadGeneration) return;
        final end = (i + poolSize < candidates.length)
            ? i + poolSize
            : candidates.length;
        final batch = candidates.sublist(i, end);

        await Future.wait(
          batch.map((item) async {
            final sid =
                (item['sub_id']?.toString() ?? item['id']?.toString() ?? '')
                    .trim();
            if (sid.isEmpty) return;
            final title =
                (item['title']?.toString() ??
                        item['sub_title']?.toString() ??
                        '课节 $sid')
                    .trim();
            final lessonDate = ZhiyunService.parseZhiyunTimestamp(
              item['start_at'] ?? item['class_begin'] ?? item['course_begin'],
            );

            _GeneratedLessonResource? verified;
            var hadError = false;

            try {
              if (_isSubtitleMode) {
                final transcript = await ZhiyunService.fetchLessonTranscript(
                  subId: sid,
                  throwOnError: true,
                );
                if (transcript.isNotEmpty) {
                  var chars = 0;
                  for (final seg in transcript) {
                    chars += seg.text.length;
                  }
                  verified = _GeneratedLessonResource(
                    subId: sid,
                    title: title,
                    lessonDate: lessonDate,
                    transcript: transcript,
                    charCount: chars,
                  );
                }
              } else {
                final slides = await ZhiyunService.fetchLessonPptSlides(
                  courseId: cid,
                  subId: sid,
                  throwOnError: true,
                );
                if (slides.isNotEmpty) {
                  verified = _GeneratedLessonResource(
                    subId: sid,
                    title: title,
                    lessonDate: lessonDate,
                    slides: slides,
                  );
                }
              }
            } catch (_) {
              hadError = true;
            }

            if (verified != null) {
              verified.localFilePath = await _findLocalFile(verified);
            }

            if (!mounted || gen != _loadGeneration) return;
            setState(() {
              _probedCount++;
              if (verified != null) {
                _lessons.add(verified);
                _sortLessonsInPlace();
              } else if (hadError) {
                _probeErrorCount++;
              }
            });
          }),
        );
      }

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _probing = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loadingCatalogue = false;
        _probing = false;
        _fatalError = '加载课节列表失败：$e';
      });
    }
  }

  void _toggleSelection(String subId) {
    if (_isBatchProcessing) return;
    setState(() {
      if (!_selectedSubIds.remove(subId)) {
        _selectedSubIds.add(subId);
      }
    });
  }

  void _toggleSelectAll() {
    if (_isBatchProcessing || _lessons.isEmpty) return;
    setState(() {
      if (_selectedSubIds.length == _lessons.length) {
        _selectedSubIds.clear();
      } else {
        _selectedSubIds
          ..clear()
          ..addAll(_lessons.map((e) => e.subId));
      }
    });
  }

  void _selectUndownloadedOrInvert() {
    if (_isBatchProcessing || _lessons.isEmpty) return;
    final hasDownloaded = _lessons.any((e) => e.localFilePath != null);
    final undownloaded = _lessons
        .where((e) => e.localFilePath == null)
        .map((e) => e.subId);
    setState(() {
      if (hasDownloaded && undownloaded.isNotEmpty) {
        _selectedSubIds
          ..clear()
          ..addAll(undownloaded);
      } else {
        final next = <String>{};
        for (final l in _lessons) {
          if (!_selectedSubIds.contains(l.subId)) {
            next.add(l.subId);
          }
        }
        _selectedSubIds
          ..clear()
          ..addAll(next);
      }
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _ascending = !_ascending;
      _sortLessonsInPlace();
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
    await FileDownloadShareHelper.persistDownloadPath(picked);
    await _refreshLocalStatuses();
    AppNotification.success('目录已更新', '保存路径：$picked');
  }

  Future<SavedShareFileResult?> _downloadSingleLesson(
    _GeneratedLessonResource lesson, {
    required String targetDir,
    String? customFileName,
    bool showToast = true,
  }) async {
    if (!mounted) return null;
    setState(() {
      lesson.status = _LessonDownloadStatus.downloading;
      lesson.progressText = _isSubtitleMode ? '正在生成...' : '准备下载...';
      lesson.errorMessage = null;
    });

    try {
      var effectiveDir = targetDir;
      if (effectiveDir.isEmpty) {
        await _initSaveDir();
        effectiveDir = _saveDir;
      }
      final result = _isSubtitleMode
          ? await _exportSubtitle(
              lesson,
              targetDir: effectiveDir,
              customFileName: customFileName,
            )
          : await _packagePpt(
              lesson,
              targetDir: effectiveDir,
              customFileName: customFileName,
            );
      if (!mounted) return result;

      if (result.isSuccess) {
        await FileDownloadShareHelper.saveDownloadRecord(
          _recordKey(lesson),
          savedPath: result.savedPath!,
          fileName: result.fileName,
          mimeType: result.mimeType,
        );
        setState(() {
          lesson.status = _LessonDownloadStatus.done;
          lesson.localFilePath = result.savedPath;
          lesson.customFileName = result.fileName;
          lesson.progressText = null;
        });
        if (showToast) {
          AppNotification.success(
            _isSubtitleMode ? '字幕已导出' : 'PPT 已打包保存',
            _isSubtitleMode
                ? '已保存「${result.fileName}」'
                : '已保存「${result.fileName}」(${lesson.itemCount} 页 PPT)',
          );
        }
        return result;
      } else {
        setState(() {
          lesson.status = _LessonDownloadStatus.error;
          lesson.progressText = null;
          lesson.errorMessage = '写入目标目录失败';
        });
        if (showToast) {
          AppNotification.error('保存失败', '未能保存「${lesson.title}」到目标目录');
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          lesson.status = _LessonDownloadStatus.error;
          lesson.progressText = null;
          lesson.errorMessage = '$e';
        });
      }
      if (showToast) {
        AppNotification.error('下载失败', '「${lesson.title}」：$e');
      }
      return null;
    }
  }

  Future<void> _openDownloadedLesson(_GeneratedLessonResource lesson) async {
    if (_isBatchProcessing ||
        lesson.status == _LessonDownloadStatus.downloading) {
      return;
    }
    final fileName = lesson.customFileName ?? _buildFileName(lesson);
    final mime = _isSubtitleMode ? 'text/plain' : 'application/zip';
    final savedPath = lesson.localFilePath;
    if (savedPath != null && savedPath.isNotEmpty) {
      final opened = await OhosNativeService.instance.openFileWithSystem(
        savedPath,
        mimeType: mime,
        title: fileName,
      );
      if (opened) return;
    }
    final fallbackFile = await _resolveExistingShareFile(lesson);
    if (fallbackFile != null) {
      final opened = await OhosNativeService.instance.openFileWithSystem(
        fallbackFile.path,
        mimeType: mime,
        title: fileName,
      );
      if (opened) return;
    }
    AppNotification.info('打开失败', '未能打开本地文件，可勾选后重新下载');
  }

  Future<File> _writeSubtitleTempFile(_GeneratedLessonResource lesson) async {
    final transcript =
        lesson.transcript ??
        await ZhiyunService.fetchLessonTranscript(subId: lesson.subId);
    if (transcript.isEmpty) {
      throw Exception('暂无已生成的语音转写字幕');
    }

    final buffer = StringBuffer();
    buffer.writeln('课程：${widget.course.name}');
    buffer.writeln('课节：${lesson.title}');
    if (lesson.dateLabel.isNotEmpty) {
      buffer.writeln('上课时间：${lesson.dateLabel}');
    }
    buffer.writeln('导出时间：${DateTime.now().toString().split('.').first}');
    buffer.writeln('=' * 40);
    buffer.writeln();
    for (final seg in transcript) {
      buffer.writeln('[${seg.timeLabel}] ${seg.text}');
    }

    final tempFile = File(
      '${Directory.systemTemp.path}/temp_sub_${DateTime.now().millisecondsSinceEpoch}_${lesson.subId}.txt',
    );
    await tempFile.writeAsString(buffer.toString(), encoding: utf8);
    return tempFile;
  }

  Future<SavedShareFileResult> _exportSubtitle(
    _GeneratedLessonResource lesson, {
    required String targetDir,
    String? customFileName,
  }) async {
    final defaultName = _buildFileName(lesson);
    final fileName =
        (customFileName != null && customFileName.trim().isNotEmpty)
        ? FileDownloadShareHelper.resolveFinalFileName(
            customFileName,
            defaultFileName: defaultName,
          )
        : defaultName;
    final tempFile = await _writeSubtitleTempFile(lesson);
    try {
      return await FileDownloadShareHelper.saveTempFileAndPrepareShare(
        tempFile: tempFile,
        targetDir: targetDir,
        fileName: fileName,
        mimeType: 'text/plain',
      );
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<File> _buildPptTempZip(_GeneratedLessonResource lesson) async {
    final cid = _resolvedCourseId ?? '';
    final slides =
        lesson.slides ??
        await ZhiyunService.fetchLessonPptSlides(
          courseId: cid,
          subId: lesson.subId,
        );
    if (slides.isEmpty) {
      throw Exception('暂无已生成的 PPT 切片');
    }

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    final tempFile = File(
      '${Directory.systemTemp.path}/temp_ppt_${DateTime.now().millisecondsSinceEpoch}_${lesson.subId}.zip',
    );

    try {
      final archive = Archive();
      var downloadedCount = 0;
      const poolSize = 4;

      for (var i = 0; i < slides.length; i += poolSize) {
        if (_cancelRequested) {
          throw Exception('已取消下载');
        }
        final end = (i + poolSize < slides.length)
            ? i + poolSize
            : slides.length;
        final chunk = <Future<void>>[];
        for (var j = i; j < end; j++) {
          final idx = j;
          final s = slides[idx];
          chunk.add(() async {
            try {
              final req = await client
                  .getUrl(Uri.parse(s.imageUrl))
                  .timeout(const Duration(seconds: 12));
              req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
              final resp = await req.close().timeout(
                const Duration(seconds: 20),
              );
              if (resp.statusCode == 200) {
                final bytes = await resp.fold<List<int>>(
                  [],
                  (a, b) => a..addAll(b),
                );
                final entryName =
                    'PPT_${(idx + 1).toString().padLeft(3, '0')}_${s.createdSec}s.jpg';
                archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
                downloadedCount++;
              } else {
                await resp.drain();
              }
            } catch (_) {}
          }());
        }
        await Future.wait(chunk);
        if (mounted) {
          setState(() {
            lesson.progressText = '$downloadedCount/${slides.length} 页';
          });
        }
      }

      if (downloadedCount == 0) {
        throw Exception('切片图片下载失败');
      }

      if (mounted) {
        setState(() {
          lesson.progressText = '正在压缩...';
        });
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData.isEmpty) {
        throw Exception('ZIP 压缩包生成失败');
      }

      await tempFile.writeAsBytes(zipData);
      return tempFile;
    } finally {
      client.close(force: true);
    }
  }

  Future<SavedShareFileResult> _packagePpt(
    _GeneratedLessonResource lesson, {
    required String targetDir,
    String? customFileName,
  }) async {
    final defaultName = _buildFileName(lesson);
    final fileName =
        (customFileName != null && customFileName.trim().isNotEmpty)
        ? FileDownloadShareHelper.resolveFinalFileName(
            customFileName,
            defaultFileName: defaultName,
          )
        : defaultName;
    final tempFile = await _buildPptTempZip(lesson);
    try {
      return await FileDownloadShareHelper.saveTempFileAndPrepareShare(
        tempFile: tempFile,
        targetDir: targetDir,
        fileName: fileName,
        mimeType: 'application/zip',
      );
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<File?> _resolveExistingShareFile(
    _GeneratedLessonResource lesson,
  ) async {
    final fileName = lesson.customFileName ?? _buildFileName(lesson);
    return FileDownloadShareHelper.recoverShareFileFromSavedPath(
      savedPath: lesson.localFilePath,
      fileName: fileName,
    );
  }

  Future<void> _downloadSelectedLessons({required bool shareAfter}) async {
    if (_isBatchProcessing || _selectedSubIds.isEmpty) return;

    final targets = _lessons
        .where((l) => _selectedSubIds.contains(l.subId))
        .toList();
    if (targets.isEmpty) return;

    final shareFiles = <File>[];
    final shareMimes = <String>[];
    final pendingDownload = <_GeneratedLessonResource>[];

    if (shareAfter) {
      for (final lesson in targets) {
        final existing = await _resolveExistingShareFile(lesson);
        if (existing != null) {
          shareFiles.add(existing);
          shareMimes.add(_isSubtitleMode ? 'text/plain' : 'application/zip');
        } else {
          pendingDownload.add(lesson);
        }
      }
      if (pendingDownload.isEmpty) {
        if (!mounted) return;
        await FileDownloadShareHelper.shareFilesWithBatchOption(
          context,
          shareFiles,
          mimeTypes: shareMimes,
          subject: shareFiles.length == 1
              ? (targets.first.customFileName ?? _buildFileName(targets.first))
              : '${widget.course.name}_${_isSubtitleMode ? "语音字幕" : "PPT课件"}',
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
                _buildFileName(pendingDownload.first))
          : FileDownloadShareHelper.sanitizeFileName(widget.course.name),
      currentDir: _saveDir,
      title: isSingleTarget
          ? (shareAfter
                ? (_isSubtitleMode ? '下载并分享语音字幕' : '下载并分享 PPT 课件')
                : (_isSubtitleMode ? '下载语音字幕' : '下载 PPT 课件'))
          : (shareAfter
                ? '下载并分享（${pendingDownload.length} 节）'
                : '批量下载（${pendingDownload.length} 节）'),
      description: isSingleTarget
          ? null
          : '待下载 ${pendingDownload.length} 节${_isSubtitleMode ? "语音字幕 (.txt)" : "切片课件 (.zip)"}，可修改统一文件名前缀',
      fileNamePlaceholder: isSingleTarget ? '请输入文件名' : '请输入统一文件名前缀',
      preserveExtension: isSingleTarget,
      confirmHint: shareAfter ? null : '仅下载保存，不会触发分享：',
    );
    if (saveChoice == null || !mounted) return;
    final targetDir = saveChoice.directory;
    if (targetDir != _saveDir) {
      setState(() {
        _saveDir = targetDir;
        _isCustomSaveDir = true;
      });
      await FileDownloadShareHelper.persistDownloadPath(targetDir);
    }

    setState(() {
      _isBatchProcessing = true;
      _cancelRequested = false;
      _batchCompleted = 0;
      _batchTotal = pendingDownload.length;
      _batchCurrentLabel = pendingDownload.first.title;
    });

    var successCount = 0;
    var failedCount = 0;
    final usedBatchNames = <String>{
      for (final f in shareFiles)
        f.path.split(Platform.pathSeparator).last.split('/').last.toLowerCase(),
    };

    try {
      for (final lesson in pendingDownload) {
        if (_cancelRequested || !mounted) break;
        setState(() {
          _batchCurrentLabel = lesson.title;
        });
        final rawCustomName = isSingleTarget
            ? saveChoice.fileName
            : _buildFileName(lesson, customPrefix: saveChoice.fileName);
        final customName = FileDownloadShareHelper.disambiguateFileName(
          rawCustomName,
          usedBatchNames,
        );
        final result = await _downloadSingleLesson(
          lesson,
          targetDir: targetDir,
          customFileName: customName,
          showToast: false,
        );
        if (result != null && result.isSuccess) {
          successCount++;
          File? shareTarget = result.shareFile;
          if (shareAfter && shareTarget == null) {
            shareTarget = await _resolveExistingShareFile(lesson);
          }
          if (shareTarget != null) {
            shareFiles.add(shareTarget);
            shareMimes.add(result.mimeType);
          }
          if (mounted) {
            setState(() {
              _selectedSubIds.remove(lesson.subId);
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
        AppNotification.info('批量下载已停止', '已完成 $successCount 节，其余任务已取消');
      } else if (!shareAfter) {
        if (failedCount == 0) {
          AppNotification.success(
            '批量下载完成',
            '成功保存 $successCount 节${_isSubtitleMode ? "语音字幕" : "切片课件"}',
          );
        } else {
          AppNotification.info(
            '批量下载结束',
            '成功 $successCount 节，失败 $failedCount 节',
          );
        }
      } else if (failedCount > 0 && shareFiles.isEmpty) {
        AppNotification.error('下载失败', '所选课节下载失败（$failedCount 节），未能发起分享');
      }

      if (shareAfter) {
        if (shareFiles.isNotEmpty) {
          await FileDownloadShareHelper.shareFilesWithBatchOption(
            context,
            shareFiles,
            mimeTypes: shareMimes,
            subject: shareFiles.length == 1
                ? shareFiles.first.path
                      .split(Platform.pathSeparator)
                      .last
                      .split('/')
                      .last
                : '${widget.course.name}_${_isSubtitleMode ? "语音字幕" : "PPT课件"}',
          );
        } else if (!_cancelRequested && failedCount == 0) {
          AppNotification.info('分享提示', '文件已保存，但未能准备系统分享副本，请勾选后重新点击分享');
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

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final accent = _accentColor(colors);
    final pageTitle = _isSubtitleMode ? '智云课堂语音字幕下载' : '智云课堂切片课件下载';
    final allSelected =
        _lessons.isNotEmpty && _selectedSubIds.length == _lessons.length;
    final partialSelected =
        _selectedSubIds.isNotEmpty && _selectedSubIds.length < _lessons.length;
    final hasDownloaded = _lessons.any((e) => e.localFilePath != null);
    final hasUndownloaded = _lessons.any((e) => e.localFilePath == null);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部 Ael 标题栏
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
                      pageTitle,
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
                  if (_loadingCatalogue || _probing)
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
                      onPressed: _isBatchProcessing
                          ? null
                          : () => _initAndLoad(forceRefresh: true),
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
                            icon: _isSubtitleMode
                                ? AelIcons.audio
                                : AelIcons.image,
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
                      if (_probing && _totalCandidates > 0) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 4,
                            child: Stack(
                              children: [
                                Container(color: colors.tonalTileBg),
                                FractionallySizedBox(
                                  widthFactor: (_probedCount / _totalCandidates)
                                      .clamp(0, 1),
                                  child: Container(color: accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_lessons.isNotEmpty) ...[
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
                              '已选 ${_selectedSubIds.length}/${_lessons.length}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedSubIds.isNotEmpty
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

  String _buildSummaryText() {
    final resourceName = _isSubtitleMode ? '语音字幕' : 'PPT 切片';
    if (_loadingCatalogue) {
      return '正在获取智云课堂课程目录...';
    }
    if (_probing) {
      return '正在检测已生成$resourceName的课节（$_probedCount/$_totalCandidates）· 已找到 ${_lessons.length} 节';
    }
    if (_lessons.isEmpty) {
      if (_probeErrorCount > 0) {
        return '检测过程遇到网络异常，请重试';
      }
      return '当前暂无已生成$resourceName的课节';
    }
    return '当前可下载 ${_lessons.length} 节已生成$resourceName';
  }

  Widget _buildBody(BuildContext context, AelColorTokens colors) {
    final resourceName = _isSubtitleMode ? '语音转写字幕' : 'PPT 切片课件';
    final accent = _accentColor(colors);

    if (_loadingCatalogue) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 13),
            const SizedBox(height: 12),
            Text(
              '正在读取课程目录并筛选已录制课节...',
              style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_fatalError != null && _lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AelEmptyState(
            icon: AelIcons.warning,
            title: '加载失败',
            subtitle: _fatalError!,
            actionLabel: '重新检测',
            onAction: () => _initAndLoad(forceRefresh: true),
          ),
        ),
      );
    }

    if (!_probing && _lessons.isEmpty) {
      final isNetErr = _probeErrorCount > 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AelEmptyState(
            icon: isNetErr ? AelIcons.wifi : AelIcons.folder,
            title: isNetErr ? '网络异常或智云登录态失效' : '暂无已生成的$resourceName',
            subtitle: isNetErr
                ? '未能完成已生成课节的在线检测，请检查网络或重新同步智云课堂后重试。'
                : '仅会展示已上课录制且智云课堂实际已生成$resourceName的课节；未开课或暂未生成内容的课节已自动隐藏。',
            actionLabel: '重新检测',
            onAction: () => _initAndLoad(forceRefresh: true),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      itemCount: _lessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final lesson = _lessons[idx];
        final isSelected = _selectedSubIds.contains(lesson.subId);
        final isBusy = lesson.status == _LessonDownloadStatus.downloading;
        final isDownloaded = lesson.localFilePath != null;

        return AelConstrainedWidth(
          maxWidth: AelBreakpointSpec.maxDetailWidth,
          child: AelSectionCard(
            onTap: () => _toggleSelection(lesson.subId),
            cornerRadius: AelRadius.tile,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            backgroundColor: isSelected
                ? colors.primaryContainer.withValues(alpha: 0.35)
                : colors.cardBg,
            child: Row(
              children: [
                // 左侧勾选框
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected ? AelIcons.success : LucideIcons.circle,
                    size: 21,
                    color: isSelected ? colors.primary : colors.textTertiary,
                  ),
                ),
                // 中间课节信息与已生成数量标签
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.title,
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
                          if (lesson.dateLabel.isNotEmpty)
                            Text(
                              lesson.dateLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          _buildTag(
                            _isSubtitleMode
                                ? '${lesson.itemCount} 条 · ${lesson.charCountLabel}'
                                : '${lesson.itemCount} 页 PPT',
                            accent,
                          ),
                          if (isBusy && lesson.progressText != null)
                            _buildTag(lesson.progressText!, colors.primary)
                          else if (lesson.status == _LessonDownloadStatus.error)
                            _buildTag('下载失败', colors.error)
                          else if (isDownloaded)
                            _buildTag('已下载', colors.success),
                        ],
                      ),
                    ],
                  ),
                ),
                // 右侧仅在下载中或已下载时显示状态/快捷打开（避免与底部全局「仅下载 / 分享」重复）
                if (isBusy) ...[
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: CupertinoActivityIndicator(radius: 8),
                  ),
                ] else if (isDownloaded) ...[
                  const SizedBox(width: 8),
                  _actionPill(
                    icon: AelIcons.externalLink,
                    label: '打开',
                    bg: colors.successContainer,
                    fg: colors.onSuccessContainer,
                    onTap: _isBatchProcessing
                        ? null
                        : () => _openDownloadedLesson(lesson),
                  ),
                ],
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
    final selectedCount = _selectedSubIds.length;
    final canDownload =
        !_isBatchProcessing && !_loadingCatalogue && selectedCount > 0;

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
                // 保存目录选择行
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
                                    _downloadSelectedLessons(shareAfter: false)
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
                              ? () => _downloadSelectedLessons(shareAfter: true)
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
