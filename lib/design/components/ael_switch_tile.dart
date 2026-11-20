import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable, MiuixSwitch;

import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 前导图标徽标外形。
enum AelIconBadgeStyle {
  /// 起伏花瓣形（参考图「VPN / 状态」图标底）。
  cookie,

  /// 正圆形（参考图「局域网代理」图标底）。
  circle,
}

/// 统一图标徽标：在花瓣或圆形容器中居中放置线性图标。
class AelIconBadge extends StatelessWidget {
  const AelIconBadge({
    super.key,
    required this.icon,
    this.size = 42,
    this.iconSize = 20,
    this.backgroundColor,
    this.iconColor,
    this.style = AelIconBadgeStyle.cookie,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? iconColor;
  final AelIconBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final bg = backgroundColor ?? colors.primary;
    final fg = iconColor ?? colors.onPrimary;
    final shape = style == AelIconBadgeStyle.cookie
        ? AelShapes.cookie()
        : const CircleBorder();

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: bg, shape: shape),
        child: Center(
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
  }
}

/// 参考图「VPN 已开启」开关行：
/// 前导花瓣/圆形图标底 + 标题/副标题 + 右侧 Miuix 胶囊开关。
class AelSwitchTile extends StatelessWidget {
  const AelSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.badgeStyle = AelIconBadgeStyle.cookie,
    this.useTonalContainer = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final AelIconBadgeStyle badgeStyle;
  final bool useTonalContainer;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final enabled = onChanged != null;

    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: useTonalContainer ? 14 : 0,
        vertical: useTonalContainer ? 12 : 4,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            AelIconBadge(
              icon: icon!,
              style: badgeStyle,
              backgroundColor: value ? colors.primary : colors.tonalTileBg,
              iconColor: value ? colors.onPrimary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
          ],
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
                    color: enabled ? colors.textPrimary : colors.textTertiary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          MiuixSwitch(value: value, enabled: enabled, onChanged: onChanged),
        ],
      ),
    );

    if (!useTonalContainer) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: row,
      );
    }

    return MiuixPressable(
      onPressed: enabled ? () => onChanged!(!value) : null,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(AelRadius.tile),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.tonalTileBg,
          shape: AelShapes.squircle(AelRadius.tile),
        ),
        child: row,
      ),
    );
  }
}

/// 参考图内嵌列表行（圆形图标 + 标题/副标题 + 右侧自定义控件或箭头）。
class AelListRow extends StatelessWidget {
  const AelListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBgColor,
    this.iconColor,
    this.trailing,
    this.showChevron = true,
    this.useTonalContainer = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconBgColor;
  final Color? iconColor;
  final Widget? trailing;
  final bool showChevron;
  final bool useTonalContainer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: useTonalContainer ? 14 : 0,
        vertical: useTonalContainer ? 12 : 6,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            AelIconBadge(
              icon: icon!,
              size: 38,
              iconSize: 18,
              style: AelIconBadgeStyle.circle,
              backgroundColor: iconBgColor ?? colors.cardBg,
              iconColor: iconColor ?? colors.textSecondary,
            ),
            const SizedBox(width: 12),
          ],
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
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showChevron && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(AelIcons.chevronRight, size: 17, color: colors.textTertiary),
          ],
        ],
      ),
    );

    if (!useTonalContainer) {
      if (onTap == null) return row;
      return MiuixPressable(
        onPressed: onTap,
        feedbackType: MiuixPressFeedbackType.sink,
        borderRadius: BorderRadius.circular(AelRadius.sm),
        child: row,
      );
    }

    return MiuixPressable(
      onPressed: onTap,
      feedbackType: onTap != null
          ? MiuixPressFeedbackType.sink
          : MiuixPressFeedbackType.none,
      borderRadius: BorderRadius.circular(AelRadius.tile),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.tonalTileBg,
          shape: AelShapes.squircle(AelRadius.tile),
        ),
        child: row,
      ),
    );
  }
}
