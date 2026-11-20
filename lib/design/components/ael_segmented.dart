import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;

import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

class AelSegmentItem<T> {
  const AelSegmentItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 参考图「出站模式（规则 / 全局 / 直连）」风格的分段胶囊控件：
/// - 选中项：主色实心胶囊 + onPrimary 文字/图标
/// - 未选中项：tonal 容器底 + 次级文字/图标
/// - 支持「图标在上、文字在下」（参考图样式）或「横向紧凑」两种排版
class AelSegmented<T> extends StatelessWidget {
  const AelSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.stackedIcon = true,
    this.gap = AelSpacing.sm,
  });

  final List<AelSegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool stackedIcon;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: _SegmentButton<T>(
              item: items[i],
              selected: items[i].value == value,
              stackedIcon: stackedIcon,
              colors: colors,
              onTap: () => onChanged(items[i].value),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.item,
    required this.selected,
    required this.stackedIcon,
    required this.colors,
    required this.onTap,
  });

  final AelSegmentItem<T> item;
  final bool selected;
  final bool stackedIcon;
  final AelColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? colors.primary : colors.tonalTileBg;
    final fg = selected ? colors.onPrimary : colors.textSecondary;

    final inner = AnimatedContainer(
      duration: AelDurations.fast,
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: stackedIcon ? 10 : 9,
      ),
      decoration: ShapeDecoration(
        color: bg,
        shape: AelShapes.squircle(AelRadius.pill),
      ),
      child: stackedIcon
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 17, color: fg),
                  const SizedBox(height: 4),
                ],
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
    );

    return MiuixPressable(
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(AelRadius.pill),
      child: inner,
    );
  }
}
