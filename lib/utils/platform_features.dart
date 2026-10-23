import 'dart:io';

final class PlatformFeatures {
  static bool get hasBackgroundRefresh {
    return isOhos || isAndroid || isIOS;
  }

  static bool get hasNotificationSupport {
    return isOhos || isAndroid || isIOS;
  }

  static bool get hasWidgetSupport {
    return false;
  }

  static bool get isMobile {
    return isOhos || isAndroid || isIOS;
  }

  static bool get isDesktop {
    return false;
  }

  static bool get isOhos {
    return Platform.operatingSystem == 'ohos';
  }

  static bool get isAndroid {
    return Platform.isAndroid;
  }

  static bool get isIOS {
    return Platform.isIOS;
  }

  /// Android / iOS：使用 Flutter 插件实现原生能力（日历、通知、文件选择等）。
  static bool get usesFlutterPlugins {
    return isAndroid || isIOS;
  }
}
