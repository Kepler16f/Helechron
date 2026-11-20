import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixCard, MiuixCardColors, MiuixPressFeedbackType;

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 参考图分区大卡片：
/// - 连续曲率 squircle 大圆角（24dp）
/// - 无重描边，靠中层 [AelColorTokens.cardBg] 与页面底色区分
/// - 顶部可选「小线性图标 + 标题 + 状态胶囊/操作区」头部行
class AelSectionCard extends StatelessWidget {
  const AelSectionCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(AelSpacing.lg),
    this.cornerRadius = AelRadius.card,
    this.backgroundColor,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double cornerRadius;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final bg = backgroundColor ?? colors.cardBg;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || icon != null || trailing != null) ...[
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: colors.textSecondary),
                const SizedBox(width: 8),
              ],
              if (title != null)
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: AelSpacing.md),
        ],
        child,
      ],
    );

    return MiuixCard(
      cornerRadius: cornerRadius,
      insideMargin: padding,
      colors: MiuixCardColors(color: bg, contentColor: colors.textPrimary),
      onPressed: onTap,
      onLongPress: onLongPress,
      feedbackType: (onTap != null || onLongPress != null)
          ? MiuixPressFeedbackType.sink
          : MiuixPressFeedbackType.none,
      child: body,
    );
  }
}
