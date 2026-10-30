import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/model/option.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/flow/flow_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/option/option_view.dart';

import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/worker/fuse.dart';
import 'package:celechron/utils/legal_links.dart';

class _BarItemDef {
  final IconData icon;
  final String label;
  const _BarItemDef({required this.icon, required this.label});
}

const List<_BarItemDef> _kBarItems = [
  _BarItemDef(icon: CupertinoIcons.time, label: '接下来'),
  _BarItemDef(icon: CupertinoIcons.calendar, label: '日程'),
  _BarItemDef(icon: CupertinoIcons.check_mark, label: '任务'),
  _BarItemDef(icon: Icons.school_rounded, label: '学业'),
  _BarItemDef(icon: CupertinoIcons.settings, label: '设置'),
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
    OhosNativeService.instance.installNativeTabHandler(_onNativeTabChanged);
    initFuse();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 原生底栏点击 → 跳转对应页
  void _onNativeTabChanged(int index) {
    if (index == _indexNum) return;
    if (index < 0 || index >= _pages.length) return;
    // 如果当前有子页面在栈上，先返回主页再切换 Tab
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.popUntil((route) => route.isFirst);
    }
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final option = Get.find<Option>(tag: 'option');
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
      MediaQueryData newMediaQuery =
          existingMediaQuery.removeViewInsets(removeBottom: true);
      final EdgeInsets contentPadding =
          EdgeInsets.only(bottom: existingMediaQuery.viewInsets.bottom);

      if (floating) {
        // 悬浮底栏：可滚动内容底部预留栏高，使最后一个条目能继续滚动到
        // 悬浮底栏上方；页面用 SafeArea(bottom:false) 把该值交给
        // CustomScrollView 作为 SliverPadding，内容仍延伸到栏后方（镂空）。
        const double floatingBarInset = 64.0; // 底部外边距 8 + 栏高 56
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: existingMediaQuery.padding.bottom + floatingBarInset,
          ),
        );
      } else {
        // 普通原生底栏：底部留出栏高，避免内容被遮挡
        const double barHeight = 56.0;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: barHeight + existingMediaQuery.padding.bottom,
          ),
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            MediaQuery(
              data: newMediaQuery,
              child: Padding(padding: contentPadding, child: content),
            ),
            if (!useNativeBar)
              _buildFlutterBottomBar(
                context: context,
                existingMediaQuery: existingMediaQuery,
                floating: floating,
                immersiveLight: immersiveLight,
              ),
          ],
        ),
      );
    });
  }

  Widget _buildFlutterBottomBar({
    required BuildContext context,
    required MediaQueryData existingMediaQuery,
    required bool floating,
    required bool immersiveLight,
  }) {
    final Brightness brightness = CupertinoTheme.brightnessOf(context);
    final bool isDark = brightness == Brightness.dark;

    final Widget barWidget = floating
        ? _buildFloatingBarCapsule(
            context: context,
            existingMediaQuery: existingMediaQuery,
            isDark: isDark,
            immersiveLight: immersiveLight,
          )
        : _buildDockedBar(
            context: context,
            existingMediaQuery: existingMediaQuery,
            isDark: isDark,
          );

    return MediaQuery.withNoTextScaling(
      child: ValueListenableBuilder<bool>(
        valueListenable: OhosNativeService.instance.bottomBarVisibleNotifier,
        builder: (context, visible, child) {
          return AnimatedSlide(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOutCubic,
            offset: visible ? Offset.zero : const Offset(0, 1.4),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              opacity: visible ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !visible,
                child: child,
              ),
            ),
          );
        },
        child: barWidget,
      ),
    );
  }

  Widget _buildFloatingBarCapsule({
    required BuildContext context,
    required MediaQueryData existingMediaQuery,
    required bool isDark,
    required bool immersiveLight,
  }) {
    final double screenWidth = existingMediaQuery.size.width;
    final double capsuleWidth = math.min(screenWidth * 0.92, 500.0);

    final Color bgColor = isDark
        ? (immersiveLight ? const Color(0x991E1E22) : const Color(0xDE222226))
        : (immersiveLight ? const Color(0x88FFFFFF) : const Color(0xDEFFFFFF));

    final Color borderColor =
        isDark ? const Color(0x33FFFFFF) : const Color(0x55FFFFFF);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          bottom: existingMediaQuery.padding.bottom + 8.0,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: capsuleWidth,
            minWidth: 260.0,
            minHeight: 56.0,
            maxHeight: 56.0,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 18.0,
                  offset: Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: borderColor,
                width: 0.75,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: immersiveLight ? 28.0 : 20.0,
                  sigmaY: immersiveLight ? 28.0 : 20.0,
                ),
                child: Container(
                  color: bgColor,
                  child: _buildBarItemsRow(context, floating: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockedBar({
    required BuildContext context,
    required MediaQueryData existingMediaQuery,
    required bool isDark,
  }) {
    final Color separatorColor =
        CupertinoColors.separator.resolveFrom(context).withValues(alpha: 0.35);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        height: 56.0 + existingMediaQuery.padding.bottom,
        padding: EdgeInsets.only(bottom: existingMediaQuery.padding.bottom),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: separatorColor, width: 0.5),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemBackground,
                context,
              ).withValues(alpha: 0.85),
              child: _buildBarItemsRow(context, floating: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarItemsRow(BuildContext context, {required bool floating}) {
    final Color activeColor = CupertinoTheme.of(context).primaryColor;
    final Color inactiveColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);

    return Row(
      children: List.generate(_kBarItems.length, (index) {
        final bool isSelected = _indexNum == index;
        final Color itemColor = isSelected ? activeColor : inactiveColor;
        final item = _kBarItems[index];

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              if (_indexNum != index) {
                setState(() {
                  _indexNum = index;
                });
                _pageController.jumpToPage(index);
                OhosNativeService.instance.setCurrentTab(index);
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: floating ? 21.0 : 23.0,
                  color: itemColor,
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: floating ? 10.0 : 10.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: itemColor,
                    height: 1.1,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> initFuse() async {
    await Future.delayed(const Duration(seconds: 1));
    var fuse = Get.find<Rx<Fuse>>(tag: 'fuse');
    var response =
        await fuse.value.checkUpdate().whenComplete(() => fuse.refresh());
    if (response != null) {
      if (!mounted) return;
      showCupertinoDialog(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: const Text('更新可用'),
              content: Text(response),
              actions: [
                CupertinoDialogAction(
                  child: const Text('忽略'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoDialogAction(
                  child: const Text('查看 Helechron 发布'),
                  onPressed: () async {
                    await launchUrlString(
                      releasesUrl,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            );
          });
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
