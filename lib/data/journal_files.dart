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

  final Directory dir;

  File fileFor(DateTime day) => File(p.join(dir.path, '${day.year}', '${dateKey(day)}.md'));

  static String _heading(DateTime day) =>
      '# ${weekdayNames[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1]} ${day.year}';

  bool has(DateTime day) => fileFor(day).existsSync();

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
