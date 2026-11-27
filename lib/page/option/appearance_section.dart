import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/theme/ael_theme_controller.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/option/option_controller.dart';

/// 设置页「外观」分组：主题色来源（默认蓝 / 莫奈 / 自定义）、预设色板、配色风格、对比度。
///
/// 采用参考图美学卡片组件（[AelSectionCard] + [AelListRow]）重排，
/// 保持所有主题选项与弹窗交互不变。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  OptionController get _controller =>
      Get.find<OptionController>(tag: 'optionController');

  AelThemeController get _themeController =>
      Get.find<AelThemeController>(tag: 'themeController');

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final source = _controller.themeColorSource;
      final style = _controller.themePaletteStyle;
      final contrast = _controller.themeContrastLevel;
      final seedValue = _controller.themeSeedColorValue;
      final monetSupported = _themeController.supportsPlatformMonet;
      final colors = AelTheme.colorsOf(context);

      final footerText = switch (source) {
        ThemeColorSource.monet =>
          monetSupported
              ? '主题色将跟随系统壁纸自动变化（Material 莫奈动态取色）。'
              : '当前系统不支持读取壁纸取色，已自动使用默认蓝。可改用「自定义主题色」。',
        ThemeColorSource.custom => '点选下方色块，或输入 HEX 色值自定义主题色。',
        ThemeColorSource.defaultBlue => '默认使用晴空蓝；也可切换为莫奈动态取色或自定义。',
      };

      final trailingStyle = TextStyle(
        color: colors.textSecondary,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      );

      return AelSectionCard(
        title: '外观',
        icon: AelIcons.palette,
        trailing: AelChip(label: source.label, tone: AelChipTone.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AelListRow(
              title: '主题色',
              subtitle: source.subtitle,
              icon: AelIcons.palette,
              iconBgColor: colors.primaryContainer,
              iconColor: colors.onPrimaryContainer,
              trailing: Text(source.label, style: trailingStyle),
              onTap: () => _showSourcePicker(context, monetSupported),
            ),
            if (source == ThemeColorSource.custom) ...[
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.tonalTileBg,
                  shape: AelShapes.squircle(AelRadius.tile),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: _SwatchWrap(
                    selectedValue: seedValue,
                    onSelected: (value) =>
                        _controller.themeSeedColorValue = value,
                    onCustom: () => _showHexDialog(context, seedValue),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            AelListRow(
              title: '配色风格',
              subtitle: '决定莫奈/主题色生成整套配色的方式',
              icon: AelIcons.sparkles,
              iconBgColor: colors.primaryContainer,
              iconColor: colors.onPrimaryContainer,
              trailing: Text(style.label, style: trailingStyle),
              onTap: () => _showStylePicker(context),
            ),
            const SizedBox(height: 6),
            AelListRow(
              title: '对比度',
              subtitle: '提高文字与背景对比，便于阅读',
              icon: AelIcons.contrast,
              iconBgColor: colors.primaryContainer,
              iconColor: colors.onPrimaryContainer,
              trailing: Text(contrast.label, style: trailingStyle),
              onTap: () => _showContrastPicker(context),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                footerText,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showSourcePicker(BuildContext context, bool monetSupported) {
    showAelActionSheet<ThemeColorSource>(
      context: context,
      title: '选择主题色来源',
      actions: ThemeColorSource.values.map((value) {
        final unavailable = value == ThemeColorSource.monet && !monetSupported;
        return AelActionOption<ThemeColorSource>(
          value: value,
          label: value.label,
          subtitle: unavailable ? '当前系统不支持，将回退默认蓝' : null,
          isSelected: value == _controller.themeColorSource,
          onTap: () => _controller.themeColorSource = value,
        );
      }).toList(),
    );
  }

  void _showStylePicker(BuildContext context) {
    showAelActionSheet<ThemePaletteStyle>(
      context: context,
      title: '选择配色风格',
      actions: ThemePaletteStyle.values
          .map(
            (value) => AelActionOption<ThemePaletteStyle>(
              value: value,
              label: value.label,
              isSelected: value == _controller.themePaletteStyle,
              onTap: () => _controller.themePaletteStyle = value,
            ),
          )
          .toList(),
    );
  }

  void _showContrastPicker(BuildContext context) {
    showAelActionSheet<ThemeContrastLevel>(
      context: context,
      title: '选择对比度',
      actions: ThemeContrastLevel.values
          .map(
            (value) => AelActionOption<ThemeContrastLevel>(
              value: value,
              label: value.label,
              isSelected: value == _controller.themeContrastLevel,
              onTap: () => _controller.themeContrastLevel = value,
            ),
          )
          .toList(),
    );
  }

  void _showHexDialog(BuildContext context, int currentValue) {
    final rgb = currentValue & 0x00FFFFFF;
    final initialHex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    showAelInputDialog(
      context: context,
      title: '自定义主题色',
      message: '请输入 6 位十六进制色值（不含 #），例如 007AFF',
      initialValue: initialHex,
      placeholder: 'RRGGBB',
      confirmLabel: '应用',
      validator: (raw) {
        final normalized = raw.trim().replaceAll('#', '');
        final parsed = int.tryParse(normalized, radix: 16);
        if (parsed == null || normalized.length != 6) {
          return '请输入 6 位十六进制色值，例如 007AFF';
        }
        return null;
      },
    ).then((result) {
      if (result == null) return;
      final normalized = result.trim().replaceAll('#', '');
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null && normalized.length == 6) {
        _controller.themeSeedColorValue = 0xFF000000 | parsed;
      }
    });
  }
}

class _SwatchWrap extends StatelessWidget {
  const _SwatchWrap({
    required this.selectedValue,
    required this.onSelected,
    required this.onCustom,
  });

  final int selectedValue;
  final ValueChanged<int> onSelected;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final isPreset = AelPalettePresets.presets.any(
      (p) => p.seedColor.toARGB32() == selectedValue,
    );
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final preset in AelPalettePresets.presets)
          _Swatch(
            color: preset.seedColor,
            label: preset.name,
            selected: preset.seedColor.toARGB32() == selectedValue,
            onTap: () => onSelected(preset.seedColor.toARGB32()),
          ),
        _Swatch(
          color: Color(selectedValue),
          label: '自定义',
          selected: !isPreset,
          icon: AelIcons.edit,
          onTap: onCustom,
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final onColor = color.computeLuminance() > 0.5
        ? AelSemanticPalette.pureBlack
        : AelSemanticPalette.pureWhite;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            AnimatedContainer(
              duration: AelDurations.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? onColor.withValues(alpha: 0.9)
                      : AelSemanticPalette.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                selected ? AelIcons.check : icon,
                size: 22,
                color: onColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
