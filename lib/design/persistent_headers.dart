import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'package:celechron/design/components/ael_large_title_bar.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';

class CelechronSliverTextHeader extends StatelessWidget {
  final String subtitle;
  final Widget? right;
  final Widget? bottom;
  final double fontSize;
  final bool firstPage;

  const CelechronSliverTextHeader({
    super.key,
    required this.subtitle,
    this.right,
    this.bottom,
    this.fontSize = 20,
    this.firstPage = false,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: CelechronHeader(
        fontSize: fontSize,
        firstPage: firstPage,
        subtitle: subtitle,
        right: right,
        bottom: bottom,
        padding: MediaQuery.of(context).padding.top,
      ),
    );
  }
}

class CelechronHeader extends SliverPersistentHeaderDelegate {
  final String subtitle;
  final Widget? bottom;
  final Widget? right;
  final double padding;
  final double fontSize;
  final bool firstPage;

  CelechronHeader({
    required this.subtitle,
    this.right,
    this.bottom,
    required this.padding,
    this.fontSize = 20,
    this.firstPage = false,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = AelTheme.colorsOf(context);
    final bgAlpha = shrinkOffset > 12
        ? 0.78
        : (shrinkOffset / 16).clamp(0.0, 0.78);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: shrinkOffset > 12 ? 12 : shrinkOffset,
          sigmaY: shrinkOffset > 12 ? 12 : shrinkOffset,
        ),
        child: Container(
          padding: EdgeInsets.only(top: padding),
          color: colors.pageBg.withValues(alpha: bgAlpha),
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!firstPage)
                      Positioned(
                        left: 12,
                        child: AelCircleIconButton(
                          icon: AelIcons.back,
                          size: 36,
                          iconSize: 18,
                          tooltip: '返回',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: right != null
                              ? 104
                              : (firstPage ? 16 : 56),
                        ),
                        child: Center(
                          child: Hero(
                            tag: subtitle,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize:
                                          fontSize - (bottom == null ? 0 : 2),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                if (bottom != null) bottom!,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (right != null) Positioned(right: 0, child: right!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  double get minExtent => 52 + padding + (bottom == null ? 0 : 48);

  @override
  double get maxExtent => 52 + padding + (bottom == null ? 0 : 48);

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}
