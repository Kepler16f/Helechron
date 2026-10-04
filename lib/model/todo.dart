import 'package:celechron/utils/json_utils.dart';

class Todo {
  String id;
  String name;
  String course;
  DateTime? endTime;
  String courseId;

  Todo.fromJson(Map<String, dynamic> json)
      : id = asString(json["id"]) ?? json["id"]?.toString() ?? '',
        name = asString(json["title"]) ?? '未命名作业',
        course = asString(json["course_name"]) ?? '未知课程',
        endTime = DateTime.tryParse(asString(json["end_time"]) ?? ''),
        courseId = json["course_id"]?.toString() ?? '';

  /// 学在浙大作业直达提交页；缺少课程 ID 时回退到待办主页。
  String get submitUrl => courseId.isNotEmpty && id.isNotEmpty
      ? 'https://courses.zju.edu.cn/course/$courseId/learning-activity#/$id'
      : 'https://courses.zju.edu.cn/user/index#/todo';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': name,
        'course_name': course,
        'end_time': endTime?.toIso8601String(),
        'course_id': courseId,
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
