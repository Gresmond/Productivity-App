import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_app/app_state.dart';
import 'package:productivity_app/data/backups.dart';
import 'package:productivity_app/data/store.dart';
import 'package:productivity_app/main.dart';
import 'package:productivity_app/models.dart';
import 'package:productivity_app/theme/app_theme.dart';

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
      final meditate = state.habits.firstWhere((h) => h.name == 'Meditate');
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
      final again = state.habits.firstWhere((h) => h.name == 'Meditate');
      expect(state.habits, hasLength(14), reason: 'seed runs only once');
      expect(state.statusOf(day, again), HabitStatus.other);
      expect(state.noteOf(day, again), 'Sick');
      expect(state.statusOf(DateTime(2026, 10, 1), state.habits.first), HabitStatus.missed);
      expect(state.todos[TodoScope.week]!.map((t) => t.text), ['Book dentist']);
      expect(state.journalOf(day), 'A good day.');
      expect(state.themeName, 'Sunset');
      store.close();
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
  });

  group('per-month rituals', () {
    test('a new month copies the last one, and edits stay in their month', () {
      var now = DateTime(2026, 10, 31);
      final state = AppState(Store.memory(), clock: () => now);

      // Future months preview the latest list without saving it.
      expect(state.habitsFor(2026, 12), hasLength(14));
      state.addHabit(2026, 10, 'Stretch');
      expect(state.habitsFor(2026, 12), hasLength(15));

      now = DateTime(2026, 11, 1);
      state.checkDate();
      final nov = state.habitsFor(2026, 11);
      expect(nov.map((h) => h.name), state.habitsFor(2026, 10).map((h) => h.name));
      expect(state.habits, same(nov));

      state.renameHabit(2026, 11, nov.first, 'Get up at 7');
      state.removeHabit(2026, 11, nov.last);
      state.reorderHabit(2026, 11, 0, 2); // move first to third place
      expect(nov.take(3).map((h) => h.name), ['Clean room', 'No phone until breakfast', 'Get up at 7']);
      expect(nov, hasLength(14));

      final oct = state.store.monthHabits(2026, 10);
      expect(oct.first.name, 'Get up at 8');
      expect(oct, hasLength(15));

      // Same ritual id across months keeps streaks going.
      final getUp = oct.first;
      state.cycle(DateTime(2026, 10, 31), getUp);
      state.cycle(DateTime(2026, 11, 1), nov[2]);
      expect(state.currentStreak(nov[2]), 2);
    });
  });

  group('preview months', () {
    test('months before the first list are saved only when ticked or edited', () {
      final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));

      // Browsing back a year shows October's rituals but saves nothing.
      final preview = state.habitsFor(2025, 10);
      expect(preview, hasLength(14));
      expect(state.isPreviewMonth(2025, 10), isTrue);
      expect(state.store.monthHabits(2025, 10), isEmpty);

      // Ticking a ritual saves the month.
      state.cycle(DateTime(2025, 10, 5), preview.first);
      expect(state.store.monthHabits(2025, 10), hasLength(14));
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
      expect(sep.first.name, 'Get up at 8');
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
      expect(state.store.monthHabits(2026, 10), hasLength(14));
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

    await tester.pumpWidget(ProductivityApp(state: state));
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
    await tester.pumpWidget(ProductivityApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Daily rituals'), findsOneWidget);
    expect(find.text('Dust room'), findsOneWidget);

    final weights = state.habits.firstWhere((h) => h.name == 'Weights');
    state.cycle(state.today, weights);
    expect(state.currentStreak(weights), 1);
    await tester.pumpAndSettle();
    await _shoot(tester, 'today');

    await tester.tap(find.text('Oct').first); // a hidden copy reserves its bold width
    await tester.pumpAndSettle();
    expect(find.text('31'), findsOneWidget);
    await _shoot(tester, 'month');

    await tester.tap(find.text('Edit rituals'));
    await tester.pumpAndSettle();
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

  testWidgets('switching views and months never shows two at once', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(Store.memory(), clock: () => DateTime(2026, 10, 23));
    await tester.pumpWidget(ProductivityApp(state: state));
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

    // Steps through a transition, failing if both sides are visible in one frame.
    Future<void> expectFadeThrough(Finder from, Finder to, String name) async {
      for (var i = 1; i <= 12; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final a = from.evaluate().isEmpty ? 0.0 : opacityOf(from.first);
        final b = to.evaluate().isEmpty ? 0.0 : opacityOf(to.last); // the incoming child is built last
        expect(a == 0 || b == 0, isTrue, reason: '$name frame $i: $a and $b');
        if (i == 3 || i == 9) await _shoot(tester, '${name}_$i');
      }
      await tester.pumpAndSettle();
    }

    state.showMonth(10);
    await expectFadeThrough(find.text('Daily rituals'), find.text('31'), 'today_to_month');

    state.showMonth(9); // 30 days, so '31' is only in October's grid
    await tester.pump();
    final card = tester.getRect(find.text('Edit rituals'));
    await expectFadeThrough(find.text('31'), find.text('30'), 'oct_to_sep');
    expect(tester.getRect(find.text('Edit rituals')), card, reason: 'the card stays put');
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

    await tester.pumpWidget(ProductivityApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Sage & Sunset'), findsOneWidget);
    await _shoot(tester, 'theme_menu');
    await tester.tap(find.text('Soft Pastel'));
    await tester.pumpAndSettle();
    expect(state.themeName, 'Soft Pastel');

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
