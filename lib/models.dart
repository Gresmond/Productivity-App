enum HabitStatus {
  none,
  done,
  missed,
  other;

  /// Click order: blank -> done -> not done -> other -> blank.
  HabitStatus get next => values[(index + 1) % values.length];
}

class Habit {
  Habit(this.id, this.name, {this.description, this.minutes});

  final int id;
  String name;

  /// Shown on hover in place of the name: the note you wrote for a ritual.
  String? description;

  /// A sleep item's time this month, in minutes after midnight; null when
  /// none is set. Rituals have none.
  int? minutes;
}

/// The sleep schedule: the same four in every month, below the rituals.
/// The items are fixed here; their times are set month by month.
enum SleepItem {
  riseEarly('Rise Early', 8 * 60 + 30),
  unwind('Unwind', 21 * 60),
  screenCurfew('Screen Curfew', 22 * 60),
  sleepEarly('Sleep Early', 23 * 60);

  const SleepItem(this.label, this.minutes);
  final String label;

  /// The time before any month sets its own, in minutes after midnight.
  final int minutes;
}

enum TodoScope {
  today('Today'),
  week('This week'),
  month('This month');

  const TodoScope(this.label);
  final String label;

  /// Key for the period containing [day]. Weeks start on Monday.
  String period(DateTime day) => switch (this) {
        today => dateKey(day),
        week => dateKey(DateTime(day.year, day.month, day.day - (day.weekday - 1))),
        month => '${day.year}-${day.month.toString().padLeft(2, '0')}',
      };
}

class TodoItem {
  TodoItem(this.id, this.text, {required this.since, this.done = false, this.carried = 0});

  final int id;
  String text;
  bool done;

  /// The day it was added. An item still open from an earlier day, week or
  /// month shows it as "From dd/mm".
  final DateTime since;

  /// How many times this item has rolled over unfinished.
  int carried;
}

/// '24/10'.
String dayMonth(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// [text] with its first letter upper-case; the rest is left alone.
String capitaliseFirst(String text) {
  final i = text.indexOf(RegExp(r'\S'));
  if (i == -1) return text;
  return text.substring(0, i) + text[i].toUpperCase() + text.substring(i + 1);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day [now] counts towards when each day starts at [startHour] o'clock:
/// before then, it's still the day before. Works in calendar days, so a
/// clock change doesn't shift it.
DateTime dayOf(DateTime now, int startHour) =>
    DateTime(now.year, now.month, now.day - (now.hour < startHour ? 1 : 0));

/// When the day after the one [now] counts towards begins.
DateTime nextDayStart(DateTime now, int startHour) {
  final day = dayOf(now, startHour);
  return DateTime(day.year, day.month, day.day + 1, startHour);
}

/// 'Midnight', '4am'.
String hourLabel(int hour) => hour == 0 ? 'Midnight' : '${hour}am';

/// A time of day as the sleep schedule shows it: "8:30 am", "9 pm".
String clockLabel(int minutes) {
  final (h, m) = (minutes ~/ 60, minutes % 60);
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} ${h < 12 ? 'am' : 'pm'}';
}

/// A sleep item's saved time: "21:00", or a time inside a note written
/// before times were picked ("Awaken at 8:30 am"). Null when there's none.
int? parseClock(String text) {
  if (RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text) case final m?) {
    return int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }
  final m = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\b', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final hour = int.parse(m[1]!) % 12 + (m[3]!.toLowerCase() == 'p' ? 12 : 0);
  return hour * 60 + int.parse(m[2] ?? '0');
}

/// How a sleep item's time is saved: "08:30".
String clockKey(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

const weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
