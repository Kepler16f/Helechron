import 'dart:convert';

import 'package:get/get.dart';

import 'package:celechron/model/option.dart';
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
///    （updateDuration + setFormNextRefreshTime 链式边界调度）仍能正确切换课程。
/// 3. 这里**不做去重**：原生侧每次收到推送都会重新按当前时间计算倒计时并
///    `updateForm`，所以高频推送正是倒计时平滑刷新的来源。磁盘写入由原生侧
///    按数据是否变化去重，高频推送的开销很小。
class ScholarWidgetSync {
  ScholarWidgetSync._();

  /// 提前进入倒计时的窗口（分钟）
  static const int leadWindowMinutes = 120;

  /// 下发到原生侧的课程条目上限（覆盖当天剩余与次日课程即可）
  static const int _maxCourses = 16;

  /// 开课前多久开始展示"距上课"实况窗（分钟）
  static const int _liveViewLeadMinutes = 30;

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

    _syncLiveView(now, upcoming);
  }

  /// 实况窗：上课中展示"距下课"原生倒计时；开课前 30 分钟内展示"距上课"。
  /// 其余情况（无课/开关关闭）结束实况窗。原生侧按内容去重，计时由系统推进，
  /// 5 秒级同步在普通上课期间不会产生实况窗更新。
  static void _syncLiveView(DateTime now, List<Period> upcoming) {
    bool enabled;
    try {
      enabled = Get.find<Option>(tag: 'option').liveViewEnabled.value;
    } catch (_) {
      // 选项尚未就绪（极早期同步）时不动实况窗
      return;
    }

    Map<String, Object>? state;
    if (enabled && upcoming.isNotEmpty) {
      final first = upcoming.first;
      final leadEnd = now.add(const Duration(minutes: _liveViewLeadMinutes));
      final isOngoing = !first.startTime.isAfter(now);
      if (isOngoing || first.startTime.isBefore(leadEnd)) {
        final target = isOngoing ? first.endTime : first.startTime;
        final pad = (int n) => n.toString().padLeft(2, '0');
        final timeLabel =
            '${pad(target.hour)}:${pad(target.minute)} ${isOngoing ? '下课' : '上课'}';
        final locationLabel =
            first.location.isEmpty ? timeLabel : '$timeLabel · ${first.location}';
        state = {
          'phase': isOngoing ? 'ongoing' : 'upcoming',
          'title': first.summary,
          'subtitle': locationLabel,
          'targetTimestamp': target.millisecondsSinceEpoch,
        };
      }
    }

    final native = OhosNativeService.instance;
    if (state == null) {
      native.stopLiveView();
    } else {
      native.updateLiveView(
        phase: state['phase']! as String,
        title: state['title']! as String,
        subtitle: state['subtitle']! as String,
        targetTimestamp: state['targetTimestamp']! as int,
      );
    }
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
