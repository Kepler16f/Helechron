import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/page/scholar/scholar_view.dart';
import 'package:celechron/services/file_download_share_helper.dart';

Widget _wrapApp(Widget child) {
  final bundle = AelThemeEngine.resolve(
    brightness: Brightness.light,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Get.reset();
  });

  testWidgets(
    'Cold-start ScholarPage renders without gray ErrorWidget even when OptionController is not registered',
    (tester) async {
      final semester = Semester('2026-2027秋冬');
      semester.courses['c1'] = Course.fromJson(const {
        'id': 'c1',
        'name': '高等数学',
        'confirmed': true,
        'credit': 4.0,
        'sessions': <dynamic>[],
        'exams': <dynamic>[],
      });
      final scholar = Scholar()
        ..isLogan = true
        ..username = '3240000001'
        ..semesters = [semester]
        ..gpa = [4.5, 3.8, 3.7, 92.0]
        ..credit = 24.0
        ..majorGpaAndCredit = [4.6, 18.0];

      Get.put(scholar.obs, tag: 'scholar');
      Get.put(
        Option(
          workTime: const Duration(minutes: 45).obs,
          restTime: const Duration(minutes: 15).obs,
          allowTime: <DateTime, DateTime>{}.obs,
          gpaStrategy: GpaStrategy.first.obs,
          pushOnGradeChange: true.obs,
          pushOnDdlReminder: true.obs,
          brightnessMode: BrightnessMode.system.obs,
          courseIdMappingList: <CourseIdMap>[].obs,
          hideHomeGpa: false.obs,
          asyncRefresh: true.obs,
          calendarReminderMode: CalendarReminderMode.notification.obs,
          bottomBarFloating: false.obs,
          bottomBarImmersiveLight: false.obs,
          bottomBarMaterialLevel: 10.obs,
        ),
        tag: 'option',
      );
      // Intentionally do NOT register OptionController(tag: 'optionController')
      // to simulate jumping straight to the 学业 tab on cold start.

      await tester.pumpWidget(_wrapApp(ScholarPage()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('学业'), findsOneWidget);
      expect(find.text('成绩'), findsOneWidget);
      expect(find.text('4.50'), findsOneWidget);
      expect(find.text('课程'), findsWidgets);

      // Dispose GetX controllers (including ScholarController's periodic timer)
      // before Flutter test framework checks pending timers on teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      Get.deleteAll(force: true);
      Get.reset();
    },
  );

  test('FileDownloadShareHelper infers accurate Office OpenXML MIME types', () {
    expect(
      FileDownloadShareHelper.inferMimeType('第1讲.pptx'),
      equals(
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ),
    );
    expect(
      FileDownloadShareHelper.inferMimeType('实验报告.docx'),
      equals(
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
    );
    expect(
      FileDownloadShareHelper.inferMimeType('数据表.xlsx'),
      equals(
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    );
    expect(
      FileDownloadShareHelper.inferMimeType('讲义.pdf'),
      equals('application/pdf'),
    );
  });

  test(
    'FileDownloadShareHelper.shareFiles invokes native shareFiles channel when available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'helechron_share_test_',
      );
      final sampleFile = File('${tempDir.path}/lecture1.pdf');
      await sampleFile.writeAsBytes([0x25, 0x50, 0x44, 0x46, 0x2D]);

      const nativeChannel = MethodChannel('top.celechron.helechron/native');
      const sharePlusChannel = MethodChannel('dev.fluttercommunity.plus/share');

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            calls.add(call);
            if (call.method == 'shareFiles') return true;
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sharePlusChannel, (call) async {
            calls.add(call);
            return 'ok';
          });

      try {
        final ok = await FileDownloadShareHelper.shareFiles(
          [sampleFile],
          mimeTypes: const ['application/pdf'],
          subject: 'lecture1.pdf',
        );
        expect(ok, isTrue);
        expect(calls, isNotEmpty);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sharePlusChannel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
