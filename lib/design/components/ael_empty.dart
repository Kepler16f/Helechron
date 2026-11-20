import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_button.dart';
import 'package:celechron/design/components/ael_section_card.dart';
import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/components/ael_switch_tile.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 统一空状态卡片（带起伏花瓣徽标、标题、副标题与可选主操作按钮）。
class AelEmptyState extends StatelessWidget {
  const AelEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AelIconBadge(
            icon: icon,
            size: 56,
            iconSize: 26,
            style: AelIconBadgeStyle.cookie,
            backgroundColor: colors.primaryContainer,
            iconColor: colors.onPrimaryContainer,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            AelButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// 统一轻量呼吸骨架占位块。
class AelSkeletonBox extends StatefulWidget {
  const AelSkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = AelRadius.sm,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<AelSkeletonBox> createState() => _AelSkeletonBoxState();
}

class _AelSkeletonBoxState extends State<AelSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 0.95,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.tonalTileBg,
            shape: AelShapes.squircle(widget.borderRadius),
          ),
        ),
      ),
    );
  }
}
