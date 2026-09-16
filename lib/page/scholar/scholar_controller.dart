import 'dart:async';

import 'package:get/get.dart';

import 'package:celechron/http/spider.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/services/ohos_native_service.dart';

class ScholarController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _option = Get.find<Option>(tag: 'option');

  final Rx<Duration> _durationToLastUpdateGrade = const Duration().obs;
  final Rx<Duration> _durationToLastUpdateCourse = const Duration().obs;
  final Rx<Duration> _durationToLastUpdateHomework = const Duration().obs;

  // 直接初始化为 0，避免 late final 的初始化时机问题
  final RxInt semesterIndex = 0.obs;

  Timer? _timer;

  // —— 刷新状态文案 ——
  // 刷新超过约 5 秒（第 _statusFirstShowTick 个周期）才开始展示，
  // 之后每个周期轮换一条；文案基于 Scholar.refresh 上报的真实模块进度
  static const int _statusFirstShowTick = 2;
  static const Duration _statusInterval = Duration(milliseconds: 2500);

  // 各抓取模块（本科生与研究生两套标签）的进行中文案
  static const Map<String, String> _progressCopy = {
    '校历': '正在同步校历...',
    '课表': '正在获取课表...',
    '考试': '正在解析考试安排...',
    '成绩': '正在等待成绩数据...',
    '主修': '正在核对主修成绩...',
    '作业': '正在同步作业列表...',
    '实践': '正在统计实践学分...',
    '配置': '正在同步校历...',
    '本科生课考试': '正在解析本科生考试...',
    '本科生课成绩': '正在等待本科生成绩...',
    '研究生课考试': '正在解析研究生考试...',
    '研究生课成绩': '正在等待研究生成绩...',
  };
  // 拿不到任何真实进度（如启动自动刷新占用互斥锁）时的兜底轮播
  static const List<String> _genericCarousel = [
    '正在同步教务数据...',
    '正在等待服务器响应...',
    '仍在努力获取中...',
  ];

  /// 当前展示的刷新状态文案，null 表示不展示
  final Rxn<String> refreshStatusMessage = Rxn<String>();

  Timer? _statusTimer;
  int _statusTick = 0;
  int _activeFetchCount = 0;
  List<ModuleFetchStatus> _statuses = const [];
  int _rotation = 0;

  Scholar get scholar => _scholar.value;

  List<Semester> get semesters => _scholar.value.semesters;

  // Getter 保持纯净，不包含任何副作用（不修改状态）
  Semester get selectedSemester {
    final index = semesterIndex.value;

    // 如果学期列表为空，返回当前学期
    if (semesters.isEmpty) {
      return _scholar.value.thisSemester;
    }

    // 如果索引无效，返回当前学期
    if (index < 0 || index >= semesters.length) {
      return _scholar.value.thisSemester;
    }

    // 索引有效，返回对应的学期
    return semesters[index];
  }

  Duration get durationToLastUpdateGrade => _durationToLastUpdateGrade.value;
  Duration get durationToLastUpdateCourse => _durationToLastUpdateCourse.value;
  Duration get durationToLastUpdateHomework =>
      _durationToLastUpdateHomework.value;

  List<double> get gpa => _option.gpaStrategy.value == GpaStrategy.first
      ? _scholar.value.gpa
      : _scholar.value.aboardGpa;

  List<Todo> get todos => _scholar.value.todos
    ..sort((a, b) {
      if (a.endTime == null) return 1;
      if (b.endTime == null) return -1;
      return a.endTime!.compareTo(b.endTime!);
    });

  // 获取当前学期的未完成作业
  List<Todo> get currentSemesterPendingTodos {
    final thisSemester = _scholar.value.thisSemester;
    final currentSemesterCourseNames =
        thisSemester.courses.values.map((course) => course.name).toSet();

    return todos.where((todo) {
      // 检查作业是否属于当前学期的课程
      final isCurrentSemester =
          currentSemesterCourseNames.contains(todo.course);
      // 检查作业是否未完成（截止时间未过或没有截止时间）
      final isPending =
          todo.endTime == null || !todo.endTime!.isBefore(DateTime.now());
      return isCurrentSemester && isPending;
    }).toList();
  }

  List<Todo> get todosInOneDay =>
      currentSemesterPendingTodos.where((e) => e.isInOneDay()).toList();

  List<Todo> get todosInOneWeek =>
      currentSemesterPendingTodos.where((e) => e.isInOneWeek()).toList();

  void _updateDurations() {
    _durationToLastUpdateGrade.value =
        DateTime.now().difference(_scholar.value.lastUpdateTimeGrade);
    _durationToLastUpdateCourse.value =
        DateTime.now().difference(_scholar.value.lastUpdateTimeCourse);
    _durationToLastUpdateHomework.value =
        DateTime.now().difference(_scholar.value.lastUpdateTimeHomework);
  }

  void _updateCourseWidget() {
    try {
      final now = DateTime.now();
      final allPeriods = _scholar.value.periods;
      final upcoming = allPeriods
          .where(
              (p) => p.type == PeriodType.classes && p.endTime.isAfter(now))
          .toList();
      upcoming.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (upcoming.isNotEmpty) {
        final next = upcoming.first;
        final teacherMatch =
            RegExp(r'教师:\s*(.+)').firstMatch(next.description);
        final teacher = teacherMatch?.group(1) ?? '';
        OhosNativeService.instance.updateCourseWidget(
          courseName: next.summary,
          weekday: next.startTime.weekday,
          startTime: next.startTime,
          endTime: next.endTime,
          location: next.location,
          teacher: teacher,
        );
      } else {
        OhosNativeService.instance.clearCourseWidget();
      }
    } catch (e) {
      // Widget update is best-effort
    }
  }

  Future<List<String?>> fetchData() async {
    // scholar.refresh 使用 single-flight；并发调用会共同等待同一个结果。
    // 这里计数以保证最后一个调用结束时才收起状态文案。
    _activeFetchCount++;
    if (_activeFetchCount == 1) _startStatusFeed();
    try {
      // 异步刷新开启时，每合并一部分数据就刷新界面和“更新于”时长
      return await _scholar.value
          .refresh(
              onPartialUpdate: () {
                _scholar.refresh();
                _updateDurations();
              },
              onFetchStatus: _onFetchStatus)
          .then((value) {
        _scholar.refresh();
        _updateDurations();
        _updateCourseWidget();
        return value;
      });
    } finally {
      _activeFetchCount--;
      if (_activeFetchCount == 0) _stopStatusFeed();
    }
  }

  void _startStatusFeed() {
    _statusTick = 0;
    _rotation = 0;
    _statuses = const [];
    refreshStatusMessage.value = null;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(_statusInterval, (_) => _onStatusTick());
  }

  void _stopStatusFeed() {
    _statusTimer?.cancel();
    _statusTimer = null;
    // 置空即收起；展示组件自行缓存末条文案以配合收起动画
    refreshStatusMessage.value = null;
  }

  void _onFetchStatus(List<ModuleFetchStatus> statuses) {
    if (_statusTimer == null) return; // 刷新已结束的迟到回调，忽略
    _statuses = statuses;
  }

  void _onStatusTick() {
    _statusTick++;
    if (_statusTick < _statusFirstShowTick) return;
    var pending = _statuses
        .where((s) => s.state == FetchModuleState.pending)
        .toList(growable: false);
    if (pending.isNotEmpty) {
      var label = pending[_rotation++ % pending.length].label;
      refreshStatusMessage.value = _progressCopy[label] ?? '正在获取$label...';
    } else if (_statuses.isNotEmpty) {
      refreshStatusMessage.value = '正在完成刷新...';
    } else {
      refreshStatusMessage.value =
          _genericCarousel[_rotation++ % _genericCarousel.length];
    }
  }

  @override
  void onReady() {
    super.onReady();
    // 在生命周期方法中正确初始化 semesterIndex
    final thisSemesterIndex =
        semesters.indexWhere((e) => e.name == _scholar.value.thisSemester.name);
    semesterIndex.value = thisSemesterIndex >= 0 ? thisSemesterIndex : 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDurations();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    _statusTimer?.cancel();
    super.onClose();
  }
}
