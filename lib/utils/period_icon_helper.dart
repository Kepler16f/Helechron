import 'package:flutter/widgets.dart';

import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/model/period.dart';

/// 识别体育与身体素质类课程（按课程名及授课场地关键词匹配）。
bool isPhysicalEducationPeriod(Period period) {
  if (period.type != PeriodType.classes) return false;
  final text = '${period.summary} ${period.location}'.toLowerCase();
  const keywords = <String>[
    '体育',
    '身体素质',
    '体质',
    '体测',
    '体适能',
    '形体',
    '健美',
    '瑜伽',
    '游泳',
    '篮球',
    '足球',
    '排球',
    '羽毛球',
    '乒乓',
    '网球',
    '武术',
    '太极',
    '跆拳道',
    '空手道',
    '击剑',
    '散打',
    '田径',
    '龙舟',
    '轮滑',
    '匹克球',
    '棒垒球',
    '橄榄球',
    '高尔夫',
    '台球',
    '射箭',
    '攀岩',
    '皮划艇',
    '赛艇',
    '定向越野',
    '体育舞蹈',
    '啦啦操',
    '八段锦',
    '健身',
    '跑操',
    '操场',
    '体育馆',
    '游泳馆',
    '网球场',
    '篮球场',
    '排球场',
    '足球场',
    '羽毛球场',
    '羽毛球馆',
    '乒乓球馆',
    '健身房',
    '体操馆',
  ];
  return keywords.any(text.contains);
}

/// 统一解析日程条目装饰图标：考试 / 体育课 / 室内普通课程 / 任务 / 规划流。
IconData resolvePeriodIcon(Period period) {
  return switch (period.type) {
    PeriodType.test => AelIcons.exam,
    PeriodType.classes =>
      isPhysicalEducationPeriod(period) ? AelIcons.sport : AelIcons.book,
    PeriodType.user => AelIcons.tabTask,
    PeriodType.flow => AelIcons.tabFlow,
    PeriodType.virtual => AelIcons.sparkles,
  };
}
