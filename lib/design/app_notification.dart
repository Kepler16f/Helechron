import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:celechron/model/option.dart';

/// 统一的应用内悬浮弹出通知组件。
///
/// 具备完整的深色/浅色模式自适应能力：
/// 1. 自动跟随全局主题切换文字颜色（浅色深字、深色浅字）与半透明磨砂亚克力容器背景；
/// 2. 避免原生 Get.snackbar 默认不适配深浅色导致的黑底黑字或反白不可读问题；
/// 3. 提供统一的 success / error / info / custom 预设，后续所有新加的通知均可直接调用此组件实现自动适配。
class AppNotification {
  AppNotification._();

  /// 判断当前应用是否处于深色模式
  static bool get isDark {
    final ctx = Get.context;
    if (ctx != null) {
      try {
        return CupertinoTheme.brightnessOf(ctx) == Brightness.dark;
      } catch (_) {}
    }
    if (Get.isRegistered<Option>(tag: 'option')) {
      final mode = Get.find<Option>(tag: 'option').brightnessMode.value;
      if (mode == BrightnessMode.dark) return true;
      if (mode == BrightnessMode.light) return false;
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  /// 弹出通用应用内通知
  static void show({
    required String title,
    required String message,
    Widget? icon,
    Duration duration = const Duration(seconds: 3),
    SnackPosition snackPosition = SnackPosition.TOP,
    VoidCallback? onTap,
  }) {
    final bool dark = isDark;

    final Color bgColor = dark
        ? const Color(0xF22C2C2E)
        : const Color(0xF2FFFFFF);
    final Color titleColor = dark
        ? const Color(0xFFF2F2F7)
        : const Color(0xFF1C1C1E);
    final Color messageColor = dark
        ? const Color(0xD9EBEBF5)
        : const Color(0x993C3C43);
    final Color borderColor = dark
        ? const Color(0x33FFFFFF)
        : const Color(0x1F000000);

    Get.showSnackbar(
      GetSnackBar(
        titleText: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: titleColor,
            letterSpacing: -0.2,
          ),
        ),
        messageText: Text(
          message,
          style: TextStyle(fontSize: 13.5, color: messageColor, height: 1.35),
        ),
        icon: icon != null
            ? Padding(
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: icon,
              )
            : null,
        snackPosition: snackPosition,
        duration: duration,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 16,
        backgroundColor: bgColor,
        borderColor: borderColor,
        borderWidth: 0.8,
        boxShadows: [
          BoxShadow(
            color: dark ? const Color(0x66000000) : const Color(0x1A000000),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
        onTap: onTap != null ? (_) => onTap() : null,
        isDismissible: true,
        animationDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  /// 成功类通知（绿色勾选图标）
  static void success(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackPosition snackPosition = SnackPosition.TOP,
    VoidCallback? onTap,
  }) {
    show(
      title: title,
      message: message,
      icon: const Icon(
        CupertinoIcons.checkmark_alt_circle_fill,
        color: CupertinoColors.systemGreen,
        size: 24,
      ),
      duration: duration,
      snackPosition: snackPosition,
      onTap: onTap,
    );
  }

  /// 错误/失败类通知（红色警告图标）
  static void error(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackPosition snackPosition = SnackPosition.TOP,
    VoidCallback? onTap,
  }) {
    show(
      title: title,
      message: message,
      icon: const Icon(
        CupertinoIcons.exclamationmark_circle_fill,
        color: CupertinoColors.systemRed,
        size: 24,
      ),
      duration: duration,
      snackPosition: snackPosition,
      onTap: onTap,
    );
  }

  /// 提示/信息类通知（蓝色感叹号图标）
  static void info(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackPosition snackPosition = SnackPosition.TOP,
    VoidCallback? onTap,
  }) {
    show(
      title: title,
      message: message,
      icon: const Icon(
        CupertinoIcons.info_circle_fill,
        color: CupertinoColors.activeBlue,
        size: 24,
      ),
      duration: duration,
      snackPosition: snackPosition,
      onTap: onTap,
    );
  }
}
