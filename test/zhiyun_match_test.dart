import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/services/zhiyun_service.dart';
import 'package:hive/hive.dart';

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

  group('ZhiyunService 秋/冬学期同门课程分流与下架链接防护测试', () {
    Course makeCourse({
      required String id,
      required String name,
      String teacher = '张老师',
      required bool firstHalf,
      required bool secondHalf,
    }) {
      final session = Session.fromJson({
        'id': '$id-1',
        'name': name,
        'teacher': teacher,
        'confirmed': true,
        'firstHalf': firstHalf,
        'secondHalf': secondHalf,
        'oddWeek': true,
        'evenWeek': true,
        'day': 1,
        'time': [1, 2],
        'location': '紫金港',
      });
      return Course.fromGrsSession(session)..id = id;
    }

    test('无 sub_id 时 buildCourseLivingroomUrl 必须跳转 /coursedetail 避免 /livingroom 报课程已下架', () {
      expect(
        ZhiyunService.buildCourseLivingroomUrl('85940'),
        equals('https://classroom.zju.edu.cn/coursedetail?course_id=85940&tenant_code=112'),
      );
      expect(
        ZhiyunService.buildCourseLivingroomUrl('85940', subId: ''),
        equals('https://classroom.zju.edu.cn/coursedetail?course_id=85940&tenant_code=112'),
      );
      expect(
        ZhiyunService.buildCourseLivingroomUrl('85940', subId: '1973989'),
        equals('https://classroom.zju.edu.cn/livingroom?course_id=85940&sub_id=1973989&tenant_code=112'),
      );
    });

    test('inferSemesterHint 与 scoreSemesterMatch 精准区分纯秋、纯冬及秋冬分期课程', () {
      final autumnCourse = makeCourse(
        id: '(2026-2027-1)-061B0010-001',
        name: '程序设计基础',
        firstHalf: true,
        secondHalf: false,
      );
      final winterCourse = makeCourse(
        id: '(2026-2027-1)-061B0010-002',
        name: '程序设计基础',
        firstHalf: false,
        secondHalf: true,
      );
      final fullCourse = makeCourse(
        id: '(2026-2027-1)-061B0010-003',
        name: '微积分(甲)Ⅰ',
        firstHalf: true,
        secondHalf: true,
      );

      final autumnHint = ZhiyunService.inferSemesterHint(course: autumnCourse);
      expect(autumnHint.academicYearStart, equals(2026));
      expect(autumnHint.halfTag, equals('autumn'));
      expect(autumnHint.preferredYearMonths, containsAll(['2026-09', '2026-10']));
      expect(autumnHint.preferredYearMonths, isNot(contains('2026-11')));

      final winterHint = ZhiyunService.inferSemesterHint(course: winterCourse);
      expect(winterHint.halfTag, equals('winter'));
      expect(winterHint.preferredYearMonths, containsAll(['2026-11', '2026-12', '2027-01']));

      final septHint = ZhiyunService.inferSemesterHint(
        course: fullCourse,
        targetDate: DateTime(2026, 9, 20),
      );
      expect(septHint.halfTag, equals('autumn'));
      expect(septHint.exactYearMonth, equals('2026-09'));

      // 即使处于 11 月（冬学期），查询纯秋课程也必须秋分高于冬且冬/旧课/已下架课为负分
      final scoreAutumnForAutumn = ZhiyunService.scoreSemesterMatch(
        autumnHint,
        title: '程序设计基础(秋)',
        termName: '2026-2027学年秋学期',
        activeMonths: ['2026-9', '2026-10'],
        nowForTiebreak: DateTime(2026, 11, 12),
      );
      final scoreWinterForAutumn = ZhiyunService.scoreSemesterMatch(
        autumnHint,
        title: '程序设计基础(冬)',
        termName: '2026-2027学年冬学期',
        activeMonths: ['2026-11', '2026-12'],
        nowForTiebreak: DateTime(2026, 11, 12),
      );
      final score2023ForAutumn = ZhiyunService.scoreSemesterMatch(
        autumnHint,
        title: '程序设计基础',
        termName: '2023-2024学年秋学期',
      );
      final scoreOffShelf = ZhiyunService.scoreSemesterMatch(
        autumnHint,
        title: '程序设计基础(秋)',
        termName: '2026-2027学年秋学期',
        meta: {'publish': 2, 'show': 'no'},
      );

      expect(scoreAutumnForAutumn, greaterThan(0));
      expect(scoreWinterForAutumn, lessThan(0));
      expect(score2023ForAutumn, lessThan(0));
      expect(scoreOffShelf, lessThan(0));
    });

    test('isCatalogueMismatchedWithHint 不以超过45天误杀9月秋学期课程，但拦截下架与错学期目录', () {
      final autumnCourse = makeCourse(
        id: '(2026-2027-1)-061B0010-001',
        name: '大学计算机基础',
        firstHalf: true,
        secondHalf: false,
      );
      final autumnHint = ZhiyunService.inferSemesterHint(course: autumnCourse);

      final septLessons = [
        {
          'sub_id': '101',
          'start_at':
              (DateTime(2026, 9, 15, 8, 0).millisecondsSinceEpoch ~/ 1000)
                  .toString(),
        },
        {
          'sub_id': '102',
          'start_at':
              (DateTime(2026, 9, 22, 8, 0).millisecondsSinceEpoch ~/ 1000)
                  .toString(),
        },
      ];
      // 9月课程虽距11月12日超过45天，但完全匹配2026秋，不应判定为失效
      expect(
        ZhiyunService.isCatalogueMismatchedWithHint(
          septLessons,
          autumnHint,
          meta: {'publish': '1', 'show': 'yes', 'term_name': '2026-2027学年秋学期'},
        ),
        isFalse,
      );

      // 已下架课程必须拦截
      expect(
        ZhiyunService.isCatalogueMismatchedWithHint(
          septLessons,
          autumnHint,
          meta: {'publish': '2', 'show': 'no'},
        ),
        isTrue,
      );

      // 历史学年课程目录（2023秋）与2026秋冲突，必须拦截
      final old2023Lessons = [
        {
          'sub_id': '99',
          'start_at':
              (DateTime(2023, 9, 15, 8, 0).millisecondsSinceEpoch ~/ 1000)
                  .toString(),
        },
      ];
      expect(
        ZhiyunService.isCatalogueMismatchedWithHint(old2023Lessons, autumnHint),
        isTrue,
      );
    });

    test('extractSubItemsFromResponse 从 get-my-course-day 保留各自的 course_id 防混课', () {
      final decoded = {
        'code': 0,
        'list': [
          {
            'id': '85001',
            'sub_id': '1900001',
            'title': '第1讲 面向对象',
            'start_at': '1789440000',
          },
          {
            'id': '85002',
            'sub_id': '1900002',
            'title': '其他同时段课程',
            'start_at': '1789440000',
          },
        ],
      };
      final extracted = ZhiyunService.extractSubItemsFromResponse(decoded);
      expect(extracted, hasLength(2));
      expect(extracted[0]['course_id'], equals('85001'));
      expect(extracted[0]['sub_id'], equals('1900001'));
      expect(extracted[1]['course_id'], equals('85002'));
      expect(extracted[1]['sub_id'], equals('1900002'));
    });

    test('Hive 实测：秋冬同名同老师课程同时在列时按学期/日期精确分流且最近观看互不覆盖', () async {
      final tmpDir = Directory.systemTemp.createTempSync('zhiyun_match_test_');
      Hive.init(tmpDir.path);
      final box = await Hive.openBox('dbOptions');
      addTearDown(() async {
        ZhiyunService.clearCacheSync();
        await box.close();
        await Hive.deleteFromDisk();
        if (tmpDir.existsSync()) {
          tmpDir.deleteSync(recursive: true);
        }
      });

      await box.put('zhiyun_cache_schema_v', 2);
      await box.put(
        'zhiyun_my_courses',
        jsonEncode([
          {
            'course_id': '85001',
            'course_title': '程序设计专题(秋)',
            'teacher': '李老师',
            'term_name': '2026-2027学年秋学期',
            'active_months': ['2026-09', '2026-10'],
          },
          {
            'course_id': '85002',
            'course_title': '程序设计专题(冬)',
            'teacher': '李老师',
            'term_name': '2026-2027学年冬学期',
            'active_months': ['2026-11', '2026-12'],
          },
        ]),
      );

      final autumnCourse = makeCourse(
        id: '(2026-2027-1)-CS101-A',
        name: '程序设计专题',
        teacher: '李老师',
        firstHalf: true,
        secondHalf: false,
      );
      final winterCourse = makeCourse(
        id: '(2026-2027-1)-CS101-W',
        name: '程序设计专题',
        teacher: '李老师',
        firstHalf: false,
        secondHalf: true,
      );

      expect(
        ZhiyunService.getKnownCourseId(
          autumnCourse.name,
          courseCode: autumnCourse.id,
          teacher: autumnCourse.teacher,
          course: autumnCourse,
        ),
        equals('85001'),
      );
      expect(
        ZhiyunService.getKnownCourseId(
          winterCourse.name,
          courseCode: winterCourse.id,
          teacher: winterCourse.teacher,
          course: winterCourse,
        ),
        equals('85002'),
      );

      // 无名后缀的分段课程，按 targetDate 月份也能切分
      await box.put(
        'zhiyun_my_courses',
        jsonEncode([
          {
            'course_id': '86001',
            'course_title': '高等数学',
            'teacher': '王老师',
            'active_months': ['2026-09', '2026-10'],
          },
          {
            'course_id': '86002',
            'course_title': '高等数学',
            'teacher': '王老师',
            'active_months': ['2026-11', '2026-12'],
          },
        ]),
      );
      ZhiyunService.clearCacheSync();

      final sharedCourse = makeCourse(
        id: '(2026-2027-1)-MATH101-01',
        name: '高等数学',
        teacher: '王老师',
        firstHalf: true,
        secondHalf: true,
      );
      expect(
        ZhiyunService.getKnownCourseId(
          sharedCourse.name,
          courseCode: sharedCourse.id,
          teacher: sharedCourse.teacher,
          course: sharedCourse,
          targetDate: DateTime(2026, 9, 18),
        ),
        equals('86001'),
      );
      expect(
        ZhiyunService.getKnownCourseId(
          sharedCourse.name,
          courseCode: sharedCourse.id,
          teacher: sharedCourse.teacher,
          course: sharedCourse,
          targetDate: DateTime(2026, 11, 12),
        ),
        equals('86002'),
      );

      // 验证断点播放记录按 courseCode/scopeKey 隔离不串档
      await ZhiyunService.saveLastWatchedReplay(
        courseName: '程序设计专题',
        lessonTitle: '第1讲（秋）',
        livingroomUrl:
            'https://classroom.zju.edu.cn/livingroom?course_id=85001&sub_id=1001&tenant_code=112',
        courseId: '85001',
        subId: '1001',
        courseCode: autumnCourse.id,
        scopeKey: '2026_autumn',
      );
      await ZhiyunService.saveLastWatchedReplay(
        courseName: '程序设计专题',
        lessonTitle: '第8讲（冬）',
        livingroomUrl:
            'https://classroom.zju.edu.cn/livingroom?course_id=85002&sub_id=2001&tenant_code=112',
        courseId: '85002',
        subId: '2001',
        courseCode: winterCourse.id,
        scopeKey: '2026_winter',
      );

      final lastAutumn = ZhiyunService.getLastWatchedReplay(
        courseName: '程序设计专题',
        courseCode: autumnCourse.id,
        scopeKey: '2026_autumn',
      );
      final lastWinter = ZhiyunService.getLastWatchedReplay(
        courseName: '程序设计专题',
        courseCode: winterCourse.id,
        scopeKey: '2026_winter',
      );
      expect(lastAutumn?['courseId'], equals('85001'));
      expect(lastAutumn?['lessonTitle'], equals('第1讲（秋）'));
      expect(lastWinter?['courseId'], equals('85002'));
      expect(lastWinter?['lessonTitle'], equals('第8讲（冬）'));
    });

    test('ZDBK 无选课课号课程(id/session.id 为 null)支持春夏秋冬短学期精准区分', () async {
      Course makeNullIdCourse({
        required String name,
        required bool firstHalf,
        required bool secondHalf,
      }) {
        final session = Session.fromJson({
          'id': null,
          'name': name,
          'teacher': '陈老师',
          'confirmed': true,
          'firstHalf': firstHalf,
          'secondHalf': secondHalf,
          'oddWeek': true,
          'evenWeek': true,
          'day': 2,
          'time': [3, 4],
          'location': '玉泉',
        });
        return Course.fromGrsSession(session)..id = null;
      }

      final springNull = makeNullIdCourse(
        name: '数值分析',
        firstHalf: true,
        secondHalf: false,
      );
      final summerNull = makeNullIdCourse(
        name: '数值分析',
        firstHalf: false,
        secondHalf: true,
      );

      final springHint = ZhiyunService.inferSemesterHint(
        course: springNull,
        semesterName: '2025-2026春夏',
        preferredHalfTag: 'spring',
      );
      final summerHint = ZhiyunService.inferSemesterHint(
        course: summerNull,
        semesterName: '2025-2026春夏',
        preferredHalfTag: 'summer',
      );

      expect(springHint.academicYearStart, equals(2025));
      expect(springHint.halfTag, equals('spring'));
      expect(springHint.scopeKey, equals('2025_spring'));
      expect(summerHint.academicYearStart, equals(2025));
      expect(summerHint.halfTag, equals('summer'));
      expect(summerHint.scopeKey, equals('2025_summer'));

      await ZhiyunService.saveCourseId(
        '数值分析',
        '96001',
        course: springNull,
        semesterName: '2025-2026春夏',
        preferredHalfTag: 'spring',
      );
      await ZhiyunService.saveCourseId(
        '数值分析',
        '96002',
        course: summerNull,
        semesterName: '2025-2026春夏',
        preferredHalfTag: 'summer',
      );

      expect(
        ZhiyunService.getKnownCourseId(
          '数值分析',
          course: springNull,
          semesterName: '2025-2026春夏',
          preferredHalfTag: 'spring',
        ),
        equals('96001'),
      );
      expect(
        ZhiyunService.getKnownCourseId(
          '数值分析',
          course: summerNull,
          semesterName: '2025-2026春夏',
          preferredHalfTag: 'summer',
        ),
        equals('96002'),
      );
    });

    test('跨半学期/短学期边界日期防护：单半学期标记不被11月/2月/8月课表溢出日期覆盖', () {
      final pureAutumn = makeCourse(
        id: '(2026-2027-1)-PHY101-01',
        name: '大学物理',
        firstHalf: true,
        secondHalf: false,
      );
      final autumnSpillHint = ZhiyunService.inferSemesterHint(
        course: pureAutumn,
        semesterName: '2026-2027秋冬',
        targetDate: DateTime(2026, 11, 2),
      );
      expect(autumnSpillHint.halfTag, equals('autumn'));
      expect(autumnSpillHint.scopeKey, equals('2026_autumn'));

      final pureSpring = makeCourse(
        id: '(2025-2026-2)-PHY102-01',
        name: '大学物理Ⅱ',
        firstHalf: true,
        secondHalf: false,
      );
      final springFebHint = ZhiyunService.inferSemesterHint(
        course: pureSpring,
        semesterName: '2025-2026春夏',
        targetDate: DateTime(2026, 2, 20),
      );
      expect(springFebHint.academicYearStart, equals(2025));
      expect(springFebHint.halfTag, equals('spring'));
      expect(springFebHint.scopeKey, equals('2025_spring'));

      final summerShortTerm = makeCourse(
        id: '(2025-2026-2)-PRACT101-01',
        name: '工程实践',
        firstHalf: false,
        secondHalf: true,
      );
      final summerAugHint = ZhiyunService.inferSemesterHint(
        course: summerShortTerm,
        semesterName: '2025-2026春夏',
        targetDate: DateTime(2026, 8, 5),
      );
      expect(summerAugHint.academicYearStart, equals(2025));
      expect(summerAugHint.halfTag, equals('summer'));
      expect(summerAugHint.scopeKey, equals('2025_summer'));
    });
  });
}
