import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/exam.dart';
import 'package:celechron/model/location_mapper.dart';

class ExamListController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  late final RxInt semesterIndex;
  final Rx<Duration> _durationToLastUpdate = const Duration().obs;
  final RxBool showPastExams = false.obs;
  final Rx<DateTime> currentTime = DateTime.now().obs;
  Timer? _timer;

  ExamListController({required String initialName}) {
    semesterIndex = semesters.indexWhere((e) => e.name == initialName).obs;
  }

  Semester get semester => _scholar.value.semesters[semesterIndex.value];
  List<Semester> get semesters => _scholar.value.semesters;
  Duration get durationToLastUpdate => _durationToLastUpdate.value;

  /// 全量按时间升序排序的考试列表
  List<Exam> get allSortedExams {
    final list = List<Exam>.from(semester.exams);
    list.sort((a, b) {
      if (a.time.isEmpty && b.time.isEmpty) return 0;
      if (a.time.isEmpty) return 1;
      if (b.time.isEmpty) return -1;
      return a.time[0].compareTo(b.time[0]);
    });
    return list;
  }

  /// 尚未结束的考试
  List<Exam> get upcomingExams {
    final now = currentTime.value;
    return allSortedExams.where((e) {
      if (e.time.length < 2) return true;
      return !e.time[1].isBefore(now);
    }).toList();
  }

  /// 已结束的历史考试
  List<Exam> get pastExams {
    final now = currentTime.value;
    return allSortedExams.where((e) {
      if (e.time.length < 2) return false;
      return e.time[1].isBefore(now);
    }).toList();
  }

  /// 下一场即将到来的考试
  Exam? get nextExam => upcomingExams.isEmpty ? null : upcomingExams.first;

  /// 是否进入考试周冲刺模式（未来 21 天内有考试，或当前正在考试期间）
  bool get isSprintMode {
    final next = nextExam;
    if (next == null || next.time.isEmpty) return false;
    final diff = next.time[0].difference(currentTime.value);
    return diff.inDays <= 21;
  }

  /// 检查某考试是否与同天其它考试时间重叠冲突
  bool hasConflict(Exam exam) {
    if (exam.time.length < 2) return false;
    for (final other in allSortedExams) {
      if (identical(other, exam) || other.time.length < 2) continue;
      if (exam.time[1].isAfter(other.time[0]) &&
          other.time[1].isAfter(exam.time[0])) {
        return true;
      }
    }
    return false;
  }

  /// 检查某考试是否在同天连考（两场相隔 <= 90 分钟）
  (bool isBackToBack, int gapMinutes) checkBackToBack(Exam exam) {
    if (exam.time.length < 2) return (false, 0);
    for (final other in allSortedExams) {
      if (identical(other, exam) || other.time.length < 2) continue;
      if (exam.time[0].year == other.time[0].year &&
          exam.time[0].month == other.time[0].month &&
          exam.time[0].day == other.time[0].day) {
        if (!other.time[1].isAfter(exam.time[0])) {
          final gap = exam.time[0].difference(other.time[1]).inMinutes;
          if (gap >= 0 && gap <= 90) return (true, gap);
        }
        if (!exam.time[1].isAfter(other.time[0])) {
          final gap = other.time[0].difference(exam.time[1]).inMinutes;
          if (gap >= 0 && gap <= 90) return (true, gap);
        }
      }
    }
    return (false, 0);
  }

  /// 计算倒计时文本
  String countdownText(Exam exam) {
    if (exam.time.length < 2) return '';
    final now = currentTime.value;
    if (now.isAfter(exam.time[0]) && now.isBefore(exam.time[1])) {
      return '进行中';
    }
    if (now.isAfter(exam.time[1])) {
      return '已考完';
    }
    final diff = exam.time[0].difference(now);
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return '${diff.inDays}天${hours > 0 ? '$hours时' : ''}';
    }
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return '${diff.inHours}小时${mins > 0 ? '$mins分' : ''}';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟';
    }
    return '即将开考';
  }

  /// 考场地点导航与复制
  void openLocationNavigation(BuildContext context, Exam exam) {
    final raw = exam.location ?? '';
    if (raw.isEmpty) return;

    final fullAddress = CalendarLocationMapper.mapForCalendar(raw);
    final parts = fullAddress.split(',');
    final searchKeyword = parts.length > 1 ? parts[1].trim() : raw;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('考场地点：$raw'),
        message: Text(parts.length > 1
            ? '高德识别地址：$searchKeyword'
            : '选择高德导航或复制考场详细信息'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              final url =
                  'https://uri.amap.com/search?keyword=${Uri.encodeComponent(searchKeyword)}';
              launchUrlString(url, mode: LaunchMode.externalApplication);
            },
            child: const Text('高德地图搜索楼宇'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              final textToCopy =
                  '考试：${exam.name}\n地点：$raw\n座位：${exam.seat ?? "未分配"}\n时间：${exam.chineseTime}';
              Clipboard.setData(ClipboardData(text: textToCopy));
            },
            child: const Text('复制考场与座位信息'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 分组后的未考考试列表（按日期聚合）
  List<List<Exam>> get upcomingGroupedExams => _groupExams(upcomingExams);

  /// 分组后的历史考试列表
  List<List<Exam>> get pastGroupedExams => _groupExams(pastExams);

  List<List<Exam>> _groupExams(List<Exam> list) {
    final grouped = <String, List<Exam>>{};
    for (final exam in list) {
      grouped.putIfAbsent(_examDayKey(exam), () => []).add(exam);
    }
    return grouped.values.toList();
  }

  String _examDayKey(Exam exam) {
    if (exam.dateLabel != null) return 'label:${exam.dateLabel}';
    if (exam.time.isEmpty) return 'nodate';
    final date = exam.time[0];
    return 'date:${date.year}-${date.month}-${date.day}';
  }

  @override
  void onReady() {
    super.onReady();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value = DateTime.now();
      _durationToLastUpdate.value =
          DateTime.now().difference(_scholar.value.lastUpdateTimeCourse);
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}

