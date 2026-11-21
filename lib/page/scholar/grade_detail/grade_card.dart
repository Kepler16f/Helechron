import 'package:flutter/cupertino.dart'
    show CupertinoCheckbox, CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';
import 'package:celechron/page/scholar/grade_detail/grade_detail_controller.dart';
import 'package:celechron/services/diagnostic_log_service.dart';

class GradeCard extends StatelessWidget {
  final Grade grade;

  const GradeCard({super.key, required this.grade});

  bool _isHighlighted(GradeDetailController controller) {
    return !controller.customGpaMode.value ||
        (controller.customGpaSelected[grade.id] ?? false);
  }

  void _openCourseDetail(BuildContext context) {
    try {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) =>
              CourseDetailPage(courseId: grade.id, showZhiyun: false),
        ),
      );
    } catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.error,
        module: 'grade',
        operation: 'openCourseDetail',
        message: 'gradeId=${grade.id}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleTap(BuildContext context, GradeDetailController controller) {
    if (controller.customGpaMode.value) {
      final cur = controller.customGpaSelected[grade.id] ?? false;
      controller.customGpaSelected[grade.id] = !cur;
      controller.refreshCustomGpa();
    } else {
      _openCourseDetail(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final controller = Get.find<GradeDetailController>();

    return Obx(() {
      final highlighted = _isHighlighted(controller);
      final customMode = controller.customGpaMode.value;

      return AelSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        cornerRadius: AelRadius.tile,
        onTap: () => _handleTap(context, controller),
        onLongPress: () => _openCourseDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (customMode)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    child: SizedBox(
                      height: 32.0,
                      width: 32.0,
                      child: CupertinoCheckbox(
                        activeColor: colors.primary,
                        value: controller.customGpaSelected[grade.id] ?? false,
                        onChanged: (bool? value) {
                          if (value != null) {
                            controller.customGpaSelected[grade.id] = value;
                            controller.refreshCustomGpa();
                          }
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        grade.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: highlighted
                              ? colors.textPrimary
                              : colors.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${grade.realId} / ${grade.credit.toStringAsFixed(1)} 学分',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${grade.original} / ${grade.fivePoint.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: highlighted
                        ? colors.textPrimary
                        : colors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.tonalTileBg,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ((grade.fivePoint - 1.4) / 3.6).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: highlighted ? colors.primary : colors.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
