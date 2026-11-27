import 'dart:io';

import 'package:celechron/database/adapters/course_id_map_adapter.dart';
import 'package:celechron/database/adapters/duration_adapter.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/model/calendar_to_system.dart';
import 'package:celechron/model/scholar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  testWidgets(
    'AelTabBar FlClash floating dock switches tabs by tap and drag with liquid glass',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int selected = 0;
      const items = [
        AelTabItem(icon: AelIcons.tabFlow, label: '接下来'),
        AelTabItem(icon: AelIcons.tabCalendar, label: '日程'),
        AelTabItem(icon: AelIcons.tabTask, label: '任务'),
        AelTabItem(icon: AelIcons.tabScholar, label: '学业'),
        AelTabItem(icon: AelIcons.tabOption, label: '设置'),
      ];

      for (final immersive in const [true, false]) {
        for (final level in const [10, 0, 1]) {
          selected = 0;
          await tester.pumpWidget(
            CupertinoApp(
              home: CupertinoPageScaffold(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return AelTabBar(
                        items: items,
                        currentIndex: selected,
                        onSelect: (idx) => setState(() => selected = idx),
                        floating: true,
                        immersiveLight: immersive,
                        materialLevel: level,
                        captureActive: true,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('学业').first);
          await tester.pumpAndSettle();
          expect(selected, 3);
          expect(tester.takeException(), isNull);
        }
      }

      // 横向拖动透镜滑块切换标签（FlClash NavigationDock 交互）
      selected = 0;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return AelTabBar(
                    items: items,
                    currentIndex: selected,
                    onSelect: (idx) => setState(() => selected = idx),
                    floating: true,
                    immersiveLight: true,
                    materialLevel: 0,
                    captureActive: false,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startCenter = tester.getCenter(find.text('接下来').first);
      final targetCenter = tester.getCenter(find.text('设置').first);
      await tester.dragFrom(
        startCenter,
        Offset(targetCenter.dx - startCenter.dx, 0),
      );
      await tester.pumpAndSettle();
      expect(selected, greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AelTabBar docked mode renders clean without exceptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int selected = 1;
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AelTabBar(
              items: const [
                AelTabItem(icon: AelIcons.tabFlow, label: '接下来'),
                AelTabItem(icon: AelIcons.tabCalendar, label: '日程'),
              ],
              currentIndex: selected,
              onSelect: (i) => selected = i,
              floating: false,
              immersiveLight: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('接下来'));
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });

  test('CelechronHeader shouldRebuild checks delegate fields cleanly', () {
    final a = CelechronHeader(subtitle: '校园卡账单', padding: 24);
    final same = CelechronHeader(subtitle: '校园卡账单', padding: 24);
    final changedTitle = CelechronHeader(subtitle: '成绩', padding: 24);
    final changedPad = CelechronHeader(subtitle: '校园卡账单', padding: 32);

    expect(a.shouldRebuild(same), isFalse);
    expect(a.shouldRebuild(changedTitle), isTrue);
    expect(a.shouldRebuild(changedPad), isTrue);
  });

  test(
    'Calendar sync enabled state persists across simulated app restarts even when native calendar lookup returns false',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('celechron_sync_');
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      const channel = MethodChannel('plugins.builttoroam.com/device_calendar');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'hasPermissions') {
              return false;
            }
            if (call.method == 'retrieveCalendars') {
              return <Map<String, dynamic>>[];
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DurationAdapter());
      }
      if (!Hive.isAdapterRegistered(9)) {
        Hive.registerAdapter(CourseIdMapAdapter());
      }
      final box = await Hive.openBox('dbOptions');
      final db1 = DatabaseHelper()..optionsBox = box;

      expect(db1.getStoredCalendarSyncEnabled(), isNull);
      await db1.setCalendarSyncEnabled(true);
      expect(db1.getCalendarSyncEnabled(), isTrue);

      // 模拟应用退出重进：关闭 Hive Box 后重新打开并重建 Option & CalendarToSystemManager
      await box.close();
      final reopenedBox = await Hive.openBox('dbOptions');
      final db2 = DatabaseHelper()..optionsBox = reopenedBox;
      final option2 = db2.getOption();
      expect(option2.calendarSyncEnabled.value, isTrue);

      final manager = CalendarToSystemManager(
        Scholar().obs,
        db: db2,
        persistedEnabled: option2.calendarSyncEnabled,
      );
      await manager.checkInitialCalendarSyncStatus();
      // 即使系统侧返回 hasPermissions=false / retrieveCalendars=[]，也不能覆盖重置用户已开启的同步开关
      expect(manager.calendarSyncEnabled.value, isTrue);
      expect(option2.calendarSyncEnabled.value, isTrue);

      await manager.clearSyncedEvents();
      expect(manager.calendarSyncEnabled.value, isFalse);
      expect(db2.getStoredCalendarSyncEnabled(), isFalse);
    },
  );
}
