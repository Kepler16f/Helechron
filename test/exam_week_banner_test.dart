import 'package:flutter_test/flutter_test.dart';

import 'package:celechron/model/exam.dart';
import 'package:celechron/page/flow/exam_week_banner.dart';

Exam _exam(String name, DateTime start, Duration length) {
  final e = Exam.empty()
    ..id = name
    ..name = name
    ..time = [start, start.add(length)];
  return e;
}

void main() {
  final now = DateTime(2026, 1, 10, 9, 0);

  test('只保留未结束且 14 天内开考的考试，并按开考时间排序', () {
    final later = _exam('later', now.add(const Duration(days: 5)), const Duration(hours: 2));
    final sooner = _exam('sooner', now.add(const Duration(days: 1)), const Duration(hours: 2));
    final tooFar = _exam('tooFar', now.add(const Duration(days: 30)), const Duration(hours: 2));
    final finished = _exam('finished', now.subtract(const Duration(days: 1)), const Duration(hours: 2));
    final running = _exam('running', now.subtract(const Duration(minutes: 30)), const Duration(hours: 2));

    final result = ExamWeekBanner.upcomingExams(
        [later, tooFar, finished, sooner, running], now);

    expect(result.map((e) => e.name), ['running', 'sooner', 'later']);
  });

  test('倒计时文案：开考前按天/小时/分钟，考试中显示剩余时间', () {
    final inTwoDays =
        _exam('a', now.add(const Duration(days: 2, hours: 3)), const Duration(hours: 2));
    final inNinety =
        _exam('b', now.add(const Duration(minutes: 90)), const Duration(hours: 2));
    final inTen =
        _exam('c', now.add(const Duration(minutes: 10)), const Duration(hours: 2));
    final running =
        _exam('d', now.subtract(const Duration(minutes: 30)), const Duration(hours: 2));

    expect(ExamWeekBanner.countdownText(inTwoDays, now), '距开考 2 天 3 小时');
    expect(ExamWeekBanner.countdownText(inNinety, now), '距开考 1 小时 30 分钟');
    expect(ExamWeekBanner.countdownText(inTen, now), '距开考 10 分钟');
    expect(ExamWeekBanner.countdownText(running, now), '考试进行中 · 剩余 1 小时 30 分钟');
  });
}
