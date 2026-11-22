import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixCard, MiuixCardColors, MiuixPressFeedbackType;

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 参考图卡片内嵌色调数字块（例如「上传 / 下载 0 B/s」）：
/// - 采用最深一档容器色 [AelColorTokens.tonalTileBg]，16dp squircle 圆角
/// - 顶部小标签 + 可选前导图标
/// - 主视觉锚点：大号粗体等宽数字（tabularFigures）+ 小号单位
/// - 底部次要说明文字
class AelStatTile extends StatelessWidget {
  const AelStatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.valueColor,
    this.valueFontSize,
    this.valueMaxLines = 1,
    this.valueOverflow = TextOverflow.ellipsis,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? valueColor;
  final double? valueFontSize;
  final int valueMaxLines;
  final TextOverflow valueOverflow;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return MiuixCard(
      cornerRadius: AelRadius.tile,
      insideMargin: padding,
      colors: MiuixCardColors(
        color: backgroundColor ?? colors.tonalTileBg,
        contentColor: colors.textPrimary,
      ),
      onPressed: onTap,
      feedbackType: onTap != null
          ? MiuixPressFeedbackType.sink
          : MiuixPressFeedbackType.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: iconColor ?? colors.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: valueMaxLines,
                  overflow: valueOverflow,
                  style: TextStyle(
                    color: valueColor ?? colors.textPrimary,
                    fontSize: valueFontSize ?? 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing:
                        (valueFontSize != null && valueFontSize! < 20)
                        ? -0.2
                        : -0.5,
                    height: 1.15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
