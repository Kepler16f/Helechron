import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/platform_features.dart';

/// 全局主题控制器：管理 Android 12+ 莫奈壁纸取色缓存，
/// 并负责把最终生效的主色同步到鸿蒙 ArkTS 原生底栏（保留原生沉浸材质）。
class AelThemeController extends GetxController {
  final Rxn<Color> platformMonetSeed = Rxn<Color>();
  final RxBool monetChecked = false.obs;

  String? _lastSyncedPrimaryHex;

  bool get supportsPlatformMonet => PlatformFeatures.isAndroid;

  @override
  void onInit() {
    super.onInit();
    unawaited(refreshPlatformMonetSeed());
  }

  /// 探测平台莫奈种子色（仅 Android 12+ 支持系统壁纸取色；iOS / 鸿蒙自动回退）。
  Future<void> refreshPlatformMonetSeed() async {
    if (!PlatformFeatures.isAndroid) {
      monetChecked.value = true;
      return;
    }
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        platformMonetSeed.value = Color(corePalette.primary.get(40));
        monetChecked.value = true;
        return;
      }
      final accent = await DynamicColorPlugin.getAccentColor();
      if (accent != null) {
        platformMonetSeed.value = accent;
      }
    } catch (e) {
      debugPrint('AelThemeController.refreshPlatformMonetSeed failed: $e');
    } finally {
      monetChecked.value = true;
    }
  }

  ResolvedAelThemeBundle resolveForOption(
    Option option, {
    required Brightness platformBrightness,
  }) {
    final brightness = switch (option.brightnessMode.value) {
      BrightnessMode.system => platformBrightness,
      BrightnessMode.light => Brightness.light,
      BrightnessMode.dark => Brightness.dark,
    };
    return AelThemeEngine.resolve(
      brightness: brightness,
      source: option.themeColorSource.value,
      customSeed: Color(option.themeSeedColorValue.value),
      paletteStyle: option.themePaletteStyle.value,
      contrastLevel: option.themeContrastLevel.value,
      platformMonetSeed: platformMonetSeed.value,
    );
  }

  /// 将当前生效的主色同步到鸿蒙 ArkTS 原生底栏（去重避免重复调用通道）。
  void syncNativeAccent(Option option, ResolvedAelThemeBundle bundle) {
    if (!PlatformFeatures.isOhos) return;
    final hex = bundle.aelTheme.colors.primaryHex;
    if (_lastSyncedPrimaryHex == hex) return;
    _lastSyncedPrimaryHex = hex;
    unawaited(
      OhosNativeService.instance.setBottomBarStyle(
        floating: option.bottomBarFloating.value,
        immersiveLight: option.bottomBarImmersiveLight.value,
        materialLevel: option.bottomBarMaterialLevel.value,
        primaryColorHex: hex,
      ),
    );
  }
}
