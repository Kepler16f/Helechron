import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixThemePaletteStyle;

/// 主题色来源。
enum ThemeColorSource {
  /// 默认晴空蓝。
  defaultBlue,

  /// 跟随系统壁纸取色（Android 12+ Material 莫奈动态取色；iOS / 鸿蒙自动回退）。
  monet,

  /// 用户在预设色板或自定义 HEX 中指定的颜色。
  custom,
}

/// 动态配色风格（同步映射到 Miuix 与 Material 3 DynamicSchemeVariant）。
enum ThemePaletteStyle { tonalSpot, vibrant, expressive, neutral, fidelity }

/// 对比度档位。
enum ThemeContrastLevel { standard, medium, high }

extension ThemeColorSourceX on ThemeColorSource {
  String get label => switch (this) {
    ThemeColorSource.defaultBlue => '默认蓝',
    ThemeColorSource.monet => '莫奈动态取色',
    ThemeColorSource.custom => '自定义主题色',
  };

  String get subtitle => switch (this) {
    ThemeColorSource.defaultBlue => '清亮通透的默认蓝色系',
    ThemeColorSource.monet => 'Android 12+ 自动从系统壁纸提取配色',
    ThemeColorSource.custom => '从预设色板或自定义 HEX 选择主色',
  };
}

extension ThemePaletteStyleX on ThemePaletteStyle {
  String get label => switch (this) {
    ThemePaletteStyle.tonalSpot => '柔和均衡',
    ThemePaletteStyle.vibrant => '鲜明灵动',
    ThemePaletteStyle.expressive => '个性撞色',
    ThemePaletteStyle.neutral => '低饱和素雅',
    ThemePaletteStyle.fidelity => '忠实还原',
  };

  MiuixThemePaletteStyle get miuixStyle => switch (this) {
    ThemePaletteStyle.tonalSpot => MiuixThemePaletteStyle.tonalSpot,
    ThemePaletteStyle.vibrant => MiuixThemePaletteStyle.vibrant,
    ThemePaletteStyle.expressive => MiuixThemePaletteStyle.expressive,
    ThemePaletteStyle.neutral => MiuixThemePaletteStyle.neutral,
    ThemePaletteStyle.fidelity => MiuixThemePaletteStyle.fidelity,
  };

  DynamicSchemeVariant get materialVariant => switch (this) {
    ThemePaletteStyle.tonalSpot => DynamicSchemeVariant.tonalSpot,
    ThemePaletteStyle.vibrant => DynamicSchemeVariant.vibrant,
    ThemePaletteStyle.expressive => DynamicSchemeVariant.expressive,
    ThemePaletteStyle.neutral => DynamicSchemeVariant.neutral,
    ThemePaletteStyle.fidelity => DynamicSchemeVariant.fidelity,
  };
}

extension ThemeContrastLevelX on ThemeContrastLevel {
  String get label => switch (this) {
    ThemeContrastLevel.standard => '标准',
    ThemeContrastLevel.medium => '中等',
    ThemeContrastLevel.high => '高对比',
  };

  double get materialValue => switch (this) {
    ThemeContrastLevel.standard => 0.0,
    ThemeContrastLevel.medium => 0.5,
    ThemeContrastLevel.high => 1.0,
  };
}
