import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/theme/ael_theme_controller.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/option/option_controller.dart';

/// 设置页「外观」分组：主题色来源（默认蓝 / 莫奈 / 自定义）、预设色板、配色风格、对比度。
///
/// 作为设置页内新增的一个分组插入，不改变设置页其他结构。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({
    super.key,
    required this.headerStyle,
    required this.trailingStyle,
    required this.margin,
  });

  final TextStyle headerStyle;
  final TextStyle trailingStyle;
  final EdgeInsetsGeometry margin;

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
      final activeSeed = AelTheme.of(context).seedColor;
      final colors = AelTheme.colorsOf(context);

      final footerText = switch (source) {
        ThemeColorSource.monet => monetSupported
            ? '主题色将跟随系统壁纸自动变化（Material 莫奈动态取色）。'
            : '当前系统不支持读取壁纸取色，已自动使用默认蓝。可改用「自定义主题色」。',
        ThemeColorSource.custom => '点选下方色块，或输入 HEX 色值自定义主题色。',
        ThemeColorSource.defaultBlue => '默认使用晴空蓝；也可切换为莫奈动态取色或自定义。',
      };

      return CupertinoListSection.insetGrouped(
        margin: margin,
        additionalDividerMargin: 2,
        header: Container(
          padding: const EdgeInsets.only(left: 16),
          child: Text('外观', style: headerStyle),
        ),
        footer: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(footerText, style: headerStyle),
        ),
        children: <Widget>[
          CupertinoListTile(
            leading: _leadingIcon(AelIcons.palette, activeSeed),
            title: const Text('主题色'),
            subtitle: Text(source.subtitle),
            trailing: _chevronRow(
              Text(source.label, style: trailingStyle),
              colors.textTertiary,
            ),
            onTap: () => _showSourcePicker(context, monetSupported),
          ),
          if (source == ThemeColorSource.custom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _SwatchWrap(
                selectedValue: seedValue,
                onSelected: (value) => _controller.themeSeedColorValue = value,
                onCustom: () => _showHexDialog(context, seedValue),
              ),
            ),
          CupertinoListTile(
            leading: _leadingIcon(AelIcons.sparkles, activeSeed),
            title: const Text('配色风格'),
            subtitle: const Text('决定莫奈/主题色生成整套配色的方式'),
            trailing: _chevronRow(
              Text(style.label, style: trailingStyle),
              colors.textTertiary,
            ),
            onTap: () => _showStylePicker(context),
          ),
          CupertinoListTile(
            leading: _leadingIcon(AelIcons.contrast, activeSeed),
            title: const Text('对比度'),
            subtitle: const Text('提高文字与背景对比，便于阅读'),
            trailing: _chevronRow(
              Text(contrast.label, style: trailingStyle),
              colors.textTertiary,
            ),
            onTap: () => _showContrastPicker(context),
          ),
        ],
      );
    });
  }

  Widget _leadingIcon(IconData icon, Color color) {
    return Icon(icon, size: 22, color: color);
  }

  Widget _chevronRow(Widget child, Color chevronColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(width: 4),
        Icon(AelIcons.chevronRight, size: 18, color: chevronColor),
      ],
    );
  }

  void _showSourcePicker(BuildContext context, bool monetSupported) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return CupertinoActionSheet(
          title: const Text('选择主题色来源'),
          actions: ThemeColorSource.values.map((value) {
            final unavailable =
                value == ThemeColorSource.monet && !monetSupported;
            return CupertinoActionSheetAction(
              isDefaultAction: value == _controller.themeColorSource,
              onPressed: () {
                _controller.themeColorSource = value;
                Navigator.pop(sheetContext);
              },
              child: Text(
                unavailable ? '${value.label}（当前系统不支持，将回退默认蓝）' : value.label,
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  void _showStylePicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return CupertinoActionSheet(
          title: const Text('选择配色风格'),
          actions: ThemePaletteStyle.values
              .map((value) => CupertinoActionSheetAction(
                    isDefaultAction: value == _controller.themePaletteStyle,
                    onPressed: () {
                      _controller.themePaletteStyle = value;
                      Navigator.pop(sheetContext);
                    },
                    child: Text(value.label),
                  ))
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  void _showContrastPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return CupertinoActionSheet(
          title: const Text('选择对比度'),
          actions: ThemeContrastLevel.values
              .map((value) => CupertinoActionSheetAction(
                    isDefaultAction: value == _controller.themeContrastLevel,
                    onPressed: () {
                      _controller.themeContrastLevel = value;
                      Navigator.pop(sheetContext);
                    },
                    child: Text(value.label),
                  ))
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  void _showHexDialog(BuildContext context, int currentValue) {
    final rgb = currentValue & 0x00FFFFFF;
    final textController = TextEditingController(
      text: rgb.toRadixString(16).padLeft(6, '0').toUpperCase(),
    );
    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return CupertinoAlertDialog(
              title: const Text('自定义主题色'),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: textController,
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('#'),
                      ),
                      placeholder: 'RRGGBB',
                      maxLength: 6,
                      autocorrect: false,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: AelTheme.colorsOf(context).error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('应用'),
                  onPressed: () {
                    final parsed = int.tryParse(
                      textController.text.trim().replaceAll('#', ''),
                      radix: 16,
                    );
                    if (parsed == null || textController.text.trim().length != 6) {
                      setState(() => error = '请输入 6 位十六进制色值，例如 007AFF');
                      return;
                    }
                    _controller.themeSeedColorValue = 0xFF000000 | parsed;
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) => textController.dispose());
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
    final isPreset = AelPalettePresets.presets
        .any((p) => p.seedColor.toARGB32() == selectedValue);
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
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
