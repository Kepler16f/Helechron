import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/services/ics_parser.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/scholar_widget_sync.dart';
import 'package:celechron/utils/json_utils.dart';

/// JSON 备份导出/恢复与 iCal (.ics) 日程导入。
///
/// 备份内容 = 学业数据缓存 + 任务列表 + 用户手工维护的配置
/// （课程号映射、GPA 自选与加权比例、允许时段、工作/休息时长等）。
/// 账号密码只存系统安全存储、绝不写进备份文件；恢复后若目标设备没有
/// 登录态，重新登录一次即可继续刷新。
class BackupService {
  static const int backupVersion = 1;
  static const String _backupType = 'helechron_backup';

  // ==================== 备份导出 ====================

  /// 组装备份数据（导出与测试共用）。
  static Map<String, dynamic> buildBundle(
      DatabaseHelper db, Scholar scholar, Option option) {
    final allowTime = <Map<String, String>>[];
    option.allowTime.forEach((start, end) {
      allowTime.add({
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      });
    });
    return {
      'app': 'helechron',
      'type': _backupType,
      'version': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'scholar': scholar.isLogan ? scholar.toJson() : null,
      'tasks': db.getTaskList().map((task) => task.toJson()).toList(),
      'options': {
        'workTimeMinutes': option.workTime.value.inMinutes,
        'restTimeMinutes': option.restTime.value.inMinutes,
        'allowTime': allowTime,
        'gpaStrategy': option.gpaStrategy.value.index,
        'pushOnGradeChange': option.pushOnGradeChange.value,
        'pushOnDdlReminder': option.pushOnDdlReminder.value,
        'hideHomeGpa': option.hideHomeGpa.value,
        'asyncRefresh': option.asyncRefresh.value,
        'courseIdMappingList':
            option.courseIdMappingList.map((e) => e.toJson()).toList(),
        'customGpa': db.getCustomGpa(),
        'weightedGpa': db.getWeightedGpa(),
      },
    };
  }

  /// 导出备份：写临时 JSON 文件后拉起系统分享，由用户选择保存位置。
  static Future<void> exportBackup() async {
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
      final option = Get.find<Option>(tag: 'option');
      final bundle = buildBundle(db, scholar.value, option);

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/helechron_backup_$timestamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(bundle));

      await Share.shareXFiles([XFile(file.path)],
          subject: 'Helechron 备份',
          text: 'Helechron 数据备份，可在「设置 → 备份与恢复」中导入恢复。');

      _showAlert('成功', '备份已导出，请选择保存位置或分享');
    } catch (e) {
      _showAlert('错误', '导出失败：$e', isError: true);
    }
  }

  // ==================== 备份恢复 ====================

  /// 拉起文件选择、确认后恢复备份。仅在鸿蒙原生通道可用时有效。
  static Future<void> importBackup() async {
    final picked = await _pickTextFile();
    if (picked == null) return;
    final confirmed = await Get.dialog<bool>(
      CupertinoAlertDialog(
        title: const Text('恢复备份'),
        content: Text(
            '将从「${picked.name}」恢复备份。\n\n当前的学业数据、任务列表与相关配置将被覆盖，且不可撤销。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Get.back(result: false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('覆盖恢复'),
            onPressed: () => Get.back(result: true),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (confirmed != true) return;

    final error = await restoreFromContent(picked.content);
    if (error == null) {
      _showAlert('成功', '备份已恢复');
    } else {
      _showAlert('错误', error, isError: true);
    }
  }

  /// 把备份内容写回本地存储并刷新 GetX 观察项。
  /// 返回 null 表示成功，否则为面向用户的错误信息。
  static Future<String?> restoreFromContent(String content) async {
    try {
      final root = jsonDecode(content);
      if (root is! Map || root['type'] != _backupType) {
        return '这不是有效的 Helechron 备份文件';
      }
      final db = Get.find<DatabaseHelper>(tag: 'db');

      // 学业数据
      Scholar? restoredScholar;
      final rawScholar = asStringMap(root['scholar']);
      if (rawScholar != null) {
        try {
          restoredScholar = Scholar.fromJson(rawScholar);
        } catch (e) {
          // 学业数据损坏时仍恢复任务与配置
        }
      }

      // 任务列表
      final tasks = <Task>[];
      for (final raw in asDynamicList(root['tasks']) ?? const []) {
        final map = asStringMap(raw);
        if (map == null) continue;
        try {
          tasks.add(Task.fromJson(map));
        } catch (e) {
          // 跳过损坏的条目
        }
      }

      final rawOptions = asStringMap(root['options']);
      if (restoredScholar == null && tasks.isEmpty && rawOptions == null) {
        return '备份内容为空或已损坏';
      }

      // 账号密码不在备份里；保留当前登录态，避免恢复动作把凭据抹掉
      if (restoredScholar != null) {
        final current = await db.getScholar();
        restoredScholar.username ??= current.username;
        restoredScholar.password ??= current.password;
        restoredScholar.db = db;
      }

      if (rawOptions != null) {
        await _restoreOptions(db, rawOptions);
      }

      if (restoredScholar != null) {
        await db.setScholar(restoredScholar);
        Get.find<Rx<Scholar>>(tag: 'scholar').value = restoredScholar;
      }
      await db.setTaskList(tasks);
      await db.setTaskListUpdateTime(DateTime.now());
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      taskList.assignAll(tasks);
      Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate').value = DateTime.now();

      // 学业数据与任务都变了，立即同步桌面小组件
      ScholarWidgetSync.sync();
      return null;
    } catch (e) {
      return '恢复失败：$e';
    }
  }

  static Future<void> _restoreOptions(
      DatabaseHelper db, Map<String, dynamic> options) async {
    final option = Get.find<Option>(tag: 'option');

    final workTimeMinutes = asInt(options['workTimeMinutes']);
    if (workTimeMinutes != null && workTimeMinutes > 0) {
      final value = Duration(minutes: workTimeMinutes);
      db.setWorkTime(value);
      option.workTime.value = value;
    }
    final restTimeMinutes = asInt(options['restTimeMinutes']);
    if (restTimeMinutes != null && restTimeMinutes > 0) {
      final value = Duration(minutes: restTimeMinutes);
      db.setRestTime(value);
      option.restTime.value = value;
    }
    final gpaStrategyIndex = asInt(options['gpaStrategy']);
    if (gpaStrategyIndex != null &&
        gpaStrategyIndex >= 0 &&
        gpaStrategyIndex < GpaStrategy.values.length) {
      await db.setGpaStrategy(GpaStrategy.values[gpaStrategyIndex]);
      option.gpaStrategy.value = GpaStrategy.values[gpaStrategyIndex];
    }
    final pushOnGradeChange = asBool(options['pushOnGradeChange']);
    if (pushOnGradeChange != null) {
      await db.setPushOnGradeChange(pushOnGradeChange);
      option.pushOnGradeChange.value = pushOnGradeChange;
    }
    final pushOnDdlReminder = asBool(options['pushOnDdlReminder']);
    if (pushOnDdlReminder != null) {
      await db.setPushOnDdlReminder(pushOnDdlReminder);
      option.pushOnDdlReminder.value = pushOnDdlReminder;
    }
    final hideHomeGpa = asBool(options['hideHomeGpa']);
    if (hideHomeGpa != null) {
      await db.setHideHomeGpa(hideHomeGpa);
      option.hideHomeGpa.value = hideHomeGpa;
    }
    final asyncRefresh = asBool(options['asyncRefresh']);
    if (asyncRefresh != null) {
      await db.setAsyncRefresh(asyncRefresh);
      option.asyncRefresh.value = asyncRefresh;
    }

    final allowTime = <DateTime, DateTime>{};
    for (final raw in asDynamicList(options['allowTime']) ?? const []) {
      final map = asStringMap(raw);
      if (map == null) continue;
      final start = asDateTime(map['start']);
      final end = asDateTime(map['end']);
      if (start != null && end != null) allowTime[start] = end;
    }
    if (allowTime.isNotEmpty) {
      await db.setAllowTime(allowTime);
      option.allowTime.assignAll(allowTime);
    }

    final courseMappings = <CourseIdMap>[];
    for (final raw in asDynamicList(options['courseIdMappingList']) ?? const []) {
      final map = asStringMap(raw);
      if (map == null) continue;
      try {
        courseMappings.add(CourseIdMap.fromJson(map));
      } catch (e) {
        // 跳过损坏的条目
      }
    }
    if (courseMappings.isNotEmpty) {
      // ever(courseIdMappingList) 监听会自动持久化
      option.courseIdMappingList.assignAll(courseMappings);
    }

    final customGpa = <String, bool>{};
    final rawCustomGpa = options['customGpa'];
    if (rawCustomGpa is Map) {
      rawCustomGpa.forEach((key, value) {
        if (value is bool) customGpa[key.toString()] = value;
      });
    }
    if (customGpa.isNotEmpty) {
      await db.setCustomGpa(customGpa);
    }
    final weightedGpa = <String, double>{};
    final rawWeightedGpa = options['weightedGpa'];
    if (rawWeightedGpa is Map) {
      rawWeightedGpa.forEach((key, value) {
        if (value is num) weightedGpa[key.toString()] = value.toDouble();
      });
    }
    if (weightedGpa.isNotEmpty) {
      await db.setWeightedGpa(weightedGpa);
    }
  }

  // ==================== iCal 导入 ====================

  /// 导入 .ics 日历文件：VEVENT 映射为固定日程，VTODO 映射为 DDL。
  /// 按 iCal UID 去重（同一文件重复导入不会产生重复任务）；
  /// 结束时间早于一天前的条目默认跳过，避免历史日程污染。
  static Future<void> importIcs() async {
    final picked = await _pickTextFile();
    if (picked == null) return;
    final content = picked.content;
    if (!picked.name.toLowerCase().endsWith('.ics') &&
        !content.contains('BEGIN:VCALENDAR')) {
      _showAlert('提示', '请选择 .ics 日历文件');
      return;
    }

    final entries = IcsParser.parse(content);
    if (entries.isEmpty) {
      _showAlert('提示', '文件中没有可导入的日程');
      return;
    }

    final taskList = Get.find<RxList<Task>>(tag: 'taskList');
    final existingUids = taskList.map((task) => task.uid).toSet();
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    final freshTasks = <Task>[];
    var duplicateCount = 0;
    var skippedPastCount = 0;
    for (final entry in entries) {
      final task = taskFromIcsEntry(entry, existingUids);
      if (task == null) {
        skippedPastCount++;
        continue;
      }
      if (identical(task, duplicateSentinel)) {
        duplicateCount++;
        continue;
      }
      freshTasks.add(task);
    }

    if (freshTasks.isEmpty) {
      _showAlert('结果',
          '没有新的日程可导入（重复 $duplicateCount 条，已过期 $skippedPastCount 条）');
      return;
    }

    final confirmed = await Get.dialog<bool>(
      CupertinoAlertDialog(
        title: const Text('导入日程'),
        content: Text(
            '从「${picked.name}」解析出 ${freshTasks.length} 个可导入的日程/DDL。\n\n'
            '跳过：重复 $duplicateCount 条，已过期 $skippedPastCount 条。\n'
            '导入的日程会出现在「接下来」和日历中。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Get.back(result: false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('导入'),
            onPressed: () => Get.back(result: true),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (confirmed != true) return;

    taskList.addAll(freshTasks);
    final db = Get.find<DatabaseHelper>(tag: 'db');
    await db.setTaskList(taskList.toList());
    await db.setTaskListUpdateTime(DateTime.now());
    Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate').value = DateTime.now();
    ScholarWidgetSync.sync();

    _showAlert('成功', '已导入 ${freshTasks.length} 个日程/DDL');
  }

  /// 导入去重哨兵：uid 已存在时返回它以区分「跳过」与「过期」。
  @visibleForTesting
  static final Task duplicateSentinel = Task(
      endTime: DateTime.fromMicrosecondsSinceEpoch(0),
      startTime: DateTime.fromMicrosecondsSinceEpoch(0),
      repeatEndsTime: DateTime.fromMicrosecondsSinceEpoch(0));

  /// 把 iCal 条目映射为任务。返回 null 表示已过期应跳过；
  /// 返回 [duplicateSentinel] 表示与现有任务重复应跳过。
  @visibleForTesting
  static Task? taskFromIcsEntry(IcsEntry entry, Set<String> existingUids) {
    var start = entry.start;
    var end = entry.end ?? entry.start;
    if (end == null) return null;
    if (start == null) start = end;
    if (start.isAfter(end)) end = start;
    // 全天事件（VALUE=DATE）的 DTEND 是次日零点（排他语义），正常情况不会
    // 走到这里；缺 DTEND 时补足时长：全天补一天，否则补一小时
    if (!end.isAfter(start)) {
      final allDay =
          start.hour == 0 && start.minute == 0 && start.second == 0;
      end = allDay
          ? start.add(const Duration(days: 1))
          : start.add(const Duration(hours: 1));
    }
    if (end.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      return null;
    }

    final uid = entry.uid.isNotEmpty
        ? 'ics-${entry.uid}'
        : 'ics-${entry.summary}-${entry.start?.millisecondsSinceEpoch ?? 0}';
    if (existingUids.contains(uid)) return duplicateSentinel;
    existingUids.add(uid);

    final repeatEndsTime = DateTime(end.year, end.month, end.day);
    if (entry.isTodo) {
      return Task(
        uid: uid,
        summary: entry.summary.isEmpty ? '（未命名待办）' : entry.summary,
        description: entry.description,
        location: entry.location,
        type: TaskType.deadline,
        startTime: end,
        endTime: end,
        repeatEndsTime: repeatEndsTime,
      );
    }
    return Task(
      uid: uid,
      summary: entry.summary.isEmpty ? '（未命名日程）' : entry.summary,
      description: entry.description,
      location: entry.location,
      type: TaskType.fixed,
      startTime: start,
      endTime: end,
      repeatEndsTime: repeatEndsTime,
    );
  }

  // ==================== 文件选择 ====================

  /// 打开系统文件选择器读取一个文本文件；用户取消或通道不可用时返回 null。
  static Future<({String name, String content})?> _pickTextFile() async {
    final result = await OhosNativeService.instance.pickTextFile();
    if (result == null) return null;
    final content = result['content'] ?? '';
    if (content.isEmpty) return null;
    return (name: result['name'] ?? '', content: content);
  }

  static void _showAlert(String title, String message, {bool isError = false}) {
    Get.dialog(
      CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Get.back(),
          ),
        ],
      ),
      barrierDismissible: !isError,
    );
  }
}
