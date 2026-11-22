import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
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
    final list =
        all
            .where(
              (e) =>
                  e.time.length >= 2 &&
                  e.time[1].isAfter(at) &&
                  e.time[0].isBefore(horizon),
            )
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
        scholar.value.semesters.expand((s) => s.exams),
        at,
      );
      if (exams.isEmpty) return const SizedBox.shrink();
      return _buildBanner(context, exams, at);
    });
  }

  Widget _buildBanner(BuildContext context, List<Exam> exams, DateTime at) {
    final colors = AelTheme.colorsOf(context);
    final next = exams.first;
    final inProgress = !next.time[0].isAfter(at);
    final accent = inProgress ? colors.error : colors.warning;
    final others = exams.skip(1).take(_maxListed).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AelSpacing.pageHorizontal,
        0,
        AelSpacing.pageHorizontal,
        AelSpacing.sectionGap,
      ),
      child: AelSectionCard(
        icon: AelIcons.exam,
        title: '考试周',
        trailing: AelChip(
          label: next.type == ExamType.finalExam ? '期末' : '期中',
          tone: inProgress ? AelChipTone.error : AelChipTone.warning,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AelIconBadge(
                  icon: AelIcons.award,
                  style: AelIconBadgeStyle.cookie,
                  backgroundColor: inProgress
                      ? colors.errorContainer
                      : colors.warningContainer,
                  iconColor: inProgress
                      ? colors.onErrorContainer
                      : colors.onWarningContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        countdownText(next, at),
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AelSpacing.md),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AelStatTile(
                      icon: AelIcons.location,
                      iconColor: accent,
                      label: '考场',
                      value: next.location?.isNotEmpty == true
                          ? next.location!
                          : '待公布',
                      valueFontSize: 15,
                      valueMaxLines: 2,
                      subtitle: next.chineseTime,
                    ),
                  ),
                  const SizedBox(width: AelSpacing.sm),
                  Expanded(
                    child: AelStatTile(
                      icon: AelIcons.exam,
                      iconColor: accent,
                      label: '座位号',
                      value: next.seat?.isNotEmpty == true ? next.seat! : '未分配',
                      valueFontSize: 18,
                      subtitle: '携带证件与文具',
                    ),
                  ),
                ],
              ),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: AelSpacing.md),
              for (int i = 0; i < others.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                AelListRow(
                  title: others[i].name,
                  trailing: Text(
                    others[i].chineseDate,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  showChevron: false,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
