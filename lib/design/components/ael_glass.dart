import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixGlass, MiuixGlassRendering, MiuixGlassShape, MiuixLayerBackdrop;

import 'package:celechron/design/components/ael_shapes.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/utils/platform_features.dart';

/// 玻璃渲染后端分级：
/// - [ohosNative]：鸿蒙端由 ArkTS 原生承载系统沉浸材质（不在 Flutter 重复叠折射 shader）
/// - [miuixShader]：Android / iOS 使用 HyperOS 4 液态玻璃折射（需预先加载 shader）
/// - [flutterBlur]：高斯模糊半透明回退（通用降级路径）
/// - [solid]：纯色半透明（低端机 / 降低透明度）
enum AelGlassTier { ohosNative, miuixShader, flutterBlur, solid }

/// 统一玻璃表面抽象。
///
/// 严格遵循「鸿蒙原生优先，Flutter 玻璃分级降级」原则：
/// - 当 [reduceTransparency] 为 true 或 [tier] 为 [AelGlassTier.solid] 时使用高不透明度卡片底；
/// - 鸿蒙端默认不启用 `liquid_glass_renderer` / OS4 shader，走干净的 [flutterBlur] 或由 ArkTS 托管。
class AelGlassSurface extends StatelessWidget {
  const AelGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.backdrop,
    this.reduceTransparency = false,
    this.blurSigma = 20.0,
    this.tintAlpha,
    this.padding = EdgeInsets.zero,
    this.preferShader = true,
  });

  final Widget child;
  final double borderRadius;
  final MiuixLayerBackdrop? backdrop;
  final bool reduceTransparency;
  final double blurSigma;
  final double? tintAlpha;
  final EdgeInsetsGeometry padding;
  final bool preferShader;

  static AelGlassTier resolveTier({
    required bool reduceTransparency,
    required bool hasBackdrop,
    required bool preferShader,
  }) {
    if (reduceTransparency) return AelGlassTier.solid;
    if (PlatformFeatures.isOhos) {
      // 鸿蒙端底栏/弹层由 ArkTS 原生负责；Flutter 悬浮层保持轻量高斯模糊以对齐系统质感。
      return AelGlassTier.flutterBlur;
    }
    if (preferShader && hasBackdrop && MiuixGlassRendering.isLoaded) {
      return AelGlassTier.miuixShader;
    }
    return AelGlassTier.flutterBlur;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final tier = resolveTier(
      reduceTransparency: reduceTransparency,
      hasBackdrop: backdrop != null,
      preferShader: preferShader,
    );
    final shape = AelShapes.squircle(
      borderRadius,
      side: BorderSide(
        color: colors.outline.withValues(alpha: colors.isDark ? 0.16 : 0.08),
        width: 0.75,
      ),
    );

    switch (tier) {
      case AelGlassTier.miuixShader:
        return MiuixGlass(
          backdrop: backdrop,
          shape: MiuixGlassShape(cornerRadius: borderRadius),
          tint: colors.cardBg.withValues(
            alpha: tintAlpha ?? (colors.isDark ? 0.48 : 0.62),
          ),
          child: Padding(padding: padding, child: child),
        );
      case AelGlassTier.flutterBlur:
        final fill = colors.cardBg.withValues(
          alpha: tintAlpha ?? (colors.isDark ? 0.72 : 0.78),
        );
        return ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: ShapeDecoration(color: fill, shape: shape),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      case AelGlassTier.ohosNative:
      case AelGlassTier.solid:
        final fill = colors.cardBg.withValues(alpha: 0.96);
        return DecoratedBox(
          decoration: ShapeDecoration(color: fill, shape: shape),
          child: Padding(padding: padding, child: child),
        );
    }
  }
}
