import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/utils/period_icon_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Period makePeriod({
    required PeriodType type,
    required String summary,
    String location = '',
  }) {
    final start = DateTime(2026, 11, 25, 10, 0);
    return Period(
      type: type,
      summary: summary,
      location: location,
      startTime: start,
      endTime: start.add(const Duration(minutes: 95)),
    );
  }

  test('distinguishes PE/fitness, exam, and regular indoor courses', () {
    expect(
      resolvePeriodIcon(
        makePeriod(
          type: PeriodType.classes,
          summary: '体育(II) 篮球',
          location: '紫金港西田径场',
        ),
      ),
      AelIcons.sport,
    );
    expect(
      resolvePeriodIcon(
        makePeriod(
          type: PeriodType.classes,
          summary: '身体素质拓展',
          location: '风雨操场',
        ),
      ),
      AelIcons.sport,
    );
    expect(
      resolvePeriodIcon(
        makePeriod(
          type: PeriodType.test,
          summary: '数据结构期末考试',
          location: '东1A-301',
        ),
      ),
      AelIcons.exam,
    );
    expect(
      resolvePeriodIcon(
        makePeriod(
          type: PeriodType.classes,
          summary: 'Python程序设计',
          location: '紫金港东1A-301',
        ),
      ),
      AelIcons.book,
    );
  });
}
