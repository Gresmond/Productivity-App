import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'store.dart';

/// What one round of merging brought in from other computers.
class Incoming {
  Incoming(this.changes, this.from, this.journalDays, [this.keptBoth = const {}]);

  /// Rows that changed here.
  final int changes;

  /// The names of the computers they came from.
  final Set<String> from;

  /// Days whose journal entry changed, to write out as files.
  final Set<String> journalDays;

  /// Days whose journal entry was written on two computers at once, so
  /// both texts were kept.
  final Set<String> keptBoth;

  bool get isEmpty => changes == 0;
}

/// Keeps rituals, ticks, to-dos and the journal the same on several
/// computers, through a folder that each of them copies to and from a
/// shared place (Eclipse's hidden folder in Google Drive).
///
/// Every field of every row is a register with a version per computer.
/// Each computer writes only its own registers, to its own folder, one
/// file per day of changes, so no file is ever written in two places.
/// Merging takes whichever edit saw the other; between two that didn't, the
/// later one wins, except for the journal, which keeps both texts.
class SyncEngine {
  SyncEngine(this.store, this.me);

  final Store store;

  /// This computer's id: the name of its folder.
  final String me;

  Database get _db => store.raw;

  int? _last;

  /// [at], or later if a register is newer, so each edit sorts after
  /// everything this computer had seen when it was made.
  int _tick([int? at]) {
    _last ??= _db.select('SELECT MAX(ts) FROM sync_reg').first.columnAt(0) as int? ?? 0;
    return _last = max(at ?? DateTime.now().millisecondsSinceEpoch, _last! + 1);
  }

  // Rows as registers

  static const _present = '_';

  /// Kinds whose rows can be removed; the others always exist, blank.
  static const _removable = {'month_habit', 'todo'};

  static (String, String) _split(String rowkey) {
    final i = rowkey.indexOf('/');
    return (rowkey.substring(0, i), rowkey.substring(i + 1));
  }

  static (int, int) _month(String key) {
    final [y, m] = key.split('-');
    return (int.parse(y), int.parse(m));
  }

  /// The row's fields as they are now, with [_present] for removable kinds.
  Map<String, Object?> _read(String kind, String rowkey) {
    Map<String, Object?>? row(String sql, List<Object?> args) {
      final r = _db.select(sql, args);
      return r.isEmpty ? null : Map.of(r.first);
    }

    final Map<String, Object?>? fields;
    switch (kind) {
      case 'month_habit':
        final (month, uid) = _split(rowkey);
        final (y, m) = _month(month);
        fields = row(
          'SELECT name, position, note FROM month_habits JOIN habits h ON h.id = habit_id '
          'WHERE year = ? AND month = ? AND h.uid = ?',
          [y, m, uid],
        );
      case 'entry':
        final (day, uid) = _split(rowkey);
        return row('SELECT status, note FROM entries JOIN habits h ON h.id = habit_id WHERE day = ? AND h.uid = ?', [
              day,
              uid,
            ]) ??
            {'status': 0, 'note': null};
      case 'todo':
        fields = row('SELECT scope, period, text, done, carried, since FROM todos WHERE uid = ?', [rowkey]);
      case 'journal':
        return {
          'text': row('SELECT text FROM journal WHERE day = ?', [rowkey])?['text'] ?? '',
        };
      case 'sleep_note':
        final (month, item) = _split(rowkey);
        final (y, m) = _month(month);
        return {
          'note': row('SELECT note FROM sleep_notes WHERE year = ? AND month = ? AND item = ?', [y, m, item])?['note'],
        };
      case 'setting':
        return {
          'value': row('SELECT value FROM settings WHERE key = ?', [rowkey])?['value'],
        };
      default:
        throw ArgumentError(kind);
    }
    return fields == null ? {_present: false} : {...fields, _present: true};
  }

  int _habit(String uid) {
    _db.execute('INSERT OR IGNORE INTO habits (uid) VALUES (?)', [uid]);
    return _db.select('SELECT id FROM habits WHERE uid = ?', [uid]).first['id'] as int;
  }

  /// Makes the row match [f], its fields from the registers.
  void _write(String kind, String rowkey, Map<String, Object?> f) {
    final gone = _removable.contains(kind) && f[_present] != true;
    switch (kind) {
      case 'month_habit':
        final (month, uid) = _split(rowkey);
        final (y, m) = _month(month);
        final id = _habit(uid);
        if (gone) {
          _db.execute('DELETE FROM month_habits WHERE year = ? AND month = ? AND habit_id = ?', [y, m, id]);
        } else {
          _db.execute(
            'INSERT INTO month_habits (year, month, habit_id, name, position, note) VALUES (?, ?, ?, ?, ?, ?) '
            'ON CONFLICT (year, month, habit_id) DO UPDATE SET name = excluded.name, position = excluded.position, '
            'note = excluded.note',
            [y, m, id, f['name'] ?? '', f['position'] ?? 0, f['note']],
          );
        }
      case 'entry':
        final (day, uid) = _split(rowkey);
        final id = _habit(uid);
        final status = f['status'] as int? ?? 0;
        if (status == 0) {
          _db.execute('DELETE FROM entries WHERE day = ? AND habit_id = ?', [day, id]);
        } else {
          _db.execute(
            'INSERT INTO entries (day, habit_id, status, note) VALUES (?, ?, ?, ?) '
            'ON CONFLICT (day, habit_id) DO UPDATE SET status = excluded.status, note = excluded.note',
            [day, id, status, f['note']],
          );
        }
      case 'todo':
        if (gone) {
          _db.execute('DELETE FROM todos WHERE uid = ?', [rowkey]);
        } else {
          _db.execute(
            'INSERT INTO todos (uid, scope, period, text, done, carried, since) VALUES (?, ?, ?, ?, ?, ?, ?) '
            'ON CONFLICT (uid) DO UPDATE SET scope = excluded.scope, period = excluded.period, text = excluded.text, '
            'done = excluded.done, carried = excluded.carried, since = excluded.since',
            [
              rowkey,
              f['scope'] ?? 'today',
              f['period'] ?? f['since'] ?? '',
              f['text'] ?? '',
              f['done'] ?? 0,
              f['carried'] ?? 0,
              f['since'] ?? f['period'] ?? '',
            ],
          );
        }
      case 'journal':
        store.setJournal(rowkey, f['text'] as String? ?? '');
      case 'sleep_note':
        final (month, item) = _split(rowkey);
        final (y, m) = _month(month);
        final note = f['note'] as String?;
        if (note == null) {
          _db.execute('DELETE FROM sleep_notes WHERE year = ? AND month = ? AND item = ?', [y, m, item]);
        } else {
          _db.execute(
            'INSERT INTO sleep_notes (year, month, item, note) VALUES (?, ?, ?, ?) '
            'ON CONFLICT (year, month, item) DO UPDATE SET note = excluded.note',
            [y, m, item, note],
          );
        }
      case 'setting':
        final value = f['value'] as String?;
        if (value == null) {
          _db.execute('DELETE FROM settings WHERE key = ?', [rowkey]);
        } else {
          store.setSetting(rowkey, value);
        }
    }
  }

  static bool _blank(Object? v) => v == null || v == false || v == 0 || v == '';

  // Registers

  _Reg? _reg(String kind, String rowkey, String field) {
    final r = _db.select('SELECT * FROM sync_reg WHERE kind = ? AND rowkey = ? AND field = ?', [kind, rowkey, field]);
    return r.isEmpty ? null : _Reg.fromRow(r.first);
  }

  void _put(_Reg r) => _db.execute('INSERT OR REPLACE INTO sync_reg VALUES (?, ?, ?, ?, ?, ?, ?)', r.row);

  /// Turns rows written here since last time into edits of this computer.
  void flush() {
    final dirty = _db.select('SELECT kind, rowkey, at FROM sync_dirty ORDER BY at');
    if (dirty.isEmpty) return;
    _transaction(() {
      for (final d in dirty) {
        final kind = d['kind'] as String, rowkey = d['rowkey'] as String;
        for (final MapEntry(key: field, value: v) in _read(kind, rowkey).entries) {
          final value = jsonEncode(v);
          final old = _reg(kind, rowkey, field);
          if (old == null ? _blank(v) : old.value == value) continue;
          final ts = _tick(d['at'] as int);
          _put(_Reg(kind, rowkey, field, value, ts, me, {...?old?.vv, me: ts}));
        }
      }
      _db.execute('DELETE FROM sync_dirty');
    });
  }

  /// Makes every row an edit of this computer: the first computer to sync.
  void claimAll() {
    store.markAllChanged();
    flush();
  }

  /// Clears this computer's rows and registers, to take another's whole
  /// history in their place. The sleep schedule's rituals stay: they're
  /// the same everywhere.
  ///
  /// Returns the journal days that were here, to remove their files.
  List<String> clearForJoining() {
    final days = [for (final r in _db.select('SELECT day FROM journal')) r['day'] as String];
    _transaction(() {
      _db.execute('DELETE FROM month_habits');
      _db.execute('DELETE FROM entries');
      _db.execute('DELETE FROM todos');
      _db.execute('DELETE FROM journal');
      _db.execute('DELETE FROM sleep_notes');
      _db.execute('DELETE FROM settings WHERE key IN (${Store.syncedSettings.map((k) => "'$k'").join(', ')})');
      _db.execute('DELETE FROM habits WHERE id NOT IN (SELECT habit_id FROM sleep_habits)');
      _db.execute('DELETE FROM sync_reg');
      _db.execute('DELETE FROM sync_seen');
      _db.execute('DELETE FROM sync_dirty');
    });
    _last = null;
    return days;
  }

  /// This computer's edits, grouped by the day (UTC) they were made, for
  /// every day with an edit after [since].
  Map<String, List<List<Object?>>> changesSince(int since) {
    final days = [
      for (final r in _db.select(
        "SELECT DISTINCT date(ts / 1000, 'unixepoch') AS d FROM sync_reg WHERE origin = ? AND ts > ?",
        [me, since],
      ))
        r['d'] as String,
    ];
    return {
      for (final day in days)
        day: [
          for (final r in _db.select(
            "SELECT * FROM sync_reg WHERE origin = ? AND date(ts / 1000, 'unixepoch') = ? ORDER BY kind, rowkey, field",
            [me, day],
          ))
            _Reg.fromRow(r).toJson(),
        ],
    };
  }

  int get latest => _db.select('SELECT MAX(ts) FROM sync_reg WHERE origin = ?', [me]).first.columnAt(0) as int? ?? 0;

  /// Merges another computer's registers in, and brings the rows they
  /// touch up to date.
  Incoming merge(Iterable<List<Object?>> incoming, String from) => mergeAll([(incoming, from)]);

  Incoming mergeAll(Iterable<(Iterable<List<Object?>>, String)> batches) {
    flush(); // so edits made here count in the comparison
    final touched = <(String, String)>{};
    final names = <String>{};
    _keptBoth.clear();
    _transaction(() {
      for (final (regs, from) in batches) {
        for (final json in regs) {
          final theirs = _Reg.fromJson(json);
          final ours = _reg(theirs.kind, theirs.rowkey, theirs.field);
          final merged = ours == null ? theirs : _resolve(ours, theirs);
          if (merged == null) continue;
          _put(merged);
          if (ours?.value != merged.value) {
            touched.add((theirs.kind, theirs.rowkey));
            names.add(from);
          }
        }
      }
      for (final (kind, rowkey) in touched) {
        final fields = {
          for (final r in _db.select('SELECT field, value FROM sync_reg WHERE kind = ? AND rowkey = ?', [kind, rowkey]))
            r['field'] as String: jsonDecode(r['value'] as String),
        };
        _write(kind, rowkey, fields);
      }
      // Writing them marked them changed; they match their registers.
      _db.execute('DELETE FROM sync_dirty');
    });
    return Incoming(
      touched.length,
      names,
      {
        for (final (kind, rowkey) in touched)
          if (kind == 'journal') rowkey,
      },
      {..._keptBoth},
    );
  }

  final _keptBoth = <String>{};

  /// What a register becomes, given another computer's copy of it; null to
  /// keep ours as it is.
  _Reg? _resolve(_Reg ours, _Reg theirs) {
    final order = _compare(ours.vv, theirs.vv);
    if (order == 0 || order == 1) return null; // ours has seen theirs
    if (order == -1) return theirs; // theirs has seen ours
    final vv = _maxVv(ours.vv, theirs.vv);
    if (ours.value == theirs.value) {
      final keep = ours.ts >= theirs.ts ? ours : theirs;
      return _Reg(ours.kind, ours.rowkey, ours.field, ours.value, keep.ts, keep.origin, vv);
    }
    if (ours.kind == 'journal' && ours.field == 'text') {
      // Neither saw the other: keep both, the earlier one first. Every
      // computer that merges the two makes the same text with the same
      // versions, so their merges count as one edit, not two more to keep
      // both of, and writing on after it replaces it.
      final (a, b) = (ours.ts, ours.origin).compareTo(theirs.ts, theirs.origin) <= 0 ? (ours, theirs) : (theirs, ours);
      final ta = jsonDecode(a.value) as String, tb = jsonDecode(b.value) as String;
      final text = ta.trim().isEmpty
          ? tb
          : tb.trim().isEmpty
          ? ta
          : '$ta\n\n---\n\n$tb';
      if (ta.trim().isNotEmpty && tb.trim().isNotEmpty) _keptBoth.add(ours.rowkey);
      // Sent on from here as this computer's, for any that haven't merged
      // it yet.
      return _Reg(ours.kind, ours.rowkey, ours.field, jsonEncode(text), _tick(), me, vv);
    }
    final win = (ours.ts, ours.origin).compareTo(theirs.ts, theirs.origin) >= 0 ? ours : theirs;
    return _Reg(ours.kind, ours.rowkey, ours.field, win.value, win.ts, win.origin, vv);
  }

  /// 0 when equal, 1 when [a] has seen all of [b], -1 when [b] has seen all
  /// of [a], 2 when neither.
  static int _compare(Map<String, int> a, Map<String, int> b) {
    var aAhead = false, bAhead = false;
    for (final k in {...a.keys, ...b.keys}) {
      final x = a[k] ?? 0, y = b[k] ?? 0;
      if (x > y) aAhead = true;
      if (y > x) bAhead = true;
    }
    return aAhead && bAhead
        ? 2
        : aAhead
        ? 1
        : bAhead
        ? -1
        : 0;
  }

  static Map<String, int> _maxVv(Map<String, int> a, Map<String, int> b) => {
    for (final k in {...a.keys, ...b.keys}) k: max(a[k] ?? 0, b[k] ?? 0),
  };

  void _transaction(void Function() body) {
    _db.execute('SAVEPOINT sync');
    try {
      body();
      _db.execute('RELEASE sync');
    } catch (_) {
      _db.execute('ROLLBACK TO sync');
      _db.execute('RELEASE sync');
      rethrow;
    }
  }
}

extension on (int, String) {
  int compareTo(int ts, String origin) => $1 != ts ? $1.compareTo(ts) : $2.compareTo(origin);
}

class _Reg {
  _Reg(this.kind, this.rowkey, this.field, this.value, this.ts, this.origin, this.vv);

  factory _Reg.fromRow(Row r) => _Reg(
    r['kind'] as String,
    r['rowkey'] as String,
    r['field'] as String,
    r['value'] as String,
    r['ts'] as int,
    r['origin'] as String,
    (jsonDecode(r['vv'] as String) as Map).cast<String, int>(),
  );

  factory _Reg.fromJson(List<Object?> j) => _Reg(
    j[0] as String,
    j[1] as String,
    j[2] as String,
    j[3] as String,
    j[4] as int,
    j[5] as String,
    (j[6] as Map).cast<String, int>(),
  );

  final String kind, rowkey, field, value, origin;
  final int ts;
  final Map<String, int> vv;

  List<Object?> get row => [kind, rowkey, field, value, ts, origin, jsonEncode(vv)];

  List<Object?> toJson() => [kind, rowkey, field, value, ts, origin, vv];
}

/// A sync folder on disk: this computer's change files, written here, and
/// copies of the others', brought down by [Remote].
///
/// `<folder>/<computer id>/2026-10-24.json`
class SyncFolder {
  SyncFolder(this.dir, this.me, this.name);

  final Directory dir;
  final String me;

  /// This computer's name, shown on the others.
  final String name;

  Directory get mine => Directory(p.join(dir.path, me));

  /// Writes this computer's edits since [since], a file per day. Returns
  /// whether anything was written.
  bool write(SyncEngine engine, int since) {
    final days = engine.changesSince(since);
    for (final MapEntry(key: day, value: regs) in days.entries) {
      final file = File(p.join(mine.path, '$day.json'));
      file.parent.createSync(recursive: true);
      final part = File('${file.path}.part');
      part.writeAsStringSync(jsonEncode({'version': 1, 'name': name, 'registers': regs}), flush: true);
      part.renameSync(file.path);
    }
    return days.isNotEmpty;
  }

  /// Whether another computer has left any changes here.
  bool get hasOthers => _others().isNotEmpty;

  List<File> _others() {
    if (!dir.existsSync()) return [];
    return [
      for (final d in dir.listSync().whereType<Directory>())
        if (p.basename(d.path) != me)
          for (final f in d.listSync().whereType<File>())
            if (f.path.endsWith('.json')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Merges every other computer's file that's new or changed since it was
  /// last read.
  Incoming read(SyncEngine engine) {
    final db = engine.store.raw;
    final batches = <(Iterable<List<Object?>>, String)>[];
    final stamps = <String, String>{};
    for (final f in _others()) {
      final key = p.relative(f.path, from: dir.path);
      final stat = f.statSync();
      final stamp = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
      final seen = db.select('SELECT stamp FROM sync_seen WHERE file = ?', [key]);
      if (seen.isNotEmpty && seen.first['stamp'] == stamp) continue;
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        batches.add(((json['registers'] as List).cast<List<Object?>>(), json['name'] as String? ?? 'another computer'));
        stamps[key] = stamp;
      } on FormatException {
        continue; // half copied: next time
      }
    }
    final incoming = engine.mergeAll(batches);
    for (final MapEntry(:key, :value) in stamps.entries) {
      db.execute('INSERT OR REPLACE INTO sync_seen VALUES (?, ?)', [key, value]);
    }
    return incoming;
  }
}
