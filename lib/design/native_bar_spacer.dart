import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../model/option.dart';

/// 原生底栏（悬浮或普通）在系统安全区之上额外占用的高度：
/// 悬浮模式 = 底部外边距 8 + 栏高 56；普通模式 = 栏高 56。
///
/// 二级页面通过 `Navigator.of(context, rootNavigator: true)` 推入，
/// 是 HomePage 的兄弟路由，不会继承 home_page.dart 中调整过的 MediaQuery，
/// 因此必须直接读取 Option 计算底栏占位。
double nativeBottomBarInset() {
  try {
    final option = Get.find<Option>(tag: 'option');
    return option.bottomBarFloating.value ? 64 : 56;
  } catch (_) {
    return 0;
  }
}

/// 给被原生底栏遮挡的滚动页面提供底部留白，
/// 高度 = 系统安全区 + 原生底栏占位 + [extra]。
class NativeBottomBarSpacer extends StatelessWidget {
  final double extra;

  const NativeBottomBarSpacer({super.key, this.extra = 16});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SizedBox(
        height: MediaQuery.paddingOf(context).bottom +
            nativeBottomBarInset() +
            extra,
      ),
    );
  }
}
