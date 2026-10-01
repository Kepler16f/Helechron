import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/page/scholar/grade_detail/credit_progress_controller.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'package:celechron/http/zjuServices/zdbk.dart';

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
      expect(url.startsWith('https://classroom.zju.edu.cn/#/searchContent?title='), isTrue);
      expect(url.contains(Uri.encodeComponent('大学计算机基础')), isTrue);
    });

    test('ZhiyunService portal and SSO URLs are valid', () {
      expect(ZhiyunService.buildPortalUrl(), 'https://classroom.zju.edu.cn');
      expect(ZhiyunService.buildSsoLoginUrl().contains('zjuam.zju.edu.cn'), isTrue);
    });

    test('ZhiyunService isRecordableCourse correctly filters non-recordable courses', () {
      // 体育、身体素质课、体测等显然不可能有录播
      expect(ZhiyunService.isRecordableCourse('身体素质与健康课堂'), isFalse);
      expect(ZhiyunService.isRecordableCourse('体育(1)'), isFalse);
      expect(ZhiyunService.isRecordableCourse('国家学生体质健康标准测试'), isFalse);
      expect(ZhiyunService.isRecordableCourse('军训'), isFalse);
      expect(ZhiyunService.isRecordableCourse('生产实习'), isFalse);

      // 理论课、专业课属于录播课程
      expect(ZhiyunService.isRecordableCourse('军事理论'), isTrue);
      expect(ZhiyunService.isRecordableCourse('军事理论(网络)'), isTrue);
      expect(ZhiyunService.isRecordableCourse('线性代数'), isTrue);
      expect(ZhiyunService.isRecordableCourse('微积分(甲)Ⅰ'), isTrue);
      expect(ZhiyunService.isRecordableCourse('大学物理(甲)Ⅰ'), isTrue);
    });

    test('ZhiyunService buildLivingroomUrl constructs precise livingroom URL', () {
      final url = ZhiyunService.buildLivingroomUrl('85940', '1973989');
      expect(
        url,
        'https://classroom.zju.edu.cn/livingroom?course_id=85940&sub_id=1973989&tenant_code=112',
      );
    });
  });

  group('P4: Training Plan (pyfagl) & Credit Dashboard tests', () {
    test('TrainingPlanInfo serializes and deserializes properly', () {
      final plan = TrainingPlanInfo(
        pyfaId: '2024080901001',
        planName: '2024级工科试验班（信息）培养方案',
        majorName: '工科试验班（信息）',
        grade: '2024',
        collegeName: '信息与电子工程学院',
        totalCredits: 165.5,
        categoryCredits: {
          '通识必修课': 34.0,
          '通识选修课': 10.0,
          '大类基础课': 35.0,
          '专业必修课': 40.0,
          '专业选修课': 25.0,
          '实践与毕业设计': 16.0,
        },
        isFiveYear: false,
      );

      final json = plan.toJson();
      expect(json['pyfaId'], '2024080901001');
      expect(json['totalCredits'], 165.5);
      expect(json['majorName'], '工科试验班（信息）');

      final reconstructed = TrainingPlanInfo.fromJson(json);
      expect(reconstructed.pyfaId, '2024080901001');
      expect(reconstructed.planName, '2024级工科试验班（信息）培养方案');
      expect(reconstructed.totalCredits, 165.5);
      expect(reconstructed.categoryCredits['通识必修课'], 34.0);
      expect(reconstructed.isFiveYear, isFalse);
    });

    test('Training plan credit extraction regex patterns parse various formats', () {
      final testSnippets = [
        '本专业最低毕业学分要求：165.5 学分，其中通识必修 34 学分',
        '<tr><td>毕业最低学分</td><td>160.0</td></tr>',
        '本专业毕业总学分要求为 160 学分',
        '最低修读学分: 168.0',
        '总学分：210.0（五年制医学）',
        '学生在学期间需修满教学计划要求 162.5 学分方可准予毕业',
      ];

      final creditPatterns = [
        RegExp(
            r'(?:最低毕业学分|毕业要求最低学分|毕业最低学分|最低修读学分|最低学分要求|毕业总学分|最低要求学分|修读总学分|毕业要求|总学分)[^\d\r\n]{0,25}(\d{2,3}(?:\.\d+)?)',
            caseSensitive: false),
        RegExp(r'(\d{2,3}(?:\.\d+)?)\s*学分[^\w\r\n]{0,10}(?:毕业|最低)',
            caseSensitive: false),
        RegExp(r'要求[^\d\r\n]{0,10}(\d{2,3}(?:\.\d+)?)\s*学分',
            caseSensitive: false),
      ];

      for (final snippet in testSnippets) {
        double? extracted;
        for (final p in creditPatterns) {
          final m = p.firstMatch(snippet);
          if (m != null) {
            extracted = double.tryParse(m.group(1) ?? '');
            if (extracted != null && extracted >= 100 && extracted <= 300) {
              break;
            }
          }
        }
        expect(extracted, isNotNull, reason: 'Failed to extract from: $snippet');
        expect(extracted! >= 160.0 && extracted <= 210.0, isTrue);
      }
    });

    test('Five-year vs four-year major detection', () {
      const fiveYearMajors = ['建筑学', '临床医学', '口腔医学', '城乡规划'];
      const fourYearMajors = ['计算机科学与技术', '软件工程', '信息与电子工程', '机械工程'];

      for (final m in fiveYearMajors) {
        final isFive = m.contains('建筑') ||
            m.contains('临床') ||
            m.contains('口腔') ||
            m.contains('医学') ||
            m.contains('规划');
        expect(isFive, isTrue, reason: '$m should be recognized as 5-year');
      }

      for (final m in fourYearMajors) {
        final isFive = m.contains('建筑') ||
            m.contains('临床') ||
            m.contains('口腔') ||
            m.contains('医学') ||
            m.contains('规划');
        expect(isFive, isFalse, reason: '$m should be recognized as 4-year');
      }
    });
  });
}
