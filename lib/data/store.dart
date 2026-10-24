import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../models.dart';

/// SQLite persistence. Every method writes straight through; AppState keeps
/// an in-memory copy for drawing.
class Store {
  Store._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA journal_mode = WAL');
    _migrate();
  }

  Store.open(String path) : this._(sqlite3.open(path));

  Store.memory() : this._(sqlite3.openInMemory());

  final Database _db;

  void close() => _db.close();

  /// Writes a consistent, compacted copy of the whole database to [path].
  /// Written beside it first and renamed, so a crash never leaves half a file.
  void saveCopy(String path) {
    final part = File('$path.part');
    if (part.existsSync()) part.deleteSync();
    _db.execute('VACUUM INTO ?', [part.path]);
    part.renameSync(path);
  }

  /// Replaces everything in this database with the copy at [path].
  Future<void> restoreFrom(String path) async {
    final source = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final check = source.select('PRAGMA quick_check').first.columnAt(0);
      if (check != 'ok') throw StateError('Backup is damaged: $check');
      await source.backup(_db, nPage: -1).drain<void>();
    } finally {
      source.close();
    }
    _migrate(); // the copy may be from an older version of the app
  }

  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE habits (id INTEGER PRIMARY KEY AUTOINCREMENT);

        -- Each month has its own ordered list. habit_id ties a ritual across
        -- months (for streaks); the name can differ per month.
        CREATE TABLE month_habits (
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          habit_id INTEGER NOT NULL REFERENCES habits(id),
          name TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (year, month, habit_id)
        );

        CREATE TABLE entries (
          day TEXT NOT NULL,
          habit_id INTEGER NOT NULL REFERENCES habits(id),
          status INTEGER NOT NULL,
          note TEXT,
          PRIMARY KEY (day, habit_id)
        );

        -- period: yyyy-mm-dd for today, the Monday's date for week, yyyy-mm
        -- for month. All sort chronologically as strings.
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scope TEXT NOT NULL,
          period TEXT NOT NULL,
          text TEXT NOT NULL,
          done INTEGER NOT NULL DEFAULT 0,
          carried INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX todos_scope_period ON todos (scope, period);

        CREATE TABLE journal (day TEXT PRIMARY KEY, text TEXT NOT NULL);

        PRAGMA user_version = 1;
      ''');
    }
    if (version < 2) {
      _db.execute('''
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        PRAGMA user_version = 2;
      ''');
    }
    if (version < 3) {
      _transaction(() {
        _db.execute('''
          -- The sleep schedule's habits, by SleepItem name. In every month,
          -- so not in month_habits.
          CREATE TABLE sleep_habits (
            item TEXT PRIMARY KEY,
            habit_id INTEGER NOT NULL REFERENCES habits(id)
          )
        ''');
        // Rituals the sleep schedule replaces. These three keep their
        // history and streaks; Unwind starts fresh.
        const carried = {
          SleepItem.riseEarly: 'Get up at%',
          SleepItem.screenCurfew: 'Screens, shower%',
          SleepItem.sleepEarly: 'Bed by%',
        };
        for (final item in SleepItem.values) {
          final match = carried[item] == null
              ? const <Row>[]
              : _db.select(
                  'SELECT habit_id FROM month_habits WHERE name LIKE ? ORDER BY year DESC, month DESC LIMIT 1',
                  [carried[item]],
                );
          final int id;
          if (match.isNotEmpty) {
            id = match.first['habit_id'] as int;
          } else {
            _db.execute('INSERT INTO habits DEFAULT VALUES');
            id = _db.lastInsertRowId;
          }
          _db.execute('INSERT INTO sleep_habits (item, habit_id) VALUES (?, ?)', [item.name, id]);
          _db.execute('DELETE FROM month_habits WHERE habit_id = ?', [id]);
        }
        // Unwind covers these; their marks stay in entries, unseen.
        _db.execute("DELETE FROM month_habits WHERE name LIKE 'Wind down%' OR name IN ('Journal', 'Meditate')");
        _db.execute('PRAGMA user_version = 3');
      });
    }
    if (version < 4) {
      _db.execute('''
        -- A ritual's note, shown on hover. On the habit, not the month, so it
        -- follows the ritual through every month.
        ALTER TABLE habits ADD COLUMN note TEXT;
        PRAGMA user_version = 4;
      ''');
    }
    if (version < 5) {
      _transaction(() {
        _db.execute('''
          -- Notes belong to a month, like names: a new month copies them, and
          -- an edit changes only its own month. Each month keeps the note it
          -- had.
          ALTER TABLE month_habits ADD COLUMN note TEXT;
          UPDATE month_habits SET note = (SELECT note FROM habits WHERE id = habit_id);
          ALTER TABLE habits DROP COLUMN note;
          PRAGMA user_version = 5;
        ''');
      });
    }
    if (version < 6) {
      _transaction(() {
        _db.execute('''
          -- The day a to-do was added. With period (the last day, week or
          -- month it was on) it says which lists it was on. Older items get
          -- a guess, one period back per carry.
          ALTER TABLE todos ADD COLUMN since TEXT;
          UPDATE todos SET since = CASE scope
            WHEN 'today' THEN date(period, '-' || carried || ' days')
            WHEN 'week' THEN date(period, '-' || (7 * carried) || ' days')
            ELSE date(period || '-01', '-' || carried || ' months')
          END;
          PRAGMA user_version = 6;
        ''');
      });
    }
    if (version < 7) {
      _db.execute('''
        -- Your own text for a sleep item's tooltip, from this month on until
        -- a later month has its own. Empty: show just the name.
        CREATE TABLE sleep_notes (
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          item TEXT NOT NULL,
          note TEXT NOT NULL,
          PRIMARY KEY (year, month, item)
        );
        PRAGMA user_version = 7;
      ''');
    }
  }

  // Habits

  /// No ritual has ever been added (the sleep schedule doesn't count).
  bool get isEmpty =>
      _db.select('SELECT 1 FROM habits WHERE id NOT IN (SELECT habit_id FROM sleep_habits) LIMIT 1').isEmpty;

  /// The sleep schedule as it reads in a month: each item's time is the
  /// one set for that month, or the nearest month before with its own, or
  /// the original time.
  List<Habit> sleepHabits(int year, int month) {
    final ids = {
      for (final r in _db.select('SELECT item, habit_id FROM sleep_habits')) r['item'] as String: r['habit_id'] as int,
    };
    return [
      for (final item in SleepItem.values)
        Habit(ids[item.name]!, item.label, minutes: switch (sleepNote(year, month, item)) {
          null => item.minutes,
          final note => parseClock(note),
        }),
    ];
  }

  /// The time saved for [item] in force in this month ("21:00", empty for
  /// none, or a note from before times were picked); null if never set.
  /// With [own], only what was set for this very month.
  String? sleepNote(int year, int month, SleepItem item, {bool own = false}) {
    final r = _db.select(
      'SELECT note FROM sleep_notes WHERE item = ? AND year * 12 + month ${own ? '=' : '<='} ? '
      'ORDER BY year * 12 + month DESC LIMIT 1',
      [item.name, year * 12 + month],
    );
    return r.isEmpty ? null : r.first['note'] as String;
  }

  void setSleepNote(int year, int month, SleepItem item, String note) {
    _db.execute(
      'INSERT INTO sleep_notes (year, month, item, note) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (year, month, item) DO UPDATE SET note = excluded.note',
      [year, month, item.name, note],
    );
  }

  List<Habit> monthHabits(int year, int month) => [
    for (final r in _db.select(
      'SELECT habit_id, name, note FROM month_habits WHERE year = ? AND month = ? ORDER BY position',
      [year, month],
    ))
      Habit(r['habit_id'] as int, r['name'] as String, description: r['note'] as String?),
  ];

  /// The closest month that has a ritual list, preferring earlier months.
  (int, int)? nearestMonthWithHabits(int year, int month) {
    final index = year * 12 + month;
    for (final (cmp, order) in [('<', 'DESC'), ('>', 'ASC')]) {
      final r = _db.select(
        'SELECT year, month FROM month_habits WHERE year * 12 + month $cmp ? '
        'ORDER BY year * 12 + month $order LIMIT 1',
        [index],
      );
      if (r.isNotEmpty) return (r.first['year'] as int, r.first['month'] as int);
    }
    return null;
  }

  void copyMonth((int, int) from, (int, int) to) {
    _db.execute(
      'INSERT INTO month_habits (year, month, habit_id, name, position, note) '
      'SELECT ?, ?, habit_id, name, position, note FROM month_habits WHERE year = ? AND month = ?',
      [to.$1, to.$2, from.$1, from.$2],
    );
  }

  Habit addHabit(int year, int month, String name) {
    _db.execute('INSERT INTO habits DEFAULT VALUES');
    final id = _db.lastInsertRowId;
    _db.execute(
      'INSERT INTO month_habits (year, month, habit_id, name, position) VALUES (?, ?, ?, ?, '
      '(SELECT COALESCE(MAX(position) + 1, 0) FROM month_habits WHERE year = ? AND month = ?))',
      [year, month, id, name, year, month],
    );
    return Habit(id, name);
  }

  void renameHabit(int year, int month, int habitId, String name) {
    _db.execute('UPDATE month_habits SET name = ? WHERE year = ? AND month = ? AND habit_id = ?', [
      name,
      year,
      month,
      habitId,
    ]);
  }

  void setHabitNote(int year, int month, int habitId, String? note) {
    _db.execute('UPDATE month_habits SET note = ? WHERE year = ? AND month = ? AND habit_id = ?', [
      note,
      year,
      month,
      habitId,
    ]);
  }

  void removeHabit(int year, int month, int habitId) {
    _db.execute('DELETE FROM month_habits WHERE year = ? AND month = ? AND habit_id = ?', [year, month, habitId]);
  }

  void reorderHabits(int year, int month, List<int> habitIds) {
    _transaction(() {
      for (final (i, id) in habitIds.indexed) {
        _db.execute('UPDATE month_habits SET position = ? WHERE year = ? AND month = ? AND habit_id = ?', [
          i,
          year,
          month,
          id,
        ]);
      }
    });
  }

  // Entries

  Iterable<({String day, int habitId, HabitStatus status, String? note})> entries() => _db
      .select('SELECT day, habit_id, status, note FROM entries')
      .map(
        (r) => (
          day: r['day'] as String,
          habitId: r['habit_id'] as int,
          status: HabitStatus.values[r['status'] as int],
          note: r['note'] as String?,
        ),
      );

  void setEntry(String day, int habitId, HabitStatus status) {
    if (status == HabitStatus.none) {
      _db.execute('DELETE FROM entries WHERE day = ? AND habit_id = ?', [day, habitId]);
      return;
    }
    _db.execute(
      'INSERT INTO entries (day, habit_id, status) VALUES (?, ?, ?) '
      'ON CONFLICT (day, habit_id) DO UPDATE SET status = excluded.status',
      [day, habitId, status.index],
    );
  }

  void setNote(String day, int habitId, String? note) {
    _db.execute('UPDATE entries SET note = ? WHERE day = ? AND habit_id = ?', [note, day, habitId]);
  }

  // To-dos

  List<TodoItem> todos(TodoScope scope, String period) => [
    for (final r in _db.select(
      'SELECT id, text, done, carried, since FROM todos WHERE scope = ? AND period = ? ORDER BY id',
      [scope.name, period],
    ))
      _todo(r),
  ];

  /// The list as it stood on [day]: everything added by then and still open
  /// that day. An item ticked off later shows unticked, as it was.
  List<TodoItem> todosOn(TodoScope scope, DateTime day) {
    final period = scope.period(day);
    return [
      for (final r in _db.select(
        'SELECT id, text, done, carried, since, period FROM todos WHERE scope = ? AND period >= ? ORDER BY id',
        [scope.name, period],
      ))
        if (scope.period(DateTime.parse(r['since'] as String)).compareTo(period) <= 0)
          _todo(r)..done = r['done'] == 1 && r['period'] == period,
    ];
  }

  static TodoItem _todo(Row r) => TodoItem(
    r['id'] as int,
    r['text'] as String,
    since: DateTime.parse(r['since'] as String),
    done: r['done'] == 1,
    carried: r['carried'] as int,
  );

  /// Moves unfinished to-dos from earlier periods into [period]. Returns how
  /// many moved.
  ///
  /// Also brings back any from later periods, uncounted: those were carried
  /// ahead before the clock went back (travelling west over midnight), and
  /// would otherwise vanish until the date caught up.
  int carryForward(TodoScope scope, String period) {
    _db.execute(
      'UPDATE todos SET carried = carried + (period < ?), period = ? '
      'WHERE scope = ? AND done = 0 AND period != ?',
      [period, period, scope.name, period],
    );
    return _db.updatedRows;
  }

  TodoItem addTodo(TodoScope scope, DateTime day, String text, {bool done = false}) {
    _db.execute('INSERT INTO todos (scope, period, text, done, since) VALUES (?, ?, ?, ?, ?)', [
      scope.name,
      scope.period(day),
      text,
      done ? 1 : 0,
      dateKey(day),
    ]);
    return TodoItem(_db.lastInsertRowId, text, since: day, done: done);
  }

  void setTodoDone(int id, bool done) {
    _db.execute('UPDATE todos SET done = ? WHERE id = ?', [done ? 1 : 0, id]);
  }

  void deleteTodo(int id) {
    _db.execute('DELETE FROM todos WHERE id = ?', [id]);
  }

  // Settings

  String? setting(String key) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  // Journal

  Iterable<({String day, String text})> journalEntries() => _db
      .select('SELECT day, text FROM journal ORDER BY day')
      .map((r) => (day: r['day'] as String, text: r['text'] as String));

  String journal(String day) {
    final r = _db.select('SELECT text FROM journal WHERE day = ?', [day]);
    return r.isEmpty ? '' : r.first['text'] as String;
  }

  void setJournal(String day, String text) {
    if (text.trim().isEmpty) {
      _db.execute('DELETE FROM journal WHERE day = ?', [day]);
    } else {
      _db.execute(
        'INSERT INTO journal (day, text) VALUES (?, ?) '
        'ON CONFLICT (day) DO UPDATE SET text = excluded.text',
        [day, text],
      );
    }
  }

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
