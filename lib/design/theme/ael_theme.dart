import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixColors, MiuixThemeData, defaultTextStyles, miuixColorsFromSeed;

import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 语义化颜色令牌（三层面阶梯 + 语义状态色）。
@immutable
class AelColorTokens {
  const AelColorTokens({
    required this.brightness,
    required this.pageBg,
    required this.cardBg,
    required this.tonalTileBg,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.outline,
    required this.neutralChipBg,
    required this.onNeutralChip,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Brightness brightness;

  /// 页面底色（最底层浅灰 / 深炭）。
  final Color pageBg;

  /// 分区大卡片底色（中层近白 / 抬升深灰）。
  final Color cardBg;

  /// 卡片内嵌套子块底色（tonal 容器）。
  final Color tonalTileBg;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color outline;

  final Color neutralChipBg;
  final Color onNeutralChip;

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  bool get isDark => brightness == Brightness.dark;

  /// 将当前主色转为 `#AARRGGBB` / `#RRGGBB` 十六进制，供 ArkTS 原生底栏与小组件同步。
  String get primaryHex {
    final rgb = primary.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static AelColorTokens lerp(AelColorTokens a, AelColorTokens b, double t) {
    return AelColorTokens(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      pageBg: Color.lerp(a.pageBg, b.pageBg, t)!,
      cardBg: Color.lerp(a.cardBg, b.cardBg, t)!,
      tonalTileBg: Color.lerp(a.tonalTileBg, b.tonalTileBg, t)!,
      primary: Color.lerp(a.primary, b.primary, t)!,
      onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
      primaryContainer: Color.lerp(a.primaryContainer, b.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(
        a.onPrimaryContainer,
        b.onPrimaryContainer,
        t,
      )!,
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
      textTertiary: Color.lerp(a.textTertiary, b.textTertiary, t)!,
      divider: Color.lerp(a.divider, b.divider, t)!,
      outline: Color.lerp(a.outline, b.outline, t)!,
      neutralChipBg: Color.lerp(a.neutralChipBg, b.neutralChipBg, t)!,
      onNeutralChip: Color.lerp(a.onNeutralChip, b.onNeutralChip, t)!,
      success: Color.lerp(a.success, b.success, t)!,
      successContainer: Color.lerp(a.successContainer, b.successContainer, t)!,
      onSuccessContainer: Color.lerp(
        a.onSuccessContainer,
        b.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(a.warning, b.warning, t)!,
      warningContainer: Color.lerp(a.warningContainer, b.warningContainer, t)!,
      onWarningContainer: Color.lerp(
        a.onWarningContainer,
        b.onWarningContainer,
        t,
      )!,
      error: Color.lerp(a.error, b.error, t)!,
      errorContainer: Color.lerp(a.errorContainer, b.errorContainer, t)!,
      onErrorContainer: Color.lerp(a.onErrorContainer, b.onErrorContainer, t)!,
      info: Color.lerp(a.info, b.info, t)!,
      infoContainer: Color.lerp(a.infoContainer, b.infoContainer, t)!,
      onInfoContainer: Color.lerp(a.onInfoContainer, b.onInfoContainer, t)!,
    );
  }
}

/// 挂在 Material `ThemeData.extensions` 上的统一主题扩展。
@immutable
class AelThemeData extends ThemeExtension<AelThemeData> {
  const AelThemeData({
    required this.colors,
    required this.miuixColors,
    required this.seedColor,
  });

  final AelColorTokens colors;
  final MiuixColors miuixColors;
  final Color seedColor;

  @override
  AelThemeData copyWith({
    AelColorTokens? colors,
    MiuixColors? miuixColors,
    Color? seedColor,
  }) {
    return AelThemeData(
      colors: colors ?? this.colors,
      miuixColors: miuixColors ?? this.miuixColors,
      seedColor: seedColor ?? this.seedColor,
    );
  }

  @override
  AelThemeData lerp(covariant ThemeExtension<AelThemeData>? other, double t) {
    if (other is! AelThemeData) return this;
    return AelThemeData(
      colors: AelColorTokens.lerp(colors, other.colors, t),
      miuixColors: t < 0.5 ? miuixColors : other.miuixColors,
      seedColor: Color.lerp(seedColor, other.seedColor, t)!,
    );
  }
}

/// 便捷读取入口：`AelTheme.of(context)` / `AelTheme.colorsOf(context)`。
final class AelTheme {
  const AelTheme._();

  static AelColorTokens fallback([Brightness brightness = Brightness.light]) {
    return AelThemeEngine.resolve(
      brightness: brightness,
      source: ThemeColorSource.defaultBlue,
      customSeed: AelPalettePresets.defaultBlue,
      paletteStyle: ThemePaletteStyle.tonalSpot,
      contrastLevel: ThemeContrastLevel.standard,
    ).aelTheme.colors;
  }

  static AelThemeData of(BuildContext context) {
    final ext = Theme.of(context).extension<AelThemeData>();
    if (ext != null) return ext;
    final brightness =
        CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    return AelThemeEngine.resolve(
      brightness: brightness,
      source: ThemeColorSource.defaultBlue,
      customSeed: AelPalettePresets.defaultBlue,
      paletteStyle: ThemePaletteStyle.tonalSpot,
      contrastLevel: ThemeContrastLevel.standard,
    ).aelTheme;
  }

  static AelColorTokens colorsOf(BuildContext context) => of(context).colors;
}

@immutable
class ResolvedAelThemeBundle {
  const ResolvedAelThemeBundle({
    required this.seedColor,
    required this.miuixTheme,
    required this.materialTheme,
    required this.cupertinoTheme,
    required this.aelTheme,
  });

  final Color seedColor;
  final MiuixThemeData miuixTheme;
  final ThemeData materialTheme;
  final CupertinoThemeData cupertinoTheme;
  final AelThemeData aelTheme;
}

/// 统一主题引擎：同一份种子色同时驱动 Miuix、Material 3、Cupertino 与 ArkTS 底栏。
final class AelThemeEngine {
  const AelThemeEngine._();

  static Color effectiveSeed({
    required ThemeColorSource source,
    required Color customSeed,
    Color? platformMonetSeed,
  }) {
    return switch (source) {
      ThemeColorSource.defaultBlue => AelPalettePresets.defaultBlue,
      ThemeColorSource.monet =>
        platformMonetSeed ?? AelPalettePresets.defaultBlue,
      ThemeColorSource.custom => customSeed,
    };
  }

  static ResolvedAelThemeBundle resolve({
    required Brightness brightness,
    required ThemeColorSource source,
    required Color customSeed,
    required ThemePaletteStyle paletteStyle,
    required ThemeContrastLevel contrastLevel,
    Color? platformMonetSeed,
  }) {
    final isDark = brightness == Brightness.dark;
    final seed = effectiveSeed(
      source: source,
      customSeed: customSeed,
      platformMonetSeed: platformMonetSeed,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: paletteStyle.materialVariant,
      contrastLevel: contrastLevel.materialValue,
    );

    var miuixColors = miuixColorsFromSeed(
      seed: seed,
      paletteStyle: paletteStyle.miuixStyle,
      dark: isDark,
    );

    // 默认蓝且标准柔和风格时保留更接近参考图的明快主色；
    // 高对比度时采用 Material 高对比 Scheme 的主色与前景色。
    final Color primary =
        contrastLevel == ThemeContrastLevel.standard &&
            source == ThemeColorSource.defaultBlue &&
            paletteStyle == ThemePaletteStyle.tonalSpot &&
            !isDark
        ? AelPalettePresets.defaultBlue
        : (contrastLevel != ThemeContrastLevel.standard
              ? colorScheme.primary
              : miuixColors.primary);

    final Color onPrimary = contrastLevel != ThemeContrastLevel.standard
        ? colorScheme.onPrimary
        : miuixColors.onPrimary;

    // 中/高对比度时把主色写回 MiuixColors，使 Miuix 组件同样受对比度设置控制
    if (primary != miuixColors.primary || onPrimary != miuixColors.onPrimary) {
      miuixColors = miuixColors.copy(primary: primary, onPrimary: onPrimary);
    }

    // 页面三层 tonal 表面：在莫奈/自定义模式下轻微混入主题色调，保证参考图的层次感
    final basePageBg = isDark
        ? AelSemanticPalette.pageBgDark
        : AelSemanticPalette.pageBgLight;
    final baseCardBg = isDark
        ? AelSemanticPalette.cardBgDark
        : AelSemanticPalette.cardBgLight;
    final baseTileBg = isDark
        ? AelSemanticPalette.tonalTileBgDark
        : AelSemanticPalette.tonalTileBgLight;

    final double surfaceTintWeight = source == ThemeColorSource.defaultBlue
        ? 0.0
        : (isDark ? 0.05 : 0.035);
    final pageBg = Color.lerp(
      basePageBg,
      colorScheme.surfaceContainerLow,
      surfaceTintWeight == 0 ? 0 : 0.55,
    )!;
    final cardBg = Color.lerp(
      baseCardBg,
      colorScheme.surfaceContainerLowest,
      surfaceTintWeight,
    )!;
    final tonalTileBg = Color.lerp(
      baseTileBg,
      colorScheme.surfaceContainerHigh,
      surfaceTintWeight == 0 ? 0 : 0.45,
    )!;

    final tokens = AelColorTokens(
      brightness: brightness,
      pageBg: pageBg,
      cardBg: cardBg,
      tonalTileBg: tonalTileBg,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: colorScheme.primaryContainer,
      onPrimaryContainer: colorScheme.onPrimaryContainer,
      textPrimary: contrastLevel == ThemeContrastLevel.standard
          ? miuixColors.onSurface
          : colorScheme.onSurface,
      textSecondary: contrastLevel == ThemeContrastLevel.standard
          ? miuixColors.onSurfaceSecondary
          : colorScheme.onSurfaceVariant,
      textTertiary: miuixColors.onSurfaceVariantSummary,
      divider: miuixColors.dividerLine,
      outline: contrastLevel == ThemeContrastLevel.standard
          ? miuixColors.outline
          : colorScheme.outline,
      neutralChipBg: isDark
          ? AelSemanticPalette.neutralChipBgDark
          : AelSemanticPalette.neutralChipBgLight,
      onNeutralChip: isDark
          ? AelSemanticPalette.onNeutralChipDark
          : AelSemanticPalette.onNeutralChipLight,
      success: isDark
          ? AelSemanticPalette.successDark
          : AelSemanticPalette.successLight,
      successContainer: isDark
          ? AelSemanticPalette.successContainerDark
          : AelSemanticPalette.successContainerLight,
      onSuccessContainer: isDark
          ? AelSemanticPalette.onSuccessContainerDark
          : AelSemanticPalette.onSuccessContainerLight,
      warning: isDark
          ? AelSemanticPalette.warningDark
          : AelSemanticPalette.warningLight,
      warningContainer: isDark
          ? AelSemanticPalette.warningContainerDark
          : AelSemanticPalette.warningContainerLight,
      onWarningContainer: isDark
          ? AelSemanticPalette.onWarningContainerDark
          : AelSemanticPalette.onWarningContainerLight,
      error: colorScheme.error,
      errorContainer: colorScheme.errorContainer,
      onErrorContainer: colorScheme.onErrorContainer,
      info: isDark ? AelSemanticPalette.infoDark : AelSemanticPalette.infoLight,
      infoContainer: isDark
          ? AelSemanticPalette.infoContainerDark
          : AelSemanticPalette.infoContainerLight,
      onInfoContainer: isDark
          ? AelSemanticPalette.onInfoContainerDark
          : AelSemanticPalette.onInfoContainerLight,
    );

    final aelTheme = AelThemeData(
      colors: tokens,
      miuixColors: miuixColors,
      seedColor: seed,
    );

    final miuixTheme = MiuixThemeData(
      colors: miuixColors,
      textStyles: defaultTextStyles(),
      brightness: brightness,
    );

    final materialTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme.copyWith(primary: primary, onPrimary: onPrimary),
      scaffoldBackgroundColor: pageBg,
      dividerColor: tokens.divider,
      extensions: <ThemeExtension<dynamic>>[aelTheme],
    );

    final cupertinoTheme = CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      primaryContrastingColor: onPrimary,
      scaffoldBackgroundColor: pageBg,
      barBackgroundColor: pageBg,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 17.0,
          letterSpacing: -0.41,
        ),
        actionTextStyle: TextStyle(
          color: primary,
          fontSize: 17.0,
          letterSpacing: -0.41,
        ),
        navTitleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 17.0,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
        ),
        navLargeTitleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 34.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.41,
        ),
        pickerTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 19.0,
          fontWeight: FontWeight.w500,
        ),
        dateTimePickerTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 19.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return ResolvedAelThemeBundle(
      seedColor: seed,
      miuixTheme: miuixTheme,
      materialTheme: materialTheme,
      cupertinoTheme: cupertinoTheme,
      aelTheme: aelTheme,
    );
  }
}
