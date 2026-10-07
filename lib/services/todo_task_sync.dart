import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/json_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// 将学在浙大作业 (Todo) 按照任务样式与时间顺序自动同步为 DDL 任务，并支持提交与出分状态探测。
class TodoTaskSync {
  static const String kOptionAutoSyncTodoToTask = 'autoSyncTodoToTask';
  static const String kHomeworkStatusMapKey = 'homework_status_map';
  static const String _todoPrefix = 'courses-todo:';

  /// 检查是否启用了自动同步（默认开启）
  static bool isAutoSyncEnabled() {
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        return box.get(kOptionAutoSyncTodoToTask, defaultValue: true) as bool;
      }
    } catch (e) {
      debugPrint('TodoTaskSync: failed to read dbOptions: $e');
    }
    return true;
  }

  /// 设置是否启用自动同步
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        await box.put(kOptionAutoSyncTodoToTask, enabled);
      }
    } catch (e) {
      debugPrint('TodoTaskSync: failed to write dbOptions: $e');
    }
  }

  /// 读取所有已持久化的作业提交与打分状态
  static Map<String, dynamic> _getStatusMap() {
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        final raw = box.get(kHomeworkStatusMapKey);
        if (raw is String && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } else if (raw is Map) {
          return Map<String, dynamic>.from(raw);
        }
      }
    } catch (e) {
      debugPrint('TodoTaskSync: failed to read status map: $e');
    }
    return <String, dynamic>{};
  }

  /// 记录单项作业的完成度与得分记录
  static void recordHomeworkStatus(
    String activityId, {
    String? completeness,
    double? score,
    DateTime? submittedAt,
  }) {
    if (activityId.isEmpty) return;
    try {
      if (Hive.isBoxOpen('dbOptions')) {
        final box = Hive.box('dbOptions');
        final map = _getStatusMap();
        final existing =
            (map[activityId] as Map?)?.cast<String, dynamic>() ?? {};
        if (completeness != null && completeness.isNotEmpty) {
          existing['completeness'] = completeness;
        }
        if (score != null) {
          existing['score'] = score;
        }
        if (submittedAt != null) {
          existing['submitted_at'] = submittedAt.toIso8601String();
        }
        existing['updated_at'] = DateTime.now().toIso8601String();
        map[activityId] = existing;
        box.put(kHomeworkStatusMapKey, jsonEncode(map));
      }
    } catch (e) {
      debugPrint('TodoTaskSync.recordHomeworkStatus error: $e');
    }
  }

  /// 获取指定作业的持久化探测状态
  static Map<String, dynamic>? getHomeworkStatus(String activityId) {
    if (activityId.isEmpty) return null;
    final map = _getStatusMap();
    final entry = map[activityId];
    if (entry is Map) return Map<String, dynamic>.from(entry);
    return null;
  }

  /// 便捷入口：从全局 Scholar 实例同步作业
  static void syncFromScholar() {
    if (!isAutoSyncEnabled()) return;
    try {
      if (!Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) return;
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
      sync(scholar.todos);
    } catch (e) {
      debugPrint('TodoTaskSync.syncFromScholar error: $e');
    }
  }

  /// 同步作业列表到任务列表 (taskList)
  static void sync(List<Todo> todos) {
    if (!isAutoSyncEnabled() || todos.isEmpty) return;
    if (!Get.isRegistered<RxList<Task>>(tag: 'taskList')) return;

    final taskList = Get.find<RxList<Task>>(tag: 'taskList');
    final existingTodoTasks = <String, Task>{};

    for (final task in taskList) {
      if (task.fromUid != null && task.fromUid!.startsWith(_todoPrefix)) {
        existingTodoTasks[task.fromUid!] = task;
      }
    }

    bool hasChanged = false;
    final now = DateTime.now();

    for (final todo in todos) {
      if (todo.id.isEmpty || todo.endTime == null) continue;

      // 超过 14 天前的旧作业不再自动导入
      if (todo.endTime!.isBefore(now.subtract(const Duration(days: 14)))) {
        continue;
      }

      final key = '$_todoPrefix${todo.id}';
      final existingTask = existingTodoTasks[key];

      final recorded = getHomeworkStatus(todo.id);
      final isSubmitted = todo.isSubmitted ||
          recorded?['completeness'] == 'full' ||
          recorded?['score'] != null;

      final expectedSummary = '作业：${todo.name}';
      final expectedDescription =
          '课程：${todo.course}\n来源：学在浙大\n提交：${todo.submitUrl}';

      if (existingTask != null) {
        // 已存在任务：若为旧版本生成的 DDL 任务，自动平滑升级为作业专属样式
        bool modified = false;
        if (existingTask.type != TaskType.homework) {
          existingTask.type = TaskType.homework;
          existingTask.timeNeeded = Duration.zero;
          existingTask.timeSpent = Duration.zero;
          existingTask.isBreakable = false;
          modified = true;
        }
        if (existingTask.endTime != todo.endTime) {
          existingTask.endTime = todo.endTime!;
          modified = true;
        }
        if (existingTask.summary != expectedSummary) {
          existingTask.summary = expectedSummary;
          modified = true;
        }
        if (existingTask.description != expectedDescription &&
            existingTask.description.contains('来源：学在浙大')) {
          existingTask.description = expectedDescription;
          hasChanged = true;
        }
        if (isSubmitted && existingTask.status != TaskStatus.completed) {
          existingTask.status = TaskStatus.completed;
          modified = true;
        }
        if (modified) {
          existingTask.refreshStatus();
          hasChanged = true;
        }
      } else {
        // 新作业：创建作业任务（独立于 DDL 样式）
        final taskStatus = isSubmitted
            ? TaskStatus.completed
            : (todo.endTime!.isBefore(now)
                ? TaskStatus.failed
                : TaskStatus.running);

        final newTask = Task(
          uid: const Uuid().v4(),
          status: taskStatus,
          description: expectedDescription,
          timeSpent: Duration.zero,
          timeNeeded: Duration.zero,
          endTime: todo.endTime!,
          location: '',
          summary: expectedSummary,
          isBreakable: false,
          type: TaskType.homework,
          startTime: now,
          repeatType: TaskRepeatType.norepeat,
          repeatPeriod: 1,
          repeatEndsTime: todo.endTime!,
          blockArrangements: false,
          fromUid: key,
        );

        taskList.add(newTask);
        existingTodoTasks[key] = newTask;
        hasChanged = true;
      }
    }

    // 差量状态推断：若此前在 todo 列表中、但本次刷新已消失，且在截止时间附近，推断为已完成
    for (final entry in existingTodoTasks.entries) {
      final aid = entry.key.substring(_todoPrefix.length);
      final inNewTodos = todos.any((t) => t.id == aid);
      if (!inNewTodos) {
        final recorded = getHomeworkStatus(aid);
        final task = entry.value;
        if (task.status == TaskStatus.running) {
          final isSubmitted =
              recorded?['completeness'] == 'full' || recorded?['score'] != null;
          if (isSubmitted ||
              now.isBefore(task.endTime.add(const Duration(days: 3)))) {
            task.status = TaskStatus.completed;
            hasChanged = true;
          }
        }
      }
    }

    if (hasChanged) {
      // 按照截止时间升序排序
      taskList.sort((a, b) => a.endTime.compareTo(b.endTime));

      // 若 TaskController 已注册，触发更新和存库
      if (Get.isRegistered<TaskController>()) {
        final taskController = Get.find<TaskController>();
        taskController.updateDeadlineList();
        taskController.updateDeadlineListTime();
      } else if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
        final db = Get.find<DatabaseHelper>(tag: 'db');
        db.setTaskList(taskList);
        db.setTaskListUpdateTime(DateTime.now());
      }
      taskList.refresh();
    }
  }

  /// 手动/即时探测单项作业在学在浙大上的提交状态并向用户弹窗反馈
  static Future<Map<String, dynamic>?> probeSingleHomework(
    BuildContext context, {
    required String courseId,
    required String activityId,
    String? title,
  }) async {
    // 显示加载弹窗
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CupertinoAlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(radius: 14),
              SizedBox(height: 12),
              Text('正在向学在浙大探测作业状态...'),
            ],
          ),
        ),
      ),
    );

    Map<String, dynamic>? match;
    String? errorMsg;

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      applyZjuNetworkDefense(client,
          connectionTimeout: const Duration(seconds: 8));

      final res = await Courses.fetchActivityReadsForCourse(client, courseId);
      if (res != null) {
        final reads = asDynamicList(res['activity_reads']);
        if (reads != null) {
          for (final item in reads) {
            final m = asStringMap(item);
            if (m != null && m['activity_id']?.toString() == activityId) {
              match = m;
              break;
            }
          }
        }
      }
      client.close(force: true);
    } catch (e) {
      errorMsg = e.toString();
    }

    // 关闭加载框
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return match;

    if (match != null) {
      final completeness = asString(match['completeness']) ?? '';
      final subData = asStringMap(match['data']);
      final score = (subData?['score'] as num?)?.toDouble();
      final submittedAtStr = asString(subData?['submitted_at']);
      final submittedAt = DateTime.tryParse(submittedAtStr ?? '');

      recordHomeworkStatus(
        activityId,
        completeness: completeness,
        score: score,
        submittedAt: submittedAt,
      );

      // 实时更新任务列表中对应的作业状态
      if (Get.isRegistered<RxList<Task>>(tag: 'taskList')) {
        final taskList = Get.find<RxList<Task>>(tag: 'taskList');
        for (final task in taskList) {
          if (task.fromUid == '$_todoPrefix$activityId') {
            if (completeness == 'full' || score != null) {
              task.status = TaskStatus.completed;
            }
            break;
          }
        }
        taskList.refresh();
      }

      String resultTitle;
      String resultDesc;
      if (score != null) {
        final scoreText = score == score.roundToDouble()
            ? score.toInt().toString()
            : score.toStringAsFixed(1);
        resultTitle = '✅ 作业已批改';
        resultDesc = '教师已打分：$scoreText 分\n完成度：100%\n已自动将该任务标记为已完成。';
      } else if (completeness == 'full') {
        resultTitle = '✓ 作业已提交';
        resultDesc = '学在浙大记录显示作业已提交（待教师批改）\n已自动将该任务标记为已完成。';
      } else {
        resultTitle = '⏱ 作业尚未提交';
        resultDesc = '学在浙大记录显示当前尚未提交该作业，请在截止时间前完成提交。';
      }

      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(resultTitle),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(resultDesc),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    } else {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('探测未能获取到数据'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(errorMsg != null
                ? '网络请求异常：$errorMsg'
                : '未能从课程活动中匹配到此项作业，或学在浙大会话已过期。请在学业页面下拉刷新建立登录态后再试。'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }

    return match;
  }
}
