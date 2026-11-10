import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/zhiyun_service.dart';

class ZhiyunPlayerPage extends StatefulWidget {
  final String courseName;
  final String courseId;
  final String? initialSubId;
  final String initialTitle;
  final String livingroomUrl;
  final List<ZhiyunReplayInfo> replays;

  const ZhiyunPlayerPage({
    super.key,
    required this.courseName,
    required this.courseId,
    this.initialSubId,
    required this.initialTitle,
    required this.livingroomUrl,
    this.replays = const [],
  });

  @override
  State<ZhiyunPlayerPage> createState() => _ZhiyunPlayerPageState();
}

class _ZhiyunPlayerPageState extends State<ZhiyunPlayerPage> {
  String? _currentSubId;
  late String _currentTitle;
  late String _currentLivingroomUrl;

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
    if ((_currentSubId == null || _currentSubId!.isEmpty) &&
        widget.replays.isNotEmpty) {
      final firstWithSub =
          widget.replays.firstWhereOrNull((r) => r.subId?.isNotEmpty == true);
      if (firstWithSub != null) {
        _currentSubId = firstWithSub.subId;
        _currentTitle = firstWithSub.lessonTitle;
        _currentLivingroomUrl = firstWithSub.livingroomUrl;
      }
    }
    _loadLessonData(autoPlayFirstTime: true);
  }

  Future<void> _loadLessonData({bool autoPlayFirstTime = false}) async {
    final subId = _currentSubId;
    if (subId == null || subId.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    final results = await Future.wait([
      ZhiyunService.fetchLessonStreams(
          courseId: widget.courseId, subId: subId),
      ZhiyunService.fetchLessonPptSlides(
          courseId: widget.courseId, subId: subId),
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

    if (autoPlayFirstTime && !_autoLaunched && streams.isNotEmpty) {
      _autoLaunched = true;
      await _launchInAppPlayer(streams.first.url);
    }
  }

  Future<void> _launchInAppPlayer(String url) async {
    await OhosNativeService.instance.openInAppVideoPlayer(
      url: url,
      title: '${widget.courseName} · $_currentTitle',
      streams: _streams
          .map((s) => {'label': s.label, 'url': s.url})
          .toList(),
    );
  }

  Future<void> _saveAndOpenSlide(ZhiyunPptSlide slide, int index) async {
    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      String saveDir = '';
      if (Get.isRegistered<Option>(tag: 'option')) {
        saveDir = Get.find<Option>(tag: 'option').downloadPath.value.trim();
      }
      if (saveDir.isEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        saveDir = '${docDir.path}/courseware';
      }
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeCourse =
          widget.courseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath =
          '${dir.path}/${safeCourse}_PPT_${index + 1}_${slide.createdSec}s.jpg';
      final req = await client
          .getUrl(Uri.parse(slide.imageUrl))
          .timeout(const Duration(seconds: 12));
      req.headers.set('Referer', 'https://classroom.zju.edu.cn/');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final file = File(filePath);
        final sink = file.openWrite();
        await resp.pipe(sink);
        await sink.flush();
        await sink.close();
        await OhosNativeService.instance.openFileWithSystem(
          filePath,
          mimeType: 'image/jpeg',
          title: '选择打开方式',
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('保存失败', '$e', snackPosition: SnackPosition.TOP);
      }
    } finally {
      client.close(force: true);
    }
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
                onPressed: activeStream == null
                    ? null
                    : () => _launchInAppPlayer(activeStream.url),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.play_circle_fill,
                        size: 20, color: CupertinoColors.white),
                    const SizedBox(width: 8),
                    Text(
                      activeStream?.isLive == true
                          ? '观看实时直播 (${activeStream!.label})'
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
                onPressed: () => _launchInAppPlayer(_currentLivingroomUrl),
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
      children: List.generate(_slides.length, (index) {
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
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minSize: 26,
                      onPressed: () => _saveAndOpenSlide(slide, index),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.arrow_down_to_line, size: 14),
                          SizedBox(width: 4),
                          Text('保存并打开', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: InteractiveViewer(
                    child: Image.network(
                      slide.imageUrl,
                      headers: const {
                        'Referer': 'https://classroom.zju.edu.cn/',
                      },
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('PPT 图片加载失败')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
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
                      Get.snackbar('已复制', '全部语音转写字幕已复制到剪贴板',
                          snackPosition: SnackPosition.TOP);
                    }
                  },
                  child: const Text('复制全文',
                      style: TextStyle(
                          fontSize: 12, color: CupertinoColors.activeBlue)),
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
