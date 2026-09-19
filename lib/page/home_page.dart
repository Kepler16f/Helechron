import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/model/option.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/page/flow/flow_view.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/option/option_view.dart';

import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/worker/fuse.dart';

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
      final bool floating = option.bottomBarFloating.value;

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
        const double nativeBarHeight = 56.0;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: nativeBarHeight + existingMediaQuery.padding.bottom,
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
          ],
        ),
      );
    });
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
                  child: const Text('访问网站'),
                  onPressed: () async {
                    await launchUrlString(
                      'https://celechron.top',
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
