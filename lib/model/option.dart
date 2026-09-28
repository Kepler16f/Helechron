import 'package:get/get.dart';

enum BrightnessMode { system, light, dark }

enum GpaStrategy { best, first }

/// 日程提醒方式：通知提醒（系统日历横幅）或闹钟提醒（后台代理闹钟）
enum CalendarReminderMode { notification, alarm }

class CourseIdMap {
  String id1, id2;
  String comment;

  CourseIdMap({required this.id1, required this.id2, required this.comment});

  Map<String, dynamic> toJson() => {
        'id1': id1,
        'id2': id2,
        'comment': comment,
      };

  CourseIdMap.fromJson(Map<String, dynamic> json)
      : id1 = json['id1'],
        id2 = json['id2'],
        comment = json['comment'];
}

class Option {
  Rx<Duration> workTime;
  Rx<Duration> restTime;
  RxMap<DateTime, DateTime> allowTime;
  Rx<GpaStrategy> gpaStrategy;
  RxBool pushOnGradeChange;
  RxBool pushOnDdlReminder;
  Rx<BrightnessMode> brightnessMode;
  RxList<CourseIdMap> courseIdMappingList;
  RxBool hideHomeGpa;
  RxBool asyncRefresh;
  Rx<CalendarReminderMode> calendarReminderMode;
  RxBool bottomBarFloating;
  RxBool bottomBarImmersiveLight;

  /// 沉浸光感强度档位：10=跟随系统(自适应) 0=精致 1=柔和 2=流畅
  RxInt bottomBarMaterialLevel;

  Option({
    required this.workTime,
    required this.restTime,
    required this.allowTime,
    required this.gpaStrategy,
    required this.pushOnGradeChange,
    required this.pushOnDdlReminder,
    required this.brightnessMode,
    required this.courseIdMappingList,
    required this.hideHomeGpa,
    required this.asyncRefresh,
    required this.calendarReminderMode,
    required this.bottomBarFloating,
    required this.bottomBarImmersiveLight,
    required this.bottomBarMaterialLevel,
  });
}
