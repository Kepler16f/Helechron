import 'dart:convert';
import 'dart:io';

import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/services/mobile_native_service.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ohosChannel = MethodChannel('top.celechron.helechron/native');
  const mobileChannel = MethodChannel('top.celechron.celechron/widget');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ohosChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileChannel, null);
    OhosNativeService.instance.lastFilePickError = null;
    MobileNativeService.instance.lastFilePickError = null;
  });

  group('Courses directory write & fallback', () {
    test('isDirectoryDirectlyWritable rejects URI schemes and probes real dirs',
        () async {
      expect(
        await Courses.isDirectoryDirectlyWritable(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload',
        ),
        isFalse,
      );
      expect(
        await Courses.isDirectoryDirectlyWritable(
          'file://docs/storage/Users/currentUser/Download',
        ),
        isFalse,
      );
      expect(await Courses.isDirectoryDirectlyWritable('   '), isFalse);

      final tempDir =
          await Directory.systemTemp.createTemp('helechron_dir_probe_');
      try {
        expect(
          await Courses.isDirectoryDirectlyWritable(tempDir.path),
          isTrue,
        );
        // Probe file should be cleaned up automatically
        expect(tempDir.listSync(), isEmpty);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('saveHttpResponseToDirectory writes directly when POSIX dir writable',
        () async {
      final targetDir =
          await Directory.systemTemp.createTemp('helechron_direct_dl_');
      addTearDown(() async {
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      });

      var nativeInvoked = false;
      final saved = await Courses.saveHttpResponseToDirectory(
        Stream<List<int>>.value(utf8.encode('hello-courseware-bytes')),
        saveDir: targetDir.path,
        fileName: 'lecture.pdf',
        mimeType: 'application/pdf',
        nativeCopyToDir: (src, dir, name, {mimeType}) async {
          nativeInvoked = true;
          return null;
        },
      );

      expect(nativeInvoked, isFalse);
      expect(saved, '${targetDir.path}/lecture.pdf');
      expect(
        await File('${targetDir.path}/lecture.pdf').readAsString(),
        'hello-courseware-bytes',
      );
    });

    test(
        'saveHttpResponseToDirectory stages temp file and delegates URI dir via nativeCopyToDir',
        () async {
      String? capturedSource;
      String? capturedBytes;
      String? capturedDir;
      String? capturedName;
      String? capturedMime;

      const safUri =
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FCourses';
      final saved = await Courses.saveHttpResponseToDirectory(
        Stream<List<int>>.value(utf8.encode('scoped-storage-pdf-bytes')),
        saveDir: safUri,
        fileName: 'notes.pdf',
        mimeType: 'application/pdf',
        nativeCopyToDir: (src, dir, name, {mimeType}) async {
          capturedSource = src;
          capturedBytes = await File(src).readAsString();
          capturedDir = dir;
          capturedName = name;
          capturedMime = mimeType;
          return '$safUri/document/notes.pdf';
        },
      );

      expect(saved, '$safUri/document/notes.pdf');
      expect(capturedBytes, 'scoped-storage-pdf-bytes');
      expect(capturedDir, safUri);
      expect(capturedName, 'notes.pdf');
      expect(capturedMime, 'application/pdf');
      // Temp staging file should have been removed in finally
      expect(capturedSource, isNotNull);
      expect(await File(capturedSource!).exists(), isFalse);
    });
  });

  group('Native directory picker channels', () {
    test('OhosNativeService pickDirectory & copyFileToDirectory clear errors and pass args',
        () async {
      OhosNativeService.instance.lastFilePickError = 'stale error';
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ohosChannel, (call) async {
        calls.add(call);
        if (call.method == 'pickDirectory') {
          return '  /storage/Users/currentUser/Download/ZJU  ';
        }
        if (call.method == 'copyFileToDirectory') {
          return 'file://docs/storage/Users/currentUser/Download/ZJU/a.pdf';
        }
        return null;
      });

      final picked = await OhosNativeService.instance.pickDirectory();
      expect(picked, '/storage/Users/currentUser/Download/ZJU');
      expect(OhosNativeService.instance.lastFilePickError, isNull);

      final copied = await OhosNativeService.instance.copyFileToDirectory(
        '/tmp/src.tmp',
        '/storage/Users/currentUser/Download/ZJU',
        'a.pdf',
        mimeType: 'application/pdf',
      );
      expect(
          copied, 'file://docs/storage/Users/currentUser/Download/ZJU/a.pdf');
      expect(calls.map((c) => c.method),
          ['pickDirectory', 'copyFileToDirectory']);
      expect(calls[1].arguments, {
        'sourcePath': '/tmp/src.tmp',
        'targetDir': '/storage/Users/currentUser/Download/ZJU',
        'fileName': 'a.pdf',
        'mimeType': 'application/pdf',
      });
    });

    test('MobileNativeService pickDirectory records PlatformException message',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mobileChannel, (call) async {
        if (call.method == 'pickDirectory') {
          throw PlatformException(
            code: 'PICKER_UNAVAILABLE',
            message: '未找到可用的系统文件管理器',
          );
        }
        return null;
      });

      final picked = await MobileNativeService.instance.pickDirectory();
      expect(picked, isNull);
      expect(
        MobileNativeService.instance.lastFilePickError,
        '未找到可用的系统文件管理器',
      );
    });
  });
}
