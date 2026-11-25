import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'showAelActionSheet anchors strictly to bottom edge and returns choice',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int? selectedValue;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () async {
                selectedValue = await showAelActionSheet<int>(
                  context: context,
                  title: '选择底栏光感强度',
                  actions: const [
                    AelActionOption<int>(
                      value: 10,
                      label: '跟随系统',
                      isSelected: true,
                    ),
                    AelActionOption<int>(value: 0, label: '精致'),
                    AelActionOption<int>(value: 1, label: '柔和'),
                    AelActionOption<int>(value: 2, label: '流畅'),
                  ],
                );
              },
              child: const Text('打开光感'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开光感'));
      await tester.pumpAndSettle();

      final sheetFinder = find.byKey(
        const ValueKey('ael_bottom_sheet_surface'),
      );
      expect(sheetFinder, findsOneWidget);
      final rect = tester.getRect(sheetFinder);
      expect(rect.bottom, closeTo(844.0, 0.5));
      expect(rect.top, greaterThan(400.0));
      expect(find.byIcon(AelIcons.check), findsOneWidget);

      await tester.tap(find.text('精致'));
      await tester.pumpAndSettle();
      expect(selectedValue, 0);
    },
  );

  testWidgets(
    'showAelConfirmDialog anchors near bottom on phone and returns choice',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool? confirmed;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () async {
                confirmed = await showAelConfirmDialog(
                  context: context,
                  title: '删除确认',
                  message: '确定执行此操作？',
                  confirmLabel: '删除',
                  isDestructive: true,
                );
              },
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      expect(find.byType(AelDialogSurface), findsOneWidget);

      final dialogRect = tester.getRect(find.byType(AelDialogSurface));
      expect(dialogRect.bottom, greaterThan(750.0));

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    },
  );
}
