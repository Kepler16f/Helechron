import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
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
    _isLiveMode =
        widget.preferLive ||
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
        matched =
            widget.replays.firstWhereOrNull(
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
            .where(
              (r) =>
                  r.subId?.isNotEmpty == true && r.hasReplay && isNotFuture(r),
            )
            .toList();
        if (pastWithReplay.isNotEmpty) {
          pastWithReplay.sort(
            (a, b) => (b.lessonDate ?? DateTime(1970)).compareTo(
              a.lessonDate ?? DateTime(1970),
            ),
          );
          matched = pastWithReplay.first;
        } else {
          final pastAny = widget.replays
              .where((r) => r.subId?.isNotEmpty == true && isNotFuture(r))
              .toList();
          if (pastAny.isNotEmpty) {
            pastAny.sort(
              (a, b) => (b.lessonDate ?? DateTime(1970)).compareTo(
                a.lessonDate ?? DateTime(1970),
              ),
            );
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
          _currentLivingroomUrl = ZhiyunService.buildLivingroomUrl(
            widget.courseId,
            activeToday,
          );
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
          picked =
              freshCat.firstWhereOrNull(
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
              .where(
                (item) =>
                    (item['sub_id']?.toString().isNotEmpty == true ||
                        item['id']?.toString().isNotEmpty == true) &&
                    isItemNotFuture(item),
              )
              .toList();
          picked =
              validPast.firstWhereOrNull(
                (item) => ZhiyunService.checkHasReplay(item: item),
              ) ??
              validPast.firstOrNull;
        }
        final pickedSub =
            picked?['sub_id']?.toString() ?? picked?['id']?.toString();
        if (pickedSub != null && pickedSub.isNotEmpty) {
          subId = pickedSub;
          _currentSubId = pickedSub;
          _currentLivingroomUrl = ZhiyunService.buildLivingroomUrl(
            widget.courseId,
            pickedSub,
          );
          if (mounted) {
            setState(() {
              _currentTitle =
                  picked?['title']?.toString() ??
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
        await _launchInAppPlayer(_currentLivingroomUrl, preferWeb: true);
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

  Future<void> _launchInAppPlayer(String url, {bool preferWeb = false}) async {
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
    final isDirect =
        !lowerUrl.contains('livingroom') &&
        (lowerUrl.contains('.mp4') ||
            lowerUrl.contains('.m3u8') ||
            lowerUrl.contains('.flv') ||
            lowerUrl.contains('.ts'));
    final openWebDirectly = preferWeb || !isDirect || _isLiveMode;

    final bool streamIsLive =
        _isLiveMode ||
        _streams.firstWhereOrNull((s) => s.url == url)?.isLive == true;

    final ok = await OhosNativeService.instance.openInAppVideoPlayer(
      url: effectiveUrl,
      title: '${widget.courseName} · $_currentTitle',
      streams: _streams.map((s) => {'label': s.label, 'url': s.url}).toList(),
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

  String get _recordBase =>
      '${widget.courseId}|${_currentSubId ?? _currentTitle}';

  Future<bool> _fetchSlideToFile(
    HttpClient client,
    ZhiyunPptSlide slide,
    File target,
  ) async {
    final req = await client
        .getUrl(Uri.parse(slide.imageUrl))
        .timeout(const Duration(seconds: 12));
    req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      await resp.drain();
      AppNotification.error('下载失败', 'HTTP ${resp.statusCode}');
      return false;
    }
    final sink = target.openWrite();
    await resp.pipe(sink);
    await sink.flush();
    await sink.close();
    return true;
  }

  Widget _buildSlideBar(
    ZhiyunPptSlide slide,
    int index, {
    bool compact = false,
  }) {
    final safeCourse = FileDownloadShareHelper.sanitizeFileName(
      widget.courseName,
    );
    return AelDownloadShareBar(
      key: ValueKey('${_recordBase}|slide_$index'),
      recordKey: '${_recordBase}|slide_$index',
      defaultFileName:
          '${safeCourse}_PPT_${index + 1}_${slide.createdSec}s.jpg',
      mimeType: 'image/jpeg',
      title: 'PPT 第 ${index + 1} 页截图',
      compact: compact,
      writeTemp: (tempFile) async {
        final client = HttpClient();
        applyZjuNetworkDefense(client);
        try {
          return await _fetchSlideToFile(client, slide, tempFile);
        } finally {
          client.close(force: true);
        }
      },
    );
  }

  Widget _buildZipBar() {
    final safeCourse = FileDownloadShareHelper.sanitizeFileName(
      widget.courseName,
    );
    final safeTitle = FileDownloadShareHelper.sanitizeFileName(_currentTitle);
    return AelDownloadShareBar(
      key: ValueKey('${_recordBase}|zip'),
      recordKey: '${_recordBase}|zip',
      defaultFileName: '${safeCourse}_${safeTitle}_切片课件.zip',
      mimeType: 'application/zip',
      title: '切片课件压缩包',
      description: '共 ${_slides.length} 页 PPT 切片截图，将打包为 ZIP 压缩包。',
      writeTemp: _writeSlidesZip,
    );
  }

  Future<bool> _writeSlidesZip(File tempFile) async {
    final slides = List<ZhiyunPptSlide>.of(_slides);
    AppNotification.info('正在打包 PPT', '共 ${slides.length} 页，正在下载切片并生成压缩包...');
    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final archive = Archive();
      var downloadedCount = 0;
      const poolSize = 4;
      for (var i = 0; i < slides.length; i += poolSize) {
        final end = (i + poolSize < slides.length)
            ? i + poolSize
            : slides.length;
        final chunk = <Future<void>>[];
        for (var j = i; j < end; j++) {
          final idx = j;
          final slide = slides[idx];
          chunk.add(() async {
            try {
              final req = await client
                  .getUrl(Uri.parse(slide.imageUrl))
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
        return false;
      }
      final zipData = ZipEncoder().encode(archive);
      if (zipData.isEmpty) {
        AppNotification.error('打包失败', 'ZIP 压缩包生成失败');
        return false;
      }
      await tempFile.writeAsBytes(zipData);
      return true;
    } finally {
      client.close(force: true);
    }
  }

  Widget _buildTranscriptBar() {
    final safeCourse = FileDownloadShareHelper.sanitizeFileName(
      widget.courseName,
    );
    final safeTitle = FileDownloadShareHelper.sanitizeFileName(_currentTitle);
    return AelDownloadShareBar(
      key: ValueKey('${_recordBase}|txt'),
      recordKey: '${_recordBase}|txt',
      defaultFileName: '${safeCourse}_${safeTitle}_语音字幕.txt',
      mimeType: 'text/plain',
      title: '语音字幕',
      description: '共 ${_transcript.length} 条语音字幕，将保存为 txt 文本。',
      writeTemp: (tempFile) async {
        final buffer = StringBuffer();
        buffer.writeln('课程：${widget.courseName}');
        buffer.writeln('课节：$_currentTitle');
        buffer.writeln('导出时间：${DateTime.now().toString().split('.').first}');
        buffer.writeln('=' * 40);
        buffer.writeln();
        for (final seg in _transcript) {
          buffer.writeln('[${seg.timeLabel}] ${seg.text}');
        }
        await tempFile.writeAsString(buffer.toString(), encoding: utf8);
        return true;
      },
    );
  }

  void _showFullscreenSlide(int index) {
    if (index < 0 || index >= _slides.length) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (ctx) => _FullscreenPptViewer(
          slides: _slides,
          initialIndex: index,
          barBuilder: (slide, i) => _buildSlideBar(slide, i, compact: true),
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
              .map(
                (r) => CupertinoActionSheetAction(
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
                    '${r.lessonTitle}${r.isLive
                        ? " [直播中]"
                        : r.hasReplay
                        ? " [有回放]"
                        : ""}',
                    style: TextStyle(
                      fontWeight: r.subId == _currentSubId
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              )
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
    final colors = AelTheme.colorsOf(context);
    final activeStream =
        (_streams.isNotEmpty && _selectedStreamIndex < _streams.length)
        ? _streams[_selectedStreamIndex]
        : null;

    return AelSectionCard(
      title: _currentTitle,
      icon: AelIcons.video,
      trailing: widget.replays.length > 1
          ? AelChip(
              label: '切换课节',
              tone: AelChipTone.primary,
              onTap: () => _showLessonPicker(context),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AelSpacing.lg),
              child: Center(
                child: Column(
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(height: AelSpacing.sm),
                    Text(
                      '正在解析智云直播/回放流媒体与课堂 PPT...',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_streams.isNotEmpty) ...[
            if (_streams.length > 1) ...[
              Wrap(
                spacing: AelSpacing.sm,
                runSpacing: AelSpacing.sm,
                children: List.generate(_streams.length, (i) {
                  return AelChip(
                    label: _streams[i].label,
                    tone: i == _selectedStreamIndex
                        ? AelChipTone.primary
                        : AelChipTone.neutral,
                    onTap: () => setState(() => _selectedStreamIndex = i),
                  );
                }),
              ),
              const SizedBox(height: AelSpacing.md),
            ],
            AelButton(
              expanded: true,
              icon: AelIcons.video,
              label: _isLiveMode
                  ? '观看实时直播（网页播放器）'
                  : '播放视频 (${activeStream?.label ?? "回放"})',
              onPressed: _isLiveMode
                  ? () => _launchInAppPlayer(
                      _currentLivingroomUrl,
                      preferWeb: true,
                    )
                  : (activeStream == null
                        ? null
                        : () => _launchInAppPlayer(activeStream.url)),
            ),
          ] else ...[
            Text(
              '当前课节暂未生成直接视频流（可能尚未开课或录播转码中），您仍可尝试播放网页版或查看下方 PPT 与语音转写。',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: AelSpacing.md),
            AelButton(
              expanded: true,
              variant: AelButtonVariant.tonal,
              icon: AelIcons.globe,
              label: '打开网页播放器',
              onPressed: () =>
                  _launchInAppPlayer(_currentLivingroomUrl, preferWeb: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlidesView(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    if (_slides.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AelSpacing.lg),
        child: AelEmptyState(
          icon: AelIcons.image,
          title: '该课节暂无抓取到的 PPT 幻灯片截图',
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AelSpacing.lg,
            AelSpacing.xxs,
            AelSpacing.lg,
            AelSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${_slides.length} 页切片 · 点击可放大浏览',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ),
              _buildZipBar(),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.lg,
                vertical: 6,
              ),
              child: AelSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '第 ${index + 1} 页 · 课堂时间 ${slide.timeLabel}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AelSpacing.sm),
                        _buildSlideBar(slide, index, compact: true),
                      ],
                    ),
                    const SizedBox(height: AelSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AelRadius.xs),
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
                              errorBuilder: (_, __, ___) => SizedBox(
                                height: 120,
                                child: Center(
                                  child: Text(
                                    'PPT 图片加载失败',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(AelSpacing.sm),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AelSpacing.sm,
                                vertical: AelSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AelSemanticPalette.pureBlack.withValues(
                                  alpha: 0.6,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AelIcons.search,
                                    size: 13,
                                    color: AelSemanticPalette.pureWhite,
                                  ),
                                  SizedBox(width: AelSpacing.xs),
                                  Text(
                                    '点击放大',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AelSemanticPalette.pureWhite,
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
    final colors = AelTheme.colorsOf(context);
    final filtered = _searchKeyword.trim().isEmpty
        ? _transcript
        : _transcript
              .where(
                (s) =>
                    s.text.toLowerCase().contains(_searchKeyword.toLowerCase()),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AelSpacing.lg,
            vertical: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoSearchTextField(
                placeholder: '搜索课堂语音转写内容...',
                backgroundColor: colors.tonalTileBg,
                itemColor: colors.textSecondary,
                style: TextStyle(color: colors.textPrimary),
                placeholderStyle: TextStyle(color: colors.textTertiary),
                onChanged: (val) {
                  setState(() {
                    _searchKeyword = val;
                  });
                },
              ),
              if (_transcript.isNotEmpty) ...[
                const SizedBox(height: AelSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '共 ${_transcript.length} 条转写',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    AelChip(
                      label: '复制全文',
                      tone: AelChipTone.primary,
                      leadingIcon: AelIcons.copy,
                      onTap: () async {
                        final allText = _transcript
                            .map((e) => '[${e.timeLabel}] ${e.text}')
                            .join('\n');
                        await Clipboard.setData(ClipboardData(text: allText));
                        if (mounted) {
                          AppNotification.success('已复制', '全部语音转写字幕已复制到剪贴板');
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildTranscriptBar(),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AelSpacing.lg),
            child: AelEmptyState(
              icon: AelIcons.search,
              title: _transcript.isEmpty ? '该课节暂无语音转写字幕' : '未找到匹配的转写内容',
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AelSpacing.lg,
              vertical: 6,
            ),
            child: AelSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filtered
                    .map(
                      (seg) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                seg.timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: AelSpacing.sm),
                            Expanded(
                              child: SelectableText(
                                seg.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            CelechronSliverTextHeader(subtitle: '${widget.courseName} · 智云课堂'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.lg,
                  vertical: 6,
                ),
                child: _buildPlayerControlCard(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.lg,
                  vertical: AelSpacing.sm,
                ),
                child: AelSegmented<int>(
                  stackedIcon: false,
                  value: _tabIndex,
                  items: [
                    AelSegmentItem(
                      value: 0,
                      label: '课堂 PPT (${_slides.length})',
                    ),
                    AelSegmentItem(
                      value: 1,
                      label: '语音字幕 (${_transcript.length})',
                    ),
                  ],
                  onChanged: (val) => setState(() => _tabIndex = val),
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
  final Widget Function(ZhiyunPptSlide slide, int index) barBuilder;

  const _FullscreenPptViewer({
    required this.slides,
    required this.initialIndex,
    required this.barBuilder,
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
      backgroundColor: AelSemanticPalette.pureBlack,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AelSemanticPalette.pureBlack.withValues(alpha: 0.8),
        leading: Center(
          widthFactor: 1,
          child: AelCircleIconButton(
            icon: AelIcons.back,
            size: 32,
            iconSize: 16,
            backgroundColor: AelSemanticPalette.pureWhite.withValues(
              alpha: 0.16,
            ),
            iconColor: AelSemanticPalette.pureWhite,
            elevated: false,
            tooltip: '返回',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        middle: Text(
          '${_currentIndex + 1}/${widget.slides.length} · ${slide.timeLabel}',
          style: const TextStyle(
            color: AelSemanticPalette.pureWhite,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: widget.barBuilder(slide, _currentIndex),
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
