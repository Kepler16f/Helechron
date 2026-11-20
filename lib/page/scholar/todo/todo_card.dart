import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/custom_decoration.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/task/homework_submission_page.dart';
import 'package:celechron/services/todo_task_sync.dart';
import 'package:celechron/utils/utils.dart';

class HomeworkBadgeStyle {
  final Color background;
  final Color foreground;
  final IconData icon;
  final String text;

  const HomeworkBadgeStyle({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.text,
  });
}

/// 统一计算作业/小测状态标签的配色、图标与文案，供任务页、课程详情页与待办卡片共用。
HomeworkBadgeStyle resolveHomeworkBadgeStyle({
  AelColorTokens? colors,
  required bool isQuiz,
  required bool isSubmitted,
  required bool isGraded,
  double? score,
  DateTime? endTime,
  String? customOverdueText,
}) {
  final resolvedColors = colors ?? AelTheme.fallback(Brightness.light);
  final isOverdue =
      !isSubmitted &&
      !isGraded &&
      endTime != null &&
      endTime.isBefore(DateTime.now());

  if (isGraded && score != null) {
    final scoreText = score == score.roundToDouble()
        ? score.toInt().toString()
        : score.toStringAsFixed(1);
    return HomeworkBadgeStyle(
      background: resolvedColors.warningContainer,
      foreground: resolvedColors.onWarningContainer,
      icon: AelIcons.award,
      text: '已批改 · $scoreText分',
    );
  }
  if (isGraded || isSubmitted) {
    return HomeworkBadgeStyle(
      background: resolvedColors.successContainer,
      foreground: resolvedColors.onSuccessContainer,
      icon: AelIcons.success,
      text: isGraded ? '已批改' : (isQuiz ? '已作答' : '已提交'),
    );
  }
  if (isOverdue) {
    return HomeworkBadgeStyle(
      background: resolvedColors.errorContainer,
      foreground: resolvedColors.onErrorContainer,
      icon: AelIcons.warning,
      text: customOverdueText ?? '逾期',
    );
  }
  if (isQuiz) {
    return HomeworkBadgeStyle(
      background: resolvedColors.infoContainer,
      foreground: resolvedColors.onInfoContainer,
      icon: AelIcons.edit,
      text: '待作答',
    );
  }
  return HomeworkBadgeStyle(
    background: resolvedColors.primaryContainer,
    foreground: resolvedColors.onPrimaryContainer,
    icon: AelIcons.homework,
    text: '待提交',
  );
}

class HomeworkStatusPill extends StatelessWidget {
  final HomeworkBadgeStyle style;
  final VoidCallback? onPressed;
  final double borderRadius;
  final EdgeInsets padding;

  const HomeworkStatusPill({
    super.key,
    required this.style,
    this.onPressed,
    this.borderRadius = AelRadius.pill,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    final badgeBody = DecoratedBox(
      decoration: ShapeDecoration(
        color: style.background,
        shape: AelShapes.squircle(borderRadius),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 11, color: style.foreground),
            const SizedBox(width: 3),
            Text(
              style.text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: style.foreground,
              ),
            ),
          ],
        ),
      ),
    );
    if (onPressed == null) return badgeBody;
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: badgeBody,
    );
  }
}

/// 作业条目共享正文视图（含圆点、标题+状态标签、课程名+去提交/查看提交按钮、截止时间），
/// 供任务页面与课程详情“作业”卡片统一复用。
class HomeworkTaskItemContent extends StatelessWidget {
  final Color indicatorColor;
  final String title;
  final String courseName;
  final DateTime? endTime;
  final bool isQuiz;
  final bool isSubmitted;
  final bool isGraded;
  final double? score;
  final double titleFontSize;
  final VoidCallback? onOpenSubmission;

  const HomeworkTaskItemContent({
    super.key,
    required this.indicatorColor,
    required this.title,
    required this.courseName,
    required this.endTime,
    required this.isQuiz,
    required this.isSubmitted,
    required this.isGraded,
    this.score,
    this.titleFontSize = 16.5,
    this.onOpenSubmission,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final isDone = isSubmitted || isGraded;
    final badgeStyle = resolveHomeworkBadgeStyle(
      colors: colors,
      isQuiz: isQuiz,
      isSubmitted: isSubmitted,
      isGraded: isGraded,
      score: score,
      endTime: endTime,
    );
    final overdueSuffix =
        !isDone && endTime != null && endTime!.isBefore(DateTime.now())
        ? ' - 已过期'
        : '';
    final deadlineLabel = endTime != null
        ? ' 截止于：${toStringHumanReadable(endTime!)}$overdueSuffix'
        : ' 截止于：无截止时间';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10.0,
              height: 10.0,
              decoration: customDecoration(
                color: indicatorColor,
                shape: periodTypeShape[PeriodType.user]!,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            HomeworkStatusPill(style: badgeStyle, onPressed: onOpenSubmission),
          ],
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            Icon(AelIcons.book, size: 13.5, color: colors.textTertiary),
            const SizedBox(width: 5.0),
            Expanded(
              child: Text(
                courseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
            ),
            if (onOpenSubmission != null) ...[
              const SizedBox(width: 6.0),
              CupertinoButton(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: isDone
                    ? colors.successContainer
                    : colors.primaryContainer,
                borderRadius: BorderRadius.circular(AelRadius.pill),
                onPressed: onOpenSubmission,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AelIcons.externalLink,
                      size: 12,
                      color: isDone
                          ? colors.onSuccessContainer
                          : colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isDone ? '查看提交' : (isQuiz ? '去作答' : '去提交'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDone
                            ? colors.onSuccessContainer
                            : colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4.0),
        Row(
          children: [
            Icon(AelIcons.activity, size: 13.5, color: colors.textTertiary),
            Expanded(
              child: Text(
                deadlineLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 学在浙大作业提交链接操作面板（打开 / 复制 / 探测提交状态），供作业卡片与任务详情复用。
void showTodoSubmitSheet(
  BuildContext context,
  String url, {
  String? title,
  String? courseId,
  String? activityId,
}) {
  String? cid = courseId;
  String? aid = activityId;
  if (cid == null || aid == null) {
    final match = RegExp(
      r'/course/(\d+)/learning-activity#/(\d+)',
    ).firstMatch(url);
    if (match != null) {
      cid ??= match.group(1);
      aid ??= match.group(2);
    }
  }

  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(title ?? '学在浙大作业'),
      message: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
      actions: [
        if (aid != null)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => HomeworkSubmissionPage(
                    activityId: aid,
                    courseId: cid,
                    title: title,
                    submitUrl: url,
                  ),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AelIcons.edit, size: 18),
                SizedBox(width: 6),
                Text('应用内查看与提交'),
              ],
            ),
          ),
        if (cid != null && aid != null)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              TodoTaskSync.probeSingleHomework(
                context,
                courseId: cid!,
                activityId: aid!,
                title: title,
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AelIcons.search, size: 18),
                SizedBox(width: 6),
                Text('探测作业提交状态'),
              ],
            ),
          ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.of(ctx).pop();
            launchUrlString(url, mode: LaunchMode.externalApplication);
          },
          child: const Text('打开网页提交页面'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.of(ctx).pop();
            Clipboard.setData(ClipboardData(text: url));
          },
          child: const Text('复制提交链接'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('取消'),
      ),
    ),
  );
}

/// 从任务说明文本中提取学在浙大链接。
String? extractCoursesUrl(String text) =>
    RegExp(r'https://courses\.zju\.edu\.cn\S+').firstMatch(text)?.group(0);

class TodoCard extends StatelessWidget {
  final Todo todo;

  const TodoCard({super.key, required this.todo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (context) => HomeworkSubmissionPage(todo: todo),
        ),
      ),
      onLongPress: () => showTodoSubmitSheet(
        context,
        todo.submitUrl,
        title: '${todo.course} · ${todo.name}',
        courseId: todo.resolvedCourseId,
        activityId: todo.id,
      ),
      child: _buildCard(context),
    );
  }

  Widget _buildStatusBadge(BuildContext context, Todo todo) {
    final colors = AelTheme.colorsOf(context);
    final style = resolveHomeworkBadgeStyle(
      colors: colors,
      isQuiz: todo.isQuiz,
      isSubmitted: todo.isSubmitted,
      isGraded: todo.isGraded,
      score: todo.score,
      endTime: todo.endTime,
      customOverdueText: todo.statusText,
    );
    return HomeworkStatusPill(
      style: style,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.tonalTileBg,
        shape: AelShapes.squircle(AelRadius.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (todo.isQuiz)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: ShapeDecoration(
                      color: colors.infoContainer,
                      shape: AelShapes.squircle(4),
                    ),
                    child: Text(
                      '测验',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.onInfoContainer,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    todo.course,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildStatusBadge(context, todo),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              todo.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              todo.endTime != null ? toStringHumanReadable(todo.endTime!) : '无',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
