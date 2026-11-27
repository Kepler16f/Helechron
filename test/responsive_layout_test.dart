import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/model/practice_score_item.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/page/scholar/practice_score/practice_score_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
