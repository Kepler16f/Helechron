import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;
import 'package:flutter_test/flutter_test.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/option/credits_page.dart';
import 'package:celechron/utils/legal_links.dart';

Widget _wrapDarkApp(Widget child) {
  final bundle = AelThemeEngine.resolve(
    brightness: Brightness.dark,
    source: ThemeColorSource.defaultBlue,
    customSeed: AelPalettePresets.defaultBlue,
    paletteStyle: ThemePaletteStyle.tonalSpot,
    contrastLevel: ThemeContrastLevel.standard,
  );
  return CupertinoApp(
    theme: bundle.cupertinoTheme,
    builder: (context, inner) => CupertinoTheme(
      data: bundle.cupertinoTheme,
      child: MiuixTheme(
        data: bundle.miuixTheme,
        child: Theme(data: bundle.materialTheme, child: inner!),
      ),
    ),
    home: child,
  );
}

void main() {
  test('AelThemeEngine dark bundle provides high-contrast text & pickers', () {
    final bundle = AelThemeEngine.resolve(
      brightness: Brightness.dark,
      source: ThemeColorSource.defaultBlue,
      customSeed: AelPalettePresets.defaultBlue,
      paletteStyle: ThemePaletteStyle.tonalSpot,
      contrastLevel: ThemeContrastLevel.standard,
    );
    final colors = bundle.aelTheme.colors;
    expect(colors.isDark, isTrue);
    expect(colors.pageBg.computeLuminance(), lessThan(0.1));
    expect(colors.textPrimary.computeLuminance(), greaterThan(0.7));
    expect(
      bundle.cupertinoTheme.textTheme.pickerTextStyle.color,
      equals(colors.textPrimary),
    );
    expect(
      bundle.cupertinoTheme.textTheme.dateTimePickerTextStyle.color,
      equals(colors.textPrimary),
    );
  });

  testWidgets(
    'CreditsPage person names and headings use dark-mode text color',
    (tester) async {
      await tester.pumpWidget(
        _wrapDarkApp(const CreditsPage(version: '0.2.1_dev3')),
      );
      await tester.pump();

      for (final label in [
        'Helechron',
        'Helechron 移植、开发与维护',
        developerName,
        'nosig',
        '空之探险队的 Kate',
        '参考与致谢开源项目',
      ]) {
        final textWidget = tester.widget<Text>(find.text(label).first);
        final color = textWidget.style?.color;
        expect(
          color,
          isNotNull,
          reason: '$label should set explicit text color',
        );
        expect(
          color!.computeLuminance(),
          greaterThan(0.7),
          reason: '$label should render bright foreground in dark mode',
        );
      }
    },
  );

  testWidgets(
    'SubSubtitleRow & AelStatTile adapt foreground colors in dark mode',
    (tester) async {
      final darkColors = AelTheme.fallback(Brightness.dark);
      await tester.pumpWidget(
        _wrapDarkApp(
          CupertinoPageScaffold(
            backgroundColor: darkColors.pageBg,
            child: Column(
              children: [
                const SubSubtitleRow(subtitle: '基本信息'),
                AelStatTile(
                  label: '加权学分',
                  value: '24.0',
                  backgroundColor: darkColors.primaryContainer,
                ),
                AelStatTile(
                  label: '加权五分制',
                  value: '4.65',
                  backgroundColor: darkColors.infoContainer,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final sectionTitle = tester.widget<Text>(find.text('基本信息'));
      expect(sectionTitle.style?.color, equals(darkColors.textPrimary));

      final primaryVal = tester.widget<Text>(find.text('24.0'));
      expect(primaryVal.style?.color, equals(darkColors.onPrimaryContainer));

      final infoVal = tester.widget<Text>(find.text('4.65'));
      expect(infoVal.style?.color, equals(darkColors.onInfoContainer));
    },
  );

  testWidgets('showAelDialog injects bright DefaultTextStyle in dark mode', (
    tester,
  ) async {
    late BuildContext hostContext;
    final darkColors = AelTheme.fallback(Brightness.dark);

    await tester.pumpWidget(
      _wrapDarkApp(
        Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    showAelDialog<void>(
      context: hostContext,
      title: '测试弹窗',
      content: Builder(
        builder: (ctx) {
          final inheritedColor = DefaultTextStyle.of(ctx).style.color;
          return Text(
            '对话框内容',
            key: ValueKey('dialog-body-${inheritedColor?.toARGB32()}'),
          );
        },
      ),
      actions: const [AelDialogAction<void>(label: '确定')],
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('dialog-body-${darkColors.textPrimary.toARGB32()}')),
      findsOneWidget,
    );
  });
}
