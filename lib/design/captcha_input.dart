import 'dart:async';
import 'dart:typed_data';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:celechron/utils/global.dart';

class ImageCodePortal {
  static final TextEditingController _inputController = TextEditingController();

  /// 异步显示弹窗，返回用户输入的字符串。若取消则返回 null。
  static Future<String?> show({
    required Uint8List imageBytes,
    required Future<Uint8List> Function() onRefresh,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return null;

    // 创建一个 Completer 来管理异步返回
    final Completer<String?> completer = Completer<String?>();

    Uint8List currentImage = imageBytes;
    _inputController.clear();

    final result = await showAelBottomSheet<String>(
      context: context,
      title: '安全验证',
      subtitle: '输入下方图形验证码以继续',
      isDismissible: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setDialogState) {
            final colors = AelTheme.colorsOf(sheetContext);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final newImage = await onRefresh();
                      setDialogState(() => currentImage = newImage);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(AelSpacing.sm),
                      decoration: ShapeDecoration(
                        color: colors.tonalTileBg,
                        shape: AelShapes.squircle(AelRadius.tile),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AelRadius.sm),
                        child: Image.memory(
                          currentImage,
                          height: 60,
                          width: 168,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              Icon(AelIcons.refresh, color: colors.primary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AelSpacing.xs + 2),
                Center(
                  child: Text(
                    '点击图片刷新',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                const SizedBox(height: AelSpacing.lg),
                CupertinoTextField(
                  controller: _inputController,
                  placeholder: '请输入验证码',
                  autofocus: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: AelSpacing.md,
                    horizontal: AelSpacing.md,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: colors.textPrimary),
                  placeholderStyle: TextStyle(
                    fontSize: 15,
                    color: colors.textTertiary,
                  ),
                  decoration: BoxDecoration(
                    color: colors.tonalTileBg,
                    borderRadius: BorderRadius.circular(AelRadius.tile),
                  ),
                  onSubmitted: (val) => Navigator.of(sheetContext).pop(val),
                ),
                const SizedBox(height: AelSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AelButton(
                        variant: AelButtonVariant.tonal,
                        expanded: true,
                        label: '取消',
                        onPressed: () => Navigator.of(sheetContext).pop(null),
                      ),
                    ),
                    const SizedBox(width: AelSpacing.md),
                    Expanded(
                      child: AelButton(
                        expanded: true,
                        label: '确定',
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(_inputController.text),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (!completer.isCompleted) {
      completer.complete(result);
    }
    return completer.future;
  }
}
