enum HabitStatus {
  none,
  done,
  missed,
  other;

  /// Click order: blank -> done -> not done -> other -> blank.
  HabitStatus get next => values[(index + 1) % values.length];
}

class Habit {
  Habit(this.id, this.name, {this.description});

  final int id;
  String name;

  /// Shown on hover in place of the name; only the sleep schedule has one.
  final String? description;
}

/// The sleep schedule: the same four in every month, below the rituals.
/// Fixed here rather than edited in the app.
enum SleepItem {
  riseEarly('Rise Early', 'Awaken at 8:30 am'),
  unwind('Unwind', 'Complete daily tasks, journal, shower, brush teeth, and meditate at 9 pm'),
  screenCurfew('Screen Curfew', 'Turn off all screens at 10 pm'),
  sleepEarly('Sleep Early', 'Sleep at 11 pm');

  const SleepItem(this.label, this.description);
  final String label;
  final String description;
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
  TodoItem(this.id, this.text, {this.done = false, this.carried = 0});

  final int id;
  String text;
  bool done;

  /// How many times this item has rolled over unfinished.
  int carried;
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
