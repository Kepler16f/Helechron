import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:celechron/design/app_notification.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/file_download_share_helper.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

enum ZhiyunResourceBatchMode {
  subtitles,
  pptSlides,
}

enum _LessonDownloadStatus {
  idle,
  downloading,
  done,
  error,
}

class _GeneratedLessonResource {
  final String subId;
  final String title;
  final DateTime? lessonDate;
  final List<ZhiyunTranscriptSegment>? transcript;
  final List<ZhiyunPptSlide>? slides;
  final int charCount;
  String? localFilePath;
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
  int _filteredNotReadyCount = 0;
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

  Color get _accentColor => _isSubtitleMode
      ? CupertinoColors.systemTeal
      : CupertinoColors.systemPurple;

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

  String _buildFileName(_GeneratedLessonResource lesson) {
    final safeCourse = widget.course.name
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
    if (_saveDir.isEmpty ||
        _saveDir.startsWith('content://') ||
        _saveDir.startsWith('file://')) {
      return null;
    }
    try {
      final file = File('$_saveDir/${_buildFileName(lesson)}');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
    } catch (_) {}
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
        _filteredNotReadyCount = 0;
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
      final skippedBySchedule =
          (rawCat.length - candidates.length).clamp(0, rawCat.length);

      if (candidates.isEmpty) {
        setState(() {
          _loadingCatalogue = false;
          _probing = false;
          _filteredNotReadyCount = skippedBySchedule;
        });
        return;
      }

      setState(() {
        _loadingCatalogue = false;
        _probing = true;
        _totalCandidates = candidates.length;
        _probedCount = 0;
        _filteredNotReadyCount = skippedBySchedule;
      });

      const poolSize = 4;
      for (var i = 0; i < candidates.length; i += poolSize) {
        if (!mounted || gen != _loadGeneration) return;
        final end =
            (i + poolSize < candidates.length) ? i + poolSize : candidates.length;
        final batch = candidates.sublist(i, end);

        await Future.wait(batch.map((item) async {
          final sid =
              (item['sub_id']?.toString() ?? item['id']?.toString() ?? '')
                  .trim();
          if (sid.isEmpty) return;
          final title = (item['title']?.toString() ??
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
            } else {
              _filteredNotReadyCount++;
            }
          });
        }));
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
    final undownloaded =
        _lessons.where((e) => e.localFilePath == null).map((e) => e.subId);
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
    await _refreshLocalStatuses();
    AppNotification.success('目录已更新', '保存路径：$picked');
  }

  Future<SavedShareFileResult?> _downloadSingleLesson(
    _GeneratedLessonResource lesson, {
    required String targetDir,
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
          ? await _exportSubtitle(lesson, targetDir: effectiveDir)
          : await _packagePpt(lesson, targetDir: effectiveDir);
      if (!mounted) return result;

      if (result.isSuccess) {
        setState(() {
          lesson.status = _LessonDownloadStatus.done;
          lesson.localFilePath = result.savedPath;
          lesson.progressText = null;
        });
        if (showToast) {
          AppNotification.success(
            _isSubtitleMode ? '字幕已导出' : 'PPT 已打包保存',
            _isSubtitleMode
                ? '已保存「${lesson.title}」语音字幕'
                : '已保存「${lesson.title}」(${lesson.itemCount} 页 PPT)',
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

  Future<void> _handleSingleDownloadAndShare(
    _GeneratedLessonResource lesson,
  ) async {
    if (_isBatchProcessing ||
        lesson.status == _LessonDownloadStatus.downloading) {
      return;
    }
    if (_saveDir.isEmpty) {
      await _initSaveDir();
    }
    if (!mounted) return;
    final pickedDir = await FileDownloadShareHelper.chooseSaveDirectory(
      context,
      currentDir: _saveDir,
      title: _isSubtitleMode ? '下载并分享语音字幕' : '下载并分享 PPT 课件',
      fileLabel: _buildFileName(lesson),
    );
    if (pickedDir == null || !mounted) return;
    if (pickedDir != _saveDir) {
      setState(() {
        _saveDir = pickedDir;
        _isCustomSaveDir = true;
      });
    }

    final result = await _downloadSingleLesson(
      lesson,
      targetDir: pickedDir,
      showToast: true,
    );
    if (!mounted || result == null || !result.isSuccess) return;

    if (result.shareFile != null) {
      await FileDownloadShareHelper.shareFiles(
        [result.shareFile!],
        mimeTypes: [result.mimeType],
        subject: result.fileName,
      );
    }
  }

  Future<void> _handleShareAlreadyDownloaded(
    _GeneratedLessonResource lesson,
  ) async {
    final fileName = _buildFileName(lesson);
    await FileDownloadShareHelper.shareSavedOrPrepare(
      savedPath: lesson.localFilePath,
      fileName: fileName,
      mimeType: _isSubtitleMode ? 'text/plain' : 'application/zip',
      subject: fileName,
      onPrepareShareFile: () => _prepareShareFileOnly(lesson),
    );
  }

  Future<File?> _prepareShareFileOnly(_GeneratedLessonResource lesson) async {
    try {
      if (_isSubtitleMode) {
        final tempFile = await _writeSubtitleTempFile(lesson);
        try {
          return await FileDownloadShareHelper.prepareShareCacheFile(
            _buildFileName(lesson),
            sourceFile: tempFile,
          );
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      } else {
        final tempFile = await _buildPptTempZip(lesson);
        try {
          return await FileDownloadShareHelper.prepareShareCacheFile(
            _buildFileName(lesson),
            sourceFile: tempFile,
          );
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      }
    } catch (_) {
      return null;
    }
  }

  Future<File> _writeSubtitleTempFile(_GeneratedLessonResource lesson) async {
    final transcript = lesson.transcript ??
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
  }) async {
    final fileName = _buildFileName(lesson);
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
    final slides = lesson.slides ??
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
        final end =
            (i + poolSize < slides.length) ? i + poolSize : slides.length;
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
              final resp =
                  await req.close().timeout(const Duration(seconds: 20));
              if (resp.statusCode == 200) {
                final bytes =
                    await resp.fold<List<int>>([], (a, b) => a..addAll(b));
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
  }) async {
    final fileName = _buildFileName(lesson);
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

  Future<void> _downloadSelectedLessons() async {
    if (_isBatchProcessing || _selectedSubIds.isEmpty) return;

    final targets =
        _lessons.where((l) => _selectedSubIds.contains(l.subId)).toList();
    if (targets.isEmpty) return;

    if (_saveDir.isEmpty) {
      await _initSaveDir();
    }
    if (!mounted) return;
    final targetDir = await FileDownloadShareHelper.chooseSaveDirectory(
      context,
      currentDir: _saveDir,
      title: '批量下载并分享（${targets.length} 节）',
      fileLabel:
          '${targets.length} 节${_isSubtitleMode ? "语音字幕 (.txt)" : "切片课件 (.zip)"}',
    );
    if (targetDir == null || !mounted) return;
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
      _batchTotal = targets.length;
      _batchCurrentLabel = targets.first.title;
    });

    var successCount = 0;
    var failedCount = 0;
    final shareFiles = <File>[];
    final shareMimes = <String>[];

    try {
      for (final lesson in targets) {
        if (_cancelRequested || !mounted) break;
        setState(() {
          _batchCurrentLabel = lesson.title;
        });
        final result = await _downloadSingleLesson(
          lesson,
          targetDir: targetDir,
          showToast: false,
        );
        if (result != null && result.isSuccess) {
          successCount++;
          if (result.shareFile != null) {
            shareFiles.add(result.shareFile!);
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
        AppNotification.info(
          '批量下载已停止',
          '已完成 $successCount 节，其余任务已取消',
        );
      } else if (failedCount == 0) {
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

      if (shareFiles.isNotEmpty) {
        await FileDownloadShareHelper.shareFiles(
          shareFiles,
          mimeTypes: shareMimes,
          subject:
              '${widget.course.name}_${_isSubtitleMode ? "语音字幕" : "PPT课件"}',
        );
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
    final pageTitle = _isSubtitleMode ? '智云课堂语音字幕下载' : '智云课堂切片课件下载';
    final bgColor =
        CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final cardColor =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);
    final allSelected =
        _lessons.isNotEmpty && _selectedSubIds.length == _lessons.length;
    final partialSelected =
        _selectedSubIds.isNotEmpty && _selectedSubIds.length < _lessons.length;
    final hasDownloaded = _lessons.any((e) => e.localFilePath != null);
    final hasUndownloaded = _lessons.any((e) => e.localFilePath == null);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          pageTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 32,
          onPressed: (_loadingCatalogue || _probing || _isBatchProcessing)
              ? null
              : () => _initAndLoad(forceRefresh: true),
          child: (_loadingCatalogue || _probing)
              ? const CupertinoActivityIndicator(radius: 9)
              : const Icon(CupertinoIcons.arrow_clockwise, size: 20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部课程概览与多选操作工具栏
            Container(
              width: double.infinity,
              color: cardColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _accentColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isSubtitleMode
                              ? CupertinoIcons.waveform_circle_fill
                              : CupertinoIcons.photo_on_rectangle,
                          size: 16,
                          color: CupertinoColors.white,
                        ),
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
                                color: labelColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _buildSummaryText(),
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryColor,
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
                            Container(
                              color: CupertinoColors.systemFill
                                  .resolveFrom(context),
                            ),
                            FractionallySizedBox(
                              widthFactor:
                                  (_probedCount / _totalCandidates).clamp(0, 1),
                              child: Container(color: _accentColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_lessons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(height: 0.5, color: separatorColor),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minSize: 30,
                          onPressed:
                              _isBatchProcessing ? null : _toggleSelectAll,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                allSelected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : partialSelected
                                        ? CupertinoIcons.minus_circle_fill
                                        : CupertinoIcons.circle,
                                size: 18,
                                color: (allSelected || partialSelected)
                                    ? CupertinoColors.activeBlue
                                        .resolveFrom(context)
                                    : CupertinoColors.tertiaryLabel
                                        .resolveFrom(context),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                allSelected ? '取消全选' : '全选',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: labelColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          minSize: 28,
                          color: CupertinoColors.tertiarySystemFill
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(7),
                          onPressed: _isBatchProcessing
                              ? null
                              : _selectUndownloadedOrInvert,
                          child: Text(
                            (hasDownloaded && hasUndownloaded) ? '选未下载' : '反选',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minSize: 28,
                          color: CupertinoColors.tertiarySystemFill
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(7),
                          onPressed: _toggleSortOrder,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_up_arrow_down,
                                size: 12,
                                color: secondaryColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _ascending ? '正序' : '倒序',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: secondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '已选 ${_selectedSubIds.length}/${_lessons.length}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _selectedSubIds.isNotEmpty
                                ? CupertinoColors.activeBlue
                                    .resolveFrom(context)
                                : secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(height: 0.5, color: separatorColor),

            // 主列表区域
            Expanded(
              child: _buildBody(
                context,
                cardColor: cardColor,
                labelColor: labelColor,
                secondaryColor: secondaryColor,
              ),
            ),

            // 底部固定操作栏
            _buildBottomBar(
              context,
              cardColor: cardColor,
              labelColor: labelColor,
              secondaryColor: secondaryColor,
              separatorColor: separatorColor,
            ),
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
    final filteredPart = _filteredNotReadyCount > 0
        ? ' · 已自动过滤 $_filteredNotReadyCount 节未生成课节'
        : '';
    return '当前可下载 ${_lessons.length} 节已生成$resourceName$filteredPart';
  }

  Widget _buildBody(
    BuildContext context, {
    required Color cardColor,
    required Color labelColor,
    required Color secondaryColor,
  }) {
    final resourceName = _isSubtitleMode ? '语音转写字幕' : 'PPT 切片课件';

    if (_loadingCatalogue) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 13),
            const SizedBox(height: 12),
            Text(
              '正在读取课程目录并筛选已录制课节...',
              style: TextStyle(fontSize: 13.5, color: secondaryColor),
            ),
          ],
        ),
      );
    }

    if (_fatalError != null && _lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 42,
                color: CupertinoColors.systemOrange.resolveFrom(context),
              ),
              const SizedBox(height: 12),
              Text(
                _fatalError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: labelColor, height: 1.45),
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                onPressed: () => _initAndLoad(forceRefresh: true),
                child: const Text('重新检测', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_probing && _lessons.isEmpty) {
      final isNetErr = _probeErrorCount > 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNetErr
                    ? CupertinoIcons.wifi_exclamationmark
                    : CupertinoIcons.tray,
                size: 44,
                color: secondaryColor,
              ),
              const SizedBox(height: 12),
              Text(
                isNetErr ? '网络异常或智云登录态失效' : '暂无已生成的$resourceName',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isNetErr
                    ? '未能完成已生成课节的在线检测，请检查网络或重新同步智云课堂后重试。'
                    : '仅会展示已上课录制且智云课堂实际已生成$resourceName的课节；未开课或暂未生成内容的课节已自动隐藏。',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: secondaryColor, height: 1.4),
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
                onPressed: () => _initAndLoad(forceRefresh: true),
                child: Text(
                  '重新检测',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: _lessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final lesson = _lessons[idx];
        final isSelected = _selectedSubIds.contains(lesson.subId);
        final isBusy = lesson.status == _LessonDownloadStatus.downloading;
        final isDownloaded = lesson.localFilePath != null;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleSelection(lesson.subId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? CupertinoColors.activeBlue.resolveFrom(context)
                    : CupertinoColors.separator
                        .resolveFrom(context)
                        .withValues(alpha: 0.35),
                width: isSelected ? 1.4 : 0.6,
              ),
            ),
            child: Row(
              children: [
                // 左侧勾选框
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 22,
                    color: isSelected
                        ? CupertinoColors.activeBlue.resolveFrom(context)
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
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
                          color: labelColor,
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
                                color: secondaryColor,
                              ),
                            ),
                          _buildTag(
                            _isSubtitleMode
                                ? '${lesson.itemCount} 条 · ${lesson.charCountLabel}'
                                : '${lesson.itemCount} 页 PPT',
                            _accentColor,
                          ),
                          if (isBusy && lesson.progressText != null)
                            _buildTag(
                              lesson.progressText!,
                              CupertinoColors.activeBlue.resolveFrom(context),
                            )
                          else if (lesson.status == _LessonDownloadStatus.error)
                            _buildTag(
                              '下载失败',
                              CupertinoColors.systemRed.resolveFrom(context),
                            )
                          else if (isDownloaded)
                            _buildTag(
                              '已下载',
                              CupertinoColors.activeGreen.resolveFrom(context),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧快捷操作（分享 / 下载并分享）
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: CupertinoActivityIndicator(radius: 8),
                  )
                else if (isDownloaded)
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minSize: 30,
                    color: CupertinoColors.activeGreen
                        .resolveFrom(context)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _isBatchProcessing
                        ? null
                        : () => _handleShareAlreadyDownloaded(lesson),
                    child: Text(
                      '分享',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeGreen.resolveFrom(context),
                      ),
                    ),
                  )
                else
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minSize: 30,
                    color: CupertinoColors.activeBlue
                        .resolveFrom(context)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _isBatchProcessing
                        ? null
                        : () => _handleSingleDownloadAndShare(lesson),
                    child: Text(
                      '下载并分享',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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

  Widget _buildBottomBar(
    BuildContext context, {
    required Color cardColor,
    required Color labelColor,
    required Color secondaryColor,
    required Color separatorColor,
  }) {
    final selectedCount = _selectedSubIds.length;
    final canDownload =
        !_isBatchProcessing && !_loadingCatalogue && selectedCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: separatorColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 保存目录选择行
              Row(
                children: [
                  Icon(
                    CupertinoIcons.folder,
                    size: 14,
                    color: secondaryColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '保存至：${_formatSaveDirShort()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondaryColor),
                    ),
                  ),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    minSize: 26,
                    onPressed: _isBatchProcessing ? null : _pickSaveDirectory,
                    child: Text(
                      '更改目录',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
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
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                children: [
                                  Container(
                                    color: CupertinoColors.systemFill
                                        .resolveFrom(context),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: _batchTotal > 0
                                        ? (_batchCompleted / _batchTotal)
                                            .clamp(0, 1)
                                        : 0,
                                    child: Container(
                                      color: CupertinoColors.activeBlue
                                          .resolveFrom(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minSize: 34,
                      color: CupertinoColors.systemRed
                          .resolveFrom(context)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () {
                        setState(() {
                          _cancelRequested = true;
                        });
                      },
                      child: Text(
                        '停止',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: canDownload
                        ? CupertinoColors.activeBlue.resolveFrom(context)
                        : CupertinoColors.tertiarySystemFill
                            .resolveFrom(context),
                    borderRadius: BorderRadius.circular(11),
                    onPressed: canDownload ? _downloadSelectedLessons : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (canDownload) ...[
                          const Icon(
                            CupertinoIcons.share,
                            size: 16,
                            color: CupertinoColors.white,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          selectedCount == 0
                              ? '请勾选需要下载并分享的课节'
                              : '下载并分享（$selectedCount 节）',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: canDownload
                                ? CupertinoColors.white
                                : secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
