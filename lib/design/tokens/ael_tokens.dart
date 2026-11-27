import 'package:flutter/widgets.dart';

/// Aelechron / Helechron 统一设计令牌（唯一允许定义原始色值字面量的位置）。
///
/// 视觉层次对齐参考设计：页面浅灰底 -> 近白大圆角分区卡片 -> 卡片内 tonal 色调子块，
/// 主色仅用于当前选中、主操作按钮与强强调元素。

final class AelSpacing {
  const AelSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double sectionGap = 14;
  static const double pageHorizontal = 16;
}

final class AelRadius {
  const AelRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double tile = 16;
  static const double button = 18;
  static const double card = 24;
  static const double sheet = 28;
  static const double bar = 28;
  static const double pill = 999;
}

final class AelDurations {
  const AelDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 380);
}

/// 三端共享的底栏与平板侧栏几何规格（Flutter 玻璃导航与鸿蒙 ArkTS HdsTabs 对齐同一规格）。
final class AelTabBarSpec {
  const AelTabBarSpec._();

  static const double height = 56;
  static const double bottomMargin = 8;
  static const double borderRadius = 28;
  static const double horizontalInset = 16;
  static const double iconSize = 22;
  static const double floatingIconSize = 20;
  static const double labelFontSize = 10.5;

  /// 平板 / 宽屏左侧导航栏宽度与触发断点（三端一致）。
  static const double sideRailWidth = 80;
  static const double sideRailFloatingWidth = 66;
  static const double sideRailBreakpoint = 600;

  /// Android / iOS FlClash 风格悬浮胶囊底栏与停靠底栏几何规格。
  static const double dockHeight = 62;
  static const double dockPadding = 4;
  static const double dockBottomMargin = 10;
  static const double dockHorizontalMargin = 20;
  static const double dockMaxWidth = 440;
  static const double dockedBarHeight = 64;
  static const double dockIconSize = 24;
  static const double dockLabelSize = 10.5;
}

/// 响应式窗口断点与多栏限宽规格。
final class AelBreakpointSpec {
  const AelBreakpointSpec._();

  static const double mediumMinWidth = 600;
  static const double expandedMinWidth = 840;
  static const double largeMinWidth = 1200;

  /// 扣减左侧栏后的正文双栏最小触发宽度（约对应窗口总宽 >= 800）。
  static const double bodyTwoPaneMinWidth = 720;

  /// 二级阅读/详情页最大内容宽度（防止超宽行距难以阅读）。
  static const double maxDetailWidth = 880;

  /// 宽屏首页/多列网格最大内容宽度。
  static const double maxWideContentWidth = 1240;
}

@immutable
class AelColorPreset {
  const AelColorPreset({
    required this.id,
    required this.name,
    required this.seedColor,
  });

  final String id;
  final String name;
  final Color seedColor;
}

/// 主题种子色预设（出厂默认蓝 + 校园与常用色系）。
final class AelPalettePresets {
  const AelPalettePresets._();

  /// 默认主色：清亮蓝（近似参考图主操作色 / HyperOS 蓝）。
  static const Color defaultBlue = Color(0xFF007AFF);
  static const int defaultBlueValue = 0xFF007AFF;

  static const List<AelColorPreset> presets = [
    AelColorPreset(id: 'default_blue', name: '晴空蓝', seedColor: defaultBlue),
    AelColorPreset(id: 'zju_blue', name: '求是蓝', seedColor: Color(0xFF003F88)),
    AelColorPreset(id: 'teal', name: '松石青', seedColor: Color(0xFF0D9488)),
    AelColorPreset(id: 'emerald', name: '竹叶绿', seedColor: Color(0xFF16A34A)),
    AelColorPreset(id: 'amber', name: '银杏黄', seedColor: Color(0xFFD97706)),
    AelColorPreset(id: 'coral', name: '丹桂橙', seedColor: Color(0xFFEA580C)),
    AelColorPreset(id: 'rose', name: '红梅粉', seedColor: Color(0xFFE11D48)),
    AelColorPreset(id: 'violet', name: '紫藤紫', seedColor: Color(0xFF7C3AED)),
  ];
}

/// 语义状态色（亮/暗双态，用于状态胶囊、异常预警、通过/完成标记等）。
final class AelSemanticPalette {
  const AelSemanticPalette._();

  // Success
  static const Color successLight = Color(0xFF15803D);
  static const Color successContainerLight = Color(0xFFDCFCE7);
  static const Color onSuccessContainerLight = Color(0xFF14532D);

  static const Color successDark = Color(0xFF4ADE80);
  static const Color successContainerDark = Color(0xFF14532D);
  static const Color onSuccessContainerDark = Color(0xFFBBF7D0);

  // Warning (例如参考图右上角「2 项异常」暖橙胶囊)
  static const Color warningLight = Color(0xFFC2410C);
  static const Color warningContainerLight = Color(0xFFFFEDD5);
  static const Color onWarningContainerLight = Color(0xFF9A3412);

  static const Color warningDark = Color(0xFFFB923C);
  static const Color warningContainerDark = Color(0xFF431407);
  static const Color onWarningContainerDark = Color(0xFFFED7AA);

  // Info
  static const Color infoLight = Color(0xFF0369A1);
  static const Color infoContainerLight = Color(0xFFE0F2FE);
  static const Color onInfoContainerLight = Color(0xFF0C4A6E);

  static const Color infoDark = Color(0xFF38BDF8);
  static const Color infoContainerDark = Color(0xFF082F49);
  static const Color onInfoContainerDark = Color(0xFFBAE6FD);

  // Neutral chip
  static const Color neutralChipBgLight = Color(0xFFEAECEF);
  static const Color onNeutralChipLight = Color(0xFF525866);

  static const Color neutralChipBgDark = Color(0xFF2B2E36);
  static const Color onNeutralChipDark = Color(0xFFB4BAC6);

  // Tonal surface adjustments for crisp 3-layer hierarchy (page < card < nested tile)
  static const Color pageBgLight = Color(0xFFF2F3F7);
  static const Color cardBgLight = Color(0xFFFFFFFF);
  static const Color tonalTileBgLight = Color(0xFFF2F3F7);

  static const Color pageBgDark = Color(0xFF0E1014);
  static const Color cardBgDark = Color(0xFF191C22);
  static const Color tonalTileBgDark = Color(0xFF232730);

  // Base contrast primitives for swatch checkmarks & transparent borders
  static const Color transparent = Color(0x00000000);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pureBlack = Color(0xFF000000);
}

/// 液态玻璃材质与胶囊高光/阴影光学色值（集中于 tokens，供 ael_glass 与 ael_tab_bar 读取）。
final class AelGlassTokens {
  const AelGlassTokens._();

  static const Color lightTint = Color(0x96F7F8FC);
  static const Color lightStandardTint = Color(0xB8F5F7FA);
  static const Color lightLensTint = Color(0xD8FFFFFF);
  static const Color lightRimHighlight = Color(0xE6FFFFFF);
  static const Color lightSecondaryRim = Color(0x73FFFFFF);
  static const Color lightDropShadow = Color(0x22000000);
  static const Color lightLensShadow = Color(0x1C000000);
  static const Color lightHairlineDark = Color(0x16000000);

  static const Color darkTint = Color(0x7A242832);
  static const Color darkStandardTint = Color(0xA61E222B);
  static const Color darkLensTint = Color(0x42FFFFFF);
  static const Color darkRimHighlight = Color(0x70FFFFFF);
  static const Color darkSecondaryRim = Color(0x2BFFFFFF);
  static const Color darkDropShadow = Color(0x52000000);
  static const Color darkLensShadow = Color(0x36000000);
  static const Color darkHairlineDark = Color(0x22000000);
}
