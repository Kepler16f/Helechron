import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/services/zhiyun_service.dart';

void main() {
  group('ZhiyunService 课程名称与回放匹配逻辑测试', () {
    test('课程名称归一化测试', () {
      expect(ZhiyunService.normalizeCourseName('微积分（甲）Ⅰ(01)'), equals('微积分甲1'));
      expect(ZhiyunService.normalizeCourseName('微积分(乙)Ⅱ'), equals('微积分乙2'));
      expect(ZhiyunService.normalizeCourseName('线性代数Ⅰ(H)'), equals('线性代数1'));
      expect(ZhiyunService.normalizeCourseName('大学英语(3)'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('大学英语（三）'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('大学英语Ⅲ'), equals('大学英语3'));
      expect(ZhiyunService.normalizeCourseName('面向对象程序设计（Python）'),
          equals('面向对象程序设计python'));
      expect(ZhiyunService.normalizeCourseName('微积分（甲）Ⅰ (冬)'), equals('微积分甲1'));
      expect(ZhiyunService.normalizeCourseName('离散数学 (2026-2027秋冬)'), equals('离散数学'));
    });

    test('秋冬/春夏跨学期与冬学期课程智能匹配', () {
      expect(
        ZhiyunService.matchesCourseName('微积分（甲）Ⅰ', '微积分(甲)Ⅰ (冬)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('微积分(甲)Ⅰ (冬)', '微积分（甲）Ⅰ'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('微积分（甲）Ⅰ', '微积分（甲）Ⅰ (2026-2027秋冬)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('离散数学', '离散数学 (冬学期)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('大学物理', '大学物理 (后半学期)'),
        isTrue,
      );
      expect(
        ZhiyunService.matchesCourseName('大学英语(3)', '大学英语Ⅲ (秋冬)'),
        isTrue,
      );
    });

    test('智云秒级与毫秒级时间戳解析兼容性测试', () {
      final secDt = ZhiyunService.parseZhiyunTimestamp(1731229200);
      final msDt = ZhiyunService.parseZhiyunTimestamp(1731229200000);
      expect(secDt, isNotNull);
      expect(msDt, isNotNull);
      expect(secDt!.millisecondsSinceEpoch, equals(msDt!.millisecondsSinceEpoch));
      expect(secDt.year, equals(2024));
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

  group('ZhiyunService 直播与回放状态精准区分测试', () {
    test('status=1 普通已发布课节绝不误判为正在直播', () {
      final now = DateTime.now();
      final pastStart = now.subtract(const Duration(days: 3, hours: 2));
      final pastEnd = now.subtract(const Duration(days: 3));
      final item = <String, dynamic>{
        'sub_id': '1973989',
        'title': '第1讲 绪论',
        'status': '1',
        'start_at': (pastStart.millisecondsSinceEpoch ~/ 1000).toString(),
        'end_at': (pastEnd.millisecondsSinceEpoch ~/ 1000).toString(),
        'playback': 'https://cdn.example.com/replay.m3u8',
      };
      expect(ZhiyunService.checkIsLive(item: item), isFalse);
      expect(ZhiyunService.checkHasReplay(item: item), isTrue);
    });

    test('没有时间窗且仅 status=1 且非直播标签时不误判为直播', () {
      final item = <String, dynamic>{
        'sub_id': '1973990',
        'title': '普通课节',
        'status': '1',
      };
      expect(ZhiyunService.checkIsLive(item: item), isFalse);
    });

    test('服务端 status=2 或 status_label=直播 且未过时间窗时正确识别为直播', () {
      final now = DateTime.now();
      final item = <String, dynamic>{
        'sub_id': '1973991',
        'title': '正在上课',
        'status': '2',
        'status_label': '直播',
        'start_at': (now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000).toString(),
        'end_at': (now.add(const Duration(minutes: 40)).millisecondsSinceEpoch ~/ 1000).toString(),
      };
      expect(ZhiyunService.checkIsLive(item: item), isTrue);
      expect(ZhiyunService.checkHasReplay(item: item), isFalse);
    });

    test('status=3/4 或含回放/已结束标识绝不判定为直播', () {
      final now = DateTime.now();
      final item = <String, dynamic>{
        'sub_id': '1973992',
        'title': '已转回放',
        'status': '3',
        'status_label': '回放',
        'start_at': (now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000).toString(),
        'end_at': (now.add(const Duration(minutes: 40)).millisecondsSinceEpoch ~/ 1000).toString(),
        'playback': {'m3u8': 'https://cdn.example.com/live_end.m3u8'},
      };
      expect(ZhiyunService.checkIsLive(item: item), isFalse);
      expect(ZhiyunService.checkHasReplay(item: item), isTrue);
    });

    test('无 playback 且含实时 live_url 的直播课节正确识别为直播而非回放', () {
      final now = DateTime.now();
      final item = <String, dynamic>{
        'sub_id': '1973993',
        'title': '第8讲 实时授课',
        'status': '2',
        'live_url': 'https://live.example.com/live/stream.m3u8',
        'start_at': (now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000).toString(),
        'end_at': (now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000).toString(),
      };
      expect(ZhiyunService.checkIsLive(item: item), isTrue);
      expect(ZhiyunService.checkHasReplay(item: item), isFalse);
    });

    test('sub_status=2 与 class_begin/course_begin 字段可正确识别正在直播并匹配当节', () {
      final now = DateTime.now();
      final liveItem = <String, dynamic>{
        'sub_id': '2026001',
        'title': '第9讲 实时直播',
        'sub_status': '2',
        'class_begin':
            (now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch ~/
                    1000)
                .toString(),
        'class_end':
            (now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000)
                .toString(),
      };
      final futureItem = <String, dynamic>{
        'sub_id': '2026099',
        'title': '下学期预排课节',
        'sub_status': '1',
        'course_begin':
            (now.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000)
                .toString(),
      };
      expect(ZhiyunService.checkIsLive(item: liveItem), isTrue);
      expect(ZhiyunService.checkIsLive(item: futureItem), isFalse);

      final matched = ZhiyunService.findBestMatchingCatalogueItem(
        catalogue: [futureItem, liveItem],
        targetDate: now,
      );
      expect(matched?['sub_id'], equals('2026001'));
    });

    test('PHP 序列化 _token Cookie 与网页播放器 token Query 拼接正确', () {
      const token = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.payload.sig';
      final encoded = ZhiyunService.buildPhpSerializedTokenCookie(token);
      final decoded = Uri.decodeComponent(encoded);
      expect(
        decoded,
        equals('a:2:{i:0;s:6:"_token";i:1;s:${token.length}:"$token";}'),
      );

      final appended = ZhiyunService.appendTokenToUrl(
        'https://livingroom.cmc.zju.edu.cn/living?course_id=85940&sub_id=1973989',
        token,
      );
      expect(appended, contains('&token='));
      expect(appended, contains(Uri.encodeComponent(token)));

      final refreshed = ZhiyunService.appendTokenToUrl(
        'https://livingroom.cmc.zju.edu.cn/living?token=stale_token',
        token,
      );
      final refreshedUri = Uri.parse(refreshed);
      expect(refreshedUri.queryParameters['token'], equals(token));
      expect(refreshedUri.queryParameters['tenant_code'], equals('112'));

      final signed = ZhiyunService.signPlayUrl(
        'https://live.cmc.zju.edu.cn/live/stream.m3u8',
        isLive: true,
      );
      expect(Uri.parse(signed).queryParameters['clientUUID'], isNotEmpty);
    });
  });
}
