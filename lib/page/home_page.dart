import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_responsive.dart';
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
  final ValueNotifier<int> _activeIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();

  late final List<Widget> _pages = [
    _KeepAlivePage(
      tabIndex: 0,
      activeIndexListenable: _activeIndex,
      child: FlowPage(),
    ),
    _KeepAlivePage(
      tabIndex: 1,
      activeIndexListenable: _activeIndex,
      child: CalendarPage(),
    ),
    _KeepAlivePage(
      tabIndex: 2,
      activeIndexListenable: _activeIndex,
      child: TaskPage(),
    ),
    _KeepAlivePage(
      tabIndex: 3,
      activeIndexListenable: _activeIndex,
      child: ScholarPage(),
    ),
    _KeepAlivePage(
      tabIndex: 4,
      activeIndexListenable: _activeIndex,
      child: OptionPage(),
    ),
  ];

  int get _indexNum => _activeIndex.value;

  @override
  void initState() {
    super.initState();
    OhosNativeService.instance.installNativeTabHandler(_onNativeTabChanged);
    initFuse();
  }

  @override
  void dispose() {
    _activeIndex.dispose();
    _pageController.dispose();
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
    _activeIndex.value = index;
    _pageController.jumpToPage(index);
  }

  void _selectTab(int index) {
    if (_indexNum == index) return;
    setState(() {
      _activeIndex.value = index;
    });
    _pageController.jumpToPage(index);
    if (PlatformFeatures.isOhos) {
      OhosNativeService.instance.setCurrentTab(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final option = Get.find<Option>(tag: 'option');
    final colors = AelTheme.colorsOf(context);
    final bool useSideRail = AelResponsive.useSideRail(context);
    final bool isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return Obx(() {
      final bool useNativeBar = PlatformFeatures.isOhos;
      final bool floating = option.bottomBarFloating.value;
      final bool immersiveLight = option.bottomBarImmersiveLight.value;
      final int materialLevel = option.bottomBarMaterialLevel.value;

      final ScrollBehavior scrollBehavior = ScrollConfiguration.of(context);
      final Widget content = HeroMode(
        enabled: false,
        child: PageView(
          controller: _pageController,
          physics: useSideRail ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (index) {
            if (index != _indexNum) {
              setState(() {
                _activeIndex.value = index;
              });
              if (PlatformFeatures.isOhos) {
                OhosNativeService.instance.setCurrentTab(index);
              }
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

      if (useSideRail) {
        // 左侧导航栏已占去左安全区，正文中移除多余 left padding 防止二次缩进，也不再叠加底栏高度。
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            left: 0,
            bottom: existingMediaQuery.padding.bottom,
          ),
        );
      } else if (floating) {
        final double floatingBarInset = useNativeBar
            ? AelTabBarSpec.height + AelTabBarSpec.bottomMargin
            : AelTabBarSpec.dockHeight + AelTabBarSpec.dockBottomMargin;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: existingMediaQuery.padding.bottom + floatingBarInset,
          ),
        );
      } else {
        final double dockedBarInset = useNativeBar
            ? AelTabBarSpec.height
            : AelTabBarSpec.dockedBarHeight;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: dockedBarInset + existingMediaQuery.padding.bottom,
          ),
        );
      }

      final Widget pageBody = MediaQuery(
        data: newMediaQuery,
        child: Padding(padding: contentPadding, child: content),
      );

      if (useSideRail) {
        final double nativeRailSpacerWidth =
            AelTabBarSpec.sideRailWidth + existingMediaQuery.padding.left;
        return DecoratedBox(
          decoration: BoxDecoration(color: colors.pageBg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!useNativeBar)
                MediaQuery.withNoTextScaling(
                  child: AelSideRail(
                    items: _kBarItems,
                    currentIndex: _indexNum,
                    onSelect: _selectTab,
                    floating: floating,
                    immersiveLight: immersiveLight,
                    materialLevel: materialLevel,
                    captureActive: isRouteCurrent,
                  ),
                )
              else
                SizedBox(width: nativeRailSpacerWidth),
              Expanded(child: pageBody),
            ],
          ),
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(color: colors.pageBg),
        child: Stack(
          children: [
            pageBody,
            if (!useNativeBar)
              MediaQuery.withNoTextScaling(
                child: Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
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
                          child: IgnorePointer(
                            ignoring: !visible,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: AelTabBar(
                      items: _kBarItems,
                      currentIndex: _indexNum,
                      onSelect: _selectTab,
                      floating: floating,
                      immersiveLight: immersiveLight,
                      materialLevel: materialLevel,
                      captureActive: isRouteCurrent,
                    ),
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
  const _KeepAlivePage({
    required this.tabIndex,
    required this.activeIndexListenable,
    required this.child,
  });

  final int tabIndex;
  final ValueNotifier<int> activeIndexListenable;
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
    return ValueListenableBuilder<int>(
      valueListenable: widget.activeIndexListenable,
      builder: (context, activeIndex, child) {
        return TickerMode(
          enabled: activeIndex == widget.tabIndex,
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}
