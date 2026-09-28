import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/simulated_course.dart';
import 'package:celechron/utils/gpa_helper.dart';

void main() {
  group('SimulatedCourse and Grade conversion tests', () {
    test('SimulatedCourse.toGrade creates complete and valid Grade', () {
      final sim = SimulatedCourse(
        id: 'course_101',
        name: '高等数学',
        credit: 5.0,
        expectedFivePoint: 4.8,
      );

      final grade = sim.toGrade();
      expect(grade.id, 'course_101');
      expect(grade.name, '高等数学');
      expect(grade.credit, 5.0);
      expect(grade.fivePoint, 4.8);
      expect(grade.original, 'A');
      expect(grade.fourPoint, 4.2); // 4.8 on 5.0 scale -> 4.2 on 4.3 scale
      expect(grade.fourPointLegacy, 4.0); // >4.0 is 4.0 on legacy scale
      expect(grade.hundredPoint, 90); // 'A' corresponds to 90
      expect(grade.gpaIncluded, isTrue);
      expect(grade.creditIncluded, isTrue);
      expect(grade.earnedCredit, 5.0);
    });

    test('fivePointToLetter mapping correctly formats grades', () {
      expect(Grade.fivePointToLetter(5.0), 'A+');
      expect(Grade.fivePointToLetter(4.8), 'A');
      expect(Grade.fivePointToLetter(4.5), 'A-');
      expect(Grade.fivePointToLetter(4.2), 'B+');
      expect(Grade.fivePointToLetter(3.9), 'B');
      expect(Grade.fivePointToLetter(3.6), 'B-');
      expect(Grade.fivePointToLetter(3.3), 'C+');
      expect(Grade.fivePointToLetter(3.0), 'C');
      expect(Grade.fivePointToLetter(2.5), 'C-');
      expect(Grade.fivePointToLetter(2.0), 'D');
      expect(Grade.fivePointToLetter(0.0), 'F');
    });

    test('SimulatedCourse JSON serialization and deserialization', () {
      final original = SimulatedCourse(
        id: 'cust_123',
        name: '机器学习基础',
        credit: 3.5,
        expectedFivePoint: 4.5,
        originalFivePoint: 4.2,
        isEnabled: false,
        isCustom: true,
      );

      final json = original.toJson();
      final restored = SimulatedCourse.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.credit, original.credit);
      expect(restored.expectedFivePoint, original.expectedFivePoint);
      expect(restored.originalFivePoint, original.originalFivePoint);
      expect(restored.isEnabled, original.isEnabled);
      expect(restored.isCustom, original.isCustom);
    });
  });

  group('What-If GPA calculation tests', () {
    test('calculateGpa handles combination of real and simulated grades', () {
      // Historical base: 10 credits at 4.0 GPA
      final baseGrade1 = Grade.fromSimulated(
        id: 'base_1',
        name: '线性代数',
        credit: 4.0,
        fivePoint: 4.0,
      );
      final baseGrade2 = Grade.fromSimulated(
        id: 'base_2',
        name: '程序设计',
        credit: 6.0,
        fivePoint: 4.0,
      );

      final baseGpa = GpaHelper.calculateGpa([baseGrade1, baseGrade2]);
      expect(baseGpa.item1[0], closeTo(4.0, 0.001));
      expect(baseGpa.item2, 10.0);

      // What-If: user takes 10 new credits and expects 5.0
      final simCourse1 = SimulatedCourse(
        id: 'sim_1',
        name: '微积分II',
        credit: 5.0,
        expectedFivePoint: 5.0,
      );
      final simCourse2 = SimulatedCourse(
        id: 'sim_2',
        name: '离散数学',
        credit: 5.0,
        expectedFivePoint: 5.0,
      );

      final combinedGrades = [
        baseGrade1,
        baseGrade2,
        simCourse1.toGrade(),
        simCourse2.toGrade(),
      ];

      final combinedGpa = GpaHelper.calculateGpa(combinedGrades);
      // (10 * 4.0 + 10 * 5.0) / 20 = 4.5
      expect(combinedGpa.item1[0], closeTo(4.5, 0.001));
      expect(combinedGpa.item2, 20.0);
    });
  });

  group('Goal-Seeking calculation tests', () {
    test('Calculates correct required GPA for achievable target', () {
      const currentCredits = 50.0;
      const currentGpa = 4.2;
      const currentPoints = currentCredits * currentGpa; // 210.0

      const remainingCredits = 20.0;
      const targetGpa = 4.4;
      const totalCredits = currentCredits + remainingCredits; // 70.0

      // targetPoints = 4.4 * 70 = 308.0
      // requiredPoints = 308.0 - 210.0 = 98.0
      // requiredGpa = 98.0 / 20.0 = 4.9
      final requiredGpa =
          (targetGpa * totalCredits - currentPoints) / remainingCredits;
      final maxPossible =
          (currentPoints + 5.0 * remainingCredits) / totalCredits;

      expect(requiredGpa, closeTo(4.9, 0.01));
      expect(maxPossible, closeTo((210.0 + 100.0) / 70.0, 0.01)); // ~4.428
      expect(requiredGpa <= 5.0, isTrue);
    });

    test('Detects impossible target when required GPA exceeds 5.0', () {
      const currentCredits = 50.0;
      const currentGpa = 3.5;
      const currentPoints = currentCredits * currentGpa; // 175.0

      const remainingCredits = 10.0;
      const targetGpa = 4.5;
      const totalCredits = currentCredits + remainingCredits; // 60.0

      // targetPoints = 4.5 * 60 = 270.0
      // requiredPoints = 270.0 - 175.0 = 95.0
      // requiredGpa = 95.0 / 10.0 = 9.5 (> 5.0, Impossible)
      final requiredGpa =
          (targetGpa * totalCredits - currentPoints) / remainingCredits;
      final maxPossible =
          (currentPoints + 5.0 * remainingCredits) / totalCredits; // (175 + 50) / 60 = 3.75

      expect(requiredGpa > 5.0, isTrue);
      expect(maxPossible, closeTo(3.75, 0.01));
    });
  });
}
