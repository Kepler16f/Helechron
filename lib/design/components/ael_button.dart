import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixButton, MiuixButtonColors, MiuixButtonDefaults;

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

enum AelButtonVariant { primary, tonal, destructive }

/// 统一 Miuix 超椭圆按钮门面（支持主色、tonal 次级与危险操作）。
class AelButton extends StatelessWidget {
  const AelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AelButtonVariant.primary,
    this.cornerRadius = AelRadius.button,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AelButtonVariant variant;
  final double cornerRadius;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final MiuixButtonColors buttonColors = switch (variant) {
      AelButtonVariant.primary => MiuixButtonDefaults.buttonColorsPrimary(
        context,
      ),
      AelButtonVariant.tonal => MiuixButtonColors(
        color: colors.tonalTileBg,
        disabledColor: colors.neutralChipBg,
        contentColor: colors.textPrimary,
        disabledContentColor: colors.textTertiary,
      ),
      AelButtonVariant.destructive => MiuixButtonColors(
        color: colors.errorContainer,
        disabledColor: colors.neutralChipBg,
        contentColor: colors.onErrorContainer,
        disabledContentColor: colors.textTertiary,
      ),
    };

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

    final btn = MiuixButton(
      onPressed: onPressed,
      cornerRadius: cornerRadius,
      colors: buttonColors,
      insideMargin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: child,
    );

    if (!expanded) return btn;
    return SizedBox(width: double.infinity, child: btn);
  }
}
