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
  }

  // Habits

  bool get isEmpty => _db.select('SELECT 1 FROM habits LIMIT 1').isEmpty;

  List<Habit> monthHabits(int year, int month) => [
        for (final r in _db.select(
          'SELECT habit_id, name FROM month_habits WHERE year = ? AND month = ? ORDER BY position',
          [year, month],
        ))
          Habit(r['habit_id'] as int, r['name'] as String),
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
      'INSERT INTO month_habits (year, month, habit_id, name, position) '
      'SELECT ?, ?, habit_id, name, position FROM month_habits WHERE year = ? AND month = ?',
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
    _db.execute(
      'UPDATE month_habits SET name = ? WHERE year = ? AND month = ? AND habit_id = ?',
      [name, year, month, habitId],
    );
  }

  void removeHabit(int year, int month, int habitId) {
    _db.execute(
      'DELETE FROM month_habits WHERE year = ? AND month = ? AND habit_id = ?',
      [year, month, habitId],
    );
  }

  void reorderHabits(int year, int month, List<int> habitIds) {
    _transaction(() {
      for (final (i, id) in habitIds.indexed) {
        _db.execute(
          'UPDATE month_habits SET position = ? WHERE year = ? AND month = ? AND habit_id = ?',
          [i, year, month, id],
        );
      }
    });
  }

  // Entries

  Iterable<({String day, int habitId, HabitStatus status, String? note})> entries() =>
      _db.select('SELECT day, habit_id, status, note FROM entries').map(
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
    _db.execute(
      'UPDATE entries SET note = ? WHERE day = ? AND habit_id = ?',
      [note, day, habitId],
    );
  }

  // To-dos

  List<TodoItem> todos(TodoScope scope, String period) => [
        for (final r in _db.select(
          'SELECT id, text, done, carried FROM todos WHERE scope = ? AND period = ? ORDER BY id',
          [scope.name, period],
        ))
          TodoItem(
            r['id'] as int,
            r['text'] as String,
            done: r['done'] == 1,
            carried: r['carried'] as int,
          ),
      ];

  /// Moves unfinished to-dos from earlier periods into [period]. Returns how
  /// many moved.
  int carryForward(TodoScope scope, String period) {
    _db.execute(
      'UPDATE todos SET period = ?, carried = carried + 1 WHERE scope = ? AND done = 0 AND period < ?',
      [period, scope.name, period],
    );
    return _db.updatedRows;
  }

  TodoItem addTodo(TodoScope scope, String period, String text, {bool done = false}) {
    _db.execute(
      'INSERT INTO todos (scope, period, text, done) VALUES (?, ?, ?, ?)',
      [scope.name, period, text, done ? 1 : 0],
    );
    return TodoItem(_db.lastInsertRowId, text, done: done);
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
