import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/backups.dart';
import 'data/data_folder.dart';
import 'data/journal_files.dart';
import 'data/night_light.dart';
import 'data/store.dart';
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
  final data = DataFolder.load(dir, await getApplicationDocumentsDirectory());
  await data.root.create(recursive: true);
  late final AppState state;
  state = AppState(
    Store.open(data.database),
    backups: Backups(data.backups),
    journalFiles: JournalFiles(data.journal),
    dataFolder: data,
    restart: () => _restart(state),
  );

  _watchDate(state);
  _watchNightLight(state);

  // Only when installed by linux/install.sh: watches its folder for newer commits.
  final updater = Updater.forExecutable(Platform.resolvedExecutable, onRestart: () async => state.store.close());
  if (updater != null) {
    unawaited(updater.check());
    Timer.periodic(const Duration(minutes: 2), (_) => updater.check());
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
    final wait = until < const Duration(minutes: 1) ? until + const Duration(milliseconds: 20) : const Duration(minutes: 1);
    Timer(wait, () {
      check();
      schedule();
    });
  }

  schedule();
  AppLifecycleListener(onResume: check, onShow: check);
}

/// Mirrors night light into [AppState]: hyprsunset can't announce a
/// change, so it's asked every few seconds and whenever the window comes back.
void _watchNightLight(AppState state) {
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
