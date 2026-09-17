import 'dart:convert';

import 'package:get/get.dart';

import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';

/// 课程小组件数据同步。
///
/// 关键点：
/// 1. 不依赖任何页面的生命周期（原实现放在由页面 `Get.put` 的控制器里，
///    离开页面即停止刷新，导致小组件不刷新、下课也不切换）。
/// 2. 一次性下发“后续若干节课”的时间表，交由原生侧按当前时间选择
///    当前/下一节课并计算状态与倒计时。这样即使应用被杀，系统级刷新
///    仍能正确切换课程。
class ScholarWidgetSync {
  ScholarWidgetSync._();

  /// 提前进入倒计时的窗口（分钟）
  static const int leadWindowMinutes = 120;

  /// 下发到原生侧的课程条目上限（覆盖当天剩余与次日课程即可）
  static const int _maxCourses = 16;

  /// 防止重入
  static bool _running = false;

  /// 计算最近的未结束课程并推送到原生小组件。
  static void sync() {
    if (_running) {
      return;
    }
    _running = true;
    try {
      final scholarRx = Get.find<Rx<Scholar>>(tag: 'scholar');
      _syncScholar(scholarRx.value);
    } catch (_) {
      // 数据尚未就绪时静默忽略
    } finally {
      _running = false;
    }
  }

  static void _syncScholar(Scholar scholar) {
    final now = DateTime.now();
    final upcoming = scholar.periods
        .where((p) => p.endTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    OhosNativeService.instance.updateCourseWidget(
      coursesJson: jsonEncode(
        upcoming.take(_maxCourses).map(_encodeCourse).toList(),
      ),
      leadWindowMinutes: leadWindowMinutes,
    );
  }

  static Map<String, Object> _encodeCourse(Period period) {
    final start = period.startTime;
    final end = period.endTime;
    final pad = (int n) => n.toString().padLeft(2, '0');
    final teacherMatch = RegExp(r'教师:\s*(.+)').firstMatch(period.description);
    return {
      's': start.millisecondsSinceEpoch,
      'e': end.millisecondsSinceEpoch,
      'n': period.summary,
      't':
          '${pad(start.hour)}:${pad(start.minute)} - ${pad(end.hour)}:${pad(end.minute)}',
      'l': period.location,
      'c': teacherMatch?.group(1) ?? '',
    };
  }
}
