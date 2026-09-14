DateTime dateOnly(DateTime date, {int? hour, int? minute}) {
  return DateTime(date.year, date.month, date.day, hour ?? 0, minute ?? 0);
}

String durationToString(Duration duration) {
  String str = '';
  if (duration.inHours != 0) {
    str = '${duration.inHours} 小时';
  }
  if (duration.inMinutes % 60 != 0 || duration.inHours == 0) {
    if (str != '') str = '$str ';
    str = '$str${duration.inMinutes % 60} 分钟';
  }
  return str;
}

String toStringHumanReadable(DateTime dateTime) {
  String str =
      dateTime.toLocal().toIso8601String().replaceFirst(RegExp(r'T'), ' ');
  str = str.substring(0, str.length - 7);
  return str;
}
