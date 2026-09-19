import 'dart:async';
import 'package:get/get.dart';
import 'package:celechron/algorithm/arrange.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/utils.dart';

class FlowController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final flowList = Get.find<RxList<Period>>(tag: 'flowList');
  final flowListLastUpdate = Get.find<Rx<DateTime>>(tag: 'flowListLastUpdate');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final taskListLastUpdate = Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  late var _scholarFlowList = scholar.value.periods;
  var _currentScholarFlowCursor = -1;
  var timeNow = DateTime.now().obs;
  Timer? _timer;
  Timer? _precisionCooldownTimer;
  bool _walkPending = false;
  DateTime _nextWalkAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastFlowSig = 0;
  DateTime _lastAccrualSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 应用存活时使用精确显示（时:分），切到后台 2 分钟后降级为粗略显示（30 分钟粒度）
  bool _foregroundPrecision = true;

  bool get isDuringFlow => flowList.first.startTime.isBefore(DateTime.now());

  void onAppResumed() {
    _foregroundPrecision = true;
    _precisionCooldownTimer?.cancel();
    _precisionCooldownTimer = Timer(const Duration(minutes: 2), () {
      _foregroundPrecision = false;
    });
  }

  void onAppBackgrounded() {
    _precisionCooldownTimer?.cancel();
    _precisionCooldownTimer = Timer(const Duration(minutes: 2), () {
      _foregroundPrecision = false;
    });
  }

  /// 倒计时文本：始终显示 "开始还有 X 时 X 分" / "离结束还有 X 时 X 分"
  /// 精确模式显示时+分，粗略模式按 30 分钟粒度取整
  String countdownText(DateTime from, DateTime to) {
    final diff = to.difference(from);
    final totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) return '';
    final hours = totalMinutes ~/ 60;
    if (_foregroundPrecision) {
      final minutes = totalMinutes % 60;
      if (hours > 0 && minutes > 0) {
        return '$hours 时 $minutes 分';
      } else if (hours > 0) {
        return '$hours 时';
      } else {
        return '$minutes 分';
      }
    } else {
      final rounded = ((totalMinutes + 15) ~/ 30) * 30;
      final rHours = rounded ~/ 60;
      final rMinutes = rounded % 60;
      if (rHours > 0 && rMinutes > 0) {
        return '$rHours 时 $rMinutes 分';
      } else if (rHours > 0) {
        return '$rHours 时';
      } else {
        return '$rMinutes 分';
      }
    }
  }

  @override
  void onInit() {
    refreshScholarFlowList();
    walkFlowList();

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _onTick());

    ever(scholar, (callback) {
      refreshScholarFlowList();
      _walkPending = true;
    });
    ever(taskList, (callback) {
      _walkPending = true;
    });

    super.onInit();
  }

  void _onTick() {
    final now = DateTime.now();
    timeNow.value = now;
    if (_walkPending || !now.isBefore(_nextWalkAt)) {
      _walkPending = false;
      walkFlowList();
    } else if (flowList.isNotEmpty && !flowList.first.startTime.isAfter(now)) {
      _syncFlowProgress(now);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _precisionCooldownTimer?.cancel();
    super.onClose();
  }

  Future<void> saveFlowListToDb() async {
    await _db.setFlowList(flowList);
    await _db.setFlowListUpdateTime(flowListLastUpdate.value);
  }

  void loadFlowListLastUpdate() {
    flowListLastUpdate.value = _db.getFlowListUpdateTime();
  }

  bool isFlowListOutdated() {
    return flowListLastUpdate.value.isBefore(taskListLastUpdate.value);
  }

  void updateDeadlineListTime() {
    flowListLastUpdate.value = taskListLastUpdate.value.copyWith();
    _db.setFlowListUpdateTime(flowListLastUpdate.value);
  }

  void removeFlowInFlowList() {
    flowList.removeWhere((element) => element.type == PeriodType.flow);
    _walkPending = true;
  }

  int generateNewFlowList(DateTime startsAt) {
    Duration workTime = _db.getWorkTime();
    Duration restTime = _db.getRestTime();

    List<Task> deadlines = [];
    DateTime lastDeadlineEndsAt = startsAt;
    for (var x in taskList) {
      if (x.type == TaskType.deadline) {
        if (x.status == TaskStatus.running) {
          if (x.endTime.isBefore(startsAt)) {
            return -1;
          } else {
            deadlines.add(x.copyWith());
            if (x.endTime.isAfter(lastDeadlineEndsAt)) {
              lastDeadlineEndsAt = x.endTime;
            }
          }
        }
      }
    }
    flowList.removeWhere((element) =>
        element.type == PeriodType.flow || element.type == PeriodType.classes);
    if (lastDeadlineEndsAt.difference(startsAt) < const Duration(days: 1)) {
      lastDeadlineEndsAt = startsAt.add(const Duration(days: 1));
    }

    List<DateTime> mappedList = [];

    mappedList.add(startsAt);
    mappedList.add(lastDeadlineEndsAt);

    Map allowTime = _db.getAllowTime();
    allowTime.forEach((allowStart, allowEnd) {
      for (int i = 0;; i++) {
        DateTime tmpl = allowStart;
        tmpl = tmpl.copyWith(
            year: startsAt.year, month: startsAt.month, day: startsAt.day);
        tmpl = tmpl.add(Duration(days: i));

        DateTime tmpr = allowEnd;
        tmpr = tmpr.copyWith(
            year: startsAt.year, month: startsAt.month, day: startsAt.day);
        tmpr = tmpr.add(Duration(days: i));
        if (tmpr.isBefore(tmpl)) tmpr.add(const Duration(days: 1));

        if (tmpr.isBefore(startsAt)) continue;
        if (!tmpl.isBefore(lastDeadlineEndsAt)) break;
        if (tmpr.isAfter(lastDeadlineEndsAt)) tmpr = lastDeadlineEndsAt;
        if (tmpl.isBefore(startsAt)) tmpl = startsAt;

        mappedList.add(tmpl);
        mappedList.add(tmpr);
      }
    });

    List<Period> blockedPeriod = <Period>[];
    for (var x in taskList) {
      if (x.type == TaskType.fixed && x.blockArrangements) {
        DateTime date = DateTime(startsAt.year, startsAt.month, startsAt.day);
        while (!date.isAfter(dateOnly(lastDeadlineEndsAt))) {
          List<Period> periods = x.getPeriodOfDay(date);
          for (var p in periods) {
            DateTime tmpl = p.startTime;
            DateTime tmpr = p.endTime;
            if (tmpr.isAfter(lastDeadlineEndsAt)) tmpr = lastDeadlineEndsAt;
            if (tmpl.isBefore(startsAt)) tmpl = startsAt;
            tmpl = tmpl.copyWith();
            tmpr = tmpr.copyWith();

            mappedList.add(tmpl);
            mappedList.add(tmpr);
            blockedPeriod.add(Period(startTime: tmpl, endTime: tmpr));
          }
          date = date.add(const Duration(days: 1));
        }
      }
    }

    for (var x in _scholarFlowList) {
      if (!x.startTime.isAfter(lastDeadlineEndsAt)) {
        mappedList.add(x.startTime.copyWith());
      }
      if (!x.endTime.isBefore(startsAt)) {
        mappedList.add(x.endTime.copyWith());
      }
    }
    for (var x in deadlines) {
      mappedList.add(x.endTime.copyWith());
    }

    mappedList = mappedList.toSet().toList();
    mappedList.sort();
    Map<DateTime, int> atListIndex = {};
    for (int i = 0; i < mappedList.length; i++) {
      atListIndex[mappedList[i]] = i;
    }
    List<bool> useAble = List.generate(mappedList.length, (index) => false);

    allowTime.forEach((allowStart, allowEnd) {
      for (int i = 0;; i++) {
        DateTime tmpl = allowStart;
        tmpl = tmpl.copyWith(
            year: startsAt.year, month: startsAt.month, day: startsAt.day);
        tmpl = tmpl.add(Duration(days: i));

        DateTime tmpr = allowEnd;
        tmpr = tmpr.copyWith(
            year: startsAt.year, month: startsAt.month, day: startsAt.day);
        tmpr = tmpr.add(Duration(days: i));
        if (tmpr.isBefore(tmpl)) tmpr.add(const Duration(days: 1));

        if (tmpr.isBefore(startsAt)) continue;
        if (!tmpl.isBefore(lastDeadlineEndsAt)) break;
        if (tmpr.isAfter(lastDeadlineEndsAt)) tmpr = lastDeadlineEndsAt;
        if (tmpl.isBefore(startsAt)) tmpl = startsAt;

        int indexl = atListIndex[tmpl]!;
        int indexr = atListIndex[tmpr]!;
        for (int i = indexl; i < indexr; i++) {
          useAble[i] = true;
        }
      }
    });

    for (var p in blockedPeriod) {
      int indexl = atListIndex[p.startTime]!;
      int indexr = atListIndex[p.endTime]!;
      for (int i = indexl; i < indexr; i++) {
        useAble[i] = false;
      }
    }

    for (var x in _scholarFlowList) {
      DateTime tmpl = x.startTime.copyWith();
      DateTime tmpr = x.endTime.copyWith();

      if (!tmpl.isBefore(lastDeadlineEndsAt)) continue;
      if (!tmpr.isAfter(startsAt)) continue;
      if (tmpr.isAfter(lastDeadlineEndsAt)) tmpr = lastDeadlineEndsAt;
      if (tmpl.isBefore(startsAt)) tmpl = startsAt;

      flowList.add(x.copyWith());

      int indexl = atListIndex[tmpl]!;
      int indexr = atListIndex[tmpr]!;
      for (int i = indexl; i < indexr; i++) {
        useAble[i] = false;
      }
    }

    List<Period> ableList = [];

    for (int i = 0, j = 0; i < mappedList.length; i++) {
      if (!useAble[i]) continue;
      j = i;
      while (j + 1 < mappedList.length && useAble[j]) {
        j++;
      }
      Period period = Period(
        type: PeriodType.virtual,
        startTime: mappedList[i],
        endTime: mappedList[j],
      );
      period.genUid();
      if (period.endTime.difference(period.startTime) > restTime) {
        ableList.add(period);
      }
      i = j;
    }

    TimeAssignSet ans =
        getTimeAssignSet(workTime, restTime, deadlines, ableList);
    if (!ans.isValid) return -1;
    flowList.addAll(ans.assignSet);
    flowList.sort((a, b) {
      return a.startTime.compareTo(b.startTime);
    });
    updateDeadlineListTime();
    flowList.refresh();
    _refreshScholarCursor();
    walkFlowList();
    return ans.restTime.inMinutes;
  }

  void walkFlowList() {
    Map<String, Task> existingDeadlineUid = {};
    for (var x in taskList) {
      if (x.type == TaskType.deadline) {
        existingDeadlineUid[x.uid] = x;
      }
    }
    for (var i = 0; i < flowList.length; i++) {
      if (flowList[i].type == PeriodType.user ||
          flowList[i].type == PeriodType.classes ||
          flowList[i].type == PeriodType.test) {
        flowList.removeAt(i);
        i--;
        continue;
      }
      if (flowList[i].type == PeriodType.flow) {
        if (!existingDeadlineUid.containsKey(flowList[i].fromUid)) {
          flowList.removeAt(i);
          i--;
        } else {
          flowList[i].summary =
              existingDeadlineUid[flowList[i].fromUid]!.summary;
          flowList[i].location =
              existingDeadlineUid[flowList[i].fromUid]!.location;
          flowList[i].description =
              existingDeadlineUid[flowList[i].fromUid]!.description;
        }
      }
    }
    flowList.sort((a, b) {
      return a.startTime.compareTo(b.startTime);
    });

    _syncFlowProgress(DateTime.now());

    _refreshScholarCursor();
    if (_currentScholarFlowCursor != -1) {
      for (var i = 0;
          i < 6 && i + _currentScholarFlowCursor < _scholarFlowList.length;
          i++) {
        if (!flowList.any((e) =>
                e.uid == _scholarFlowList[i + _currentScholarFlowCursor].uid) &&
            _scholarFlowList[i + _currentScholarFlowCursor]
                    .endTime
                    .difference(DateTime.now())
                    .inMinutes <
                2880) {
          flowList
              .add(_scholarFlowList[i + _currentScholarFlowCursor].copyWith());
        }
      }
    }

    for (var x in taskList) {
      if (x.type == TaskType.fixed) {
        DateTime time = DateTime.now();
        DateTime? last;
        for (int i = 0; i < 5; i++) {
          Period? period = x.deadlineOfTime(time, predicting: true);
          if (period != null) {
            if (last == null || last.compareTo(period.startTime) != 0) {
              flowList.add(period);
              last = period.startTime.copyWith();
            }
          }
          time = time.add(const Duration(days: 1));
        }
      }
    }
    flowList.sort((a, b) {
      return a.startTime.compareTo(b.startTime);
    });

    final sig = _computeFlowSig();
    if (sig != _lastFlowSig) {
      _lastFlowSig = sig;
      saveFlowListToDb();
    }
    _nextWalkAt = _computeNextWalkAt(DateTime.now());
  }

  void _syncFlowProgress(DateTime now) {
    var didAccrue = false;
    for (var i = 0; i < flowList.length; i++) {
      if (flowList[i].startTime.isAfter(now)) break;
      if (flowList[i].type == PeriodType.flow) {
        Duration prevProgress =
            (flowList[i].lastUpdateTime ?? flowList[i].startTime)
                .difference(flowList[i].startTime);
        flowList[i].lastUpdateTime = now;
        Duration currProgress =
            flowList[i].lastUpdateTime!.difference(flowList[i].startTime);
        Duration length = flowList[i].endTime.difference(flowList[i].startTime);

        if (currProgress <= Duration.zero) break;
        if (currProgress > length) currProgress = length;

        for (var deadline in taskList) {
          if (deadline.uid != flowList[i].fromUid) continue;
          deadline.updateTimeSpent(
              deadline.timeSpent - prevProgress + currProgress);
        }
        didAccrue = true;
        taskList.refresh();
        flowList.refresh();
      }
      if (flowList[i].endTime.isBefore(now)) {
        flowList.removeAt(i);
        i--;
        flowList.refresh();
        taskList.refresh();
        _walkPending = true;
      }
    }
    if (didAccrue &&
        now.difference(_lastAccrualSaveAt) >= const Duration(seconds: 15)) {
      _lastAccrualSaveAt = now;
      saveFlowListToDb();
      _db.setTaskList(taskList);
      _db.setTaskListUpdateTime(taskListLastUpdate.value);
    }
  }

  int _computeFlowSig() {
    return Object.hashAll(flowList.map((p) => Object.hash(p.uid, p.type,
        p.startTime, p.endTime, p.summary, p.location, p.description)));
  }

  DateTime _computeNextWalkAt(DateTime now) {
    var next = now.add(const Duration(seconds: 60));
    void consider(DateTime t) {
      if (t.isAfter(now) && t.isBefore(next)) next = t;
    }

    for (var p in flowList) {
      consider(p.startTime);
      consider(p.endTime);
    }
    if (_currentScholarFlowCursor != -1) {
      for (var i = 0;
          i < 6 && i + _currentScholarFlowCursor < _scholarFlowList.length;
          i++) {
        var p = _scholarFlowList[i + _currentScholarFlowCursor];
        consider(p.endTime);
        consider(p.endTime.subtract(const Duration(minutes: 2880)));
      }
    }
    return next;
  }

  void refreshScholarFlowList() {
    _scholarFlowList = scholar.value.periods;
    _scholarFlowList.sort((a, b) {
      return a.startTime.compareTo(b.startTime);
    });
    _refreshScholarCursor();
  }

  void _refreshScholarCursor() {
    _currentScholarFlowCursor =
        _scholarFlowList.indexWhere((e) => e.endTime.isAfter(DateTime.now()));
  }
}
