import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/backups.dart';
import 'data/journal_files.dart';
import 'data/store.dart';
import 'data/system_time_zone.dart';
import 'data/updates.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemTimeZone.instance?.sync();
  // ~/.local/share/dev.nicholas.productivity_app/productivity.db
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final state = AppState(
    Store.open(p.join(dir.path, 'productivity.db')),
    // ~/.local/share/dev.nicholas.productivity_app/backups/
    backups: Backups(Directory(p.join(dir.path, 'backups'))),
    // ~/Documents/Eclipse Journal/
    journalFiles: JournalFiles(Directory(p.join((await getApplicationDocumentsDirectory()).path, 'Eclipse Journal'))),
  );

  _watchDate(state);

  // Only when installed by linux/install.sh: watches its folder for newer commits.
  final updater = Updater.forExecutable(Platform.resolvedExecutable, onRestart: () async => state.store.close());
  if (updater != null) {
    unawaited(updater.check());
    Timer.periodic(const Duration(minutes: 2), (_) => updater.check());
  }

  runApp(EclipseApp(state: state, updater: updater));
}

/// Rolls the day over on the stroke of midnight. Also looks once a minute,
/// because timers stand still while the computer sleeps and the time zone
/// can change, and whenever the window comes back.
void _watchDate(AppState state) {
  void check() {
    SystemTimeZone.instance?.sync();
    state.checkDate();
  }

  void schedule() {
    final now = DateTime.now();
    final untilMidnight = DateTime(now.year, now.month, now.day + 1).difference(now);
    // Just past midnight, so the clock has certainly turned.
    final wait = untilMidnight < const Duration(minutes: 1)
        ? untilMidnight + const Duration(milliseconds: 20)
        : const Duration(minutes: 1);
    Timer(wait, () {
      check();
      schedule();
    });
  }

  schedule();
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
          themeAnimationDuration: const Duration(milliseconds: 350),
          themeAnimationCurve: Curves.easeOutCubic,
          home: Shell(updater: updater),
        ),
      ),
    );
  }
}
