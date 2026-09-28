import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/grade_detail/credit_progress_controller.dart';
import 'package:celechron/services/zhiyun_service.dart';

void main() {
  group('P2: Grade Category and Credit Progress tests', () {
    test('Grade parses category from JSON', () {
      final json = {
        'xkkh': '(2023-2024-1)-CS101-1',
        'kcmc': '面向对象程序设计',
        'xf': '3.0',
        'cj': '88',
        'jd': '4.5',
        'kcxzmc': '专业必修课',
      };
      final grade = Grade(json);
      expect(grade.category, '专业必修课');
      expect(grade.name, '面向对象程序设计');
      expect(grade.credit, 3.0);
      expect(grade.fivePoint, 4.5);
    });

    test('Grade infers category when kcxzmc is missing', () {
      final peJson = {
        'xkkh': '(2023-2024-1)-PE101-1',
        'kcmc': '体质健康标准测试',
        'xf': '0.5',
        'cj': '合格',
        'jd': '0.0',
      };
      final peGrade = Grade(peJson);
      expect(peGrade.category, '体育与体测');

      final politicsJson = {
        'xkkh': '(2023-2024-1)-POL101-1',
        'kcmc': '思想道德与法治',
        'xf': '3.0',
        'cj': '92',
        'jd': '4.8',
      };
      final polGrade = Grade(politicsJson);
      expect(polGrade.category, '通识必修课');
    });

    test('CreditProgressController normalizeCategory groups properly', () {
      final grade = Grade.empty()..id = '123'..name = '测试课'..credit = 2.0;

      expect(CreditProgressController.normalizeCategory('通识必修课', grade), '通识必修课');
      expect(CreditProgressController.normalizeCategory('通识核心课程', grade), '通识选修课');
      expect(CreditProgressController.normalizeCategory('学科基础课', grade), '大类基础课');
      expect(CreditProgressController.normalizeCategory('专业核心课', grade), '专业必修课');
      expect(CreditProgressController.normalizeCategory('专业方向课', grade), '专业选修课');
      expect(CreditProgressController.normalizeCategory('生产实习', grade), '实践与毕业设计');
      expect(CreditProgressController.normalizeCategory('个性化修读', grade), '跨专业与个性修读');
    });
  });

  group('P3: Zhiyun Classroom Service tests', () {
    test('ZhiyunService cleanCourseName strips section and brackets', () {
      expect(ZhiyunService.cleanCourseName('大学物理（甲）(01)'), '大学物理(甲)');
      expect(ZhiyunService.cleanCourseName('高等数学（乙）'), '高等数学(乙)');
      expect(ZhiyunService.cleanCourseName('微积分 (02)'), '微积分');
      expect(ZhiyunService.cleanCourseName('计算机系统概论'), '计算机系统概论');
    });

    test('ZhiyunService buildSearchUrl constructs valid URL', () {
      final url = ZhiyunService.buildSearchUrl('大学计算机基础');
      expect(url.startsWith('https://classroom.zju.edu.cn/search?keywords='), isTrue);
      expect(url.contains(Uri.encodeComponent('大学计算机基础')), isTrue);
    });

    test('ZhiyunService portal and SSO URLs are valid', () {
      expect(ZhiyunService.buildPortalUrl(), 'https://classroom.zju.edu.cn');
      expect(ZhiyunService.buildSsoLoginUrl().contains('zjuam.zju.edu.cn'), isTrue);
    });
  });
}
