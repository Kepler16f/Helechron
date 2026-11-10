import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/model/exam.dart';
import 'package:celechron/model/scholar.dart';

/// 「接下来」页顶部的考试周横幅。
///
/// 近 [lookAheadDays] 天内有考试（或正在考试）时出现：
/// 突出下一场考试的倒计时、考场与座位，并列出其后的几场考试。
/// 没有临近的考试时整个组件不占空间。
class ExamWeekBanner extends StatelessWidget {
  const ExamWeekBanner({super.key, required this.now});

  /// 由首页控制器每秒推进的当前时间，用于刷新倒计时。
  final Rx<DateTime> now;

  static const int lookAheadDays = 14;
  static const int _maxListed = 4;

  /// 取 [at] 时刻起未结束、且开考时间在 [lookAheadDays] 天内的考试，按开考时间排序。
  static List<Exam> upcomingExams(Iterable<Exam> all, DateTime at) {
    final horizon = at.add(const Duration(days: lookAheadDays));
    final list = all
        .where((e) =>
            e.time.length >= 2 &&
            e.time[1].isAfter(at) &&
            e.time[0].isBefore(horizon))
        .toList()
      ..sort((a, b) => a.time[0].compareTo(b.time[0]));
    return list;
  }

  static String countdownText(Exam exam, DateTime at) {
    if (!exam.time[0].isAfter(at)) {
      final left = exam.time[1].difference(at);
      return '考试进行中 · 剩余 ${_fmt(left)}';
    }
    return '距开考 ${_fmt(exam.time[0].difference(at))}';
  }

  static String _fmt(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天 ${d.inHours % 24} 小时';
    if (d.inHours >= 1) return '${d.inHours} 小时 ${d.inMinutes % 60} 分钟';
    return '${d.inMinutes.clamp(0, 59)} 分钟';
  }

  @override
  Widget build(BuildContext context) {
    final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
    return Obx(() {
      final at = now.value;
      final exams = upcomingExams(
          scholar.value.semesters.expand((s) => s.exams), at);
      if (exams.isEmpty) return const SizedBox.shrink();
      return _buildBanner(context, exams, at);
    });
  }

  Widget _buildBanner(BuildContext context, List<Exam> exams, DateTime at) {
    final next = exams.first;
    final inProgress = !next.time[0].isAfter(at);
    final accent =
        inProgress ? CupertinoColors.systemRed : CupertinoColors.systemOrange;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final secondary =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final others = exams.skip(1).take(_maxListed).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
      child: Column(
        children: [
          SubtitleRow(subtitle: '考试周'),
          RoundRectangleCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          next.type == ExamType.finalExam ? '期末' : '期中',
                          style: const TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          next.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    countdownText(next, at),
                    style: textStyle.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: accent),
                  ),
                  const SizedBox(height: 8),
                  _infoRow(context, CupertinoIcons.clock, next.chineseTime),
                  const SizedBox(height: 4),
                  _infoRow(context, CupertinoIcons.location_solid,
                      next.location?.isNotEmpty == true ? next.location! : '考场未知'),
                  const SizedBox(height: 4),
                  _infoRow(context, CupertinoIcons.square_grid_2x2,
                      '座位 ${next.seat?.isNotEmpty == true ? next.seat! : '未分配'}'),
                  const SizedBox(height: 8),
                  Text('带好：身份证 · 校园卡 · 文具 · 计算器（按考试要求）',
                      style: TextStyle(fontSize: 12, color: secondary)),
                  if (others.isNotEmpty) ...[
                    Divider(
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                      height: 20,
                      thickness: 0,
                    ),
                    for (final e in others)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle.copyWith(fontSize: 14)),
                            ),
                            const SizedBox(width: 8),
                            Text(e.chineseDate,
                                style:
                                    TextStyle(fontSize: 13, color: secondary)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final color =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(fontSize: 14)),
        ),
      ],
    );
  }
}
