import 'package:celechron/model/grade.dart';

/// 成绩模拟器（What-If 计算器）课程项
class SimulatedCourse {
  final String id;
  String name;
  double credit;
  double expectedFivePoint;
  double originalFivePoint;
  bool isEnabled;
  final bool isCustom;

  SimulatedCourse({
    required this.id,
    required this.name,
    required this.credit,
    this.expectedFivePoint = 4.5,
    double? originalFivePoint,
    this.isEnabled = true,
    this.isCustom = false,
  }) : originalFivePoint = originalFivePoint ?? expectedFivePoint;

  /// 转为 Grade 实体，直接复用 GpaHelper 的核心计算逻辑
  Grade toGrade() {
    return Grade.fromSimulated(
      id: id,
      name: name,
      credit: credit,
      fivePoint: expectedFivePoint,
    );
  }

  /// 对应等级字母 (A+, A, A- 等)
  String get gradeLetter => Grade.fivePointToLetter(expectedFivePoint);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'credit': credit,
        'expectedFivePoint': expectedFivePoint,
        'originalFivePoint': originalFivePoint,
        'isEnabled': isEnabled,
        'isCustom': isCustom,
      };

  factory SimulatedCourse.fromJson(Map<String, dynamic> json) {
    return SimulatedCourse(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名课程',
      credit: (json['credit'] as num?)?.toDouble() ?? 1.0,
      expectedFivePoint:
          (json['expectedFivePoint'] as num?)?.toDouble() ?? 4.5,
      originalFivePoint:
          (json['originalFivePoint'] as num?)?.toDouble() ?? 4.5,
      isEnabled: json['isEnabled'] as bool? ?? true,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }
}
