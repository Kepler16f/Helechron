import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
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
    final colors = AelTheme.colorsOf(context);
    final pad = EdgeInsets.symmetric(
      horizontal: widget.compact ? 9 : 12,
      vertical: widget.compact ? 5 : 7,
    );
    Widget pill({
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
            padding: pad,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(
          icon: _downloaded ? AelIcons.check : AelIcons.download,
          label: _downloaded ? '已下载' : '下载',
          bg: _downloaded ? colors.successContainer : colors.primaryContainer,
          fg: _downloaded
              ? colors.onSuccessContainer
              : colors.onPrimaryContainer,
          onTap: _busy ? null : () => _run(false),
        ),
        const SizedBox(width: 6),
        pill(
          icon: AelIcons.share,
          label: '分享',
          bg: colors.tonalTileBg,
          fg: colors.textPrimary,
          onTap: _busy ? null : () => _run(true),
        ),
      ],
    );
  }
}
