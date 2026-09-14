import 'dart:io';

final class PlatformFeatures {
  static bool get hasBackgroundRefresh {
    return false;
  }

  static bool get hasWidgetSupport {
    return false;
  }

  static bool get isMobile {
    return Platform.operatingSystem == 'ohos';
  }

  static bool get isDesktop {
    return false;
  }

  static bool get isOhos {
    return Platform.operatingSystem == 'ohos';
  }
}
