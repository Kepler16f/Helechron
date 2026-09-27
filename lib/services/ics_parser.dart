/// iCal (.ics) 文件解析：把 VEVENT / VTODO 条目解析为可导入的日程数据。
///
/// 遵循 RFC 5545 的行折叠（CRLF 后跟空格/HTAB 为续行）与转义规则；
/// 只做单文件静态解析，不支持展开 RRULE 重复规则（重复事件按单次导入）。
/// 时区参数（TZID）按本地时间解释——现实场景基本只有 Asia/Shanghai；
/// 以 Z 结尾的 UTC 时间转本地时间。
library;

class IcsEntry {
  IcsEntry({
    required this.uid,
    required this.summary,
    required this.description,
    required this.location,
    required this.isTodo,
    this.start,
    this.end,
  });

  final String uid;
  final String summary;
  final String description;
  final String location;

  /// VEVENT: DTSTART；VTODO: DTSTART（可空）
  final DateTime? start;

  /// VEVENT: DTEND；VTODO: DUE
  final DateTime? end;

  /// true = VTODO（映射为 DDL 任务），false = VEVENT（映射为固定日程）
  final bool isTodo;
}

class IcsParser {
  static final RegExp _dateTimePattern =
      RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$');

  /// 解析 iCal 文本，返回全部 VEVENT / VTODO 条目。
  /// 结构非法的条目直接跳过，不影响其它条目。
  static List<IcsEntry> parse(String content) {
    final entries = <IcsEntry>[];
    var depth = <String>[];
    final props = <String, String>{};

    void flushEntry() {
      if (props.isEmpty) return;
      final isTodo = depth.isNotEmpty && depth.last == 'VTODO';
      final entry = IcsEntry(
        uid: _unescape(props['UID'] ?? ''),
        summary: _unescape(props['SUMMARY'] ?? ''),
        description: _unescape(props['DESCRIPTION'] ?? ''),
        location: _unescape(props['LOCATION'] ?? ''),
        isTodo: isTodo,
        start: _parseIcsDateTime(props['DTSTART']),
        end: isTodo
            ? _parseIcsDateTime(props['DUE'])
            : _parseIcsDateTime(props['DTEND']),
      );
      // 至少要有时间信息才可导入
      if (entry.start != null || entry.end != null) {
        entries.add(entry);
      }
      props.clear();
    }

    for (final rawLine in _unfoldLines(content)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final name = _propertyName(line).toUpperCase();

      if (name == 'BEGIN') {
        final value = _propertyValue(line).toUpperCase();
        // VEVENT/VTODO 内嵌的 VALARM 等组件：进入子组件后暂停收集，
        // 子组件的属性（如 VALARM 的 TRIGGER）不会误当作主条目属性
        if (value == 'VEVENT' || value == 'VTODO') {
          flushEntry();
          depth.add(value);
        } else if (depth.isNotEmpty) {
          depth.add(value);
        }
        continue;
      }
      if (name == 'END') {
        final value = _propertyValue(line).toUpperCase();
        if (value == 'VEVENT' || value == 'VTODO') {
          flushEntry();
          final index = depth.lastIndexOf(value);
          if (index >= 0) {
            depth.removeRange(index, depth.length);
          } else {
            depth.clear();
          }
        } else if (depth.isNotEmpty) {
          depth.removeLast();
        }
        continue;
      }
      // 只收集顶层 VEVENT/VTODO 组件自身的属性
      if (depth.length == 1) {
        final value = _propertyValue(line);
        if (value.isNotEmpty || name == 'DESCRIPTION') {
          props[name] = value;
        }
      }
    }
    flushEntry();
    return entries;
  }

  /// 处理 RFC 5545 行折叠：以空格/HTAB 开头的行是上一行的续行。
  static List<String> _unfoldLines(String content) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = <String>[];
    for (final line in normalized.split('\n')) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] = lines.last + line.substring(1);
      } else {
        lines.add(line);
      }
    }
    return lines;
  }

  /// 把 `NAME;PARAM=VALUE;...:文本` 拆成名称部分。带引号的参数值里
  /// 可能包含冒号，因此扫描时跳过引号内的冒号。
  static String _propertyName(String line) {
    final colon = _splitColon(line);
    final head = colon < 0 ? line : line.substring(0, colon);
    final semi = head.indexOf(';');
    return semi < 0 ? head : head.substring(0, semi);
  }

  static String _propertyValue(String line) {
    final colon = _splitColon(line);
    return colon < 0 ? '' : line.substring(colon + 1);
  }

  static int _splitColon(String line) {
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuote = !inQuote;
      } else if (ch == ':' && !inQuote) {
        return i;
      }
    }
    return -1;
  }

  /// 解析 DTSTART/DTEND/DUE 的值；解析失败返回 null。
  /// 支持 DATE-TIME（floating / UTC）与 VALUE=DATE（全天）两种形式。
  static DateTime? _parseIcsDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = _dateTimePattern.firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (match.group(4) == null) {
      return DateTime(year, month, day);
    }
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final isUtc = (match.group(7) ?? '') == 'Z';
    final dateTime = isUtc
        ? DateTime.utc(year, month, day, hour, minute, second)
        : DateTime(year, month, day, hour, minute, second);
    return isUtc ? dateTime.toLocal() : dateTime;
  }

  /// 反转义文本属性（\n、\,、\;、\\）。
  static String _unescape(String raw) {
    if (!raw.contains('\\')) return raw;
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '\\' && i + 1 < raw.length) {
        final next = raw[i + 1];
        if (next == 'n' || next == 'N') {
          buffer.write('\n');
        } else {
          buffer.write(next);
        }
        i++;
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }
}
