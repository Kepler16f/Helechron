import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixGlassNavigationBar,
        MiuixGlassNavigationItem,
        MiuixGlassRendering,
        MiuixLayerBackdrop;

import 'package:celechron/design/components/ael_glass.dart';
import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

class AelTabItem {
  const AelTabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Android / iOS 端使用的自适应玻璃底栏（对齐鸿蒙 ArkTS HdsTabs 几何规格）：
/// - 悬浮模式下：若 [backdrop] 可用且 OS4 玻璃 shader 已加载，使用 HyperOS 4 真液态玻璃拖拽导航条
///   [MiuixGlassNavigationBar]；否则平滑降级到 [AelGlassSurface]（高斯模糊 / 纯色）
/// - 停靠模式下：全宽底栏，读 [AelTheme.colorsOf] 与 [AelTabBarSpec]
/// - 鸿蒙端不渲染此控件，继续由 ArkTS 原生 `HdsTabs` 承载
class AelTabBar extends StatelessWidget {
  const AelTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.floating,
    required this.immersiveLight,
    this.backdrop,
  });

  final List<AelTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool floating;
  final bool immersiveLight;
  final MiuixLayerBackdrop? backdrop;

  void _handleSelect(int index) {
    HapticFeedback.selectionClick();
    onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = AelTheme.colorsOf(context);

    if (!floating) {
      return _buildDockedBar(context, media, colors);
    }

    final screenWidth = media.size.width;
    final capsuleWidth = math.min(screenWidth * 0.92, 500.0);
    final bottomPadding = media.padding.bottom + AelTabBarSpec.bottomMargin;

    final bool useMiuixGlass =
        immersiveLight && backdrop != null && MiuixGlassRendering.isLoaded;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: AelTabBarSpec.horizontalInset,
          right: AelTabBarSpec.horizontalInset,
          bottom: bottomPadding,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: capsuleWidth, minWidth: 260),
          child: useMiuixGlass
              ? MiuixGlassNavigationBar(
                  backdrop: backdrop,
                  selectedIndex: currentIndex,
                  onSelect: _handleSelect,
                  height: AelTabBarSpec.height,
                  selectedColor: colors.primary,
                  unselectedColor: colors.textSecondary,
                  indicatorColor: colors.primary.withValues(
                    alpha: colors.isDark ? 0.22 : 0.14,
                  ),
                  indicatorPressedColor: colors.primary.withValues(
                    alpha: colors.isDark ? 0.30 : 0.20,
                  ),
                  items: items
                      .map(
                        (item) => MiuixGlassNavigationItem(
                          icon: Icon(
                            item.icon,
                            size: AelTabBarSpec.floatingIconSize,
                          ),
                          label: item.label,
                        ),
                      )
                      .toList(),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AelTabBarSpec.borderRadius,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.textPrimary.withValues(
                          alpha: colors.isDark ? 0.24 : 0.08,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: AelTabBarSpec.height,
                    child: AelGlassSurface(
                      borderRadius: AelTabBarSpec.borderRadius,
                      backdrop: backdrop,
                      preferShader: false,
                      blurSigma: immersiveLight ? 28.0 : 20.0,
                      tintAlpha: colors.isDark
                          ? (immersiveLight ? 0.62 : 0.86)
                          : (immersiveLight ? 0.56 : 0.86),
                      child: _buildItemsRow(colors, floating: true),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDockedBar(
    BuildContext context,
    MediaQueryData media,
    AelColorTokens colors,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.divider.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              height: AelTabBarSpec.height + media.padding.bottom,
              padding: EdgeInsets.only(bottom: media.padding.bottom),
              color: colors.cardBg.withValues(alpha: 0.88),
              child: _buildItemsRow(colors, floating: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemsRow(AelColorTokens colors, {required bool floating}) {
    return Row(
      children: List.generate(items.length, (index) {
        final selected = index == currentIndex;
        final item = items[index];
        final fg = selected ? colors.primary : colors.textSecondary;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleSelect(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: floating
                      ? AelTabBarSpec.floatingIconSize
                      : AelTabBarSpec.iconSize,
                  color: fg,
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: floating ? 10.0 : AelTabBarSpec.labelFontSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Android / iOS 平板与宽屏使用的左侧自适应玻璃导航栏（与鸿蒙 ArkTS 竖排 HdsTabs 对齐）。
class AelSideRail extends StatelessWidget {
  const AelSideRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.floating,
    required this.immersiveLight,
    this.backdrop,
  });

  final List<AelTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool floating;
  final bool immersiveLight;
  final MiuixLayerBackdrop? backdrop;

  void _handleSelect(int index) {
    HapticFeedback.selectionClick();
    onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = AelTheme.colorsOf(context);
    final leftSafe = media.padding.left;
    final outerWidth = AelTabBarSpec.sideRailWidth + leftSafe;

    if (floating) {
      final capsuleHeight = math.min(
        math.max(media.size.height * 0.62, 320.0),
        440.0,
      );
      return SizedBox(
        width: outerWidth,
        height: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(
            left: leftSafe + 7,
            right: 7,
            top: math.max(media.padding.top, AelSpacing.md),
            bottom: math.max(media.padding.bottom, AelSpacing.md),
          ),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AelTabBarSpec.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: colors.textPrimary.withValues(
                      alpha: colors.isDark ? 0.24 : 0.08,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                width: AelTabBarSpec.sideRailFloatingWidth,
                height: capsuleHeight,
                child: AelGlassSurface(
                  borderRadius: AelTabBarSpec.borderRadius,
                  backdrop: backdrop,
                  preferShader: false,
                  blurSigma: immersiveLight ? 28.0 : 20.0,
                  tintAlpha: colors.isDark
                      ? (immersiveLight ? 0.62 : 0.86)
                      : (immersiveLight ? 0.56 : 0.88),
                  child: _buildDestinations(colors),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: outerWidth,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colors.divider.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: colors.cardBg.withValues(alpha: 0.88),
              padding: EdgeInsets.only(
                left: leftSafe,
                top: math.max(media.padding.top, AelSpacing.md),
                bottom: math.max(media.padding.bottom, AelSpacing.md),
              ),
              child: _buildDestinations(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinations(AelColorTokens colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(items.length, (index) {
        final selected = index == currentIndex;
        final item = items[index];
        final fg = selected ? colors.primary : colors.textSecondary;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleSelect(index),
            child: SizedBox(
              width: 56,
              height: 54,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: selected
                      ? colors.primary.withValues(
                          alpha: colors.isDark ? 0.22 : 0.12,
                        )
                      : AelSemanticPalette.transparent,
                  shape: AelShapes.squircle(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: AelTabBarSpec.iconSize, color: fg),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: fg,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
