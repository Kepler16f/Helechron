import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:flutter_test/flutter_test.dart';

Semester _semesterWithSession(String name, String courseName) {
  return Semester.fromJson({
    'name': name,
    'sessions': [
      {
        'id': '$name-$courseName',
        'name': courseName,
        'teacher': '测试教师',
        'confirmed': true,
        'firstHalf': true,
        'secondHalf': true,
        'oddWeek': true,
        'evenWeek': true,
        'day': 1,
        'time': [1, 2],
        'location': '紫金港测试楼',
      }
    ],
  });
}

/// 只有考试、没有课程安排的学期：模拟课表查询被清空、但成绩/考试仍可查的情况。
Semester _semesterWithExamOnly(String name, String examName) {
  return Semester.fromJson({
    'name': name,
    'exams': [
      {
        'id': '$name-$examName',
        'name': examName,
        'type': 0,
        'time': ['2026-01-20T15:30:00.000', '2026-01-20T17:30:00.000'],
        'location': '紫金港测试楼',
        'seat': '1',
      }
    ],
  });
}

void main() {
  test('空课表保护：缺失的学期补回，空学期沿用缓存并上报降级', () {
    final scholar = Scholar();
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '现行课'),
      _semesterWithSession('2024-2025春夏', '历史课'),
    ], {}, const [], {}, const [], null);
    expect(scholar.semesters.length, 2);

    // 模拟选课期空响应：当前学期整段被移除，历史学期只剩空对象
    final guards = <String>[];
    scholar.setScholar(const [], [
      Semester('2024-2025春夏'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards.length, 1);
    expect(isDegradedRefreshText(guards.first), true);
    expect(guards.first.contains('课表'), true);

    expect(scholar.semesters.length, 2);
    final autumn =
        scholar.semesters.firstWhere((e) => e.name == '2025-2026秋冬');
    expect(autumn.sessions.map((e) => e.name), contains('现行课'));
    final spring =
        scholar.semesters.firstWhere((e) => e.name == '2024-2025春夏');
    expect(spring.sessions.map((e) => e.name), contains('历史课'));
  });

  test('空课表保护：沿用缓存的同时吸收新结果里的考试增量', () {
    final scholar = Scholar();
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '现行课'),
    ], {}, const [], {}, const [], null);

    final guards = <String>[];
    scholar.setScholar(const [], [
      _semesterWithExamOnly('2025-2026秋冬', '新发布的考试'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards.length, 1);
    final autumn =
        scholar.semesters.firstWhere((e) => e.name == '2025-2026秋冬');
    expect(autumn.sessions.map((e) => e.name), contains('现行课'));
    expect(autumn.exams.map((e) => e.name), contains('新发布的考试'));
  });

  test('有课程数据时正常替换，不触发保护', () {
    final scholar = Scholar();
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '旧课'),
    ], {}, const [], {}, const [], null);

    final guards = <String>[];
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '新课'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards, isEmpty);
    expect(scholar.semesters.single.sessions.map((e) => e.name), ['新课']);
  });

  test('首次登录无缓存时不触发保护', () {
    final scholar = Scholar();
    final guards = <String>[];
    scholar.setScholar(const [], [
      Semester('2025-2026秋冬'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards, isEmpty);
    expect(scholar.semesters.single.name, '2025-2026秋冬');
    expect(scholar.semesters.single.sessions, isEmpty);
  });

  test('降级错误不阻止整表替换，守护仍然生效', () {
    final scholar = Scholar();
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '现行课'),
    ], {}, const [], {}, const [], null);

    final guards = <String>[];
    scholar.setScholar([
      degradedRefreshText('课表：使用缓存降级'),
    ], [
      Semester('2025-2026秋冬'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards.length, 1);
    expect(
        scholar.semesters.single.sessions.map((e) => e.name), contains('现行课'));
  });

  test('非降级课表错误仍走增量合并分支，缓存保持不变', () {
    final scholar = Scholar();
    scholar.setScholar(const [], [
      _semesterWithSession('2025-2026秋冬', '现行课'),
    ], {}, const [], {}, const [], null);

    final guards = <String>[];
    scholar.setScholar([
      '课表查询出错：测试错误',
    ], [
      Semester('2025-2026秋冬'),
    ], {}, const [], {}, const [], null, emptyGuardMessages: guards);

    expect(guards, isEmpty);
    expect(
        scholar.semesters.single.sessions.map((e) => e.name), contains('现行课'));
  });
}
