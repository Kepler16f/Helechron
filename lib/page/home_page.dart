import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_miuix/miuix.dart'
    show MiuixLayerBackdrop, MiuixLayerBackdropCapture;
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_tab_bar.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/flow/flow_view.dart';
import 'package:celechron/page/option/option_view.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/update_service.dart';
import 'package:celechron/utils/platform_features.dart';

const List<AelTabItem> _kBarItems = [
  AelTabItem(icon: AelIcons.tabFlow, label: '接下来'),
  AelTabItem(icon: AelIcons.tabCalendar, label: '日程'),
  AelTabItem(icon: AelIcons.tabTask, label: '任务'),
  AelTabItem(icon: AelIcons.tabScholar, label: '学业'),
  AelTabItem(icon: AelIcons.tabOption, label: '设置'),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _indexNum = 0;
  final PageController _pageController = PageController();
  MiuixLayerBackdrop? _glassBackdrop;

  late final List<Widget> _pages = [
    _KeepAlivePage(child: FlowPage()),
    _KeepAlivePage(child: CalendarPage()),
    _KeepAlivePage(child: TaskPage()),
    _KeepAlivePage(child: ScholarPage()),
    _KeepAlivePage(child: OptionPage()),
  ];

  @override
  void initState() {
    super.initState();
    if (!PlatformFeatures.isOhos) {
      _glassBackdrop = MiuixLayerBackdrop();
    }
    OhosNativeService.instance.installNativeTabHandler(_onNativeTabChanged);
    initFuse();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _glassBackdrop?.dispose();
    super.dispose();
  }

  /// 原生底栏点击 → 跳转对应页
  void _onNativeTabChanged(int index) {
    if (index == _indexNum) return;
    if (index < 0 || index >= _pages.length) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.popUntil((route) => route.isFirst);
    }
    _pageController.jumpToPage(index);
  }

  void _selectTab(int index) {
    if (_indexNum == index) return;
    setState(() {
      _indexNum = index;
    });
    _pageController.jumpToPage(index);
    OhosNativeService.instance.setCurrentTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final option = Get.find<Option>(tag: 'option');
    final colors = AelTheme.colorsOf(context);
    return Obx(() {
      final bool useNativeBar = PlatformFeatures.isOhos;
      final bool floating = option.bottomBarFloating.value;
      final bool immersiveLight = option.bottomBarImmersiveLight.value;

      final ScrollBehavior scrollBehavior = ScrollConfiguration.of(context);
      Widget content = HeroMode(
        enabled: false,
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            if (index != _indexNum) {
              setState(() {
                _indexNum = index;
              });
              OhosNativeService.instance.setCurrentTab(index);
            }
          },
          scrollBehavior: scrollBehavior.copyWith(
            scrollbars: false,
            dragDevices: {
              ...scrollBehavior.dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          children: _pages,
        ),
      );

      final MediaQueryData existingMediaQuery = MediaQuery.of(context);
      MediaQueryData newMediaQuery = existingMediaQuery.removeViewInsets(
        removeBottom: true,
      );
      final EdgeInsets contentPadding = EdgeInsets.only(
        bottom: existingMediaQuery.viewInsets.bottom,
      );

      if (floating) {
        const double floatingBarInset =
            AelTabBarSpec.height + AelTabBarSpec.bottomMargin;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: existingMediaQuery.padding.bottom + floatingBarInset,
          ),
        );
      } else {
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: AelTabBarSpec.height + existingMediaQuery.padding.bottom,
          ),
        );
      }

      Widget pageBody = MediaQuery(
        data: newMediaQuery,
        child: Padding(padding: contentPadding, child: content),
      );

      // Android / iOS 悬浮沉浸光感开启时捕获背景图层，供 MiuixGlassNavigationBar 实时折射采样；
      // 鸿蒙端由 ArkTS HdsTabs 原生托管，不在 Flutter 侧做多余的离屏截图。
      final backdrop = _glassBackdrop;
      if (!useNativeBar && floating && immersiveLight && backdrop != null) {
        pageBody = MiuixLayerBackdropCapture(
          backdrop: backdrop,
          child: pageBody,
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(color: colors.pageBg),
        child: Stack(
          children: [
            pageBody,
            if (!useNativeBar)
              MediaQuery.withNoTextScaling(
                child: ValueListenableBuilder<bool>(
                  valueListenable:
                      OhosNativeService.instance.bottomBarVisibleNotifier,
                  builder: (context, visible, child) {
                    return AnimatedSlide(
                      duration: AelDurations.normal,
                      curve: Curves.easeInOutCubic,
                      offset: visible ? Offset.zero : const Offset(0, 1.4),
                      child: AnimatedOpacity(
                        duration: AelDurations.fast,
                        curve: Curves.easeInOut,
                        opacity: visible ? 1.0 : 0.0,
                        child: IgnorePointer(ignoring: !visible, child: child),
                      ),
                    );
                  },
                  child: AelTabBar(
                    items: _kBarItems,
                    currentIndex: _indexNum,
                    onSelect: _selectTab,
                    floating: floating,
                    immersiveLight: immersiveLight,
                    backdrop: backdrop,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Future<void> initFuse() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    if (PlatformFeatures.isAndroid && UpdateService.instance.autoCheckUpdate) {
      await UpdateService.instance.performCheckUpdateFlow(
        context,
        showLoading: false,
        silentIfNoUpdate: true,
      );
    }
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
