import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';

/// 课程小组件数据同步。
///
/// 关键点：
/// 1. 不依赖任何页面的生命周期（原实现放在由页面 `Get.put` 的控制器里，
///    离开页面即停止刷新，导致小组件不刷新、下课也不切换）。
/// 2. 一次性下发"后续若干节课"的时间表，交由原生侧按当前时间选择
///    当前/下一节课并计算状态与倒计时。这样即使应用被杀，系统级刷新
///    仍能正确切换课程。
/// 3. 仅在数据变化时推送（scholar refresh、app resumed），
///    原生侧通过 setFormNextRefreshTime 预调度所有课程边界。
class ScholarWidgetSync {
  ScholarWidgetSync._();

  /// 提前进入倒计时的窗口（分钟）
  static const int leadWindowMinutes = 120;

  /// 下发到原生侧的课程条目上限（覆盖当天剩余与次日课程即可）
  static const int _maxCourses = 16;

  /// Debounce 延迟（秒），防止连续多次调用导致重复推送
  static const int _debounceSeconds = 3;

  /// 防止重入
  static bool _running = false;

  /// Debounce 定时器
  static Timer? _debounceTimer;

  /// 上一次推送的 JSON（用于去重）
  static String _lastPushedJson = '';

  /// 计算最近的未结束课程并推送到原生小组件（带 debounce）。
  static void sync() {
    if (_debounceTimer?.isActive ?? false) {
      return;
    }
    _debounceTimer = Timer(const Duration(seconds: _debounceSeconds), () {
      _doSync();
    });
  }

  /// 立即推送（忽略 debounce），用于需要即时更新的场景。
  static void syncImmediate() {
    _debounceTimer?.cancel();
    _doSync();
  }

  static void _doSync() {
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

    final json = jsonEncode(
      upcoming.take(_maxCourses).map(_encodeCourse).toList(),
    );

    // 去重：如果数据未变化，跳过推送
    if (json == _lastPushedJson) {
      debugPrint('ScholarWidgetSync: data unchanged, skip push');
      return;
    }
    _lastPushedJson = json;

    debugPrint('ScholarWidgetSync: pushing ${upcoming.length} courses');
    OhosNativeService.instance.updateCourseWidget(
      coursesJson: json,
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
