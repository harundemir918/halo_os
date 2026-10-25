/// Date and time strings as the designs show them.
abstract final class HaloFormat {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String two(int n) => n.toString().padLeft(2, '0');

  /// `09` and `41`, 24-hour.
  static String hours(DateTime t) => two(t.hour);
  static String minutes(DateTime t) => two(t.minute);

  /// `10:00`
  static String clock(DateTime t) => '${hours(t)}:${minutes(t)}';

  /// `FRIDAY — 23 OCTOBER` (the Lock date line).
  static String lockDate(DateTime t) =>
      '${_weekdays[t.weekday - 1]} — ${t.day} ${_months[t.month - 1]}'
          .toUpperCase();
}
