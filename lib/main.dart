import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/backups.dart';
import 'data/store.dart';
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
  );

  // Picks up midnight (and waking from sleep) to roll the day over.
  Timer.periodic(const Duration(minutes: 1), (_) => state.checkDate());

  runApp(ProductivityApp(state: state));
}

class ProductivityApp extends StatelessWidget {
  const ProductivityApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ValueListenableBuilder<String?>(
        valueListenable: state.themeNotifier,
        builder: (context, themeName, _) => MaterialApp(
          title: 'Productivity',
          debugShowCheckedModeBanner: false,
          theme: themeNamed(themeName),
          themeAnimationDuration: const Duration(milliseconds: 350),
          themeAnimationCurve: Curves.easeOutCubic,
          home: const Shell(),
        ),
      ),
    );
  }
}
