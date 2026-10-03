import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// 将学在浙大作业 (Todo) 按照任务样式与时间顺序自动同步为 DDL 任务。
class TodoTaskSync {
  static const String kOptionAutoSyncTodoToTask = 'autoSyncTodoToTask';
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

      final expectedSummary = '作业：${todo.name}';
      final expectedDescription = '课程：${todo.course}\n来源：学在浙大';

      if (existingTask != null) {
        // 已存在任务：若截止时间或名称变更，平滑更新，保留用户标记的完成度与状态
        bool modified = false;
        if (existingTask.endTime != todo.endTime) {
          existingTask.endTime = todo.endTime!;
          modified = true;
        }
        if (existingTask.summary != expectedSummary) {
          existingTask.summary = expectedSummary;
          modified = true;
        }
        if (modified) {
          existingTask.refreshStatus();
          hasChanged = true;
        }
      } else {
        // 新作业：创建对应 DDL 任务
        final newTask = Task(
          uid: const Uuid().v4(),
          status: todo.endTime!.isBefore(now)
              ? TaskStatus.failed
              : TaskStatus.running,
          description: expectedDescription,
          timeSpent: Duration.zero,
          timeNeeded: const Duration(hours: 2),
          endTime: todo.endTime!,
          location: '',
          summary: expectedSummary,
          isBreakable: true,
          type: TaskType.deadline,
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
}

