import 'package:celechron/model/todo.dart';
import 'package:celechron/services/todo_task_sync.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 学在浙大作业提交链接操作面板（打开 / 复制 / 探测提交状态），供作业卡片与任务详情复用。
void showTodoSubmitSheet(BuildContext context, String url,
    {String? title, String? courseId, String? activityId}) {
  String? cid = courseId;
  String? aid = activityId;
  if (cid == null || aid == null) {
    final match =
        RegExp(r'/course/(\d+)/learning-activity#/(\d+)').firstMatch(url);
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
                Icon(CupertinoIcons.search, size: 18),
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
          child: const Text('打开提交页面'),
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
      onTap: () => showTodoSubmitSheet(
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
    final status = todo.effectiveStatus;
    Color bg;
    Color fg;
    IconData icon;
    String text = todo.statusText;

    switch (status) {
      case HomeworkSubmissionStatus.graded:
        bg = CupertinoColors.systemOrange.withValues(alpha: 0.15);
        fg = CupertinoColors.systemOrange;
        icon = CupertinoIcons.star_fill;
        break;
      case HomeworkSubmissionStatus.submitted:
        bg = CupertinoColors.systemGreen.withValues(alpha: 0.15);
        fg = CupertinoColors.systemGreen;
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case HomeworkSubmissionStatus.overdue:
        bg = CupertinoColors.systemRed.withValues(alpha: 0.12);
        fg = CupertinoColors.systemRed;
        icon = CupertinoIcons.exclamationmark_circle_fill;
        break;
      case HomeworkSubmissionStatus.unsubmitted:
        bg = CupertinoColors.activeBlue.withValues(alpha: 0.12);
        fg = CupertinoColors.activeBlue;
        icon = CupertinoIcons.clock;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    var brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.of(context).platformBrightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: brightness == Brightness.dark
            ? CupertinoColors.secondarySystemFill
            : CupertinoColors.systemGroupedBackground,
        // boxShadow
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        // add a colored edge
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  todo.course,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  strutStyle:
                      const StrutStyle(leading: 0.5, forceStrutHeight: true),
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
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
            strutStyle: const StrutStyle(leading: 0.5, forceStrutHeight: true),
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: brightness == Brightness.dark
                      ? CupertinoColors.systemBackground
                      : CupertinoTheme.of(context).textTheme.textStyle.color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            todo.endTime != null ? toStringHumanReadable(todo.endTime!) : "无",
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: brightness == Brightness.dark
                      ? CupertinoColors.systemBackground
                      : CupertinoTheme.of(context).textTheme.textStyle.color,
                ),
          ),
        ],
      ),
    );
  }
}
