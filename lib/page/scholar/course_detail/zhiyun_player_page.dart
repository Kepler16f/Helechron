import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/design/app_notification.dart';
import 'package:celechron/services/file_download_share_helper.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/zhiyun_service.dart';

class ZhiyunPlayerPage extends StatefulWidget {
  final String courseName;
  final String courseId;
  final String? initialSubId;
  final String initialTitle;
  final String livingroomUrl;
  final List<ZhiyunReplayInfo> replays;
  final bool preferLive;

  const ZhiyunPlayerPage({
    super.key,
    required this.courseName,
    required this.courseId,
    this.initialSubId,
    required this.initialTitle,
    required this.livingroomUrl,
    this.replays = const [],
    this.preferLive = false,
  });

  @override
  State<ZhiyunPlayerPage> createState() => _ZhiyunPlayerPageState();
}

class _ZhiyunPlayerPageState extends State<ZhiyunPlayerPage> {
  String? _currentSubId;
  late String _currentTitle;
  late String _currentLivingroomUrl;
  late bool _isLiveMode;

  bool _loading = true;
  List<ZhiyunStreamOption> _streams = [];
  int _selectedStreamIndex = 0;
  List<ZhiyunPptSlide> _slides = [];
  List<ZhiyunTranscriptSegment> _transcript = [];
  int _tabIndex = 0;
  String _searchKeyword = '';
  bool _autoLaunched = false;

  @override
  void initState() {
    super.initState();
    _currentSubId = widget.initialSubId;
    _currentTitle = widget.initialTitle;
    _currentLivingroomUrl = widget.livingroomUrl;
    _isLiveMode = widget.preferLive ||
        widget.initialTitle.contains('直播') ||
        widget.replays.any((r) => r.subId == _currentSubId && r.isLive);
    if ((_currentSubId == null || _currentSubId!.isEmpty) &&
        widget.replays.isNotEmpty) {
      final now = DateTime.now();
      bool isNotFuture(ZhiyunReplayInfo r) =>
          r.lessonDate == null ||
          !r.lessonDate!.isAfter(now.add(const Duration(minutes: 30)));
      bool isSameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;

      ZhiyunReplayInfo? matched;
      if (_isLiveMode) {
        matched = widget.replays.firstWhereOrNull(
              (r) => r.isLive && r.subId?.isNotEmpty == true,
            ) ??
            widget.replays.firstWhereOrNull(
              (r) =>
                  r.subId?.isNotEmpty == true &&
                  r.lessonDate != null &&
                  isSameDay(r.lessonDate!, now),
            );
      } else {
        final pastWithReplay = widget.replays
            .where((r) =>
                r.subId?.isNotEmpty == true && r.hasReplay && isNotFuture(r))
            .toList();
        if (pastWithReplay.isNotEmpty) {
          pastWithReplay.sort((a, b) => (b.lessonDate ?? DateTime(1970))
              .compareTo(a.lessonDate ?? DateTime(1970)));
          matched = pastWithReplay.first;
        } else {
          final pastAny = widget.replays
              .where((r) => r.subId?.isNotEmpty == true && isNotFuture(r))
              .toList();
          if (pastAny.isNotEmpty) {
            pastAny.sort((a, b) => (b.lessonDate ?? DateTime(1970))
                .compareTo(a.lessonDate ?? DateTime(1970)));
            matched = pastAny.first;
          }
        }
      }
      if (matched != null) {
        _currentSubId = matched.subId;
        _currentTitle = matched.lessonTitle;
        _currentLivingroomUrl = matched.livingroomUrl;
      }
    }
    _loadLessonData(autoPlayFirstTime: _isLiveMode);
  }

  Future<void> _loadLessonData({bool autoPlayFirstTime = false}) async {
    var subId = _currentSubId;
    if ((subId == null || subId.isEmpty) && widget.courseId.isNotEmpty) {
      final now = DateTime.now();
      if (_isLiveMode) {
        final activeToday = await ZhiyunService.fetchActiveSubIdForDate(
          widget.courseId,
          now,
        );
        if (activeToday != null && activeToday.isNotEmpty) {
          subId = activeToday;
          _currentSubId = activeToday;
          _currentLivingroomUrl =
              ZhiyunService.buildLivingroomUrl(widget.courseId, activeToday);
        }
      }

      if (subId == null || subId.isEmpty) {
        // 实时直播常在开课瞬间才生成 sub_id，强制刷新一次课程目录获取最新直播 sub_id
        final freshCat = await ZhiyunService.fetchCourseCatalogue(
          widget.courseId,
          forceRefresh: true,
        );
        bool isItemNotFuture(Map<String, dynamic> item) {
          final dt = ZhiyunService.parseZhiyunTimestamp(
            item['start_at'] ?? item['class_begin'] ?? item['course_begin'],
          );
          return dt == null ||
              !dt.isAfter(now.add(const Duration(minutes: 30)));
        }

        Map<String, dynamic>? picked;
        if (_isLiveMode) {
          picked = freshCat.firstWhereOrNull(
                (item) =>
                    ZhiyunService.checkIsLive(item: item) &&
                    (item['sub_id']?.toString().isNotEmpty == true ||
                        item['id']?.toString().isNotEmpty == true),
              ) ??
              ZhiyunService.findBestMatchingCatalogueItem(
                catalogue: freshCat,
                targetDate: now,
              );
        } else {
          final validPast = freshCat
              .where((item) =>
                  (item['sub_id']?.toString().isNotEmpty == true ||
                      item['id']?.toString().isNotEmpty == true) &&
                  isItemNotFuture(item))
              .toList();
          picked = validPast.firstWhereOrNull(
                (item) => ZhiyunService.checkHasReplay(item: item),
              ) ??
              validPast.firstOrNull;
        }
        final pickedSub =
            picked?['sub_id']?.toString() ?? picked?['id']?.toString();
        if (pickedSub != null && pickedSub.isNotEmpty) {
          subId = pickedSub;
          _currentSubId = pickedSub;
          _currentLivingroomUrl =
              ZhiyunService.buildLivingroomUrl(widget.courseId, pickedSub);
          if (mounted) {
            setState(() {
              _currentTitle = picked?['title']?.toString() ??
                  picked?['sub_title']?.toString() ??
                  _currentTitle;
            });
          }
        }
      }
    }

    if (subId == null || subId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      if (autoPlayFirstTime &&
          _isLiveMode &&
          !_autoLaunched &&
          _currentLivingroomUrl.isNotEmpty) {
        _autoLaunched = true;
        await _launchInAppPlayer(_currentLivingroomUrl);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    final results = await Future.wait([
      ZhiyunService.fetchLessonStreams(
        courseId: widget.courseId,
        subId: subId,
        preferLive: _isLiveMode,
      ),
      ZhiyunService.fetchLessonPptSlides(
        courseId: widget.courseId,
        subId: subId,
      ),
      ZhiyunService.fetchLessonTranscript(subId: subId),
    ]);

    if (!mounted) return;
    final streams = results[0] as List<ZhiyunStreamOption>;
    final slides = results[1] as List<ZhiyunPptSlide>;
    final transcript = results[2] as List<ZhiyunTranscriptSegment>;

    setState(() {
      _streams = streams;
      _selectedStreamIndex = 0;
      _slides = slides;
      _transcript = transcript;
      _loading = false;
    });

    await ZhiyunService.saveLastWatchedReplay(
      courseName: widget.courseName,
      lessonTitle: _currentTitle,
      livingroomUrl: _currentLivingroomUrl,
      courseId: widget.courseId,
      subId: subId,
    );

    if (autoPlayFirstTime && _isLiveMode && !_autoLaunched) {
      _autoLaunched = true;
      // For live mode, always open the web player (livingroom URL) directly,
      // matching the same behaviour as replay web playback.
      final webUrl = _currentLivingroomUrl.isNotEmpty
          ? _currentLivingroomUrl
          : (streams.isNotEmpty ? streams.first.url : '');
      if (webUrl.isNotEmpty) {
        await _launchInAppPlayer(webUrl, preferWeb: true);
      }
    }
  }

  Future<void> _launchInAppPlayer(
    String url, {
    bool preferWeb = false,
  }) async {
    final authResults = await Future.wait<String?>([
      ZhiyunService.ensureValidToken(),
      ZhiyunService.ensureSsoCookieValue(),
    ]);
    final token = authResults[0] ?? ZhiyunService.getCachedZhiyunToken();
    final ssoCookie = authResults[1];
    var effectiveLivingroom = _currentLivingroomUrl;
    if (widget.courseId.isNotEmpty) {
      effectiveLivingroom = ZhiyunService.buildCourseLivingroomUrl(
        widget.courseId,
        subId: _currentSubId,
      );
    }
    effectiveLivingroom = ZhiyunService.appendTokenToUrl(
      effectiveLivingroom,
      token,
    );
    var rawTargetUrl = url;
    if (rawTargetUrl.contains('classroom.zju.edu.cn/livingroom') &&
        !rawTargetUrl.contains('sub_id=') &&
        widget.courseId.isNotEmpty) {
      rawTargetUrl = ZhiyunService.buildCourseLivingroomUrl(
        widget.courseId,
        subId: _currentSubId,
      );
    }
    final effectiveUrl = rawTargetUrl.contains('classroom.zju.edu.cn')
        ? ZhiyunService.appendTokenToUrl(rawTargetUrl, token)
        : rawTargetUrl;

    final lowerUrl = effectiveUrl.toLowerCase();
    final isDirect = !lowerUrl.contains('livingroom') &&
        (lowerUrl.contains('.mp4') ||
            lowerUrl.contains('.m3u8') ||
            lowerUrl.contains('.flv') ||
            lowerUrl.contains('.ts'));
    final openWebDirectly = preferWeb || !isDirect || _isLiveMode;

    final bool streamIsLive = _isLiveMode ||
        _streams.firstWhereOrNull((s) => s.url == url)?.isLive == true;

    final ok = await OhosNativeService.instance.openInAppVideoPlayer(
      url: effectiveUrl,
      title: '${widget.courseName} · $_currentTitle',
      streams: _streams
          .map((s) => {'label': s.label, 'url': s.url})
          .toList(),
      livingroomUrl: effectiveLivingroom,
      token: token,
      ssoCookie: ssoCookie,
      isLive: streamIsLive,
      preferWeb: openWebDirectly,
    );
    if (!ok && mounted) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('未能启动内置播放器'),
          content: const Text('可尝试改用系统浏览器打开智云课堂页面播放。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                ZhiyunService.openUrl(_currentLivingroomUrl);
              },
              child: const Text('浏览器打开'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _downloadAndShareSlide(ZhiyunPptSlide slide, int index) async {
    final safeCourse =
        FileDownloadShareHelper.sanitizeFileName(widget.courseName);
    final defaultFileName =
        '${safeCourse}_PPT_${index + 1}_${slide.createdSec}s.jpg';
    final target = await FileDownloadShareHelper.chooseSaveTarget(
      context,
      defaultFileName: defaultFileName,
      title: '下载并分享 PPT 截图',
    );
    if (target == null) return;
    final saveDir = target.directory;
    final fileName = target.fileName;

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    final tempFile = File(
      '${Directory.systemTemp.path}/temp_slide_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    try {
      final req = await client
          .getUrl(Uri.parse(slide.imageUrl))
          .timeout(const Duration(seconds: 12));
      req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final sink = tempFile.openWrite();
        await resp.pipe(sink);
        await sink.flush();
        await sink.close();

        final res = await FileDownloadShareHelper.saveTempFileAndPrepareShare(
          tempFile: tempFile,
          targetDir: saveDir,
          fileName: fileName,
          mimeType: 'image/jpeg',
        );
        if (res.isSuccess) {
          AppNotification.success('已保存', 'PPT 第 ${index + 1} 页已保存，正在调起分享...');
          if (res.shareFile != null) {
            await FileDownloadShareHelper.shareFiles(
              [res.shareFile!],
              mimeTypes: [res.mimeType],
              subject: fileName,
            );
          }
        } else {
          AppNotification.error('保存失败', '未能写入目标目录');
        }
      } else {
        await resp.drain();
        AppNotification.error('下载失败', 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.error('保存失败', '$e');
      }
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      client.close(force: true);
    }
  }

  Future<void> _exportTranscriptAsTxt(BuildContext context) async {
    if (_transcript.isEmpty) {
      AppNotification.info('提示', '当前课节暂无语音转写字幕可导出');
      return;
    }
    final safeCourse =
        FileDownloadShareHelper.sanitizeFileName(widget.courseName);
    final safeTitle = FileDownloadShareHelper.sanitizeFileName(_currentTitle);
    final defaultFileName = '${safeCourse}_${safeTitle}_语音字幕.txt';
    final nameCtrl = TextEditingController(text: defaultFileName);

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('下载并分享语音字幕'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${_transcript.length} 条语音字幕，将保存为 txt 文本并在完成后调起原生分享。可自定义文件名：',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(dialogCtx),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(dialogCtx),
                ),
                placeholderStyle: TextStyle(
                  color: CupertinoColors.placeholderText.resolveFrom(dialogCtx),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill
                      .resolveFrom(dialogCtx),
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
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final pickedDir =
                  await OhosNativeService.instance.pickDirectory();
              if (pickedDir != null && pickedDir.isNotEmpty) {
                await _doSaveTranscriptFile(nameCtrl.text.trim(),
                    targetDir: pickedDir);
              }
            },
            child: const Text('选择目录并分享'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await _doSaveTranscriptFile(nameCtrl.text.trim());
            },
            child: const Text('默认目录并分享'),
          ),
        ],
      ),
    );
  }

  Future<void> _doSaveTranscriptFile(String fileName,
      {String? targetDir}) async {
    final cleanName = FileDownloadShareHelper.sanitizeFileName(fileName);
    final finalName = cleanName.endsWith('.txt') ? cleanName : '$cleanName.txt';
    final saveDir = (targetDir != null && targetDir.isNotEmpty)
        ? targetDir
        : await FileDownloadShareHelper.resolveDefaultSaveDir();

    final buffer = StringBuffer();
    buffer.writeln('课程：${widget.courseName}');
    buffer.writeln('课节：$_currentTitle');
    buffer.writeln('导出时间：${DateTime.now().toString().split('.').first}');
    buffer.writeln('=' * 40);
    buffer.writeln();
    for (final seg in _transcript) {
      buffer.writeln('[${seg.timeLabel}] ${seg.text}');
    }

    final tempFile = File(
        '${Directory.systemTemp.path}/temp_sub_${DateTime.now().millisecondsSinceEpoch}.txt');
    try {
      await tempFile.writeAsString(buffer.toString(), encoding: utf8);
      final res = await FileDownloadShareHelper.saveTempFileAndPrepareShare(
        tempFile: tempFile,
        targetDir: saveDir,
        fileName: finalName,
        mimeType: 'text/plain',
      );
      if (res.isSuccess) {
        AppNotification.success('字幕已保存', '已保存至：$finalName，正在调起分享...');
        if (res.shareFile != null) {
          await FileDownloadShareHelper.shareFiles(
            [res.shareFile!],
            mimeTypes: [res.mimeType],
            subject: finalName,
          );
        }
      } else {
        AppNotification.error('保存失败', '未能将字幕文件写入目标目录');
      }
    } catch (e) {
      AppNotification.error('导出失败', '$e');
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _exportAllSlidesAsZip(BuildContext context) async {
    if (_slides.isEmpty) {
      AppNotification.info('提示', '当前课节暂无 PPT 幻灯片可打包');
      return;
    }
    final safeCourse =
        FileDownloadShareHelper.sanitizeFileName(widget.courseName);
    final safeTitle = FileDownloadShareHelper.sanitizeFileName(_currentTitle);
    final defaultFileName = '${safeCourse}_${safeTitle}_切片课件.zip';
    final nameCtrl = TextEditingController(text: defaultFileName);

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('打包下载并分享切片课件'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${_slides.length} 页 PPT 切片截图，将打包为 ZIP 压缩包保存并在完成后调起原生分享。可自定义文件名：',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(dialogCtx),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(dialogCtx),
                ),
                placeholderStyle: TextStyle(
                  color: CupertinoColors.placeholderText.resolveFrom(dialogCtx),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill
                      .resolveFrom(dialogCtx),
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
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final pickedDir =
                  await OhosNativeService.instance.pickDirectory();
              if (pickedDir != null && pickedDir.isNotEmpty) {
                await _doPackageSlidesZip(nameCtrl.text.trim(),
                    targetDir: pickedDir);
              }
            },
            child: const Text('选择目录并分享'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await _doPackageSlidesZip(nameCtrl.text.trim());
            },
            child: const Text('默认目录并分享'),
          ),
        ],
      ),
    );
  }

  Future<void> _doPackageSlidesZip(String fileName, {String? targetDir}) async {
    final cleanName = FileDownloadShareHelper.sanitizeFileName(fileName);
    final finalName = cleanName.endsWith('.zip') ? cleanName : '$cleanName.zip';
    final saveDir = (targetDir != null && targetDir.isNotEmpty)
        ? targetDir
        : await FileDownloadShareHelper.resolveDefaultSaveDir();

    AppNotification.info('正在打包 PPT', '共 ${_slides.length} 页，正在下载切片并生成压缩包...');

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    final tempFile = File(
        '${Directory.systemTemp.path}/temp_ppt_${DateTime.now().millisecondsSinceEpoch}.zip');

    try {
      final archive = Archive();
      var downloadedCount = 0;
      const poolSize = 4;
      for (var i = 0; i < _slides.length; i += poolSize) {
        final end =
            (i + poolSize < _slides.length) ? i + poolSize : _slides.length;
        final chunk = <Future<void>>[];
        for (var j = i; j < end; j++) {
          final idx = j;
          final slide = _slides[idx];
          chunk.add(() async {
            try {
              final req = await client
                  .getUrl(Uri.parse(slide.imageUrl))
                  .timeout(const Duration(seconds: 12));
              req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
              final resp =
                  await req.close().timeout(const Duration(seconds: 20));
              if (resp.statusCode == 200) {
                final bytes =
                    await resp.fold<List<int>>([], (a, b) => a..addAll(b));
                final entryName =
                    'PPT_${(idx + 1).toString().padLeft(3, '0')}_${slide.createdSec}s.jpg';
                archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
                downloadedCount++;
              } else {
                await resp.drain();
              }
            } catch (_) {}
          }());
        }
        await Future.wait(chunk);
      }

      if (downloadedCount == 0) {
        AppNotification.error('打包失败', '未能下载任何一页 PPT 切片截图');
        return;
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData.isEmpty) {
        AppNotification.error('打包失败', 'ZIP 压缩包生成失败');
        return;
      }

      await tempFile.writeAsBytes(zipData);
      final res = await FileDownloadShareHelper.saveTempFileAndPrepareShare(
        tempFile: tempFile,
        targetDir: saveDir,
        fileName: finalName,
        mimeType: 'application/zip',
      );
      if (res.isSuccess) {
        AppNotification.success(
            '打包完成', '已保存 $downloadedCount 页 PPT 切片，正在调起分享...');
        if (res.shareFile != null) {
          await FileDownloadShareHelper.shareFiles(
            [res.shareFile!],
            mimeTypes: [res.mimeType],
            subject: finalName,
          );
        }
      } else {
        AppNotification.error('保存失败', '未能将 ZIP 压缩包写入目标目录');
      }
    } catch (e) {
      AppNotification.error('打包异常', '$e');
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      client.close(force: true);
    }
  }

  void _showFullscreenSlide(int index) {
    if (index < 0 || index >= _slides.length) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (ctx) => _FullscreenPptViewer(
          slides: _slides,
          initialIndex: index,
          courseName: widget.courseName,
          lessonTitle: _currentTitle,
          onSave: (slide, i) => _downloadAndShareSlide(slide, i),
        ),
      ),
    );
  }

  void _showLessonPicker(BuildContext context) {
    if (widget.replays.isEmpty) return;
    showCupertinoModalPopup(
      context: context,
      builder: (sheetCtx) {
        return CupertinoActionSheet(
          title: Text('${widget.courseName} · 切换课节'),
          actions: widget.replays
              .where((r) => r.subId != null && r.subId!.isNotEmpty)
              .map((r) => CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      setState(() {
                        _currentSubId = r.subId;
                        _currentTitle = r.lessonTitle;
                        _currentLivingroomUrl = r.livingroomUrl;
                        _isLiveMode = r.isLive;
                      });
                      _loadLessonData(autoPlayFirstTime: false);
                    },
                    child: Text(
                      '${r.lessonTitle}${r.isLive ? " [直播中]" : r.hasReplay ? " [有回放]" : ""}',
                      style: TextStyle(
                        fontWeight: r.subId == _currentSubId
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ))
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetCtx),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  Widget _buildPlayerControlCard(BuildContext context) {
    final activeStream =
        (_streams.isNotEmpty && _selectedStreamIndex < _streams.length)
            ? _streams[_selectedStreamIndex]
            : null;

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.play_rectangle_fill,
                  color: CupertinoColors.activeBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentTitle,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.replays.length > 1)
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minSize: 28,
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () => _showLessonPicker(context),
                  child: const Text(
                    '切换课节',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    CupertinoActivityIndicator(),
                    SizedBox(height: 8),
                    Text('正在解析智云直播/回放流媒体与课堂 PPT...',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (_streams.isNotEmpty) ...[
            if (_streams.length > 1) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_streams.length, (i) {
                  final s = _streams[i];
                  final selected = i == _selectedStreamIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedStreamIndex = i;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? CupertinoColors.activeBlue
                            : CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected
                              ? CupertinoColors.white
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.label, context),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 12),
                borderRadius: BorderRadius.circular(12),
                onPressed: _isLiveMode
                    ? () => _launchInAppPlayer(
                          _currentLivingroomUrl,
                          preferWeb: true,
                        )
                    : (activeStream == null
                        ? null
                        : () => _launchInAppPlayer(activeStream.url)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.play_circle_fill,
                        size: 20, color: CupertinoColors.white),
                    const SizedBox(width: 8),
                    Text(
                      _isLiveMode
                          ? '观看实时直播（网页播放器）'
                          : '播放视频 (${activeStream?.label ?? "回放"})',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              '当前课节暂未生成直接视频流（可能尚未开课或录播转码中），您仍可尝试播放网页版或查看下方 PPT 与语音转写。',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: CupertinoColors.activeBlue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                onPressed: () => _launchInAppPlayer(
                  _currentLivingroomUrl,
                  preferWeb: true,
                ),
                child: const Text(
                  '打开网页播放器',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlidesView(BuildContext context) {
    if (_slides.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            '该课节暂无抓取到的 PPT 幻灯片截图',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondaryLabel, context),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Text(
                '共 ${_slides.length} 页切片 · 点击可放大浏览',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                minSize: 30,
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _exportAllSlidesAsZip(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.archivebox_fill,
                        size: 14, color: CupertinoColors.white),
                    SizedBox(width: 4),
                    Text(
                      '下载并分享',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _slides.length,
          itemBuilder: (context, index) {
            final slide = _slides[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: RoundRectangleCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '第 ${index + 1} 页 · 课堂时间 ${slide.timeLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label, context),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minSize: 26,
                          onPressed: () => _downloadAndShareSlide(slide, index),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.share, size: 14),
                              SizedBox(width: 4),
                              Text('下载并分享', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () => _showFullscreenSlide(index),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Image.network(
                              slide.imageUrl,
                              headers: const {
                                'Referer': 'https://classroom.zju.edu.cn/',
                              },
                              fit: BoxFit.contain,
                              cacheWidth: 1080,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                height: 120,
                                child: Center(child: Text('PPT 图片加载失败')),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x99000000),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.zoom_in,
                                      size: 13, color: CupertinoColors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    '点击放大',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: CupertinoColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTranscriptView(BuildContext context) {
    final filtered = _searchKeyword.trim().isEmpty
        ? _transcript
        : _transcript
            .where((s) =>
                s.text.toLowerCase().contains(_searchKeyword.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: CupertinoSearchTextField(
                  placeholder: '搜索课堂语音转写内容...',
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label, context),
                  ),
                  placeholderStyle: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.placeholderText, context),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchKeyword = val;
                    });
                  },
                ),
              ),
              if (_transcript.isNotEmpty) ...[
                const SizedBox(width: 8),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minSize: 32,
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () async {
                    final allText = _transcript
                        .map((e) => '[${e.timeLabel}] ${e.text}')
                        .join('\n');
                    await Clipboard.setData(ClipboardData(text: allText));
                    if (mounted) {
                      AppNotification.success('已复制', '全部语音转写字幕已复制到剪贴板');
                    }
                  },
                  child: const Text('复制全文',
                      style: TextStyle(
                          fontSize: 12, color: CupertinoColors.activeBlue)),
                ),
                const SizedBox(width: 6),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minSize: 32,
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => _exportTranscriptAsTxt(context),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.share,
                          size: 14, color: CupertinoColors.white),
                      SizedBox(width: 4),
                      Text(
                        '下载并分享',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _transcript.isEmpty ? '该课节暂无语音转写字幕' : '未找到匹配的转写内容',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: RoundRectangleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filtered
                    .map((seg) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.activeBlue
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  seg.timeLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: CupertinoColors.activeBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  seg.text,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            CelechronSliverTextHeader(subtitle: '${widget.courseName} · 智云课堂'),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _buildPlayerControlCard(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tabIndex,
                  children: {
                    0: Text('课堂 PPT (${_slides.length})'),
                    1: Text('语音字幕 (${_transcript.length})'),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _tabIndex = val;
                      });
                    }
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _tabIndex == 0
                  ? _buildSlidesView(context)
                  : _buildTranscriptView(context),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }
}

class _FullscreenPptViewer extends StatefulWidget {
  final List<ZhiyunPptSlide> slides;
  final int initialIndex;
  final String courseName;
  final String lessonTitle;
  final void Function(ZhiyunPptSlide slide, int index) onSave;

  const _FullscreenPptViewer({
    required this.slides,
    required this.initialIndex,
    required this.courseName,
    required this.lessonTitle,
    required this.onSave,
  });

  @override
  State<_FullscreenPptViewer> createState() => _FullscreenPptViewerState();
}

class _FullscreenPptViewerState extends State<_FullscreenPptViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_currentIndex];
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xCC000000),
        middle: Text(
          '第 ${_currentIndex + 1} / ${widget.slides.length} 页 (${slide.timeLabel})',
          style: const TextStyle(color: CupertinoColors.white),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => widget.onSave(slide, _currentIndex),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.share,
                  size: 15, color: CupertinoColors.white),
              SizedBox(width: 4),
              Text('下载并分享',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
      child: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.slides.length,
          onPageChanged: (idx) => setState(() => _currentIndex = idx),
          itemBuilder: (ctx, i) {
            final s = widget.slides[i];
            return Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(
                  s.imageUrl,
                  headers: const {'Referer': 'https://classroom.zju.edu.cn/'},
                  fit: BoxFit.contain,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
