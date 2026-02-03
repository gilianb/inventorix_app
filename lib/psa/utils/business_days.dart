// lib/psa/utils/business_days.dart

bool _isBusinessDay(DateTime d) {
  final wd = d.weekday; // 1=Mon ... 7=Sun
  return wd != DateTime.saturday && wd != DateTime.sunday;
}

/// Elapsed business days after `start` up to `end`.
/// - If start == end => 0
/// - If start=Mon and end=Tue => 1
int businessDaysElapsed(DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);

  if (e.isBefore(s)) return 0;

  int count = 0;
  var cur = s.add(const Duration(days: 1));
  while (!cur.isAfter(e)) {
    if (_isBusinessDay(cur)) count++;
    cur = cur.add(const Duration(days: 1));
  }
  return count;
}

DateTime addBusinessDays(DateTime start, int businessDays) {
  var d = DateTime(start.year, start.month, start.day);
  int added = 0;
  while (added < businessDays) {
    d = d.add(const Duration(days: 1));
    if (_isBusinessDay(d)) added++;
  }
  return d;
}
