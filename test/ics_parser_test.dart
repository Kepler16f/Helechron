import 'package:celechron/services/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IcsParser', () {
    test('解析普通 VEVENT（本地时间、地点、描述）', () {
      const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:event-001@example.com
SUMMARY:高等数学
LOCATION:紫金港东1B-302
DESCRIPTION:第一次习题课
DTSTART:20260928T080000
DTEND:20260928T095500
END:VEVENT
END:VCALENDAR
''';
      final entries = IcsParser.parse(ics);
      expect(entries.length, 1);
      final entry = entries.single;
      expect(entry.isTodo, false);
      expect(entry.uid, 'event-001@example.com');
      expect(entry.summary, '高等数学');
      expect(entry.location, '紫金港东1B-302');
      expect(entry.description, '第一次习题课');
      expect(entry.start, DateTime(2026, 9, 28, 8, 0, 0));
      expect(entry.end, DateTime(2026, 9, 28, 9, 55, 0));
    });

    test('行折叠与转义（RFC 5545）', () {
      const ics = '''
BEGIN:VEVENT
UID:fold-001
SUMMARY:很长的课程名\r
  续行内容
DESCRIPTION:第一行\\n第二行\\, 带逗号\\; 带分号
DTSTART:20261001T100000
DTEND:20261001T110000
END:VEVENT
''';
      final entries = IcsParser.parse(ics);
      expect(entries.length, 1);
      expect(entries.single.summary, '很长的课程名续行内容');
      expect(entries.single.description, '第一行\n第二行, 带逗号; 带分号');
    });

    test('UTC 时间转本地时间', () {
      const ics = '''
BEGIN:VEVENT
UID:utc-001
SUMMARY:UTC 事件
DTSTART:20261001T000000Z
DTEND:20261001T010000Z
END:VEVENT
''';
      final entry = IcsParser.parse(ics).single;
      expect(entry.start!.isUtc, false);
      expect(entry.start, DateTime.utc(2026, 10, 1, 0, 0, 0).toLocal());
    });

    test('全天事件（VALUE=DATE，无时间部分）', () {
      const ics = '''
BEGIN:VEVENT
UID:date-001
SUMMARY:运动会
DTSTART;VALUE=DATE:20261015
DTEND;VALUE=DATE:20261016
END:VEVENT
''';
      final entry = IcsParser.parse(ics).single;
      expect(entry.start, DateTime(2026, 10, 15));
      expect(entry.end, DateTime(2026, 10, 16));
    });

    test('VTODO 解析为待办（DUE 为截止时间）', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:mix-event
SUMMARY:某日程
DTSTART:20261101T090000
DTEND:20261101T100000
END:VEVENT
BEGIN:VTODO
UID:todo-001
SUMMARY:提交实验报告
DTSTART:20261102T120000
DUE:20261102T235900
END:VTODO
END:VCALENDAR
''';
      final entries = IcsParser.parse(ics);
      expect(entries.length, 2);
      final todo = entries.firstWhere((e) => e.isTodo);
      expect(todo.summary, '提交实验报告');
      expect(todo.end, DateTime(2026, 11, 2, 23, 59, 0));
      final event = entries.firstWhere((e) => !e.isTodo);
      expect(event.summary, '某日程');
    });

    test('VALARM 子组件属性不污染主条目', () {
      const ics = '''
BEGIN:VEVENT
UID:alarm-001
SUMMARY:带提醒的事件
DTSTART:20261001T080000
DTEND:20261001T090000
BEGIN:VALARM
TRIGGER:-PT15M
DESCRIPTION:提醒
END:VALARM
END:VEVENT
''';
      final entry = IcsParser.parse(ics).single;
      expect(entry.summary, '带提醒的事件');
      expect(entry.description, isEmpty);
      expect(entry.start, DateTime(2026, 10, 1, 8));
    });

    test('带引号参数中的冒号不影响属性切分', () {
      const ics = '''
BEGIN:VEVENT
UID:quote-001
SUMMARY;LANGUAGE=zh-cn:冒号测试
DTSTART;TZID="Asia/Shanghai":20261001T080000
DTEND;TZID="Asia/Shanghai":20261001T090000
END:VEVENT
''';
      final entry = IcsParser.parse(ics).single;
      expect(entry.summary, '冒号测试');
      expect(entry.start, DateTime(2026, 10, 1, 8));
    });

    test('无时间信息的条目被跳过', () {
      const ics = '''
BEGIN:VEVENT
UID:no-time
SUMMARY:坏数据
END:VEVENT
BEGIN:VEVENT
UID:good
SUMMARY:好数据
DTSTART:20261001T080000
DTEND:20261001T090000
END:VEVENT
''';
      final entries = IcsParser.parse(ics);
      expect(entries.length, 1);
      expect(entries.single.uid, 'good');
    });
  });
}
