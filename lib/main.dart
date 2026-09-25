import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/page/home_page.dart';
import 'package:celechron/page/option/ecard_pay_page.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/refresh_coordinator.dart';
import 'package:celechron/services/scholar_widget_sync.dart';
import 'package:celechron/worker/ecard_widget_messenger.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/global.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/platform_features.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获 Flutter 未处理异常并写入诊断日志，便于定位闪退（可在「测试日志」查看）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: 'flutter',
      operation: 'uncaughtError',
      message: details.context?.toString(),
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  ECardWidgetMessenger.installNativeHandler();
  OhosNativeService.instance.installWidgetRouteHandler(_handleWidgetRoute);
  OhosNativeService.instance.installBackPressedHandler(_handleBackPressed);

  // 尽可能早地声明前台活跃
  await RefreshCoordinator.setForegroundActive(true);

  // 初始化数据库
  await Hive.initFlutter();
  var db = Get.put(DatabaseHelper(), tag: 'db');
  await db.init();

  // 注入数据观察项（相当于事件总线，更新这些变量将导致Widget重绘
  Get.put((await db.getScholar()).obs, tag: 'scholar');
  Get.put(db.getTaskList().obs, tag: 'taskList');
  Get.put(db.getTaskListUpdateTime().obs, tag: 'taskListLastUpdate');
  Get.put(db.getFlowList().obs, tag: 'flowList');
  Get.put(db.getFlowListUpdateTime().obs, tag: 'flowListLastUpdate');
  Get.put(db.getOption(), tag: 'option');

  // 将底栏样式同步到原生
  final option = Get.find<Option>(tag: 'option');
  OhosNativeService.instance.setBottomBarStyle(
    floating: option.bottomBarFloating.value,
    immersiveLight: option.bottomBarImmersiveLight.value,
    materialLevel: option.bottomBarMaterialLevel.value,
  );

  Get.put(db.getFuse().obs, tag: 'fuse');

  runApp(const CelechronApp());

  // 应用级课程小组件同步：独立于页面生命周期，进程存活期间持续刷新，
  // 保证下课能及时切换到下一节课。主动刷新走 updateForm，不计入系统
  // 50 次/天配额，因此用 5 秒高频推送让倒计时尽量平滑；应用不在时由
  // 原生侧 updateDuration(30min) + 边界预调度兜底。
  ScholarWidgetSync.sync();
  Timer.periodic(
    const Duration(seconds: 5),
    (_) => ScholarWidgetSync.sync(),
  );

  var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  if (scholar.value.isLogan) {
    unawaited(
      _refreshRestoredScholar(scholar)
          .whenComplete(ECardWidgetMessenger.update)
          .whenComplete(ECardWidgetMessenger.updatePaymentCode),
    );
  } else {
    unawaited(ECardWidgetMessenger.update());
    unawaited(ECardWidgetMessenger.updatePaymentCode());
  }

  // 领取冷启动时由小组件传入的待处理路由
  unawaited(_consumePendingWidgetRoute());
}

/// 处理来自桌面小组件的点击跳转
void _handleWidgetRoute(String target) {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    return;
  }
  if (target == 'ecardpaypage') {
    navigator.popUntil((route) => route.isFirst);
    navigator.pushNamed('/ecardpaypage');
  }
}

/// 全面屏手势侧滑返回 / 系统返回键拦截：
/// 1. 若当前有 GetX 弹窗 (Get.isDialogOpen) 或底部弹层 (Get.isBottomSheetOpen)，优先关闭它并返回 true
/// 2. 若当前根导航器 (navigatorKey.currentState) 栈上有可 pop 的路由（包括所有 CupertinoDialog、CupertinoModalPopup、二级 PageRoute 等），
///    调用 maybePop() 关闭上一级，返回 true
/// 3. 若处于根页面首页且无弹窗，返回 false，交由系统退出或切入后台
Future<bool> _handleBackPressed() async {
  // 1. 优先关闭 GetX 弹窗或底部 Sheet
  if (Get.isDialogOpen == true) {
    Get.back();
    return true;
  }
  if (Get.isBottomSheetOpen == true) {
    Get.back();
    return true;
  }

  // 2. 检查全局 NavigatorState 栈
  final navigator = navigatorKey.currentState;
  if (navigator != null && navigator.canPop()) {
    return await navigator.maybePop();
  }

  // 3. 根页面且无弹窗，允许系统退出/退后台
  return false;
}

Future<void> _consumePendingWidgetRoute() async {
  final target = await OhosNativeService.instance.consumePendingRoute();
  if (target == null) {
    return;
  }
  WidgetsBinding.instance
      .addPostFrameCallback((_) => _handleWidgetRoute(target));
}

Future<void> _refreshRestoredScholar(Rx<Scholar> scholar) async {
  GlobalStatus.isFirstScreenReq = true;
  try {
    await scholar.value.refresh(onPartialUpdate: scholar.refresh);
  } on Object catch (error, stackTrace) {
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.error,
      module: 'refresh',
      operation: 'startupRefresh',
      message: '启动自动刷新异常结束',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    GlobalStatus.isFirstScreenReq = false;
    scholar.refresh();
  }
}

/// 监听路由栈变化（弹窗 / 二级页面 / 对话框 / 底部选择器），精准同步原生底栏的显隐：
/// 1. 仅在处于根页面 (HomePage) 且没有弹窗/对话框/底部选择器时才显示原生底栏
/// 2. 进入任何二级页面 (PageRoute) 时自动隐藏原生底栏，避免遮挡二级页面底部内容及二级页面弹窗
/// 3. 弹出任何模态弹窗 (PopupRoute: ActionSheet/对话框/时间选择器等) 时自动隐藏底栏
/// 4. 模态窗口全部关闭且回到首页后，恢复底栏显示
class _NativeBarVisibilityObserver extends NavigatorObserver {
  static _NativeBarVisibilityObserver? instance;

  final Set<Route<dynamic>> _popupRoutes = {};
  final Set<Route<dynamic>> _pageRoutes = {};
  bool _isSnackbarActive = false;

  _NativeBarVisibilityObserver() {
    instance = this;
  }

  void setSnackbarActive(bool active) {
    if (_isSnackbarActive != active) {
      _isSnackbarActive = active;
      _sync();
    }
  }

  void _sync() {
    // 只有在根页面（只有1个页面路由）且没有任何PopupRoute（弹窗/选择器/对话框）且无底层通知时，才显示原生底栏
    final bool shouldShow = _pageRoutes.length <= 1 &&
        _popupRoutes.isEmpty &&
        !_isSnackbarActive;
    OhosNativeService.instance.setBottomBarVisible(shouldShow);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) {
      _popupRoutes.add(route);
    } else {
      _pageRoutes.add(route);
    }
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PopupRoute) {
      _popupRoutes.remove(route);
    } else {
      _pageRoutes.remove(route);
    }
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _popupRoutes.remove(route);
    _pageRoutes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) {
      _popupRoutes.remove(oldRoute);
      _pageRoutes.remove(oldRoute);
    }
    if (newRoute != null) {
      if (newRoute is PopupRoute) {
        _popupRoutes.add(newRoute);
      } else {
        _pageRoutes.add(newRoute);
      }
    }
    _sync();
  }
}

class CelechronApp extends StatefulWidget {
  const CelechronApp({super.key});

  @override
  State<CelechronApp> createState() => _CelechronAppState();
}

class _CelechronAppState extends State<CelechronApp>
    with WidgetsBindingObserver {
  Timer? _foregroundLeaseHeartbeat;
  final _nativeBarVisibilityObserver = _NativeBarVisibilityObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundLease();

    // 监听AppLinks，用于跳转至付款码页面
    _initAppLinks();

    // 在鸿蒙平台上尝试预热通知权限
    if (PlatformFeatures.isOhos) {
      _initOhosNotification();
    }
  }

  void _initOhosNotification() async {
    final option = Get.find<Option>(tag: 'option');
    if (option.pushOnGradeChange.value || option.pushOnDdlReminder.value) {
      await OhosNativeService.instance.requestNotificationPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundLease();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    return await _handleBackPressed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundLease();
      unawaited(_consumePendingWidgetRoute());
      // 回到前台立即刷新一次（定时器可能已被系统挂起）
      ScholarWidgetSync.sync();
      unawaited(ECardWidgetMessenger.updatePaymentCode());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopForegroundLease();
      // 离开前台时补一次推送
      ScholarWidgetSync.sync();
    }
    if (state == AppLifecycleState.paused) {
      ECardWidgetMessenger.update();
      ECardWidgetMessenger.updatePaymentCode();
    }
  }

  void _startForegroundLease() {
    unawaited(RefreshCoordinator.setForegroundActive(true));
    _foregroundLeaseHeartbeat ??= Timer.periodic(
      RefreshCoordinator.foregroundHeartbeatInterval,
      (_) => unawaited(RefreshCoordinator.setForegroundActive(true)),
    );
  }

  void _stopForegroundLease() {
    _foregroundLeaseHeartbeat?.cancel();
    _foregroundLeaseHeartbeat = null;
    unawaited(RefreshCoordinator.setForegroundActive(false));
  }

  @override
  Widget build(BuildContext context) {
    var brightnessMode = Get.find<Option>(tag: 'option').brightnessMode;
    return Obx(() => GetCupertinoApp(
          theme: CupertinoThemeData(
            brightness: brightnessMode.value == BrightnessMode.system
                ? null
                : brightnessMode.value == BrightnessMode.dark
                    ? Brightness.dark
                    : Brightness.light,
            scaffoldBackgroundColor: CupertinoColors.systemBackground,
            barBackgroundColor: CupertinoColors.systemBackground,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          locale: const Locale('zh'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          title: 'Helechron',
          home: const HomePage(title: 'Helechron'),
          initialRoute: '/',
          routes: {
            '/ecardpaypage': (context) => ECardPayPage(),
          },
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          navigatorObservers: [_nativeBarVisibilityObserver],
        ));
  }

  void _initAppLinks() {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((uri) {
      if (uri.toString() == 'celechron://ecardpaypage') {
        navigator?.popUntil((route) =>
            !(route.settings.name?.endsWith('ecardpaypage') ?? false));
        navigator?.pushNamed('/ecardpaypage');
      }
    });
  }
}
