import 'package:flutter/widgets.dart';

import 'data/backups.dart';
import 'data/journal_files.dart';
import 'data/store.dart';
import 'models.dart';
import 'theme/app_theme.dart';

/// App state backed by [Store]. Keeps habit entries and the current to-do
/// lists in memory and writes every change straight to SQLite.
class AppState extends ChangeNotifier {
  AppState(this.store, {this.backups, this.journalFiles, DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    today = dayOf(_clock(), dayStartHour);
    lateNight = dateOnly(_clock()) != today;
    viewYear = today.year;
    if (store.isEmpty) _seed();
    _backUp();
    _exportJournal();
    _load();
  }

  final Store store;

  /// Null where nothing should be written to disk (tests).
  final Backups? backups;

  /// Where the journal lives as documents; null keeps it in the database
  /// only (tests).
  final JournalFiles? journalFiles;
  final DateTime Function() _clock;

  /// The day ticks, to-dos and the journal count towards: the calendar
  /// date, except before [dayStartHour], when it's still the day before.
  late DateTime today;

  /// Past midnight but before [dayStartHour], so [today] is yesterday's date.
  late bool lateNight;

  /// The hour a new day starts: 0 for midnight, up to 6 for night owls.
  late int dayStartHour = int.tryParse(store.setting('dayStartHour') ?? '') ?? 0;

  void setDayStartHour(int hour) {
    dayStartHour = hour;
    store.setSetting('dayStartHour', '$hour');
    checkDate();
    notifyListeners();
  }

  late int viewYear;

  /// 1-12 when a month tab is open, null for the Today view.
  int? viewMonth;

  /// Name of the chosen colour theme; null until one is picked.
  late String? themeName = _savedTheme();
  late final ValueNotifier<String?> themeNotifier = ValueNotifier(themeName);

  /// Brings saved names up to date: version 2 paired the themes light and
  /// dark (the old Sunset was light and is now Sunrise), version 3 dropped
  /// Citrus, version 4 named the Pastels Morning and Evening. Runs once per
  /// database (a restored backup may need it again).
  String? _savedTheme() {
    final saved = store.setting('theme');
    final version = int.tryParse(store.setting('themeNames') ?? '') ?? 1;
    if (saved == null || version >= _themeNames) return saved;
    var name = version >= 2
        ? saved
        : switch (saved) {
            'Main' => 'Solar Eclipse',
            'Dark' || 'Eclipse' => 'Lunar Eclipse',
            'Soft Pastel' => 'Pastel',
            'Sage & Sunset' => 'Citrus',
            'Sunset' => 'Sunrise',
            final name => name,
          };
    name = switch (name) {
      'Citrus' => 'Solar Eclipse',
      'Dark Citrus' => 'Lunar Eclipse',
      'Pastel' => 'Morning Pastel',
      'Dark Pastel' => 'Evening Pastel',
      final name => name,
    };
    store.setSetting('theme', name);
    store.setSetting('themeNames', '$_themeNames');
    return name;
  }

  static const _themeNames = 4;

  void setTheme(String name) {
    themeName = name;
    themeNotifier.value = name;
    store.setSetting('theme', name);
    store.setSetting('themeNames', '$_themeNames');
    notifyListeners();
  }

  /// True where night light can be read (a Hyprland session); the menu
  /// hides the switch otherwise.
  bool nightLightAvailable = false;

  /// Switch to the dark partner when night light comes on, and back when it
  /// goes off. A theme picked in between holds until the next change.
  late bool followNightLight = store.setting('followNightLight') != '0';

  /// Night light as last seen, kept across restarts so a change while the
  /// app was closed still switches, but a restart alone doesn't.
  late bool? _nightLight = switch (store.setting('nightLight')) { '1' => true, '0' => false, _ => null };

  void setFollowNightLight(bool follow) {
    followNightLight = follow;
    store.setSetting('followNightLight', follow ? '1' : '0');
    if (follow && _nightLight != null) _matchNightLight(_nightLight!);
    notifyListeners();
  }

  /// Call with each reading of night light.
  void nightLightIs(bool on) {
    if (on == _nightLight) return;
    _nightLight = on;
    store.setSetting('nightLight', on ? '1' : '0');
    if (followNightLight) _matchNightLight(on);
  }

  void _matchNightLight(bool on) {
    final name = partnerOf(themeName, dark: on).name;
    if (name != themeName) setTheme(name);
  }

  /// Weekends shown greyed as rest days. A blank rest day doesn't break a
  /// streak; a ritual done on one still counts.
  late bool restWeekends = store.setting('restWeekends') == '1';

  void setRestWeekends(bool rest) {
    restWeekends = rest;
    store.setSetting('restWeekends', rest ? '1' : '0');
    _streaks.clear();
    notifyListeners();
  }

  bool isRestDay(DateTime day) => restWeekends && day.weekday >= DateTime.saturday;

  final Map<(int, int), List<Habit>> _monthHabits = {};
  final Map<String, HabitStatus> _status = {};
  final Map<String, String> _notes = {};
  final Map<TodoScope, List<TodoItem>> todos = {};

  /// (current, best) streak by ritual id, until a mark or the day changes.
  final Map<int, (int, int)> _streaks = {};

  String _cell(DateTime day, Habit h) => '${dateKey(day)}|${h.id}';

  /// Call periodically: when the date has changed, carries unfinished to-dos
  /// into the new day/week/month.
  void checkDate() {
    final clock = _clock();
    final now = dayOf(clock, dayStartHour);
    final late = dateOnly(clock) != now;
    if (now == today) {
      if (late != lateNight) {
        lateNight = late;
        notifyListeners();
      }
      return;
    }
    lateNight = late;
    if (viewYear == today.year) viewYear = now.year;
    today = now;
    _streaks.clear();
    _backUp();
    _startDay();
    notifyListeners();
  }

  /// Today's copy, taken before anything changes today. A failed backup
  /// must never stop the app opening.
  void _backUp() {
    try {
      backups?.daily(store, today);
    } catch (e) {
      debugPrint('Backup failed: $e');
    }
  }

  /// Reads everything from the store into memory.
  void _load() {
    _monthHabits.clear();
    _status.clear();
    _notes.clear();
    for (final e in store.entries()) {
      final key = '${e.day}|${e.habitId}';
      _status[key] = e.status;
      if (e.note != null) _notes[key] = e.note!;
    }
    themeName = _savedTheme();
    themeNotifier.value = themeName;
    restWeekends = store.setting('restWeekends') == '1';
    followNightLight = store.setting('followNightLight') != '0';
    dayStartHour = int.tryParse(store.setting('dayStartHour') ?? '') ?? 0;
    sleepHabits = store.sleepHabits();
    _streaks.clear();
    _startDay();
  }

  /// Bumped by each restore, so widgets holding their own copy of data
  /// (the journal's text field) start afresh.
  int restores = 0;

  /// Replaces all data with [backup]. What was there before is kept as a
  /// backup of its own.
  Future<void> restore(Backup backup) async {
    await backups!.restore(store, backup);
    restores++;
    _load();
    checkDate(); // the backup may start its days at another hour
    notifyListeners();
  }

  void _startDay() {
    for (final scope in TodoScope.values) {
      final period = scope.period(today);
      store.carryForward(scope, period);
      todos[scope] = store.todos(scope, period);
    }
    habitsFor(today.year, today.month);
  }

  // Navigation

  void showToday() {
    viewMonth = null;
    viewYear = today.year;
    notifyListeners();
  }

  void showMonth(int month) {
    viewMonth = month;
    notifyListeners();
  }

  void shiftYear(int delta) {
    viewYear += delta;
    viewMonth ??= today.month;
    notifyListeners();
  }

  // Ritual lists

  bool isFutureMonth(int year, int month) =>
      year * 12 + month > today.year * 12 + today.month;

  /// Today's month's rituals.
  List<Habit> get habits => habitsFor(today.year, today.month);

  /// The sleep schedule, the same in every month.
  late List<Habit> sleepHabits = store.sleepHabits();

  /// A month's ritual list. A month between your first list and today is
  /// saved as a copy of the month before it. Future months, and months
  /// before your first list, are previews: nothing is saved until a ritual
  /// there is ticked or edited.
  List<Habit> habitsFor(int year, int month) {
    final cached = _monthHabits[(year, month)];
    if (cached != null) return cached;

    final source = store.monthHabits(year, month).isNotEmpty
        ? (year, month)
        : store.nearestMonthWithHabits(year, month);
    if (source == null) return const [];
    final beforeFirst = source.$1 * 12 + source.$2 > year * 12 + month;
    if (source != (year, month) && (beforeFirst || isFutureMonth(year, month))) {
      return store.monthHabits(source.$1, source.$2);
    }
    return _savedList(year, month);
  }

  /// Whether [habitsFor] is showing an unsaved copy for this month.
  bool isPreviewMonth(int year, int month) =>
      habitsFor(year, month).isNotEmpty && !_monthHabits.containsKey((year, month));

  /// The month's saved list, copying the nearest month first if needed.
  List<Habit> _savedList(int year, int month) {
    final cached = _monthHabits[(year, month)];
    if (cached != null) return cached;
    if (store.monthHabits(year, month).isEmpty) {
      final source = store.nearestMonthWithHabits(year, month);
      if (source != null) store.copyMonth(source, (year, month));
    }
    return _monthHabits[(year, month)] = store.monthHabits(year, month);
  }

  // Edits take the habit's id, because [h] may come from a preview list.

  void addHabit(int year, int month, String name) {
    if (name.trim().isEmpty) return;
    _savedList(year, month).add(store.addHabit(year, month, name.trim()));
    notifyListeners();
  }

  void renameHabit(int year, int month, Habit h, String name) {
    if (name.trim().isEmpty) return;
    final saved = _savedList(year, month).firstWhere((x) => x.id == h.id);
    saved.name = name.trim();
    store.renameHabit(year, month, h.id, saved.name);
    notifyListeners();
  }

  /// This month's note on the ritual; blank removes it.
  void setHabitNote(int year, int month, Habit h, String note) {
    final saved = _savedList(year, month).firstWhere((x) => x.id == h.id);
    saved.description = note.trim().isEmpty ? null : note.trim();
    store.setHabitNote(year, month, h.id, saved.description);
    notifyListeners();
  }

  void removeHabit(int year, int month, Habit h) {
    _savedList(year, month).removeWhere((x) => x.id == h.id);
    store.removeHabit(year, month, h.id);
    notifyListeners();
  }

  void reorderHabit(int year, int month, int from, int to) {
    final list = _savedList(year, month);
    list.insert(to, list.removeAt(from));
    store.reorderHabits(year, month, [for (final h in list) h.id]);
    notifyListeners();
  }

  // Entries

  HabitStatus statusOf(DateTime day, Habit h) =>
      _status[_cell(day, h)] ?? HabitStatus.none;

  String? noteOf(DateTime day, Habit h) => _notes[_cell(day, h)];

  HabitStatus cycle(DateTime day, Habit h) {
    _savedList(day.year, day.month); // ticking a preview month saves its list
    final next = statusOf(day, h).next;
    final key = _cell(day, h);
    if (next == HabitStatus.none) {
      _status.remove(key);
      _notes.remove(key);
    } else {
      _status[key] = next;
    }
    _streaks.remove(h.id);
    store.setEntry(dateKey(day), h.id, next);
    notifyListeners();
    return next;
  }

  /// Back to blank, whatever the mark was.
  void clear(DateTime day, Habit h) {
    final key = _cell(day, h);
    if (_status.remove(key) == null) return;
    _notes.remove(key);
    _streaks.remove(h.id);
    store.setEntry(dateKey(day), h.id, HabitStatus.none);
    notifyListeners();
  }

  void setNote(DateTime day, Habit h, String note) {
    final key = _cell(day, h);
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      _notes.remove(key);
    } else {
      _notes[key] = trimmed;
    }
    store.setNote(dateKey(day), h.id, trimmed.isEmpty ? null : trimmed);
    notifyListeners();
  }

  int doneOn(DateTime day, List<Habit> habits) =>
      habits.where((h) => statusOf(day, h) == HabitStatus.done).length;

  /// Consecutive done days ending today (or yesterday, if today is still
  /// open). An "other" day, or a blank rest day, is excused: it neither
  /// breaks nor extends a streak.
  int currentStreak(Habit h) => _streaksOf(h).$1;

  int bestStreak(Habit h) => _streaksOf(h).$2;

  bool _excused(DateTime day, HabitStatus s) =>
      s == HabitStatus.other || (s == HabitStatus.none && isRestDay(day));

  (int, int) _streaksOf(Habit h) => _streaks[h.id] ??= (_current(h), _best(h));

  int _current(Habit h) {
    // Steps by calendar day, not 24 hours: a day with a clock change is 23
    // or 25 hours long.
    var day = today;
    if (statusOf(day, h) != HabitStatus.done) day = DateTime(day.year, day.month, day.day - 1);
    var streak = 0;
    for (var i = 0; i < 365; i++) {
      final s = statusOf(day, h);
      if (s == HabitStatus.done) {
        streak++;
      } else if (!_excused(day, s)) {
        break;
      }
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  int _best(Habit h) {
    var best = 0, run = 0;
    var day = DateTime(today.year - 1, 1, 1);
    while (!day.isAfter(today)) {
      final s = statusOf(day, h);
      if (s == HabitStatus.done) {
        run++;
        if (run > best) best = run;
      } else if (!_excused(day, s)) {
        run = 0;
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return best;
  }

  // To-dos

  void addTodo(TodoScope scope, String text) {
    if (text.trim().isEmpty) return;
    todos[scope]!.add(store.addTodo(scope, scope.period(today), text.trim()));
    notifyListeners();
  }

  void toggleTodo(TodoItem item) {
    item.done = !item.done;
    store.setTodoDone(item.id, item.done);
    notifyListeners();
  }

  void removeTodo(TodoScope scope, TodoItem item) {
    todos[scope]!.remove(item);
    store.deleteTodo(item.id);
    notifyListeners();
  }

  // Journal

  String journalOf(DateTime day) => journalFiles?.read(day) ?? store.journal(dateKey(day));

  void setJournal(DateTime day, String text) {
    store.setJournal(dateKey(day), text);
    try {
      journalFiles?.write(day, text);
    } catch (e) {
      // The database still has it, and the next keystroke tries again.
      debugPrint('Saving journal file failed: $e');
    }
  }

  /// Once: writes entries from before the journal moved to documents out as
  /// files. Never overwrites a file, and never runs again, so deleting a
  /// file in the folder doesn't bring it back.
  void _exportJournal() {
    final files = journalFiles;
    if (files == null || store.setting('journalExported') != null) return;
    try {
      for (final e in store.journalEntries()) {
        final day = DateTime.parse(e.day);
        if (!files.has(day)) files.write(day, e.text);
      }
      store.setSetting('journalExported', '1');
    } catch (e) {
      debugPrint('Exporting journal failed: $e');
    }
  }

  /// First run: the ritual list (the sleep schedule is made with the database), 1 October and the to-dos from the spreadsheet.
  void _seed() {
    const names = [
      'Clean room',
      'No phone until breakfast',
      'Morning walk',
      'Brush teeth',
      'Check calendar and alarms',
      'Weights',
      'Creatine, min + fin, vit. D, protein powder',
      'Read',
    ];
    const oct1 = [1, 0, 0, 1, 1, 0, 0, 0];
    for (final (i, name) in names.indexed) {
      final h = store.addHabit(2026, 10, name);
      store.setEntry('2026-10-01', h.id, oct1[i] == 1 ? HabitStatus.done : HabitStatus.missed);
    }

    const sheetTodos = {
      'Chloe money back and forth': true,
      'Update spending tracker': true,
      'Find all sunglasses': true,
      'Change PC password': true,
      'Transfer journals': true,
      'Clean inside of car': true,
      'Dust room': false,
      'Vacuum and mop bedroom floor': false,
      'Work out how to use Google Drive on Linux': true,
      'Delete screenshots from Google Photos and all local copies': true,
    };
    final period = TodoScope.today.period(today);
    sheetTodos.forEach((text, done) => store.addTodo(TodoScope.today, period, text, done: done));
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
