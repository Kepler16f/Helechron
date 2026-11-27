import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/utils/platform_features.dart';

/// 玻璃渲染分级：
/// - [ohosNative]：鸿蒙端由 ArkTS 原生托管底栏/侧栏；Flutter 浮层使用轻量高斯模糊
/// - [liquidGlass]：Android / iOS 参考 FlClash 液态玻璃风格，使用 GPU BackdropFilter + 光学镜面高光描边
/// - [flutterBlur]：标准高斯模糊半透明层
/// - [solid]：纯色半透明卡片（关闭沉浸光感或覆盖避让期间使用）
enum AelGlassTier { ohosNative, liquidGlass, flutterBlur, solid }

/// 液态玻璃精细度档位，兼容既有 `bottomBarMaterialLevel` 持久化整数（10=自适应, 0=极致, 1=标准, 2=轻量）。
enum AelGlassQuality {
  ultra,
  standard;

  static AelGlassQuality fromMaterialLevel(int level) {
    return switch (level) {
      1 || 2 => AelGlassQuality.standard,
      _ => AelGlassQuality.ultra,
    };
  }
}

/// 统一液态玻璃与半透明表面组件（零 `toImageSync` UI 线程阻塞，安全适配 Android Impeller / Skia / iOS）。
class AelGlassSurface extends StatelessWidget {
  const AelGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.isCapsule = false,
    this.reduceTransparency = false,
    this.blurSigma = 18.0,
    this.tintAlpha,
    this.padding = EdgeInsets.zero,
    this.quality = AelGlassQuality.ultra,
    this.enableBackdrop = true,
    this.glowCenter,
    this.glowStrength = 0.0,
    this.shadows,
  });

  final Widget child;
  final double borderRadius;
  final bool isCapsule;
  final bool reduceTransparency;
  final double blurSigma;
  final double? tintAlpha;
  final EdgeInsetsGeometry padding;
  final AelGlassQuality quality;
  final bool enableBackdrop;
  final Offset? glowCenter;
  final double glowStrength;
  final List<BoxShadow>? shadows;

  static AelGlassTier resolveTier({
    required bool reduceTransparency,
    required bool enableBackdrop,
  }) {
    if (reduceTransparency || !enableBackdrop) return AelGlassTier.solid;
    if (PlatformFeatures.isOhos) {
      return AelGlassTier.flutterBlur;
    }
    return AelGlassTier.liquidGlass;
  }

  /// 生成适度增强色彩饱和度的 ColorFilter 矩阵，避免毛玻璃压灰背景色彩。
  static ui.ColorFilter _saturationFilter(double saturation) {
    final s = saturation;
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final invS = 1.0 - s;
    final r = lr * invS;
    final g = lg * invS;
    final b = lb * invS;
    return ui.ColorFilter.matrix(<double>[
      r + s,
      g,
      b,
      0,
      0,
      r,
      g + s,
      b,
      0,
      0,
      r,
      g,
      b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final isDark = colors.isDark;
    final tier = resolveTier(
      reduceTransparency: reduceTransparency,
      enableBackdrop: enableBackdrop,
    );
    final ShapeBorder shape = isCapsule
        ? const StadiumBorder()
        : AelShapes.squircle(borderRadius);

    if (tier == AelGlassTier.solid) {
      final solidColor = colors.cardBg.withValues(
        alpha: tintAlpha ?? (reduceTransparency ? 0.96 : 0.94),
      );
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: solidColor,
          shape: isCapsule
              ? StadiumBorder(
                  side: BorderSide(
                    color: colors.outline.withValues(
                      alpha: isDark ? 0.22 : 0.12,
                    ),
                    width: 0.75,
                  ),
                )
              : AelShapes.squircle(
                  borderRadius,
                  side: BorderSide(
                    color: colors.outline.withValues(
                      alpha: isDark ? 0.20 : 0.10,
                    ),
                    width: 0.75,
                  ),
                ),
          shadows:
              shadows ??
              [
                BoxShadow(
                  color: isDark
                      ? AelGlassTokens.darkDropShadow
                      : AelGlassTokens.lightDropShadow,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    final isUltra =
        tier == AelGlassTier.liquidGlass && quality == AelGlassQuality.ultra;
    final effectiveSigma = tier == AelGlassTier.flutterBlur
        ? math.min(blurSigma, 14.0)
        : (isUltra ? blurSigma : math.min(blurSigma, 13.0));
    final Color tintColor;
    if (tintAlpha != null) {
      tintColor = (isDark ? AelGlassTokens.darkTint : AelGlassTokens.lightTint)
          .withValues(alpha: tintAlpha!);
    } else if (tier == AelGlassTier.liquidGlass) {
      tintColor = isDark
          ? (isUltra
                ? AelGlassTokens.darkTint
                : AelGlassTokens.darkStandardTint)
          : (isUltra
                ? AelGlassTokens.lightTint
                : AelGlassTokens.lightStandardTint);
    } else {
      tintColor = colors.cardBg.withValues(alpha: isDark ? 0.74 : 0.80);
    }

    final ui.ImageFilter backdropFilter = tier == AelGlassTier.liquidGlass
        ? ui.ImageFilter.compose(
            outer: _saturationFilter(isUltra ? 1.28 : 1.12),
            inner: ui.ImageFilter.blur(
              sigmaX: effectiveSigma,
              sigmaY: effectiveSigma,
              tileMode: ui.TileMode.clamp,
            ),
          )
        : ui.ImageFilter.blur(
            sigmaX: effectiveSigma,
            sigmaY: effectiveSigma,
            tileMode: ui.TileMode.clamp,
          );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows:
            shadows ??
            [
              BoxShadow(
                color: isDark
                    ? AelGlassTokens.darkDropShadow
                    : AelGlassTokens.lightDropShadow,
                blurRadius: isUltra ? 24 : 18,
                offset: const Offset(0, 8),
              ),
            ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: backdropFilter,
          child: CustomPaint(
            foregroundPainter: _AelLiquidGlassRimPainter(
              borderRadius: borderRadius,
              isCapsule: isCapsule,
              isDark: isDark,
              isUltra: isUltra,
              accentColor: colors.primary,
              glowCenter: glowCenter,
              glowStrength: glowStrength,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tintColor,
                gradient: tier == AelGlassTier.liquidGlass
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (isDark
                                  ? AelGlassTokens.darkRimHighlight
                                  : AelGlassTokens.lightRimHighlight)
                              .withValues(alpha: isDark ? 0.08 : 0.24),
                          tintColor,
                          tintColor,
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      )
                    : null,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// FlClash 风格的液态玻璃倒角高光、底部反弹微光与触摸光晕绘制器。
class _AelLiquidGlassRimPainter extends CustomPainter {
  const _AelLiquidGlassRimPainter({
    required this.borderRadius,
    required this.isCapsule,
    required this.isDark,
    required this.isUltra,
    required this.accentColor,
    this.glowCenter,
    this.glowStrength = 0.0,
  });

  final double borderRadius;
  final bool isCapsule;
  final bool isDark;
  final bool isUltra;
  final Color accentColor;
  final Offset? glowCenter;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final effectiveRadius = isCapsule
        ? size.shortestSide / 2
        : math.min(borderRadius, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(effectiveRadius),
    );

    if (glowCenter != null && glowStrength > 0.005) {
      final glowRect = Rect.fromCircle(
        center: glowCenter!,
        radius: math.max(size.shortestSide * 0.85, 42),
      );
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(
          glowCenter!,
          glowRect.width / 2,
          [
            AelSemanticPalette.pureWhite.withValues(
              alpha: (isDark ? 0.16 : 0.28) * glowStrength.clamp(0.0, 1.0),
            ),
            accentColor.withValues(alpha: 0.08 * glowStrength.clamp(0.0, 1.0)),
            AelSemanticPalette.transparent,
          ],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawRRect(rrect, glowPaint);
    }

    final topHighlight = isDark
        ? AelGlassTokens.darkRimHighlight
        : AelGlassTokens.lightRimHighlight;
    final bottomHighlight = isDark
        ? AelGlassTokens.darkSecondaryRim
        : AelGlassTokens.lightSecondaryRim;
    final sideHairline = isDark
        ? AelGlassTokens.darkSecondaryRim
        : AelGlassTokens.lightHairlineDark;

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isUltra ? 1.15 : 0.85
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        [
          topHighlight.withValues(
            alpha: isUltra ? (isDark ? 0.36 : 0.78) : (isDark ? 0.24 : 0.56),
          ),
          sideHairline.withValues(alpha: isDark ? 0.14 : 0.10),
          bottomHighlight.withValues(
            alpha: isUltra ? (isDark ? 0.22 : 0.44) : (isDark ? 0.12 : 0.24),
          ),
        ],
        const [0.0, 0.48, 1.0],
      );
    canvas.drawRRect(rrect, rimPaint);

    if (isUltra) {
      // 内侧顶部极细折射反光条，呈现立体透镜厚度感
      final innerRRect = RRect.fromRectAndRadius(
        rect.deflate(1.5),
        Radius.circular(math.max(0, effectiveRadius - 1.0)),
      );
      final innerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            topHighlight.withValues(alpha: isDark ? 0.16 : 0.34),
            AelSemanticPalette.transparent,
            accentColor.withValues(alpha: isDark ? 0.14 : 0.08),
          ],
          const [0.0, 0.55, 1.0],
        );
      canvas.drawRRect(innerRRect, innerPaint);
    }
  }

  @override
  bool shouldRepaint(_AelLiquidGlassRimPainter oldDelegate) {
    return borderRadius != oldDelegate.borderRadius ||
        isCapsule != oldDelegate.isCapsule ||
        isDark != oldDelegate.isDark ||
        isUltra != oldDelegate.isUltra ||
        accentColor != oldDelegate.accentColor ||
        glowCenter != oldDelegate.glowCenter ||
        glowStrength != oldDelegate.glowStrength;
  }
}
