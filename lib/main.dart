import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/backups.dart';
import 'data/data_folder.dart';
import 'data/journal_files.dart';
import 'data/night_light.dart';
import 'data/store.dart';
import 'data/sync_service.dart';
import 'data/system_time_zone.dart';
import 'data/updates.dart';
import 'models.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemTimeZone.instance?.sync();
  // ~/.local/share/dev.nicholas.productivity_app, unless you chose a folder.
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final documents = await getApplicationDocumentsDirectory();
  DataFolder.leaveSandbox(dir, documents);
  final data = DataFolder.load(dir, documents);
  await data.root.create(recursive: true);
  final store = Store.open(data.database);
  late final AppState state;
  state = AppState(
    store,
    backups: Backups(data.backups),
    journalFiles: JournalFiles(data.journal),
    dataFolder: data,
    sync: SyncService.load(dir, store),
    restart: () => _restart(state),
  );
  state.sync?.start();
  if (state.sync?.isOn ?? false) unawaited(state.sync!.run());
  _watchWindow(state);

  if (state.firstRun) state.startTour();
  _watchDate(state);
  _watchNightLight(state);

  // Installed by linux/install.sh: watches its folder for newer commits.
  // On a Mac: asks GitHub for a newer release.
  final updater = Updater.forThisApp(onRestart: () async => state.store.close());
  if (updater != null) {
    unawaited(updater.check());
    Timer.periodic(updater.checkEvery, (_) => updater.check());
  }

  runApp(EclipseApp(state: state, updater: updater));
}

/// Reopens the app, with whatever data folder is now chosen.
Future<void> _restart(AppState state) async {
  state.store.close();
  // Only one copy runs at a time, so the new one waits for this one to exit.
  await Process.start('sh', [
    '-c',
    'while kill -0 $pid 2>/dev/null; do sleep 0.1; done; exec "\$0"',
    Platform.resolvedExecutable,
  ], mode: ProcessStartMode.detached);
  exit(0);
}

/// Rolls the day over on the stroke of midnight (or whenever the user's day
/// starts). Also looks once a minute,
/// because timers stand still while the computer sleeps and the time zone
/// can change, and whenever the window comes back.
void _watchDate(AppState state) {
  void check() {
    SystemTimeZone.instance?.sync();
    state.checkDate();
  }

  void schedule() {
    final now = DateTime.now();
    // Midnight is looked at too, for the "until 4am" in the header.
    final until = [
      DateTime(now.year, now.month, now.day + 1),
      nextDayStart(now, state.dayStartHour),
    ].map((t) => t.difference(now)).reduce((a, b) => a < b ? a : b);
    // Just past the hour, so the clock has certainly turned.
    final wait = until < const Duration(minutes: 1)
        ? until + const Duration(milliseconds: 20)
        : const Duration(minutes: 1);
    Timer(wait, () {
      check();
      schedule();
    });
  }

  schedule();
  AppLifecycleListener(onResume: check, onShow: check);
}

/// Syncs as the window comes and goes, so switching computers shows the
/// latest: what changed here goes when the window goes to the back or is
/// closed, and the others' changes come in when it comes back. Quitting
/// waits a moment for sync, and saves typing first either way.
void _watchWindow(AppState state) {
  void leaving() {
    state.saveJournalDraft();
    state.sync?.sendChanges();
  }

  AppLifecycleListener(
    onResume: () => state.sync?.refresh(),
    onShow: () => state.sync?.refresh(),
    onInactive: leaving,
    onHide: leaving,
    onExitRequested: () async {
      state.saveJournalDraft();
      await state.sync?.beforeQuit();
      return AppExitResponse.exit;
    },
  );
}

/// Mirrors night light into [AppState]: hyprsunset can't announce a
/// change, so it's asked every few seconds and whenever the window comes back.
/// A Mac has no night light to read (Night Shift has no public API), so
/// there it follows Dark mode, which macOS's Auto appearance turns on at
/// sunset and off at sunrise.
void _watchNightLight(AppState state) {
  if (Platform.isMacOS) {
    state.nightLightAvailable = true;
    WidgetsBinding.instance.addObserver(_DarkModeObserver(state));
    return;
  }
  final nightLight = NightLight.forSession();
  if (nightLight == null) return;
  state.nightLightAvailable = true;
  Future<void> check() async {
    final on = await nightLight.isOn();
    if (on != null) state.nightLightIs(on);
  }

  unawaited(check());
  Timer.periodic(const Duration(seconds: 5), (_) => check());
  AppLifecycleListener(onResume: check, onShow: check);
}

class _DarkModeObserver with WidgetsBindingObserver {
  _DarkModeObserver(this.state) {
    didChangePlatformBrightness();
  }

  final AppState state;

  @override
  void didChangePlatformBrightness() =>
      state.nightLightIs(WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
}

class EclipseApp extends StatelessWidget {
  const EclipseApp({super.key, required this.state, this.updater});

  final AppState state;
  final Updater? updater;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ValueListenableBuilder<String?>(
        valueListenable: state.themeNotifier,
        builder: (context, themeName, _) => MaterialApp(
          title: 'Eclipse',
          debugShowCheckedModeBanner: false,
          theme: themeNamed(themeName),
          themeAnimationDuration: Motion.morph,
          themeAnimationCurve: Motion.morphCurve,
          home: Shell(updater: updater),
        ),
      ),
    );
  }
}
