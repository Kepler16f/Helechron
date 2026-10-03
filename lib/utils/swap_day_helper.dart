/// 放假 / 调休 日期的纯函数解析工具。
///
/// `Scholar.specialDates` 目前只保存描述字符串（见 calendar_config_parser.dart），
/// 形如：
///   - `国庆放假`（单纯放假）
///   - `国庆放假·调 10 月 11 日`（放假日，课程被调到 10 月 11 日）
///   - `国庆调休·调 10 月 5 日`（调休上课日，按 10 月 5 日所在星期的课表上课）
///
/// 与 Semester 的换课逻辑一致：调休日 W 与放假日 H 对调，H 当天原本的课程
/// 被平移到 W，因此 W 使用的是 H 所在星期的课表。
/// 这里对描述字符串做防御式解析，解析失败时 [SwapDayInfo.kind] 为
/// [SwapDayKind.unknown]，调用方应展示 [SwapDayInfo.raw]。
library;

enum SwapDayKind {
  /// 放假（不上课）
  holiday,

  /// 调休（补班）
  makeUp,

  /// 无法识别的特殊日期，仅展示原始描述
  unknown,
}

class SwapDayInfo {
  final DateTime day;
  final SwapDayKind kind;
  final String raw;

  /// 对调的另一天（放假日对应调休日，调休日对应放假日）；解析不出则为 null
  final DateTime? counterpart;

  const SwapDayInfo({
    required this.day,
    required this.kind,
    required this.raw,
    this.counterpart,
  });

  static const _weekdayName = ['', '一', '二', '三', '四', '五', '六', '日'];

  static String dateText(DateTime d) => '${d.month}月${d.day}日';

  /// 调休日实际使用的课表星期（1~7），仅 [SwapDayKind.makeUp] 且解析成功时有值
  int? get timetableWeekday =>
      kind == SwapDayKind.makeUp ? counterpart?.weekday : null;

  /// 醒目的横幅标题
  String get title {
    switch (kind) {
      case SwapDayKind.makeUp:
        final w = timetableWeekday;
        if (w == null) return raw;
        return '${dateText(day)} 按周${_weekdayName[w]}课表上课';
      case SwapDayKind.holiday:
        return '${dateText(day)} 放假·不上课';
      case SwapDayKind.unknown:
        return raw;
    }
  }

  /// 补充说明（可为 null）
  String? get detail {
    final c = counterpart;
    switch (kind) {
      case SwapDayKind.makeUp:
        if (c == null) return raw;
        return '$raw（${dateText(c)} 周${_weekdayName[c.weekday]}的课程调至本日）';
      case SwapDayKind.holiday:
        if (c == null) return raw;
        return '$raw（本日课程调至 ${dateText(c)} 周${_weekdayName[c.weekday]}）';
      case SwapDayKind.unknown:
        return null;
    }
  }
}

final RegExp _swapPattern =
    RegExp(r'(放假|调休)\s*·\s*调\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日');

DateTime? _resolveCounterpart(DateTime day, int month, int dayOfMonth) {
  if (month < 1 || month > 12 || dayOfMonth < 1 || dayOfMonth > 31) {
    return null;
  }
  DateTime? best;
  Duration? bestGap;
  // 描述中不含年份，取与当天最近的那个年份（处理跨年调休）
  for (final y in [day.year - 1, day.year, day.year + 1]) {
    final c = DateTime(y, month, dayOfMonth);
    if (c.month != month) continue; // 如 2 月 30 日溢出
    final gap = c.difference(day).abs();
    if (bestGap == null || gap < bestGap) {
      best = c;
      bestGap = gap;
    }
  }
  return best;
}

/// 查询 [day] 是否为放假/调休日。[specialDates] 为空或无该日期时返回 null。
SwapDayInfo? swapDayInfoFor(DateTime day, Map<DateTime, String> specialDates) {
  if (specialDates.isEmpty) return null;
  final key = DateTime(day.year, day.month, day.day);
  final raw = specialDates[key];
  if (raw == null) return null;

  final m = _swapPattern.firstMatch(raw);
  if (m != null) {
    final kind = m.group(1) == '调休' ? SwapDayKind.makeUp : SwapDayKind.holiday;
    final counterpart = _resolveCounterpart(
      key,
      int.tryParse(m.group(2)!) ?? 0,
      int.tryParse(m.group(3)!) ?? 0,
    );
    return SwapDayInfo(
        day: key, kind: kind, raw: raw, counterpart: counterpart);
  }
  if (raw.contains('调休')) {
    return SwapDayInfo(day: key, kind: SwapDayKind.makeUp, raw: raw);
  }
  if (raw.contains('放假')) {
    return SwapDayInfo(day: key, kind: SwapDayKind.holiday, raw: raw);
  }
  return SwapDayInfo(day: key, kind: SwapDayKind.unknown, raw: raw);
}
