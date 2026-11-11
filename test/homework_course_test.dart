import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/scholar/todo/todo_card.dart';
import 'package:celechron/page/task/homework_submission_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('课程全部作业解析与合并排序测试', () {
    test('parseCourseHomeworkActivities 正确解析作业与测验并过滤非作业活动', () {
      final json = <String, dynamic>{
        'homework_activities': [
          {
            'id': 1001,
            'title': '第一次实验报告',
            'end_time': '2026-12-01T15:59:00Z',
            'type': 'homework',
            'submission_count': 1,
          },
          {
            'id': 1002,
            'title': '第二次上机练习',
            'end_time': '2026-12-10T15:59:00Z',
          },
        ],
        'activities': [
          {
            'id': 1001,
            'title': '第一次实验报告',
            'type': 'homework',
          },
          {
            'id': 1003,
            'title': '第三周课堂小测',
            'type': 'quiz',
            'end_time': '2026-11-25T12:00:00Z',
          },
          {
            'id': 2001,
            'title': '第一章课件',
            'type': 'material',
          },
          {
            'id': 2002,
            'title': '录播视频回放',
            'type': 'online_video',
          },
        ],
      };

      final parsed = Courses.parseCourseHomeworkActivities(
        json,
        tcCourseId: '88801',
        courseName: '数据结构基础',
      );

      expect(parsed.map((e) => e.id).toList(), ['1001', '1002', '1003']);
      expect(parsed[0].isSubmitted, isTrue);
      expect(parsed[1].isSubmitted, isFalse);
      expect(parsed[2].isQuiz, isTrue);
      expect(parsed.every((e) => e.resolvedCourseId == '88801'), isTrue);
    });

    test('mergeAndSortCourseHomeworks 正确融合 activity_reads 并按待交->逾期->已交排序', () {
      final now = DateTime.now().toUtc();
      final rawItems = <Todo>[
        Todo.fromJson({
          'id': '1',
          'title': '较晚待交作业',
          'course_name': '操作系统',
          'course_id': '99',
          'end_time': now.add(const Duration(days: 5)).toIso8601String(),
          'type': 'homework',
        }),
        Todo.fromJson({
          'id': '2',
          'title': '已完成且出分作业',
          'course_name': '操作系统',
          'course_id': '99',
          'end_time': now.add(const Duration(days: 1)).toIso8601String(),
          'type': 'homework',
        }),
        Todo.fromJson({
          'id': '3',
          'title': '已过期未交作业',
          'course_name': '操作系统',
          'course_id': '99',
          'end_time': now.subtract(const Duration(days: 3)).toIso8601String(),
          'type': 'homework',
        }),
        Todo.fromJson({
          'id': '4',
          'title': '最近待交作业',
          'course_name': '操作系统',
          'course_id': '99',
          'end_time': now.add(const Duration(days: 2)).toIso8601String(),
          'type': 'homework',
        }),
        Todo.fromJson({
          'id': '5',
          'title': '草稿状态未正式提交',
          'course_name': '操作系统',
          'course_id': '99',
          'end_time': now.add(const Duration(days: 4)).toIso8601String(),
          'type': 'homework',
        }),
      ];

      final readsJson = <String, dynamic>{
        'activity_reads': [
          {
            'activity_id': '2',
            'completeness': 'full',
            'data': {
              'score': 96,
              'submitted_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
              'is_draft': false,
            },
          },
          {
            'activity_id': '5',
            'completeness': 'full',
            'data': {
              'is_draft': true,
            },
          },
        ],
      };

      final merged = Courses.mergeAndSortCourseHomeworks(
        rawItems,
        activityReadsJson: readsJson,
        readLocalStatus: false,
      );

      // 待完成升序：4 (2天) -> 5 (4天，草稿不算已交) -> 1 (5天) -> 3 (逾期) -> 2 (已出分)
      expect(merged.map((e) => e.id).toList(), ['4', '5', '1', '3', '2']);
      expect(merged.last.isGraded, isTrue);
      expect(merged.last.score, 96);
      expect(merged.firstWhere((e) => e.id == '5').isSubmitted, isFalse);
    });
  });

  group('上传进度计算与状态标签样式测试', () {
    test('computeUploadProgress 多文件按字节占比平滑单调递增', () {
      // 文件1 (200B), 文件2 (800B), 总计 1000B
      final p0 = HomeworkSubmissionPage.computeUploadProgress(
        uploadedBytesBefore: 0,
        currentFileSentBytes: 0,
        currentFileTotalBytes: 200,
        totalBytes: 1000,
        fileIndex: 0,
        fileCount: 2,
      );
      final p1 = HomeworkSubmissionPage.computeUploadProgress(
        uploadedBytesBefore: 0,
        currentFileSentBytes: 200,
        currentFileTotalBytes: 200,
        totalBytes: 1000,
        fileIndex: 0,
        fileCount: 2,
      );
      final p2 = HomeworkSubmissionPage.computeUploadProgress(
        uploadedBytesBefore: 200,
        currentFileSentBytes: 400,
        currentFileTotalBytes: 800,
        totalBytes: 1000,
        fileIndex: 1,
        fileCount: 2,
      );
      final p3 = HomeworkSubmissionPage.computeUploadProgress(
        uploadedBytesBefore: 200,
        currentFileSentBytes: 800,
        currentFileTotalBytes: 800,
        totalBytes: 1000,
        fileIndex: 1,
        fileCount: 2,
      );

      expect(p0, closeTo(0.04, 0.001));
      expect(p1, closeTo(0.04 + 0.2 * 0.86, 0.001));
      expect(p2, closeTo(0.04 + 0.6 * 0.86, 0.001));
      expect(p3, closeTo(0.90, 0.001));

      // 空文件边界不崩溃且单调有效
      final zeroByte = HomeworkSubmissionPage.computeUploadProgress(
        uploadedBytesBefore: 0,
        currentFileSentBytes: 0,
        currentFileTotalBytes: 0,
        totalBytes: 0,
        fileIndex: 0,
        fileCount: 1,
      );
      expect(zeroByte, closeTo(0.90, 0.001));
    });

    test('resolveHomeworkBadgeStyle 准确区分已批改/已提交/逾期/待提交状态', () {
      final future = DateTime.now().add(const Duration(days: 2));
      final past = DateTime.now().subtract(const Duration(days: 1));

      expect(
        resolveHomeworkBadgeStyle(
          isQuiz: false,
          isSubmitted: true,
          isGraded: true,
          score: 92,
          endTime: past,
        ).text,
        '已批改 · 92分',
      );
      expect(
        resolveHomeworkBadgeStyle(
          isQuiz: true,
          isSubmitted: true,
          isGraded: false,
          endTime: past,
        ).text,
        '已作答',
      );
      expect(
        resolveHomeworkBadgeStyle(
          isQuiz: false,
          isSubmitted: false,
          isGraded: false,
          endTime: past,
        ).text,
        '逾期',
      );
      expect(
        resolveHomeworkBadgeStyle(
          isQuiz: false,
          isSubmitted: false,
          isGraded: false,
          endTime: future,
        ).text,
        '待提交',
      );
    });
  });
}
