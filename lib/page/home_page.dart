import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show Icons;
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

  /// 原生悬浮底栏点击 → 跳转对应页
  void _onNativeTabChanged(int index) {
    if (index == _indexNum) return;
    if (index < 0 || index >= _pages.length) return;
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final option = Get.find<Option>(tag: 'option');
    return Obx(() {
      final bool floating = option.bottomBarFloating.value;

      final tabBar = CupertinoTabBar(
        iconSize: 26,
        backgroundColor: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemBackground, context)
            .withValues(alpha: 0.5),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.time),
            label: '接下来',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: '日程',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.check_mark),
            label: '任务',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_rounded),
            label: '学业',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: '设置',
          ),
        ],
        currentIndex: _indexNum,
        onTap: (int index) => _pageController.jumpToPage(index),
      );

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
        // 原生悬浮底栏（56 高 + 12 底距）占位，内容底部留白避免被遮挡
        const double nativeBarSpace = 76.0;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(
            bottom: existingMediaQuery.padding.bottom + nativeBarSpace,
          ),
        );
      } else if (tabBar.preferredSize.height >
          existingMediaQuery.viewInsets.bottom) {
        final double bottomPadding =
            tabBar.preferredSize.height + existingMediaQuery.padding.bottom;
        newMediaQuery = newMediaQuery.copyWith(
          padding: newMediaQuery.padding.copyWith(bottom: bottomPadding),
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
            // 悬浮底栏开启时由原生渲染，隐藏 Flutter 底栏避免重叠
            if (!floating)
              MediaQuery.withNoTextScaling(
                child: Align(alignment: Alignment.bottomCenter, child: tabBar),
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
