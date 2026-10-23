import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/backups.dart';
import 'data/journal_files.dart';
import 'data/store.dart';
import 'data/updates.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Picks up midnight (and waking from sleep) to roll the day over.
  Timer.periodic(const Duration(minutes: 1), (_) => state.checkDate());

  // Only when installed by linux/install.sh: watches its folder for newer commits.
  final updater = Updater.forExecutable(Platform.resolvedExecutable, onRestart: () async => state.store.close());
  if (updater != null) {
    unawaited(updater.check());
    Timer.periodic(const Duration(minutes: 2), (_) => updater.check());
  }

  runApp(EclipseApp(state: state, updater: updater));
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
