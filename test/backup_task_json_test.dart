import 'package:celechron/model/task.dart';
import 'package:celechron/services/backup_service.dart';
import 'package:celechron/services/ics_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task JSON 往返', () {
    test('所有字段序列化后可完整恢复', () {
      final task = Task(
        uid: 'test-uid-001',
        summary: '数据结构作业',
        description: '第七章习题',
        location: '图书馆',
        endTime: DateTime(2026, 10, 8, 23, 59),
        startTime: DateTime(2026, 10, 6, 14, 0),
        repeatEndsTime: DateTime(2026, 10, 8),
        type: TaskType.fixed,
        status: TaskStatus.running,
        timeNeeded: const Duration(hours: 3),
        timeSpent: const Duration(minutes: 45),
        repeatType: TaskRepeatType.days,
        repeatPeriod: 3,
        isBreakable: true,
        blockArrangements: false,
        fromUid: 'parent-uid',
      );

      final restored = Task.fromJson(task.toJson());
      expect(restored.uid, task.uid);
      expect(restored.summary, task.summary);
      expect(restored.description, task.description);
      expect(restored.location, task.location);
      expect(restored.type, TaskType.fixed);
      expect(restored.status, TaskStatus.running);
      expect(restored.startTime, task.startTime);
      expect(restored.endTime, task.endTime);
      expect(restored.repeatEndsTime, task.repeatEndsTime);
      expect(restored.timeNeeded, task.timeNeeded);
      expect(restored.timeSpent, task.timeSpent);
      expect(restored.repeatType, TaskRepeatType.days);
      expect(restored.repeatPeriod, 3);
      expect(restored.isBreakable, true);
      expect(restored.blockArrangements, false);
      expect(restored.fromUid, 'parent-uid');
    });

    test('缺失与非法字段回退到默认值，不抛异常', () {
      final task = Task.fromJson({});
      expect(task.uid, '');
      expect(task.type, TaskType.deadline);
      expect(task.status, TaskStatus.running);
      expect(task.repeatType, TaskRepeatType.norepeat);
      expect(task.repeatPeriod, 1);
      expect(task.blockArrangements, true);
      expect(task.timeNeeded, Duration.zero);
    });

    test('越界枚举下标回退到默认值', () {
      final task = Task.fromJson({'type': 99, 'status': -1, 'repeatType': 42});
      expect(task.type, TaskType.deadline);
      expect(task.status, TaskStatus.running);
      expect(task.repeatType, TaskRepeatType.norepeat);
    });
  });

  group('iCal 条目映射为任务', () {
    IcsEntry entry({
      String uid = 'evt-1',
      String summary = '测试日程',
      bool isTodo = false,
      DateTime? start,
      DateTime? end,
    }) {
      return IcsEntry(
        uid: uid,
        summary: summary,
        description: '描述',
        location: '地点',
        isTodo: isTodo,
        start: start,
        end: end,
      );
    }

    test('VEVENT 映射为固定日程，uid 加 ics- 前缀', () {
      final task = BackupService.taskFromIcsEntry(entry(
        start: DateTime(2026, 10, 1, 8),
        end: DateTime(2026, 10, 1, 9, 30),
      ), {});
      expect(task, isNotNull);
      expect(task!.type, TaskType.fixed);
      expect(task.uid, 'ics-evt-1');
      expect(task.summary, '测试日程');
      expect(task.startTime, DateTime(2026, 10, 1, 8));
      expect(task.endTime, DateTime(2026, 10, 1, 9, 30));
    });

    test('VTODO 映射为 DDL', () {
      final task = BackupService.taskFromIcsEntry(entry(
        isTodo: true,
        start: DateTime(2026, 10, 1, 12),
        end: DateTime(2026, 10, 2, 23, 59),
      ), {});
      expect(task!.type, TaskType.deadline);
      expect(task.endTime, DateTime(2026, 10, 2, 23, 59));
    });

    test('结束时间与开始时间相同的全天条目补足一天', () {
      final task = BackupService.taskFromIcsEntry(entry(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 1),
      ), {});
      expect(task!.endTime, DateTime(2026, 10, 2));
    });

    test('一天前已结束的条目被判定为过期', () {
      final task = BackupService.taskFromIcsEntry(entry(
        start: DateTime(2020, 1, 1, 8),
        end: DateTime(2020, 1, 1, 9),
      ), {});
      expect(task, isNull);
    });

    test('uid 已存在的条目返回去重哨兵', () {
      final task = BackupService.taskFromIcsEntry(entry(
        uid: 'evt-dup',
        start: DateTime.now().add(const Duration(days: 3)),
        end: DateTime.now().add(const Duration(days: 3, hours: 1)),
      ), {'ics-evt-dup'});
      expect(identical(task, BackupService.duplicateSentinel), true);
    });
  });
}
