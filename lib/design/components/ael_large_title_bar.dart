import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 参考图顶部大标题栏：左对齐粗体大标题 + 右侧圆形操作图标按钮（白底圆钮）。
class AelLargeTitleBar extends StatelessWidget {
  const AelLargeTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AelSpacing.pageHorizontal,
      AelSpacing.md,
      AelSpacing.pageHorizontal,
      AelSpacing.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            actions[i],
          ],
        ],
      ),
    );
  }
}

/// 顶栏右侧白色圆形操作按钮（类似参考图右上角编辑笔按钮），也支持卡片内浅底圆形操作按钮。
class AelCircleIconButton extends StatelessWidget {
  const AelCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 19,
    this.tooltip,
    this.backgroundColor,
    this.iconColor,
    this.elevated = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final bg = backgroundColor ?? colors.cardBg;
    final fg = iconColor ?? colors.textPrimary;
    final btn = MiuixPressable(
      onPressed: onPressed,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(size * 0.5),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: bg,
            shape: const CircleBorder(),
            shadows: elevated
                ? [
                    BoxShadow(
                      color: colors.textPrimary.withValues(
                        alpha: colors.isDark ? 0.18 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return btn;
    return Semantics(label: tooltip, button: true, child: btn);
  }
}

/// 参考图主状态卡右侧主操作圆形按钮（主色实心 + 柔和发光阴影）。
class AelHeroButton extends StatelessWidget {
  const AelHeroButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 64,
    this.iconSize = 26,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final btn = MiuixPressable(
      onPressed: onPressed,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(size * 0.5),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.primary,
            shape: const CircleBorder(),
            shadows: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.34),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: colors.onPrimary),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return btn;
    return Semantics(label: tooltip, button: true, child: btn);
  }
}
