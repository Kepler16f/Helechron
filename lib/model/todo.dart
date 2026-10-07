import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:celechron/utils/json_utils.dart';

enum HomeworkSubmissionStatus {
  unsubmitted, // 未提交
  submitted, // 已提交（待批改）
  graded, // 已批改（已出分）
  overdue, // 逾期未交
}

class Todo {
  String id;
  String name;
  String course;
  DateTime? endTime;
  String courseId;
  HomeworkSubmissionStatus submissionStatus;
  double? score;
  String? completeness;
  DateTime? submittedAt;

  Todo.fromJson(Map<String, dynamic> json)
      : id = asString(json["id"]) ?? json["id"]?.toString() ?? '',
        name = asString(json["title"]) ?? '未命名作业',
        course = asString(json["course_name"]) ?? '未知课程',
        endTime = DateTime.tryParse(asString(json["end_time"]) ?? ''),
        courseId =
            asString(json["course_id"]) ?? json["course_id"]?.toString() ?? '',
        submissionStatus = _parseSubmissionStatus(json),
        score = (json["score"] as num?)?.toDouble(),
        completeness = asString(json["completeness"]),
        submittedAt = DateTime.tryParse(asString(json["submitted_at"]) ?? '');

  static HomeworkSubmissionStatus _parseSubmissionStatus(
      Map<String, dynamic> json) {
    final statusStr = asString(json["submission_status"]);
    if (statusStr != null) {
      for (final s in HomeworkSubmissionStatus.values) {
        if (s.name == statusStr) return s;
      }
    }
    if (json["score"] != null) return HomeworkSubmissionStatus.graded;
    if (asString(json["completeness"]) == 'full') {
      return HomeworkSubmissionStatus.submitted;
    }
    return HomeworkSubmissionStatus.unsubmitted;
  }

  bool get isSubmitted =>
      submissionStatus == HomeworkSubmissionStatus.submitted ||
      submissionStatus == HomeworkSubmissionStatus.graded ||
      completeness == 'full' ||
      score != null;

  bool get isGraded =>
      submissionStatus == HomeworkSubmissionStatus.graded || score != null;

  HomeworkSubmissionStatus get effectiveStatus {
    if (isGraded) return HomeworkSubmissionStatus.graded;
    if (isSubmitted) return HomeworkSubmissionStatus.submitted;
    if (endTime != null && endTime!.isBefore(DateTime.now())) {
      return HomeworkSubmissionStatus.overdue;
    }
    return HomeworkSubmissionStatus.unsubmitted;
  }

  String get statusText {
    switch (effectiveStatus) {
      case HomeworkSubmissionStatus.graded:
        final scoreText = score != null
            ? (score! == score!.roundToDouble()
                ? score!.toInt().toString()
                : score!.toStringAsFixed(1))
            : '';
        return scoreText.isNotEmpty ? '已批改 · $scoreText分' : '已批改';
      case HomeworkSubmissionStatus.submitted:
        return '已提交';
      case HomeworkSubmissionStatus.overdue:
        return '逾期未交';
      case HomeworkSubmissionStatus.unsubmitted:
        return '待提交';
    }
  }

  /// 优先使用当前 courseId；若历史缓存缺少该字段，从原始缓存中补全
  String get resolvedCourseId {
    if (courseId.isNotEmpty) return courseId;
    if (id.isEmpty) return '';
    try {
      if (Hive.isBoxOpen('dbOriginalWebPage')) {
        final box = Hive.box('dbOriginalWebPage');
        final cached = box.get('courses_todo');
        if (cached is String && cached.isNotEmpty) {
          final decoded = jsonDecode(cached);
          final list =
              asDynamicList(decoded is Map ? decoded['todo_list'] : null);
          if (list != null) {
            for (final item in list) {
              final m = asStringMap(item);
              if (m != null && m['id']?.toString() == id) {
                final cid = m['course_id']?.toString();
                if (cid != null && cid.isNotEmpty) {
                  courseId = cid;
                  return cid;
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return '';
  }

  /// 学在浙大作业直达提交页（按 TronClass 格式定位到作业说明与文件上传提交区）
  /// 示例：https://courses.zju.edu.cn/course/99642/learning-activity#/1158609?view=scores
  String get submitUrl {
    final cid = resolvedCourseId;
    if (cid.isNotEmpty && id.isNotEmpty) {
      return 'https://courses.zju.edu.cn/course/$cid/learning-activity#/$id?view=scores';
    }
    return 'https://courses.zju.edu.cn/user/index#/todo';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': name,
        'course_name': course,
        'end_time': endTime?.toIso8601String(),
        'course_id': courseId,
        'submission_status': submissionStatus.name,
        'score': score,
        'completeness': completeness,
        'submitted_at': submittedAt?.toIso8601String(),
      };

  static List<Todo> getAllFromCourses(Map<String, dynamic> json) {
    final rawTodos = asDynamicList(json["todo_list"]) ?? const [];
    final todos = <Todo>[];
    for (final rawTodo in rawTodos) {
      final todoMap = asStringMap(rawTodo);
      if (todoMap == null || asBool(todoMap["is_student"]) != true) continue;
      try {
        final todo = Todo.fromJson(todoMap);
        if (todo.id.isNotEmpty) todos.add(todo);
      } catch (_) {
        // 单条作业字段异常不影响其它作业。
      }
    }
    return todos;
  }

  // TODO: 对于助教/老师，是否需要将批改作业当作 todo 来显示？

  bool isInOneDay() => endTime != null
      ? endTime!.subtract(const Duration(days: 1)).isBefore(DateTime.now())
      : false;

  bool isInOneWeek() => endTime != null
      ? endTime!.subtract(const Duration(days: 7)).isBefore(DateTime.now())
      : false;
}
