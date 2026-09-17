import 'package:get/get.dart';

import 'package:celechron/model/scholar.dart';
import 'package:celechron/services/ohos_native_service.dart';

/// 课程小组件数据同步。
///
/// 关键点：不依赖任何页面的生命周期。原实现放在 `ScholarController`
/// （由 `scholar_view` 通过 `Get.put` 创建）中，离开页面后控制器被销毁、
/// 定时器停止，导致小组件不再刷新、上完课也不会切到下一节。
/// 这里改为由应用级定时器驱动，只要应用进程存活就会持续同步。
class ScholarWidgetSync {
  ScholarWidgetSync._();

  /// 提前进入倒计时的窗口（分钟）
  static const int leadWindowMinutes = 120;

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

    if (upcoming.isEmpty) {
      OhosNativeService.instance.clearCourseWidget();
      return;
    }

    final currentOrNext = upcoming.first;
    final pad = (int n) => n.toString().padLeft(2, '0');
    final timeStr =
        '${pad(currentOrNext.startTime.hour)}:${pad(currentOrNext.startTime.minute)} - '
        '${pad(currentOrNext.endTime.hour)}:${pad(currentOrNext.endTime.minute)}';
    final teacherMatch =
        RegExp(r'教师:\s*(.+)').firstMatch(currentOrNext.description);
    final teacher = teacherMatch?.group(1) ?? '';

    // 状态/进度/倒计时由原生侧依据起止时间戳计算：
    // 这样系统级刷新（30 分钟定时、setFormNextRefreshTime）无需 Dart 参与
    // 也能得到正确结果，且应用被杀后仍能切换课程。
    OhosNativeService.instance.updateCourseWidget(
      courseName: currentOrNext.summary,
      courseTime: timeStr,
      location: currentOrNext.location,
      teacher: teacher,
      courseStartMs: currentOrNext.startTime.millisecondsSinceEpoch,
      courseEndMs: currentOrNext.endTime.millisecondsSinceEpoch,
      leadWindowMinutes: leadWindowMinutes,
      hasCourse: true,
    );
  }
}
