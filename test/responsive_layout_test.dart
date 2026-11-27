import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/practice_score_item.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:celechron/page/calendar/calendar_view.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/scholar/course_detail/courseware_batch_page.dart';
import 'package:celechron/page/scholar/practice_score/practice_score_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

class _NoopTaskController extends TaskController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _NoopFlowController extends FlowController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  test('AelResponsive classifies compact/medium/expanded/large widths', () {
    expect(AelResponsive.sizeClassForWidth(412), AelWindowSizeClass.compact);
    expect(AelResponsive.sizeClassForWidth(599.9), AelWindowSizeClass.compact);
    expect(AelResponsive.sizeClassForWidth(600), AelWindowSizeClass.medium);
    expect(AelResponsive.sizeClassForWidth(840), AelWindowSizeClass.expanded);
    expect(AelResponsive.sizeClassForWidth(1200), AelWindowSizeClass.large);

    expect(AelResponsive.isWideBody(680), isFalse);
    expect(AelResponsive.isWideBody(720), isTrue);
    expect(AelResponsive.isWideBody(1200), isTrue);

    expect(AelResponsive.gridColumnsForWidth(412), 1);
    expect(AelResponsive.gridColumnsForWidth(720, maxColumns: 2), 2);
    expect(AelResponsive.gridColumnsForWidth(1100, maxColumns: 3), 3);
  });

  testWidgets('AelSideRail and AelTabBar switch cleanly at 600dp breakpoint', (
    tester,
  ) async {
    int selected = 0;
    const items = [
      AelTabItem(label: '近期', icon: AelIcons.tabFlow),
      AelTabItem(label: '日程', icon: AelIcons.tabCalendar),
      AelTabItem(label: '事项', icon: AelIcons.tabTask),
      AelTabItem(label: '学业', icon: AelIcons.tabScholar),
      AelTabItem(label: '设置', icon: AelIcons.tabOption),
    ];

    Widget buildHarness() => CupertinoApp(
      home: Builder(
        builder: (context) {
          final useRail = AelResponsive.useSideRail(context);
          return CupertinoPageScaffold(
            child: useRail
                ? Row(
                    children: [
                      AelSideRail(
                        currentIndex: selected,
                        onSelect: (i) => selected = i,
                        items: items,
                        floating: true,
                        immersiveLight: false,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'rail-${nativeBottomBarInsetForContext(context).toStringAsFixed(0)}',
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    children: [
                      const Positioned.fill(
                        child: Center(child: Text('bottom-bar')),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AelTabBar(
                          currentIndex: selected,
                          onSelect: (i) => selected = i,
                          items: items,
                          floating: true,
                          immersiveLight: false,
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );

    // 手机竖屏 -> 底栏
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    expect(find.byType(AelTabBar), findsOneWidget);
    expect(find.byType(AelSideRail), findsNothing);
    expect(find.text('bottom-bar'), findsOneWidget);

    // 平板横屏 -> 左侧栏 + 底部原生高度归零
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    expect(find.byType(AelSideRail), findsOneWidget);
    expect(find.byType(AelTabBar), findsNothing);
    expect(find.text('rail-0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('日程'));
    expect(selected, 1);
  });

  testWidgets(
    'AelTwoPane renders both panes on tablet and falls back on phone',
    (tester) async {
      Widget buildPane() => const CupertinoApp(
        home: CupertinoPageScaffold(
          child: AelTwoPane(
            master: Center(child: Text('MasterPane')),
            detail: Center(child: Text('DetailPane')),
          ),
        ),
      );

      // 手机宽度 < 720 -> 单栏
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildPane());
      await tester.pumpAndSettle();
      expect(find.text('MasterPane'), findsOneWidget);
      expect(find.text('DetailPane'), findsNothing);

      // 平板竖屏 800x1280 & 平板横屏 1280x800 -> 双栏并排
      for (final size in const [Size(800, 1280), Size(1280, 800)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(buildPane());
        await tester.pumpAndSettle();
        expect(find.text('MasterPane'), findsOneWidget);
        expect(find.text('DetailPane'), findsOneWidget);
        final masterRect = tester.getRect(find.text('MasterPane'));
        final detailRect = tester.getRect(find.text('DetailPane'));
        expect(detailRect.left, greaterThan(masterRect.right));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('AelAdaptiveGrid and AelEmbeddedBackScope behave cleanly', (
    tester,
  ) async {
    int backCount = 0;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: AelEmbeddedBackScope(
            onBack: () => backCount++,
            child: const SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 80,
                    child: CustomScrollView(
                      slivers: [CelechronSliverTextHeader(subtitle: '内嵌子页面')],
                    ),
                  ),
                  AelAdaptiveGrid(
                    maxColumns: 2,
                    minItemWidth: 360,
                    children: [
                      SizedBox(height: 60, child: Text('CardA')),
                      SizedBox(height: 60, child: Text('CardB')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rectA = tester.getRect(find.text('CardA'));
    final rectB = tester.getRect(find.text('CardB'));
    expect(rectB.left, greaterThan(rectA.left));
    expect((rectA.top - rectB.top).abs(), lessThan(1.0));

    await tester.tap(find.byIcon(AelIcons.back));
    expect(backCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PracticeScorePage renders without overflow on phone and tablet',
    (tester) async {
      final scholar = Scholar()
        ..pt2 = 2
        ..pt3 = 1
        ..pt4 = 1.5
        ..practiceScoreItems = [
          PracticeScoreItem(
            id: 1,
            categoryId: 1,
            categoryName: '第二课堂',
            projectName: '科研竞赛项目',
            projectType: '学科竞赛',
            qualityType: '创新创业',
            score: 2,
            statusValue: 5,
            statusLabel: '审核通过',
            approved: true,
            deleted: false,
            role: '负责人',
            remark: '一等奖',
            activityStart: DateTime(2026, 3, 1, 9),
            activityEnd: DateTime(2026, 3, 1, 12),
            updatedAt: DateTime(2026, 3, 2, 10),
          ),
        ]
        ..practiceDataSource = PracticeDataSource.sztzLive
        ..practiceSummarySource = PracticeSummarySource.networkMyInfo
        ..practiceUpdatedAt = DateTime(2026, 3, 2, 10)
        ..practiceDetailsAvailable = true
        ..practiceDetailsStale = false
        ..isPracticeScoresGet = true;

      for (final size in const [
        Size(412, 915),
        Size(800, 1280),
        Size(1280, 800),
      ]) {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          CupertinoApp(
            home: PracticeScorePage(scholar: scholar, initialCategoryId: 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('科研竞赛项目'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('AelMasonryGrid packs uneven cards into waterfall columns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: AelMasonryGrid(
              maxColumns: 2,
              minItemWidth: 360,
              verticalGap: 14,
              itemWeights: [2.2, 1.1, 1.5, 1.0],
              children: [
                SizedBox(height: 220, child: Text('CardGrade')),
                SizedBox(height: 110, child: Text('CardSem')),
                SizedBox(height: 150, child: Text('CardTodo')),
                SizedBox(height: 100, child: Text('CardPrac')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rGrade = tester.getRect(find.text('CardGrade'));
    final rSem = tester.getRect(find.text('CardSem'));
    final rTodo = tester.getRect(find.text('CardTodo'));
    final rPrac = tester.getRect(find.text('CardPrac'));

    // CardGrade (左列顶部), CardSem (右列顶部)
    expect((rGrade.top - rSem.top).abs(), lessThan(1.0));
    expect(rSem.left, greaterThan(rGrade.right));

    // 瀑布流紧贴：CardTodo 在右列紧跟 CardSem 下方（gap = 14），不必向下对齐 CardGrade 底边
    expect((rTodo.left - rSem.left).abs(), lessThan(1.0));
    expect((rTodo.top - (rSem.bottom + 14)).abs(), lessThan(1.0));
    expect(rTodo.top, lessThan(rGrade.bottom));

    // CardPrac 落在左列紧跟 CardGrade 下方（gap = 14）
    expect((rPrac.left - rGrade.left).abs(), lessThan(1.0));
    expect((rPrac.top - (rGrade.bottom + 14)).abs(), lessThan(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NativeBottomBarSpacer renders exact height without GetX Obx errors in landscape and portrait',
    (tester) async {
      addTearDown(Get.reset);
      final opt = Option(
        workTime: const Duration(minutes: 45).obs,
        restTime: const Duration(minutes: 15).obs,
        allowTime: <DateTime, DateTime>{}.obs,
        gpaStrategy: GpaStrategy.best.obs,
        pushOnGradeChange: false.obs,
        pushOnDdlReminder: false.obs,
        brightnessMode: BrightnessMode.system.obs,
        courseIdMappingList: <CourseIdMap>[].obs,
        hideHomeGpa: false.obs,
        asyncRefresh: false.obs,
        calendarReminderMode: CalendarReminderMode.notification.obs,
        bottomBarFloating: true.obs,
        bottomBarImmersiveLight: false.obs,
        bottomBarMaterialLevel: 10.obs,
      );
      Get.put(opt, tag: 'option');

      // 横屏宽屏（useSideRail == true）：不应抛出 Obx 异常产生灰色 ErrorBox，且高度仅为 extra (16)
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: 120)),
                SliverToBoxAdapter(
                  child: NativeBottomBarSpacer(
                    key: ValueKey('spacer'),
                    extra: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('spacer'))).height,
        closeTo(16.0, 0.5),
      );

      // 手机竖屏（floating == true）：高度 = 64 + 16 = 80
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('spacer'))).height,
        closeTo(80.0, 0.5),
      );
    },
  );

  testWidgets(
    'CalendarPage landscape allows tapping another day to switch selectedDate and events',
    (tester) async {
      await initializeDateFormatting('zh_CN');
      addTearDown(() {
        Get.deleteAll(force: true);
        Get.reset();
      });

      final targetDay = DateTime(2026, 11, 18);
      final initialDay = DateTime(2026, 11, 10);
      final fixedTask = Task(
        uid: 'fixed-18',
        summary: '横屏测试日程',
        type: TaskType.fixed,
        status: TaskStatus.running,
        startTime: DateTime(2026, 11, 18, 10, 0),
        endTime: DateTime(2026, 11, 18, 11, 30),
        repeatEndsTime: DateTime(2026, 11, 18, 11, 30),
      );

      Get.put(DatabaseHelper(), tag: 'db');
      Get.put(Scholar().obs, tag: 'scholar');
      Get.put(<Task>[fixedTask].obs, tag: 'taskList');
      Get.put(DateTime.now().obs, tag: 'taskListLastUpdate');
      Get.put(<Period>[].obs, tag: 'flowList');
      Get.put(DateTime.now().obs, tag: 'flowListLastUpdate');
      Get.put<TaskController>(_NoopTaskController());
      Get.put<FlowController>(_NoopFlowController());

      final calCtrl = Get.put(CalendarController());
      calCtrl.focusedDay.value = initialDay;
      calCtrl.selectedDay.value = initialDay;

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        CupertinoApp(home: CupertinoPageScaffold(child: CalendarPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('横屏测试日程'), findsNothing);
      await tester.tap(find.text('18').first);
      await tester.pumpAndSettle();

      expect(calCtrl.selectedDay.value.year, targetDay.year);
      expect(calCtrl.selectedDay.value.month, targetDay.month);
      expect(calCtrl.selectedDay.value.day, targetDay.day);
      expect(find.text('横屏测试日程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CoursewareBatchPage supports multi-select, select-all, and sort order toggle',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final course = Course.fromJson({'name': '数据结构基础', 'id': 'CS201'});
      final items = [
        CoursewareItem(
          name: '第01讲_绪论.pdf',
          sectionTitle: '第一章',
          sizeBytes: 1024 * 512,
          uploadId: 101,
          source: '学在浙大',
        ),
        CoursewareItem(
          name: '第02讲_线性表.pptx',
          sectionTitle: '第二章',
          sizeBytes: 1024 * 1024 * 2,
          uploadId: 102,
          source: '学在浙大',
        ),
      ];

      await tester.pumpWidget(
        CupertinoApp(
          home: CoursewareBatchPage(
            course: course,
            itemsLoader: () async => items,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('学在浙大课件下载'), findsOneWidget);
      expect(find.text('第01讲_绪论.pdf'), findsOneWidget);
      expect(find.text('第02讲_线性表.pptx'), findsOneWidget);
      expect(find.text('已选 0/2'), findsOneWidget);

      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2/2'), findsOneWidget);
      expect(find.text('仅下载 (2)'), findsOneWidget);
      expect(find.text('分享 (2)'), findsOneWidget);

      final y1Before = tester.getTopLeft(find.text('第01讲_绪论.pdf')).dy;
      final y2Before = tester.getTopLeft(find.text('第02讲_线性表.pptx')).dy;
      expect(y1Before, lessThan(y2Before));

      await tester.tap(find.text('正序'));
      await tester.pumpAndSettle();
      expect(find.text('倒序'), findsOneWidget);
      final y1After = tester.getTopLeft(find.text('第01讲_绪论.pdf')).dy;
      final y2After = tester.getTopLeft(find.text('第02讲_线性表.pptx')).dy;
      expect(y2After, lessThan(y1After));
      expect(tester.takeException(), isNull);
    },
  );
}
