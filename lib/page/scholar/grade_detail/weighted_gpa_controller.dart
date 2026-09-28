import 'package:get/get.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/utils/gpa_helper.dart';

/// 加权成绩控制器（专注各课程加权比重测算）
class WeightedGpaController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final _db = Get.find<DatabaseHelper>(tag: 'db');

  // ==================== 加权成绩状态 ====================
  final RxMap<String, double> weightedMap = RxMap<String, double>();
  final semesterIndex = 0.obs;
  final showAllSemesters = false.obs;
  late RxList<Semester> semestersWithGrades;

  @override
  void onInit() {
    super.onInit();
    // 载入加权比例
    weightedMap.value = _db.getWeightedGpa();
    semestersWithGrades = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList()
        .obs;

    ever(scholar, (callback) {
      refreshSemesters();
    });
  }

  void refreshSemesters() {
    semestersWithGrades.value = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList();
    semestersWithGrades.refresh();
  }

  // ==================== 加权绩点核心计算 ====================

  double getWeight(String gradeId) {
    return weightedMap[gradeId] ?? 1.0;
  }

  void setWeight(String gradeId, double weight) {
    weightedMap[gradeId] = weight;
    refreshWeightedGpa();
  }

  void refreshWeightedGpa() {
    _db.setWeightedGpa(Map<String, double>.from(weightedMap));
  }

  List<Grade> getAllGrades() {
    return scholar.value.grades.values.expand((g) => g).toList();
  }

  List<Grade> getCurrentSemesterGrades() {
    if (showAllSemesters.value) {
      return getAllGrades();
    }
    if (semestersWithGrades.isEmpty ||
        semesterIndex.value >= semestersWithGrades.length) {
      return [];
    }
    return semestersWithGrades[semesterIndex.value].grades;
  }

  Tuple<List<double>, double> calculateWeightedGpa() {
    final allGrades = getAllGrades();
    return GpaHelper.calculateWeightedGpa(allGrades, weightedMap);
  }

  Tuple<List<double>, double> calculateCurrentSemesterWeightedGpa() {
    final grades = getCurrentSemesterGrades();
    return GpaHelper.calculateWeightedGpa(grades, weightedMap);
  }
}
