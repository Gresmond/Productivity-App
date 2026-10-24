import 'dart:io';

import 'package:path/path.dart' as p;

import 'store.dart';

/// Where everything is kept: the database, its daily backups and the
/// journal. By default the app's own folder (with the journal in
/// Documents), or one folder you choose, such as a synced one, so the
/// whole history can follow you to a new computer.
///
/// The choice itself lives in a small file in the app's own folder, which
/// is never moved.
class DataFolder {
  DataFolder._(this.home, this.chosen, this.documents);

  /// The app's own folder: ~/.local/share/dev.nicholas.productivity_app
  final Directory home;

  /// The folder you picked; null for the defaults.
  final Directory? chosen;

  final Directory documents;

  static File _pointer(Directory home) => File(p.join(home.path, 'data-folder'));

  static DataFolder load(Directory home, Directory documents) {
    final pointer = _pointer(home);
    final path = pointer.existsSync() ? pointer.readAsStringSync().trim() : '';
    return DataFolder._(home, path.isEmpty ? null : Directory(path), documents);
  }

  Directory get root => chosen ?? home;
  String get database => p.join(root.path, 'productivity.db');
  Directory get backups => Directory(p.join(root.path, 'backups'));
  Directory get journal =>
      chosen == null ? Directory(p.join(documents.path, 'Eclipse Journal')) : Directory(p.join(root.path, 'Journal'));

  /// Whether [folder] already holds Eclipse's data (from another computer,
  /// or an earlier move).
  static bool hasData(Directory folder) => File(p.join(folder.path, 'productivity.db')).existsSync();

  /// Uses [folder] from the next start. Unless it already has data of its
  /// own, everything is copied there first; the old copy stays where it
  /// was, untouched.
  void moveTo(Directory folder, Store store) {
    final target = DataFolder._(home, folder, documents);
    if (!hasData(folder)) {
      folder.createSync(recursive: true);
      _copyTree(backups, target.backups);
      _copyTree(journal, target.journal);
      // Last, so a half-finished copy never looks like data to use.
      store.saveCopy(target.database);
    }
    _pointer(home).writeAsStringSync(folder.path);
  }

  static void _copyTree(Directory from, Directory to) {
    if (!from.existsSync()) return;
    for (final entity in from.listSync(recursive: true)) {
      if (entity is! File || entity.path.endsWith('.part')) continue;
      final dest = File(p.join(to.path, p.relative(entity.path, from: from.path)));
      if (dest.existsSync()) continue;
      dest.parent.createSync(recursive: true);
      entity.copySync(dest.path);
    }
  }

  /// Asks for a folder with the desktop's own picker; null if cancelled or
  /// there's no picker to ask with.
  static Future<Directory?> pick({String? start}) async {
    final home = Platform.environment['HOME'] ?? '/';
    final commands = Platform.isMacOS
        ? [
            ['osascript', '-e', 'POSIX path of (choose folder with prompt "Keep Eclipse\'s data in")'],
          ]
        : [
            ['kdialog', '--title', 'Keep Eclipse\'s data in', '--getexistingdirectory', start ?? home],
            [
              'zenity',
              '--file-selection',
              '--directory',
              '--title=Keep Eclipse\'s data in',
              '--filename=${start ?? home}/',
            ],
          ];
    for (final command in commands) {
      try {
        final result = await Process.run(command.first, command.skip(1).toList());
        final path = (result.stdout as String).trim();
        return result.exitCode == 0 && path.isNotEmpty ? Directory(path) : null;
      } on ProcessException {
        continue; // not installed: try the next
      }
    }
    return null;
  }
}
