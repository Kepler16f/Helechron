import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';

class CourseBriefCard extends StatelessWidget {
  final Course course;
  final bool allowDirect;
  final bool showZhiyunInDetail;

  const CourseBriefCard({
    required this.course,
    this.allowDirect = false,
    this.showZhiyunInDetail = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return AelSectionCard(
      cornerRadius: AelRadius.tile,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: allowDirect
          ? () async => Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (context) => CourseDetailPage(
                  courseId: course.id,
                  showZhiyun: showZhiyunInDetail,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10.0,
                height: 10.0,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                course.credit > 0
                    ? '${course.credit.toStringAsFixed(1)} 学分'
                    : '待更新',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              Icon(AelIcons.file, size: 13, color: colors.textTertiary),
              const SizedBox(width: 4.0),
              Expanded(
                child: Text(
                  '课号：${course.realId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3.0),
          Row(
            children: [
              Icon(AelIcons.teacher, size: 13, color: colors.textTertiary),
              const SizedBox(width: 4.0),
              Expanded(
                child: Text(
                  '教师：${course.teacher ?? '未知'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ),
              if (course.grade != null) ...[
                Icon(AelIcons.award, size: 13, color: colors.success),
                const SizedBox(width: 4.0),
                Text(
                  '成绩：${course.grade!.original == "" ? course.grade!.hundredPoint : course.grade!.original} / ${course.grade!.original == "" ? 100 : course.grade!.fivePoint.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.success,
                  ),
                ),
              ],
            ],
          ),
          if (course.online == true || course.type != null) ...[
            const SizedBox(height: 6.0),
            Row(
              children: [
                if (course.online == true) ...[
                  Icon(AelIcons.globe, size: 13, color: colors.textTertiary),
                  const SizedBox(width: 4.0),
                  Text(
                    '线上课程',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 8.0),
                ],
                if (course.type != null) ...[
                  AelChip(label: course.type!, tone: AelChipTone.neutral),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
