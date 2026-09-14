import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class CalendarToIcal {
  static String _toISOString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}'
        '${dateTime.month.toString().padLeft(2, '0')}'
        '${dateTime.day.toString().padLeft(2, '0')}'
        'T'
        '${dateTime.hour.toString().padLeft(2, '0')}'
        '${dateTime.minute.toString().padLeft(2, '0')}'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  static const String dateLayoutUTC = "yyyyMMddTHHmmssZ";

  static String _generateVEvent(Period period) {
    final buffer = StringBuffer();
    final utcStr =
        '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.')[0]}Z';
    final startStr = _toISOString(period.startTime);
    final endStr = _toISOString(period.endTime);
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);

    final hash = _generateHash(period);

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('CLASS:PUBLIC');
    buffer.writeln('CREATED:$utcStr');

    if (period.description.isNotEmpty) {
      String description = period.description
          .replaceAll('\n', '\\n')
          .replaceAll(',', '\\,')
          .replaceAll(';', '\\;');
      buffer.writeln('DESCRIPTION:$description');
    }

    buffer.writeln('DTSTAMP:$utcStr');
    buffer.writeln('DTSTART;TZID=Asia/Shanghai:$startStr');
    buffer.writeln('DTEND;TZID=Asia/Shanghai:$endStr');
    buffer.writeln('LAST-MODIFIED:$utcStr');

    if (mappedLocation.isNotEmpty) {
      buffer.writeln('LOCATION:$mappedLocation');
    }

    buffer.writeln('SEQUENCE:0');
    buffer.writeln('SUMMARY;LANGUAGE=zh-cn:${period.summary}');
    buffer.writeln('TRANSP:OPAQUE');
    buffer.writeln('UID:$hash');

    buffer.writeln('BEGIN:VALARM');
    buffer.writeln('TRIGGER:-PT15M');
    buffer.writeln('ACTION:DISPLAY');
    buffer.writeln('DESCRIPTION:提醒');
    buffer.writeln('END:VALARM');

    buffer.writeln('END:VEVENT');

    return buffer.toString();
  }

  static String _generateHash(Period period) {
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);
    final content =
        '${period.description}${period.summary}$mappedLocation${_toISOString(period.startTime)}';
    final bytes = utf8.encode(content);
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  static String generateIcal({
    required List<Period> periods,
    String calendarName = "浙大课程表",
    bool includeExams = true,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('X-WR-CALNAME:$calendarName');
    buffer.writeln('X-APPLE-CALENDAR-COLOR:#2BBFF0');
    buffer.writeln('PRODID:-//Celechron//Course Calendar 1.0//CN');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('METHOD:PUBLISH');

    buffer.writeln('BEGIN:VTIMEZONE');
    buffer.writeln('TZID:Asia/Shanghai');
    buffer.writeln('BEGIN:STANDARD');
    buffer.writeln('DTSTART:16010101T000000');
    buffer.writeln('TZOFFSETFROM:+0800');
    buffer.writeln('TZOFFSETTO:+0800');
    buffer.writeln('END:STANDARD');
    buffer.writeln('END:VTIMEZONE');

    for (final period in periods) {
      if (!includeExams && period.type == PeriodType.test) {
        continue;
      }
      buffer.write(_generateVEvent(period));
    }

    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  static void _showAlert(String title, String message, {bool isError = false}) {
    Get.dialog(
      CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }

  static String generateIcalFromScholar({
    required Scholar scholar,
    String? semesterName,
    String calendarName = "浙大课程表",
    bool includeExams = true,
    bool includeAllSemesters = false,
  }) {
    List<Period> periods = [];

    if (includeAllSemesters) {
      periods = scholar.periods;
    } else if (semesterName != null) {
      final semester = scholar.semesters.firstWhere(
        (s) => s.name == semesterName,
        orElse: () => scholar.thisSemester,
      );
      periods = semester.periods;
    } else {
      periods = scholar.thisSemester.periods;
    }

    return generateIcal(
      periods: periods,
      calendarName: calendarName,
      includeExams: includeExams,
    );
  }

  static String generateIcalFromSemester({
    required Semester semester,
    String? calendarName,
    bool includeExams = true,
  }) {
    final name = calendarName ?? '${semester.name} 课程表';
    return generateIcal(
      periods: semester.periods,
      calendarName: name,
      includeExams: includeExams,
    );
  }

  static Future<void> exportIcsFile(
    Scholar scholar, {
    BuildContext? context,
  }) async {
    try {
      if (!scholar.isLogan) {
        _showAlert('提示', '请先登录后再导出课程表');
        return;
      }

      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        calendarName: "浙大课程表-${scholar.thisSemester.name}",
        includeExams: true,
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_schedule_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      await tempFile.writeAsString(icalContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表',
          text: '从 Celechron 导出的课程表文件，可导入到其他日历应用中使用。',
        ),
      );

      _showAlert('成功', '课程表已导出，请选择保存位置或分享');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  static Future<void> exportSpecificSemester(
    Scholar scholar,
    String semesterName, {
    BuildContext? context,
  }) async {
    try {
      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        semesterName: semesterName,
        calendarName: "浙大课程表-$semesterName",
        includeExams: true,
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_${semesterName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      await tempFile.writeAsString(icalContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表-$semesterName',
          text: '从 Celechron 导出的 $semesterName 课程表文件。',
        ),
      );

      _showAlert('成功', '$semesterName 课程表已导出');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  static Future<void> exportAllSemesters(
    Scholar scholar, {
    BuildContext? context,
  }) async {
    try {
      final icalContent = generateIcalFromScholar(
        scholar: scholar,
        calendarName: "课程表-完整版",
        includeExams: true,
        includeAllSemesters: true,
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'celechron_all_semesters_${DateTime.now().millisecondsSinceEpoch}.ics';
      final tempFile = File('${directory.path}/$fileName');

      await tempFile.writeAsString(icalContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: '浙大课程表-完整版',
          text: '从 Celechron 导出的完整课程表文件，包含所有学期。',
        ),
      );

      _showAlert('成功', '完整课程表已导出');
    } catch (e) {
      _showAlert('错误', '导出失败: $e', isError: true);
    }
  }

  static List<String> getAvailableSemesters(Scholar scholar) {
    return scholar.semesters.map((s) => s.name).toList();
  }

  static void showExportDialog(BuildContext context, Scholar scholar) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext popupContext) => CupertinoActionSheet(
        title: const Text('导出课程表'),
        message: const Text('选择导出方式'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              exportIcsFile(scholar, context: popupContext);
            },
            child: const Text('导出当前学期'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              _showSemesterSelectionDialog(context, scholar);
            },
            child: const Text('选择学期导出'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  static void _showSemesterSelectionDialog(
      BuildContext context, Scholar scholar) {
    final semesters = getAvailableSemesters(scholar);

    if (semesters.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext dialogContext) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('没有可导出的课程表数据'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      );
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext popupContext) => CupertinoActionSheet(
        title: const Text('选择学期'),
        message: const Text('选择要导出的学期'),
        actions: [
          ...semesters.map((semester) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(popupContext);
                  exportSpecificSemester(scholar, semester,
                      context: popupContext);
                },
                child: Text(semester),
              )),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(popupContext);
              exportAllSemesters(scholar, context: popupContext);
            },
            child: const Text('导出所有学期'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  static Map<String, dynamic> getCalendarStatistics(List<Period> periods) {
    final stats = <String, dynamic>{};

    final typeCount = <PeriodType, int>{};
    for (final period in periods) {
      typeCount[period.type] = (typeCount[period.type] ?? 0) + 1;
    }

    stats['totalEvents'] = periods.length;
    stats['courseCount'] = typeCount[PeriodType.classes] ?? 0;
    stats['examCount'] = typeCount[PeriodType.test] ?? 0;
    stats['userEventCount'] = typeCount[PeriodType.user] ?? 0;
    stats['flowCount'] = typeCount[PeriodType.flow] ?? 0;

    if (periods.isNotEmpty) {
      final sortedPeriods = List<Period>.from(periods)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      stats['startDate'] = sortedPeriods.first.startTime;
      stats['endDate'] = sortedPeriods.last.endTime;
    }

    return stats;
  }
}
