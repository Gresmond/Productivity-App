import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:eclipse/app_state.dart';
import 'package:eclipse/data/backups.dart';
import 'package:eclipse/data/journal_files.dart';
import 'package:eclipse/data/night_light.dart';
import 'package:eclipse/data/store.dart';
import 'package:eclipse/data/updates.dart';
import 'package:eclipse/main.dart';
import 'package:eclipse/models.dart';
import 'package:eclipse/theme/app_theme.dart';
import 'package:eclipse/theme/oklch.dart';
import 'package:eclipse/widgets/status_cell.dart';

/// Pass --dart-define=SCREENSHOT_DIR=/some/dir to save PNGs of each view.
const _shotDir = String.fromEnvironment('SCREENSHOT_DIR');

var _fontsLoaded = false;

/// Loads every font registered in pubspec.yaml (tests otherwise render
/// placeholder boxes). Fonts stay registered for the rest of the file.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  if (_shotDir.isEmpty) return;
  // The root layer, so popups and dialogs in the overlay are included.
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  group('persistence', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('productivity_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('habits, notes, to-dos and journal survive a reopen', () {
      final path = '${dir.path}/test.db';
      final day = DateTime(2026, 10, 23);

      var store = Store.open(path);
      var state = AppState(store, clock: () => day);
      final meditate = state.habits.firstWhere((h) => h.name == 'Read');
      state.cycle(day, meditate); // done
      state.cycle(day, meditate); // not done
      state.cycle(day, meditate); // other
      state.setNote(day, meditate, 'Sick');
      state.addTodo(TodoScope.week, 'Book dentist');
      state.setJournal(day, 'A good day.');
      state.setTheme('Sunset');
      store.close();

      store = Store.open(path);
      state = AppState(store, clock: () => day);
      final again = state.habits.firstWhere((h) => h.name == 'Read');
      expect(state.habits, hasLength(8), reason: 'seed runs only once');
      expect(state.sleepHabits.map((h) => h.name), ['Rise Early', 'Unwind', 'Screen Curfew', 'Sleep Early']);
      expect(state.statusOf(day, again), HabitStatus.other);
      expect(state.noteOf(day, again), 'Sick');
      expect(state.statusOf(DateTime(2026, 10, 1), state.habits[1]), HabitStatus.missed);
      expect(state.todos[TodoScope.week]!.map((t) => t.text), ['Book dentist']);
      expect(state.journalOf(day), 'A good day.');
      expect(state.themeName, 'Sunset');
      store.close();
    });
  });

  group('themes', () {
    test('old theme names move to the new ones once', () {
      for (final (old, now) in [
        ('Main', 'Solar Eclipse'),
        ('Dark', 'Lunar Eclipse'),
        ('Eclipse', 'Lunar Eclipse'),
        ('Soft Pastel', 'Morning Pastel'),
        ('Sage & Sunset', 'Solar Eclipse'),
        ('Sunset', 'Sunrise'),
        ('Citrus', 'Solar Eclipse'),
        ('Pastel', 'Morning Pastel'),
      ]) {
        final store = Store.memory()..setSetting('theme', old);
        expect(AppState(store).themeName, now, reason: old);
        // The new dark Sunset is kept once the names are current.
        store.setSetting('theme', 'Sunset');
        expect(AppState(store).themeName, 'Sunset');
        store.close();
      }
    });

    test('every theme has a partner of the other brightness', () {
      expect(palettes.map((p) => p.name), [
        'Solar Eclipse', 'Lunar Eclipse', 'Morning Pastel', 'Evening Pastel',
        'Sunrise', 'Sunset',
      ]);
      for (final p in palettes) {
        expect(partnerOf(p.name, dark: true).brightness, Brightness.dark);
        expect(partnerOf(p.name, dark: false).brightness, Brightness.light);
      }
      expect(partnerOf('Sunrise', dark: true).name, 'Sunset');
      expect(partnerOf('Evening Pastel', dark: false).name, 'Morning Pastel');
    });

    test('OKLCH round-trips, and keeps out-of-gamut colours in sRGB', () {
      for (final c in [const Color(0xFF3B66F5), const Color(0xFFE85372), const Color(0xFF808080)]) {
        final back = Oklch.of(c).toColor();
        expect(deltaE(c, back), lessThan(1e-4));
      }
      final clipped = Oklch.of(const Oklch(0.7, 0.4, 145).toColor());
      expect(clipped.l, closeTo(0.7, 0.002), reason: 'lightness is kept, chroma gives way');
      expect(clipped.h, closeTo(145, 2));
    });

    test('every theme meets the contrast and colour-blind checks', () {
      for (final p in palettes) {
        final statuses = [p.done, p.missed, p.other];
        expect(contrast(p.ink, p.tile), greaterThanOrEqualTo(7), reason: '${p.name} text');
        expect(contrast(p.inkMuted, p.tile), greaterThanOrEqualTo(4.5), reason: '${p.name} muted text');
        expect(contrast(p.accent, p.tile), greaterThanOrEqualTo(4.5), reason: '${p.name} accent text');
        expect(contrast(p.onToday, p.today), greaterThanOrEqualTo(4.5), reason: "${p.name} today's number");
        for (final c in statuses) {
          expect(contrast(p.onAccent, c), greaterThanOrEqualTo(3), reason: '${p.name} marks on statuses');
        }
        // Done and missed stay apart for every kind of colour blindness.
        for (final type in ColourBlindness.values) {
          expect(deltaE(simulate(p.done, type), simulate(p.missed, type)), greaterThanOrEqualTo(0.08),
              reason: '${p.name} done vs missed, ${type.name}');
        }
      }
    });

    test('follows night light, and a manual pick holds until it changes', () {
      final store = Store.memory();
      var state = AppState(store)..setTheme('Morning Pastel');
      state.nightLightIs(true);
      expect(state.themeName, 'Evening Pastel');
      state.nightLightIs(true);
      state.setTheme('Sunrise');
      state.nightLightIs(true);
      expect(state.themeName, 'Sunrise', reason: 'held until night light changes');
      state.nightLightIs(false);
      expect(state.themeName, 'Sunrise');

      // A restart alone doesn't switch; a change while closed does.
      state = AppState(store)..nightLightIs(false);
      expect(state.themeName, 'Sunrise');
      state = AppState(store)..nightLightIs(true);
      expect(state.themeName, 'Sunset');

      state.setFollowNightLight(false);
      state.nightLightIs(false);
      expect(state.themeName, 'Sunset');
      state.setFollowNightLight(true);
      expect(state.themeName, 'Sunrise', reason: 'turning it on matches night light now');
      expect(AppState(store).followNightLight, isTrue);
      store.close();
    });

    test('reads night light from the hyprsunset socket', () async {
      final dir = Directory.systemTemp.createTempSync('night_light');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/.hyprsunset.sock';
      var temperature = '2371';
      final server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
      addTearDown(server.close);
      server.listen((client) {
        client.listen((request) {
          expect(utf8.decode(request), 'temperature');
          client
            ..write(temperature)
            ..close();
        });
      });

      final nightLight = NightLight(path);
      expect(await nightLight.isOn(), isTrue);
      temperature = '6000';
      expect(await nightLight.isOn(), isFalse);
      expect(await NightLight('${dir.path}/missing.sock').isOn(), isNull);
    });
  });

  group('journal files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('productivity_journal'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('entries are Markdown files, and old ones are exported once', () {
      final store = Store.open('${dir.path}/app.db');
      store.setJournal('2026-10-01', 'Written before files.');
      final files = JournalFiles(Directory('${dir.path}/Eclipse Journal'));
      final day = DateTime(2026, 10, 23);
      var state = AppState(store, journalFiles: files, clock: () => day);

      final old = File('${dir.path}/Eclipse Journal/2026/2026-10-01.md');
      expect(old.readAsStringSync(), '# Thursday 1 October 2026\n\nWritten before files.\n');

      state.setJournal(day, 'Line one\n\nLine two');
      final file = File('${dir.path}/Eclipse Journal/2026/2026-10-23.md');
      expect(file.readAsStringSync(), '# Friday 23 October 2026\n\nLine one\n\nLine two\n');
      expect(state.journalOf(day), 'Line one\n\nLine two');
      expect(store.journal('2026-10-23'), 'Line one\n\nLine two', reason: 'kept in the database for backups');

      // Edited outside the app: the file wins.
      file.writeAsStringSync('# Friday 23 October 2026\n\nEdited in a text editor\n');
      expect(state.journalOf(day), 'Edited in a text editor');

      // A deleted file stays deleted.
      old.deleteSync();
      state = AppState(store, journalFiles: files, clock: () => day);
      expect(old.existsSync(), isFalse);
      expect(state.journalOf(DateTime(2026, 10, 1)), '');

      state.setJournal(day, '  ');
      expect(file.existsSync(), isFalse, reason: 'an emptied entry leaves no file');
      store.close();
    });
  });

  group('updates', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('productivity_updates'));
    tearDown(() => dir.deleteSync(recursive: true));

    String git(List<String> args) {
      final r = Process.runSync('git', [
        '-C', dir.path, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', ...args, //
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return (r.stdout as String).trim();
    }

    test('offers newer commits from the folder the app was built from', () async {
      git(['init', '-q']);
      Directory('${dir.path}/linux').createSync();
      File('${dir.path}/linux/install.sh').writeAsStringSync('echo "Building"\necho "Error: no space left" >&2\nexit 1\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'First']);
      final built = git(['rev-parse', 'HEAD']);

      final app = Directory('${dir.path}/installed')..createSync();
      expect(Updater.forExecutable('${app.path}/eclipse'), isNull, reason: 'no build-info: not installed by the script');
      File('${app.path}/build-info').writeAsStringSync('repo=${dir.path}\ncommit=$built\n');
      final updater = Updater.forExecutable('${app.path}/eclipse')!;

      await updater.check();
      expect(updater.status, UpdateStatus.none, reason: 'up to date');

      git(['commit', '-q', '--allow-empty', '-m', 'Second']);
      git(['commit', '-q', '--allow-empty', '-m', 'Add an update banner']);
      await updater.check();
      expect(updater.status, UpdateStatus.available);
      expect(updater.newCommits, 2);
      expect(updater.latest, 'Add an update banner');

      updater.dismiss();
      await updater.check();
      expect(updater.status, UpdateStatus.none, reason: 'Later hides it until there is something newer');
      git(['commit', '-q', '--allow-empty', '-m', 'Third']);
      await updater.check();
      expect(updater.status, UpdateStatus.available);

      await updater.update();
      expect(updater.status, UpdateStatus.failed);
      expect(updater.error, 'Error: no space left');
      await updater.check();
      expect(updater.status, UpdateStatus.failed, reason: 'the error stays until there is something new');
    });
  });

  group('carry-forward', () {
    test('unfinished to-dos roll into the new day, week and month', () {
      var now = DateTime(2026, 10, 23, 22); // Friday
      final state = AppState(Store.memory(), clock: () => now);
      state.todos[TodoScope.today]!.toList().forEach((t) => state.removeTodo(TodoScope.today, t));

      state.addTodo(TodoScope.today, 'Unfinished');
      state.addTodo(TodoScope.today, 'Finished');
      state.toggleTodo(state.todos[TodoScope.today]!.last);
      state.addTodo(TodoScope.week, 'Weekly');
      state.addTodo(TodoScope.month, 'Monthly');

      now = DateTime(2026, 10, 24, 0, 1); // Saturday
      state.checkDate();
      expect(state.todos[TodoScope.today]!.map((t) => (t.text, t.carried)), [('Unfinished', 1)]);
      expect(state.todos[TodoScope.week]!.single.carried, 0, reason: 'same week');

      now = DateTime(2026, 10, 26); // Monday
      state.checkDate();
      expect(state.todos[TodoScope.today]!.single.carried, 2);
      expect(state.todos[TodoScope.week]!.map((t) => (t.text, t.carried)), [('Weekly', 1)]);
      expect(state.todos[TodoScope.month]!.single.carried, 0, reason: 'same month');

      now = DateTime(2026, 11, 2);
      state.checkDate();
      expect(state.todos[TodoScope.month]!.map((t) => (t.text, t.carried)), [('Monthly', 1)]);
    });

    test('a past day keeps its list as it stood, ticked and unticked', () {
      var now = DateTime(2026, 10, 22, 12); // Thursday
      final state = AppState(Store.memory(), clock: () => now);
      state.todos[TodoScope.today]!.toList().forEach((t) => state.removeTodo(TodoScope.today, t));
      state.addTodo(TodoScope.today, 'collect prescription');
      state.addTodo(TodoScope.today, 'Finished');
      state.toggleTodo(state.todos[TodoScope.today]!.last);
      expect(state.todos[TodoScope.today]!.first.text, 'Collect prescription', reason: 'capitalised');

      now = DateTime(2026, 10, 24, 9); // Saturday: carried twice
      state.checkDate();
      state.toggleTodo(state.todos[TodoScope.today]!.single);

      String list(DateTime day) =>
          state.todosOn(TodoScope.today, day).map((t) => '${t.text}${t.done ? ' ✓' : ''}').join(', ');
      expect(list(DateTime(2026, 10, 22)), 'Collect prescription, Finished ✓');
      expect(list(DateTime(2026, 10, 23)), 'Collect prescription', reason: 'carried through, still open then');
      expect(list(DateTime(2026, 10, 24)), 'Collect prescription ✓');
      expect(state.todos[TodoScope.today]!.single.since, DateTime(2026, 10, 22));
    });

    test('older to-dos get a since date one period back per carry', () {
      final path = '${Directory.systemTemp.createTempSync('productivity_since').path}/old.db';
      Store.open(path).close();
      final db = sqlite3.open(path);
      db.execute('''
        ALTER TABLE todos DROP COLUMN since; PRAGMA user_version = 5;
        INSERT INTO todos (scope, period, text, carried) VALUES
          ('today', '2026-10-24', 'Day', 2), ('week', '2026-10-19', 'Week', 1), ('month', '2026-10', 'Month', 1);
      ''');
      db.close();
      final store = Store.open(path);
      expect(store.todos(TodoScope.today, '2026-10-24').single.since, DateTime(2026, 10, 22));
      expect(store.todos(TodoScope.week, '2026-10-19').single.since, DateTime(2026, 10, 12));
      expect(store.todos(TodoScope.month, '2026-10').single.since, DateTime(2026, 9, 1));
      store.close();
    });

    test('nothing vanishes when the clock goes back over midnight', () {
      var now = DateTime(2026, 10, 24, 0, 30); // flew in from further east
      final state = AppState(Store.memory(), clock: () => now);
      state.todos[TodoScope.today]!.toList().forEach((t) => state.removeTodo(TodoScope.today, t));
      state.addTodo(TodoScope.today, 'Unpack');

      now = DateTime(2026, 10, 23, 23); // landed, an hour and a half behind
      state.checkDate();
      expect(state.today, DateTime(2026, 10, 23));
      expect(state.todos[TodoScope.today]!.map((t) => (t.text, t.carried)), [('Unpack', 0)]);

      now = DateTime(2026, 10, 24, 0, 1);
      state.checkDate();
      expect(state.todos[TodoScope.today]!.map((t) => (t.text, t.carried)), [('Unpack', 1)]);
    });
  });

  group('day start', () {
    test('a day can run on past midnight', () {
      expect(dayOf(DateTime(2026, 10, 24, 1, 30), 4), DateTime(2026, 10, 23));
      expect(dayOf(DateTime(2026, 10, 24, 4), 4), DateTime(2026, 10, 24));
      expect(dayOf(DateTime(2026, 10, 24, 1, 30), 0), DateTime(2026, 10, 24));
      expect(dayOf(DateTime(2026, 11, 1, 2), 3), DateTime(2026, 10, 31), reason: 'across a month');
      expect(nextDayStart(DateTime(2026, 10, 24, 1, 30), 4), DateTime(2026, 10, 24, 4));
      expect(nextDayStart(DateTime(2026, 10, 24, 22), 4), DateTime(2026, 10, 25, 4));
      expect(nextDayStart(DateTime(2026, 10, 24, 22), 0), DateTime(2026, 10, 25));
    });

    test('late-night ticks count for the day before', () {
      final store = Store.memory();
      var now = DateTime(2026, 10, 23, 23); // Friday night
      var state = AppState(store, clock: () => now);
      state.setDayStartHour(4);
      state.todos[TodoScope.today]!.toList().forEach((t) => state.removeTodo(TodoScope.today, t));
      state.addTodo(TodoScope.today, 'Unfinished');

      now = DateTime(2026, 10, 24, 1, 30);
      state.checkDate();
      expect(state.today, DateTime(2026, 10, 23));
      expect(state.lateNight, isTrue);
      final journal = state.sleepHabits.firstWhere((h) => h.name == 'Unwind');
      state.cycle(state.today, journal);
      expect(state.statusOf(DateTime(2026, 10, 23), journal), HabitStatus.done);
      expect(state.todos[TodoScope.today]!.single.carried, 0, reason: 'still Friday');

      now = DateTime(2026, 10, 24, 4, 0, 1);
      state.checkDate();
      expect(state.today, DateTime(2026, 10, 24));
      expect(state.lateNight, isFalse);
      expect(state.todos[TodoScope.today]!.single.carried, 1);

      state = AppState(store, clock: () => now);
      expect(state.dayStartHour, 4, reason: 'remembered');
    });

    test('changing it after midnight moves today back, losing nothing', () {
      var now = DateTime(2026, 10, 24, 1); // Saturday, 1am, days start at midnight
      final state = AppState(Store.memory(), clock: () => now);
      state.todos[TodoScope.today]!.toList().forEach((t) => state.removeTodo(TodoScope.today, t));
      state.addTodo(TodoScope.today, 'Added just after midnight');

      state.setDayStartHour(4);
      expect(state.today, DateTime(2026, 10, 23));
      expect(state.todos[TodoScope.today]!.map((t) => t.text), ['Added just after midnight']);

      state.setDayStartHour(0);
      expect(state.today, DateTime(2026, 10, 24));
      expect(state.lateNight, isFalse);
    });
  });

  group('streaks', () {
    // Clocks went forward on 4 October 2026 in Adelaide, making it 23 hours
    // long. Run with TZ=Australia/Adelaide to check stepping over it.
    test('step by calendar day over a clock change', () {
      final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 6));
      final h = state.habits.first;
      for (final d in [3, 5, 6]) {
        state.cycle(DateTime(2026, 10, d), h);
      }
      expect(state.currentStreak(h), 2, reason: 'the blank 4th breaks it');
      expect(state.bestStreak(h), 2);
    });

    test('a blank weekend is excused only when weekends are rest days', () {
      final store = Store.memory();
      var state = AppState(store, clock: () => DateTime(2026, 10, 27)); // Tuesday
      final h = state.habits.first;
      for (final d in [22, 23, 26, 27]) {
        state.cycle(DateTime(2026, 10, d), h); // Thu, Fri, then Mon, Tue
      }
      expect(state.currentStreak(h), 2);
      expect(state.isRestDay(DateTime(2026, 10, 24)), isFalse);

      state.setRestWeekends(true);
      expect(state.isRestDay(DateTime(2026, 10, 24)), isTrue);
      expect(state.isRestDay(DateTime(2026, 10, 23)), isFalse);
      expect(state.currentStreak(h), 4, reason: 'Saturday and Sunday neither break nor add');
      expect(state.bestStreak(h), 4);

      state.cycle(DateTime(2026, 10, 25), h);
      expect(state.currentStreak(h), 5, reason: 'a ritual done on a rest day still counts');
      state.cycle(DateTime(2026, 10, 25), h); // now "not done"
      expect(state.currentStreak(h), 2, reason: 'marked not done, it breaks the streak');

      state = AppState(store, clock: () => DateTime(2026, 10, 27));
      expect(state.restWeekends, isTrue, reason: 'remembered');
    });
  });

  group('sleep schedule', () {
    test('an older database folds its sleep rituals in, keeping their history', () {
      final path = '${Directory.systemTemp.createTempSync('productivity_sleep').path}/old.db';
      Store.open(path).close();
      // Back to how a database looked before the sleep schedule.
      final db = sqlite3.open(path);
      db.execute('''
        DELETE FROM sleep_habits; DELETE FROM habits; DROP TABLE sleep_habits;
        ALTER TABLE month_habits DROP COLUMN note; ALTER TABLE todos DROP COLUMN since; PRAGMA user_version = 2;
      ''');
      final ids = <String, int>{};
      for (final (i, name) in [
        'Get up at 8:30 am', 'Brush teeth', 'Wind down at 8:45', 'Journal', 'Meditate', //
        'Screens, shower finished by 9:30 pm', 'Read', 'Bed by 10:30 pm',
      ].indexed) {
        db.execute('INSERT INTO habits DEFAULT VALUES');
        ids[name] = db.lastInsertRowId;
        db.execute('INSERT INTO month_habits VALUES (2026, 10, ?, ?, ?)', [ids[name], name, i]);
      }
      db.execute("INSERT INTO entries (day, habit_id, status) VALUES ('2026-10-01', ?, 1)", [ids['Get up at 8:30 am']]);
      db.close();

      final store = Store.open(path);
      final state = AppState(store, clock: () => DateTime(2026, 10, 23));
      expect(state.habits.map((h) => h.name), ['Brush teeth', 'Read']);
      final sleep = state.sleepHabits;
      expect(sleep.map((h) => h.name), ['Rise Early', 'Unwind', 'Screen Curfew', 'Sleep Early']);
      expect(sleep.first.description, 'Awaken at 8:30 am');
      expect(sleep.first.id, ids['Get up at 8:30 am']);
      expect(sleep[1].id, isNot(ids['Wind down at 8:45']), reason: 'Unwind starts fresh');
      expect(sleep[2].id, ids['Screens, shower finished by 9:30 pm']);
      expect(sleep[3].id, ids['Bed by 10:30 pm']);
      expect(state.statusOf(DateTime(2026, 10, 1), sleep.first), HabitStatus.done);
      expect(state.habitsFor(2025, 3).map((h) => h.name), ['Brush teeth', 'Read'], reason: 'every month');
    });
  });

  group('per-month rituals', () {
    test('a new month copies the last one, and edits stay in their month', () {
      var now = DateTime(2026, 10, 31);
      final state = AppState(Store.memory(), clock: () => now);

      // Future months preview the latest list without saving it.
      expect(state.habitsFor(2026, 12), hasLength(8));
      state.addHabit(2026, 10, 'Stretch');
      expect(state.habitsFor(2026, 12), hasLength(9));

      now = DateTime(2026, 11, 1);
      state.checkDate();
      final nov = state.habitsFor(2026, 11);
      expect(nov.map((h) => h.name), state.habitsFor(2026, 10).map((h) => h.name));
      expect(state.habits, same(nov));

      state.renameHabit(2026, 11, nov.first, 'Tidy room');
      state.removeHabit(2026, 11, nov.last);
      state.reorderHabit(2026, 11, 0, 2); // move first to third place
      expect(nov.take(3).map((h) => h.name), ['No phone until breakfast', 'Morning walk', 'Tidy room']);
      expect(nov, hasLength(8));

      final oct = state.store.monthHabits(2026, 10);
      expect(oct.first.name, 'Clean room');
      expect(oct, hasLength(9));

      // Same ritual id across months keeps streaks going.
      final getUp = oct.first;
      state.cycle(DateTime(2026, 10, 31), getUp);
      state.cycle(DateTime(2026, 11, 1), nov[2]);
      expect(state.currentStreak(nov[2]), 2);
    });
  });

  group('ritual notes', () {
    test("a note belongs to its month: copied into a new one, then edited apart", () {
      final dir = Directory.systemTemp.createTempSync('productivity_notes');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';
      var now = DateTime(2026, 10, 31);
      var state = AppState(Store.open(path), clock: () => now);
      final read = state.habits.firstWhere((h) => h.name == 'Read');
      state.setHabitNote(2026, 10, read, '  20 pages before bed ');
      expect(state.habits.firstWhere((h) => h.name == 'Read').description, '20 pages before bed');

      now = DateTime(2026, 11, 1);
      state.checkDate();
      final nov = state.habits.firstWhere((h) => h.name == 'Read');
      expect(nov.description, '20 pages before bed', reason: 'a new month copies the one before');

      state.setHabitNote(2026, 11, nov, '30 pages');
      expect(state.habitsFor(2026, 10).firstWhere((h) => h.name == 'Read').description, '20 pages before bed');
      state.store.close();

      state = AppState(Store.open(path), clock: () => now);
      expect(state.habits.firstWhere((h) => h.name == 'Read').description, '30 pages');
      expect(state.habitsFor(2026, 10).firstWhere((h) => h.name == 'Read').description, '20 pages before bed');
      state.setHabitNote(2026, 11, state.habits.firstWhere((h) => h.name == 'Read'), '  ');
      expect(state.habits.firstWhere((h) => h.name == 'Read').description, isNull, reason: 'blank removes it');
      state.store.close();
    });

    test('notes from when they followed a ritual everywhere stay in every month it is in', () {
      final path = '${Directory.systemTemp.createTempSync('productivity_notes_v4').path}/old.db';
      Store.open(path).close();
      final db = sqlite3.open(path);
      db.execute('''
        ALTER TABLE month_habits DROP COLUMN note; ALTER TABLE habits ADD COLUMN note TEXT;
        INSERT INTO habits (note) VALUES ('Home gym');
        ALTER TABLE todos DROP COLUMN since; PRAGMA user_version = 4;
      ''');
      final id = db.lastInsertRowId;
      db.execute("INSERT INTO month_habits VALUES (2026, 9, ?, 'Gym', 0), (2026, 10, ?, 'Gym', 0)", [id, id]);
      db.close();

      final store = Store.open(path);
      expect(store.monthHabits(2026, 9).single.description, 'Home gym');
      expect(store.monthHabits(2026, 10).single.description, 'Home gym');
      store.close();
    });
  });

  group('preview months', () {
    test('months before the first list are saved only when ticked or edited', () {
      final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));

      // Browsing back a year shows October's rituals but saves nothing.
      final preview = state.habitsFor(2025, 10);
      expect(preview, hasLength(8));
      expect(state.isPreviewMonth(2025, 10), isTrue);
      expect(state.store.monthHabits(2025, 10), isEmpty);

      // Ticking a ritual saves the month.
      state.cycle(DateTime(2025, 10, 5), preview.first);
      expect(state.store.monthHabits(2025, 10), hasLength(8));
      expect(state.isPreviewMonth(2025, 10), isFalse);
      expect(state.statusOf(DateTime(2025, 10, 5), state.habitsFor(2025, 10).first), HabitStatus.done);

      // Editing (with a habit from the preview list) saves it too, and
      // leaves the months it was copied from alone.
      final sep = state.habitsFor(2026, 9);
      expect(state.isPreviewMonth(2026, 9), isFalse, reason: 'between first list and today');
      final aug = state.habitsFor(2025, 8);
      expect(state.isPreviewMonth(2025, 8), isTrue);
      state.renameHabit(2025, 8, aug.first, 'Get up at 9');
      expect(state.store.monthHabits(2025, 8).first.name, 'Get up at 9');
      expect(state.habitsFor(2025, 8).first.name, 'Get up at 9');
      expect(sep.first.name, 'Clean room');
    });

    test('adding a ritual works in a database with no lists at all', () {
      final store = Store.memory();
      final state = AppState(store, clock: () => DateTime(2026, 10, 23));
      for (final h in state.habits.toList()) {
        state.removeHabit(2026, 10, h);
      }
      expect(state.habitsFor(2026, 11), isEmpty);
      state.addHabit(2026, 10, 'Stretch');
      expect(state.habits.map((h) => h.name), ['Stretch']);
    });
  });

  group('backups', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('productivity_backups'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('one copy a day, the newest 30 kept', () {
      final backups = Backups(Directory('${dir.path}/backups'));
      var now = DateTime(2026, 10, 23);
      final state = AppState(Store.open('${dir.path}/app.db'), backups: backups, clock: () => now);
      expect(backups.list().map((b) => b.day), [DateTime(2026, 10, 23)]);

      state.checkDate(); // same day: nothing new
      expect(backups.list(), hasLength(1));

      for (var i = 1; i <= 40; i++) {
        now = DateTime(2026, 10, 23 + i); // crosses into November and over the clock change
        state.checkDate();
      }
      final days = backups.list().map((b) => b.day!).toList();
      expect(days, hasLength(30));
      expect(days.first, DateTime(2026, 12, 2));
      expect(days.last, DateTime(2026, 11, 3));
      state.store.close();
    });

    test('restore brings back old data and can itself be undone', () async {
      final backups = Backups(Directory('${dir.path}/backups'));
      var now = DateTime(2026, 10, 23);
      final state = AppState(Store.open('${dir.path}/app.db'), backups: backups, clock: () => now);
      final weights = state.habits.firstWhere((h) => h.name == 'Weights');
      state.cycle(now, weights); // done, after the 23rd's copy was taken
      state.setTheme('Sunset');

      now = DateTime(2026, 10, 24);
      state.checkDate(); // the 24th's copy has Weights done
      state.cycle(DateTime(2026, 10, 23), weights); // now "not done"
      state.addTodo(TodoScope.today, 'After the backup');

      final oct24 = backups.list().firstWhere((b) => b.day == DateTime(2026, 10, 24));
      await state.restore(oct24);
      expect(state.statusOf(DateTime(2026, 10, 23), weights), HabitStatus.done);
      expect(state.todos[TodoScope.today]!.map((t) => t.text), isNot(contains('After the backup')));
      expect(state.themeName, 'Sunset');

      final before = backups.list().first;
      expect(before.isBeforeRestore, isTrue);
      await state.restore(before); // undo
      expect(state.statusOf(DateTime(2026, 10, 23), weights), HabitStatus.missed);
      expect(state.todos[TodoScope.today]!.map((t) => t.text), contains('After the backup'));

      // Undoing again swaps back: the before-restore copy is never lost.
      await state.restore(backups.list().first);
      expect(state.statusOf(DateTime(2026, 10, 23), weights), HabitStatus.done);
      state.store.close();
    });

    test('a damaged copy is refused and changes nothing', () async {
      final backups = Backups(Directory('${dir.path}/backups'));
      final day = DateTime(2026, 10, 23);
      final state = AppState(Store.open('${dir.path}/app.db'), backups: backups, clock: () => day);
      final copy = backups.list().single;
      copy.file.writeAsStringSync('not a database');
      final weights = state.habits.firstWhere((h) => h.name == 'Weights');
      state.cycle(day, weights);

      await expectLater(state.restore(copy), throwsA(anything));
      expect(state.statusOf(day, weights), HabitStatus.done);
      expect(state.store.monthHabits(2026, 10), hasLength(8));
      state.store.close();
    });
  });

  testWidgets('backups dialog restores after asking', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('productivity_backups');
    addTearDown(() => dir.deleteSync(recursive: true));
    final backups = Backups(Directory('${dir.path}/backups'));
    var now = DateTime(2026, 10, 20);
    late AppState state;
    await tester.runAsync(() async {
      state = AppState(Store.open('${dir.path}/app.db'), backups: backups, clock: () => now);
      for (var d = 21; d <= 23; d++) {
        now = DateTime(2026, 10, d);
        state.checkDate();
      }
    });
    final weights = state.habits.firstWhere((h) => h.name == 'Weights');
    state.cycle(now, weights);
    state.setJournal(now, 'Written after the backup');

    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Backups'));
    await tester.pumpAndSettle();
    expect(find.text('Friday 23 October'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    await _shoot(tester, 'backups');

    await tester.tap(find.text('Restore').at(1)); // Thursday 22 October
    await tester.pumpAndSettle();
    expect(find.text('Replaces everything you have now.'), findsOneWidget);
    await _shoot(tester, 'backups_confirm');
    expect(state.statusOf(now, weights), HabitStatus.done, reason: 'nothing happens before confirming');

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(state.statusOf(now, weights), HabitStatus.none);
    expect(find.text('Written after the backup'), findsNothing, reason: 'the journal reloads too');
    expect(find.textContaining('Restored 22 October'), findsOneWidget);
    await _shoot(tester, 'backups_restored');
    state.store.close();
  });

  testWidgets('Today view, month grid and ritual editor', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Daily rituals'), findsOneWidget);
    expect(find.text('Sleep schedule'), findsOneWidget);
    expect(find.text('Screen Curfew'), findsOneWidget);
    expect(find.text('Dust room'), findsOneWidget);

    final weights = state.habits.firstWhere((h) => h.name == 'Weights');
    state.cycle(state.today, weights);
    expect(state.currentStreak(weights), 1);
    await tester.pumpAndSettle();
    await _shoot(tester, 'today');

    // The bottom sleep row's tooltip shows from anywhere on its height, not
    // just over the line of text.
    final name = tester.getRect(find.text('Sleep Early'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(name.center.dx, name.top - 8));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Sleep at 11 pm'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Oct').first); // a hidden copy reserves its bold width
    await tester.pumpAndSettle();
    expect(find.text('31'), findsNWidgets(2), reason: 'rituals and sleep schedule each have the days');
    expect(find.text('SLEEP SCHEDULE  ·  4'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget, reason: 'the sleep schedule shows its percentage before anything is marked');
    await _shoot(tester, 'month');

    await tester.tap(find.text('Edit rituals'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Add a note').first, 'Make the bed too');
    expect(state.habits.first.description, 'Make the bed too');
    await tester.enterText(find.byType(TextField).last, 'Stretch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.habits.last.name, 'Stretch');
    await _shoot(tester, 'month_edit');

    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Stretch'), findsOneWidget);
  });

  testWidgets('the month view fits rituals and sleep schedule without scrolling', (tester) async {
    await _loadFonts();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    state.addHabit(2026, 10, 'A ritual with a name long enough to need two lines here');
    // 2500 x 1380 is the window on the user's 1440p screen.
    for (final size in const [Size(2500, 1380), Size(1440, 900), Size(1920, 1080), Size(960, 1040)]) {
      tester.view.physicalSize = size;
      state.showMonth(10);
      await tester.pumpWidget(EclipseApp(state: state));
      await tester.pumpAndSettle();
      final scroll = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .singleWhere((s) => s.position.axis == Axis.vertical);
      await _shoot(tester, 'month_fit_${size.width.round()}x${size.height.round()}');
      expect(scroll.position.maxScrollExtent, 0, reason: '$size');
    }
  });

  testWidgets('a long ritual wraps onto more lines, its row growing to fit', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1000, 720); // a tiled window
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 24));
    state.setRestWeekends(true);
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    final tablets = tester.renderObject<RenderParagraph>(find.text('Creatine, min + fin, vit. D, protein powder'));
    final weights = tester.renderObject<RenderParagraph>(find.text('Weights'));
    expect(tablets.didExceedMaxLines, isFalse);
    expect(tablets.size.height, greaterThan(weights.size.height * 1.5));
    expect(find.text('Rest day. Nothing you have to do.'), findsNWidgets(2), reason: 'the sleep schedule rests too');
    await _shoot(tester, 'today_narrow_weekend');
  });

  testWidgets('choosing when the day starts, and the header after midnight', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 24, 1, 30));
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('SATURDAY'), findsOneWidget);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4am'));
    await tester.pumpAndSettle();
    expect(state.dayStartHour, 4);
    expect(find.text('New day starts at'), findsOneWidget, reason: 'the menu stays open');
    await _shoot(tester, 'day_start_menu');

    await tester.tapAt(const Offset(200, 600)); // closes the menu
    await tester.pumpAndSettle();
    expect(state.today, DateTime(2026, 10, 23));
    expect(find.text('SATURDAY'), findsNothing);
    expect(find.text('FRIDAY  ·  UNTIL 4AM'), findsOneWidget);
    await _shoot(tester, 'day_start_header');
  });

  testWidgets('switching views and months never shows two at once', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    // How visible a widget is, through every fade above it.
    double opacityOf(Finder f) {
      var o = 1.0;
      tester.element(f).visitAncestorElements((e) {
        final w = e.widget;
        if (w is FadeTransition) o *= w.opacity.value;
        return true;
      });
      return o;
    }

    // Steps through a transition, failing if both sides show at any real
    // strength in one frame, or if either side jumps rather than eases.
    Future<void> expectFadeThrough(Finder from, Finder to, String name) async {
      var (lastA, lastB) = (1.0, 0.0);
      for (var i = 1; i <= 18; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final a = from.evaluate().isEmpty ? 0.0 : opacityOf(from.first);
        final b = to.evaluate().isEmpty ? 0.0 : opacityOf(to.last); // the incoming child is built last
        expect(a < 0.05 || b < 0.05, isTrue, reason: '$name frame $i: $a and $b');
        expect(lastA - a < 0.25 && b - lastB < 0.25, isTrue, reason: '$name frame $i jumps: $lastA -> $a, $lastB -> $b');
        (lastA, lastB) = (a, b);
        if (i == 5 || i == 12) await _shoot(tester, '${name}_$i');
      }
      await tester.pumpAndSettle();
    }

    state.showMonth(10);
    await expectFadeThrough(find.text('Daily rituals'), find.text('31'), 'today_to_month');

    // Between months the grid stays and morphs: September has 30 days, so
    // October's 31st column closes up while everything else stays visible.
    state.showMonth(9);
    await tester.pump();
    final card = tester.getRect(find.text('Edit rituals'));
    final first = find.text('1').first;
    var lastX = tester.getRect(find.text('30').first).left;
    for (var i = 1; i <= 18; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(opacityOf(first), 1, reason: 'the grid never fades between months');
      final x = tester.getRect(find.text('30').first).left;
      expect(x >= lastX && x - lastX < 6, isTrue, reason: 'columns spread smoothly: $lastX -> $x');
      lastX = x;
      if (i == 8) await _shoot(tester, 'oct_to_sep_8');
    }
    await tester.pumpAndSettle();
    expect(find.text('31'), findsNothing);
    expect(tester.getRect(find.text('Edit rituals')), card, reason: 'the card stays put');
  });

  testWidgets('right-click clears a square, and the hover only covers squares', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    await tester.pumpWidget(EclipseApp(state: state));
    state.showMonth(10);
    await tester.pumpAndSettle();

    final weights = state.habits.firstWhere((h) => h.name == 'Weights');
    final day = DateTime(2026, 10, 5);
    state.cycle(day, weights);
    state.cycle(day, weights); // not done
    state.setNote(day, weights, 'Rest day');
    await tester.pumpAndSettle();

    final square = find.byWidgetPredicate((w) => w is StatusCell && w.day == day && w.habit.id == weights.id);
    await tester.tap(square, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(state.statusOf(day, weights), HabitStatus.none);
    expect(state.noteOf(day, weights), isNull);

    // Right-clicking a blank or future square does nothing.
    await tester.tap(square, buttons: kSecondaryButton);
    final future = find.byWidgetPredicate((w) => w is StatusCell && w.day == DateTime(2026, 10, 30));
    await tester.tap(future.first, buttons: kSecondaryButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(state.statusOf(day, weights), HabitStatus.none);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(square));
    await tester.pumpAndSettle();
    await _shoot(tester, 'row_hover');
    await gesture.removePointer();
  });

  testWidgets('a ticked to-do glides up to the top', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    for (final t in [...state.todos[TodoScope.week]!]) {
      state.removeTodo(TodoScope.week, t);
    }
    for (final t in ['Alpha', 'Bravo', 'Charlie']) {
      state.addTodo(TodoScope.week, t);
    }
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final (alpha, charlie) = (top('Alpha'), top('Charlie'));

    await tester.tap(find.text('Charlie'));
    await tester.pump();
    // The glide waits for the tick to land.
    await tester.pump(const Duration(milliseconds: 300));
    expect(top('Charlie'), allOf(lessThan(charlie), greaterThan(alpha)), reason: 'still on its way up');

    await tester.pumpAndSettle();
    expect(top('Charlie'), moreOrLessEquals(alpha));
    expect(top('Alpha'), greaterThan(top('Charlie')));
  });

  testWidgets('a removed to-do closes up before it leaves', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    for (final t in [...state.todos[TodoScope.week]!]) {
      state.removeTodo(TodoScope.week, t);
    }
    for (final t in ['Alpha', 'Bravo', 'Charlie']) {
      state.addTodo(TodoScope.week, t);
    }
    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final charlie = top('Charlie');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Bravo')));
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();
    // Bravo's remove button: the nearest one to the right of its text.
    // Clicked with the mouse, so the row stays hovered.
    final bravo = tester.getCenter(find.text('Bravo'));
    final remove = [
      for (final e in find.byTooltip('Remove').evaluate()) tester.getCenter(find.byElementPredicate((x) => x == e)),
    ].where((c) => c.dx > bravo.dx).reduce((a, b) => (a - bravo).distance <= (b - bravo).distance ? a : b);
    await gesture.moveTo(remove);
    await tester.pump();
    await gesture.down(remove);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.todos[TodoScope.week]!.length, 3, reason: 'still closing up');
    expect(top('Charlie'), lessThan(charlie), reason: 'the row below follows it up');

    await tester.pumpAndSettle();
    expect(state.todos[TodoScope.week]!.map((t) => t.text), ['Alpha', 'Charlie']);
    expect(top('Charlie'), lessThan(charlie));
  });

  testWidgets('Enter saves a note', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    await tester.pumpWidget(EclipseApp(state: state));
    state.showMonth(10);
    await tester.pumpAndSettle();

    final weights = state.habits.firstWhere((h) => h.name == 'Weights');
    final day = DateTime(2026, 10, 6);
    state.cycle(day, weights);
    state.cycle(day, weights); // next tap is "other", which asks for a note
    await tester.pumpAndSettle();

    await tester.tap(find.byWidgetPredicate((w) => w is StatusCell && w.day == day && w.habit.id == weights.id));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Sore back');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('What happened?'), findsNothing);
    expect(state.noteOf(day, weights), 'Sore back');
  });

  testWidgets('update banner', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    final updater = Updater(repo: '/nowhere', installedCommit: 'abc', executable: '/nowhere/eclipse');
    await tester.pumpWidget(EclipseApp(state: state, updater: updater));
    await tester.pumpAndSettle();
    expect(find.text('A new version is ready'), findsOneWidget, reason: 'built but hidden');
    expect(tester.widget<AnimatedOpacity>(find.ancestor(
      of: find.text('A new version is ready'),
      matching: find.byType(AnimatedOpacity),
    ).first).opacity, 0);

    updater
      ..newCommits = 3
      ..latest = 'Smooth every view switch, morph months, and save the journal as files'
      ..status = UpdateStatus.available
      ..notifyListeners();
    await tester.pumpAndSettle();
    await _shoot(tester, 'update_available');

    updater
      ..status = UpdateStatus.updating
      ..notifyListeners();
    await tester.pump(const Duration(milliseconds: 600));
    await _shoot(tester, 'update_updating');

    updater
      ..error = 'Error: lib/main.dart:12:3: Expected a semicolon'
      ..status = UpdateStatus.failed
      ..notifyListeners();
    await tester.pump(const Duration(milliseconds: 600));
    await _shoot(tester, 'update_failed');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(updater.status, UpdateStatus.none);
  });

  testWidgets('the big date opens a past day to look at', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var now = DateTime(2026, 10, 22, 12);
    final state = AppState(Store.memory(), clock: () => now);
    state.addTodo(TodoScope.today, 'Return library books');
    final read = state.habits.firstWhere((h) => h.name == 'Read');
    state.cycle(DateTime(2026, 10, 22), read);
    state.setJournal(DateTime(2026, 10, 22), 'A quiet Thursday.');
    now = DateTime(2026, 10, 24, 9);
    state.checkDate();

    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('From 22/10'), findsWidgets);

    await tester.tap(find.text('24 October').last);
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    await _shoot(tester, 'day_picker');
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    expect(state.viewDay, isNull, reason: 'the future is not open');
    await tester.tap(find.text('22'));
    await tester.pumpAndSettle();

    expect(state.viewDay, DateTime(2026, 10, 22));
    expect(find.text('THURSDAY  ·  LOOKING BACK'), findsOneWidget);
    expect(find.text('A quiet Thursday.'), findsOneWidget);
    expect(find.text('Add a task'), findsNothing, reason: 'look only');
    expect(find.text('From 22/10'), findsNothing, reason: 'it was new that day');
    await _shoot(tester, 'past_day');

    await tester.tap(find.text('Today').first);
    await tester.pumpAndSettle();
    expect(state.viewDay, isNull);
  });

  testWidgets('theme switcher, and every theme renders', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    // A little history so streaks, trails and the grid show every status.
    for (final (i, h) in state.habits.indexed) {
      for (var d = 14; d <= 23; d++) {
        final taps = (i + d) % 5 == 0 ? 3 : ((i * 3 + d) % 4 == 0 ? 2 : 1);
        for (var t = 0; t < taps; t++) {
          state.cycle(DateTime(2026, 10, d), h);
        }
      }
    }
    state.addTodo(TodoScope.week, 'Book dentist');
    state.addTodo(TodoScope.month, 'Renew passport');

    await tester.pumpWidget(EclipseApp(state: state));
    await tester.pumpAndSettle();

    state.nightLightAvailable = true;
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Sunrise'), findsOneWidget);
    expect(find.text('Follow night light'), findsOneWidget);
    await _shoot(tester, 'theme_menu');
    await tester.tap(find.text('Morning Pastel'));
    await tester.pumpAndSettle();
    expect(state.themeName, 'Morning Pastel');

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekends as rest days'));
    await tester.pumpAndSettle();
    expect(state.restWeekends, isTrue);
    state.showMonth(10);
    await tester.pumpAndSettle();
    await _shoot(tester, 'rest_weekends_month');
    state.setRestWeekends(false);

    for (final palette in palettes) {
      final slug = palette.name.toLowerCase().replaceAll(RegExp('[^a-z]+'), '_');
      state.setTheme(palette.name);
      state.showToday();
      await tester.pumpAndSettle();
      await _shoot(tester, 'theme_${slug}_today');
      state.showMonth(10);
      await tester.pumpAndSettle();
      await _shoot(tester, 'theme_${slug}_month');
    }
  });
}
