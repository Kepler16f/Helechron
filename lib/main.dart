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
import 'package:celechron/worker/ecard_widget_messenger.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/global.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ECardWidgetMessenger.installNativeHandler();

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
  Get.put(db.getFuse().obs, tag: 'fuse');

  runApp(const CelechronApp());

  var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  if (scholar.value.isLogan) {
    unawaited(
      _refreshRestoredScholar(scholar)
          .whenComplete(ECardWidgetMessenger.update),
    );
  } else {
    unawaited(ECardWidgetMessenger.update());
  }
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

class CelechronApp extends StatefulWidget {
  const CelechronApp({super.key});

  @override
  State<CelechronApp> createState() => _CelechronAppState();
}

class _CelechronAppState extends State<CelechronApp>
    with WidgetsBindingObserver {
  Timer? _foregroundLeaseHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundLease();

    // 监听AppLinks，用于跳转至付款码页面
    _initAppLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundLease();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundLease();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopForegroundLease();
    }
    if (state == AppLifecycleState.paused) {
      ECardWidgetMessenger.update();
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
