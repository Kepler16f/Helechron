import 'package:flutter/cupertino.dart';

import 'package:celechron/design/components/ael_large_title_bar.dart';
import 'package:celechron/design/components/ael_responsive.dart';
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
    final scrolled = shrinkOffset > 4 || overlapsContent;
    final bgAlpha = scrolled ? 0.96 : 0.0;
    final dividerAlpha = scrolled ? (colors.isDark ? 0.28 : 0.35) : 0.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.pageBg.withValues(alpha: bgAlpha),
        border: dividerAlpha > 0
            ? Border(
                bottom: BorderSide(
                  color: colors.divider.withValues(alpha: dividerAlpha),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.only(top: padding),
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
                        onPressed: () {
                          final onBack = AelEmbeddedBackScope.maybeOf(context);
                          if (onBack != null) {
                            onBack();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: right != null ? 104 : (firstPage ? 16 : 56),
                      ),
                      child: Center(
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
                                  fontSize: fontSize - (bottom == null ? 0 : 2),
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
                  if (right != null) Positioned(right: 0, child: right!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get minExtent => 52 + padding + (bottom == null ? 0 : 48);

  @override
  double get maxExtent => 52 + padding + (bottom == null ? 0 : 48);

  @override
  bool shouldRebuild(covariant CelechronHeader oldDelegate) {
    return subtitle != oldDelegate.subtitle ||
        fontSize != oldDelegate.fontSize ||
        firstPage != oldDelegate.firstPage ||
        padding != oldDelegate.padding ||
        right != oldDelegate.right ||
        bottom != oldDelegate.bottom;
  }
}
