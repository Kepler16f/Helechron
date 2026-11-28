import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/page/scholar/course_detail/courseware_batch_page.dart';
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

  test(
    'Download record persists across restarts even for sandboxed external SAF paths',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'helechron_record_test_',
      );
      final recordsPath = '${tempDir.path}/download_records.json';
      FileDownloadShareHelper.setRecordsFilePathForTest(recordsPath);

      const nativeChannel = MethodChannel('top.celechron.helechron/native');
      bool? mockNativeExists;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'checkSavedFileExists') return mockNativeExists;
            return null;
          });

      try {
        const key = 'courseware|学在浙大_101_202_lec1.pdf';
        const externalPath = '/storage/emulated/0/Download/课件/lec1.pdf';
        await FileDownloadShareHelper.saveDownloadRecord(
          key,
          savedPath: externalPath,
          fileName: 'lec1.pdf',
          mimeType: 'application/pdf',
        );

        // Simulate app restart by clearing in-memory cache
        FileDownloadShareHelper.setRecordsFilePathForTest(recordsPath);

        // Case 1: Native check indeterminate (null) under scoped storage -> keep memory
        mockNativeExists = null;
        final recIndeterminate =
            await FileDownloadShareHelper.getDownloadRecord(key);
        expect(recIndeterminate, isNotNull);
        expect(recIndeterminate!.savedPath, equals(externalPath));
        expect(recIndeterminate.fileName, equals('lec1.pdf'));

        // Case 2: Native check confirms exists (true) -> keep memory
        mockNativeExists = true;
        final recPresent = await FileDownloadShareHelper.getDownloadRecord(key);
        expect(recPresent, isNotNull);

        // Case 3: Native check explicitly confirms deleted (false) -> return null
        mockNativeExists = false;
        final recDeleted = await FileDownloadShareHelper.getDownloadRecord(key);
        expect(recDeleted, isNull);
      } finally {
        FileDownloadShareHelper.setRecordsFilePathForTest(null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'Batch filename disambiguation, ZIP bundling, and multi-file native share preserve ALL files',
    () async {
      final used = <String>{};
      expect(
        FileDownloadShareHelper.disambiguateFileName('课件.pdf', used),
        equals('课件.pdf'),
      );
      expect(
        FileDownloadShareHelper.disambiguateFileName('课件.pdf', used),
        equals('课件 (2).pdf'),
      );
      expect(
        FileDownloadShareHelper.disambiguateFileName('课件.pdf', used),
        equals('课件 (3).pdf'),
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'helechron_multi_share_',
      );
      final dirA = await Directory('${tempDir.path}/a').create();
      final dirB = await Directory('${tempDir.path}/b').create();
      final f1 = File('${dirA.path}/lec1.pdf')..writeAsStringSync('FILE_1');
      final f2 = File('${dirB.path}/lec1.pdf')..writeAsStringSync('FILE_2');
      final f3 = File('${tempDir.path}/lec3.pptx')..writeAsStringSync('FILE_3');

      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      const nativeChannel = MethodChannel('top.celechron.helechron/native');
      List<dynamic>? sharedPaths;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return tempDir.path;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'shareFiles') {
              sharedPaths = (call.arguments as Map)['paths'] as List<dynamic>?;
              return true;
            }
            return null;
          });

      try {
        // 1. Direct multi-file share passes all 3 files (not just the last one)
        final ok = await FileDownloadShareHelper.shareFiles(
          [f1, f2, f3],
          mimeTypes: const [
            'application/pdf',
            'application/pdf',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          ],
          subject: '高数_课程课件',
        );
        expect(ok, isTrue);
        expect(sharedPaths, isNotNull);
        expect(sharedPaths!.length, equals(3));

        // 2. ZIP bundle preserves all 3 files with disambiguated names
        final zipFile = await FileDownloadShareHelper.bundleFilesToZip([
          f1,
          f2,
          f3,
        ], zipBaseName: '高数_课程课件_3个文件');
        expect(zipFile, isNotNull);
        final decoded = ZipDecoder().decodeBytes(await zipFile!.readAsBytes());
        expect(decoded.length, equals(3));
        expect(
          decoded.map((e) => e.name).toSet(),
          equals({'lec1.pdf', 'lec1 (2).pdf', 'lec3.pptx'}),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  testWidgets(
    'CoursewareBatchPage omits duplicate per-item download/share buttons and shows downloaded state',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('helechron_cw_ui_');
      final downloadedFile = File('${tempDir.path}/第01讲_绪论.pdf')
        ..writeAsStringSync('PDF_DATA');

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
          downloadPath: tempDir.path.obs,
        ),
        tag: 'option',
      );

      final course = Course.fromJson(const {'name': '微积分', 'id': 'MATH101'});
      const items = [
        CoursewareItem(
          name: '第01讲_绪论.pdf',
          sectionTitle: '第一章',
          sizeBytes: 2048,
          uploadId: 1,
          source: '学在浙大',
        ),
        CoursewareItem(
          name: '第02讲_极限.pdf',
          sectionTitle: '第二章',
          sizeBytes: 4096,
          uploadId: 2,
          source: '学在浙大',
        ),
      ];

      try {
        FileDownloadShareHelper.setRecordsFilePathForTest(
          '${tempDir.path}/download_records.json',
        );
        expect(downloadedFile.existsSync(), isTrue);
        await tester.pumpWidget(
          _wrapApp(
            CoursewareBatchPage(course: course, itemsLoader: () async => items),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
        }
        await tester.pump();

        // Downloaded item remembered & displays '已下载' tag + '打开' button
        expect(find.text('已下载'), findsOneWidget);
        expect(find.text('打开'), findsOneWidget);
        // Zero duplicated per-item '下载' pills; bottom bar has the single global '仅下载' & '分享'
        expect(find.text('下载'), findsNothing);
        expect(find.text('仅下载'), findsOneWidget);
        expect(find.text('分享'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        FileDownloadShareHelper.setRecordsFilePathForTest(null);
        await tester.pumpWidget(const SizedBox.shrink());
        Get.deleteAll(force: true);
        Get.reset();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    },
  );
}
