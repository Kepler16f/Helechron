import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;

import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 状态胶囊语义色调。
enum AelChipTone { neutral, primary, success, warning, error, info }

/// 参考图风格的状态胶囊（例如「未运行」「2 项异常」）。
class AelChip extends StatelessWidget {
  const AelChip({
    super.key,
    required this.label,
    this.tone = AelChipTone.neutral,
    this.leadingIcon,
    this.trailingIcon,
    this.onTap,
  });

  final String label;
  final AelChipTone tone;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final (Color bg, Color fg) = switch (tone) {
      AelChipTone.neutral => (colors.neutralChipBg, colors.onNeutralChip),
      AelChipTone.primary => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      AelChipTone.success => (
        colors.successContainer,
        colors.onSuccessContainer,
      ),
      AelChipTone.warning => (
        colors.warningContainer,
        colors.onWarningContainer,
      ),
      AelChipTone.error => (colors.errorContainer, colors.onErrorContainer),
      AelChipTone.info => (colors.infoContainer, colors.onInfoContainer),
    };

    final content = DecoratedBox(
      decoration: ShapeDecoration(
        color: bg,
        shape: AelShapes.squircle(AelRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon, size: 13, color: fg),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return MiuixPressable(
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(AelRadius.pill),
      child: content,
    );
  }
}
