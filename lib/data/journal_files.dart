import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// Journal entries as plain Markdown files, one per day, in a folder you can
/// open, read, copy or back up without the app:
/// ~/Documents/Eclipse Journal/2026/2026-10-23.md
///
/// The database holds the journal; these are a copy of it, kept up to date
/// as entries are written, synced or restored. Edits made to the files
/// themselves aren't read back, and are replaced the next time that day is
/// saved.
class JournalFiles {
  JournalFiles(this.dir);

  Directory dir;

  File fileFor(DateTime day) => File(p.join(dir.path, '${day.year}', '${dateKey(day)}.md'));

  static String _heading(DateTime day) =>
      '# ${weekdayNames[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1]} ${day.year}';

  bool has(DateTime day) => fileFor(day).existsSync();

  /// Moves the entries' files into [to], replacing any there for the same
  /// day, then removes the year folders and this folder if that leaves them
  /// empty. Anything else in them stays where it is.
  void moveTo(Directory to) {
    if (!dir.existsSync() || p.equals(dir.path, to.path)) return;
    final entry = RegExp(r'^\d{4}-\d{2}-\d{2}\.md$');
    for (final year in dir.listSync().whereType<Directory>()) {
      final name = p.basename(year.path);
      if (!RegExp(r'^\d{4}$').hasMatch(name)) continue;
      for (final file in year.listSync().whereType<File>()) {
        if (!entry.hasMatch(p.basename(file.path))) continue;
        final dest = File(p.join(to.path, name, p.basename(file.path)));
        dest.parent.createSync(recursive: true);
        // Copied and then removed, as a rename can't cross drives.
        file.copySync(dest.path);
        file.deleteSync();
      }
      if (year.listSync().isEmpty) year.deleteSync();
    }
    if (dir.listSync().isEmpty) dir.deleteSync();
  }

  /// Saves the day's entry; an empty entry removes its file. Written beside
  /// the file first and renamed, so a crash never leaves half an entry.
  void write(DateTime day, String text) {
    final file = fileFor(day);
    if (text.trim().isEmpty) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.parent.createSync(recursive: true);
    final part = File('${file.path}.part');
    part.writeAsStringSync('${_heading(day)}\n\n$text\n', flush: true);
    part.renameSync(file.path);
  }
}
