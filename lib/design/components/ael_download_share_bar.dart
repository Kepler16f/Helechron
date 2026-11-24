import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_chip.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/services/file_download_share_helper.dart';

/// 「下载」与「分享」分离的紧凑操作条。
/// - 下载：仅下载保存（已下载过也可重新下载）。
/// - 分享：已下载则直接分享原文件；未下载则等同「下载并分享」。
class AelDownloadShareBar extends StatefulWidget {
  const AelDownloadShareBar({
    super.key,
    required this.recordKey,
    required this.defaultFileName,
    required this.mimeType,
    required this.writeTemp,
    this.description,
    this.title,
    this.compact = false,
  });

  final String recordKey;
  final String defaultFileName;
  final String mimeType;
  final Future<bool> Function(File tempFile) writeTemp;
  final String? description;
  final String? title;
  final bool compact;

  @override
  State<AelDownloadShareBar> createState() => _AelDownloadShareBarState();
}

class _AelDownloadShareBarState extends State<AelDownloadShareBar> {
  bool _busy = false;
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AelDownloadShareBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordKey != widget.recordKey) _refresh();
  }

  Future<void> _refresh() async {
    final r = await FileDownloadShareHelper.getDownloadRecord(widget.recordKey);
    if (mounted) setState(() => _downloaded = r != null);
  }

  Future<void> _run(bool share) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FileDownloadShareHelper.exportFile(
        context,
        recordKey: widget.recordKey,
        defaultFileName: widget.defaultFileName,
        mimeType: widget.mimeType,
        writeTemp: widget.writeTemp,
        share: share,
        description: widget.description,
        title: widget.title,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _busy ? 0.5 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AelChip(
            leadingIcon: _downloaded ? AelIcons.check : AelIcons.download,
            label: _downloaded ? '已下载' : '下载',
            tone: _downloaded ? AelChipTone.success : AelChipTone.primary,
            onTap: _busy ? null : () => _run(false),
          ),
          const SizedBox(width: 6),
          AelChip(
            leadingIcon: AelIcons.share,
            label: '分享',
            tone: AelChipTone.neutral,
            onTap: _busy ? null : () => _run(true),
          ),
        ],
      ),
    );
  }
}
