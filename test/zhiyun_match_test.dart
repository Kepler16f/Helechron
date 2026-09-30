import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/services/zhiyun_service.dart';

void main() {
  group('ZhiyunService 课程名称与回放匹配逻辑测试', () {
    test('课程名称归一化测试', () {
      expect(ZhiyunService.normalizeCourseName('微积分（甲）Ⅰ(01)'), equals('微积分甲1'));
      expect(ZhiyunService.normalizeCourseName('微积分(乙)Ⅱ'), equals('微积分乙2'));
      expect(ZhiyunService.normalizeCourseName('线性代数Ⅰ(H)'), equals('线性代数1h'));
      expect(ZhiyunService.normalizeCourseName('大学英语(3)'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('大学英语（三）'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('大学英语Ⅲ'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('面向对象程序设计（Python）'),
          equals('面向对象程序设计python'));
    });

    test('Python 课程智能模糊匹配', () {
      expect(
        ZhiyunService.matchesCourseName('面向对象程序设计(Python)', 'Python程序设计'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('Python程序设计', '面向对象程序设计(Python)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('程序设计基础(Python)', 'Python程序设计'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('面向对象程序设计(Python)', '面向对象程序设计'),
        isTrue,
      );
    });

    test('大学英语分级匹配与防串级', () {
      // 相同级别匹配（支持罗马数字、阿拉伯数字、中文数字）
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '大学英语Ⅲ'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '大学英语（三）'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '大学英语3'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '通用学术英语(3)'),
        isTrue,
      );

      // 不同级别严格区分，不应串级
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '大学英语(4)'),
        isFalse,
      );
      expect(
        ZhiyunService.matchesCourseName('大学英语(1)', '大学英语(2)'),
        isFalse,
      );
    });

    test('微积分与线性代数智能匹配', () {
      expect(
        ZhiyunService.matchesCourseName('微积分(甲)Ⅰ', '微积分'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('线性代数(乙)', '线性代数'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('线性代数', '线性代数(乙)'),
        isTrue,
      );
    });

    test('核心课程名称提取与模式修饰去除', () {
      expect(ZhiyunService.extractCoreCourseName('军事理论(网络)'), equals('军事理论'));
      expect(ZhiyunService.extractCoreCourseName('军事理论（01班）'), equals('军事理论'));
      expect(ZhiyunService.extractCoreCourseName('大学英语(双语)(02)'), equals('大学英语'));
      expect(ZhiyunService.extractCoreCourseName('微积分(MOOC)'), equals('微积分'));
      expect(ZhiyunService.extractCoreCourseName('线性代数(线上)'), equals('线性代数'));
    });

    test('军事理论与通识理论课程智能匹配', () {
      expect(
        ZhiyunService.matchesCourseName('军事理论(网络)', '军事理论'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('军事理论', '军事理论(网络)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('军事理论（01班）', '军事理论'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('思想道德与法治(01)', '思想道德与法治'),
        isTrue,
      );
    });

    test('非录播课程自动识别与过滤', () {
      expect(ZhiyunService.isRecordableCourse('身体素质课(01)'), isFalse);
      expect(ZhiyunService.isRecordableCourse('大学体育(乒乓球)'), isFalse);
      expect(ZhiyunService.isRecordableCourse('体质健康测试'), isFalse);
      expect(ZhiyunService.isRecordableCourse('金工实习'), isFalse);
      expect(ZhiyunService.isRecordableCourse('形式与政策'), isFalse);
      expect(ZhiyunService.isRecordableCourse('军训'), isFalse);
      expect(ZhiyunService.isRecordableCourse('军事技能'), isFalse);
      expect(ZhiyunService.isRecordableCourse('军事理论'), isTrue);
      expect(ZhiyunService.isRecordableCourse('军事理论(网络)'), isTrue);
      expect(ZhiyunService.isRecordableCourse('毛泽东思想和中国特色社会主义理论体系概论'), isTrue);
      expect(ZhiyunService.isRecordableCourse('思想道德与法治'), isTrue);
      expect(ZhiyunService.isRecordableCourse('微积分(甲)Ⅰ'), isTrue);
      expect(ZhiyunService.isRecordableCourse('线性代数(乙)'), isTrue);
      expect(ZhiyunService.isRecordableCourse('面向对象程序设计(Python)'), isTrue);
    });

    test('课程ID与链接提取支持', () {
      expect(ZhiyunService.extractCourseId('85940'), equals('85940'));
      expect(
        ZhiyunService.extractCourseId(
            'https://classroom.zju.edu.cn/livingroom?course_id=85940&sub_id=1973989&tenant_code=112'),
        equals('85940'),
      );
      expect(
        ZhiyunService.extractCourseId(
            'https://classroom.zju.edu.cn/coursedetail/86957?tenant_code=112'),
        equals('86957'),
      );
      expect(
        ZhiyunService.extractCourseId('https://classroom.zju.edu.cn/detail/85941'),
        equals('85941'),
      );
      expect(
        ZhiyunService.extractCourseId('?cid=86957'),
        equals('86957'),
      );
    });
  });
}
