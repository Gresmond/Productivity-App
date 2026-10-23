import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// Journal entries as plain Markdown files, one per day, in a folder you can
/// open, read, copy or back up without the app:
/// ~/Documents/Eclipse Journal/2026/2026-10-23.md
///
/// The files are the journal. The database keeps a copy of each entry only
/// so the daily backups include it.
class JournalFiles {
  JournalFiles(this.dir);

  final Directory dir;

  File fileFor(DateTime day) => File(p.join(dir.path, '${day.year}', '${dateKey(day)}.md'));

  static String _heading(DateTime day) =>
      '# ${weekdayNames[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1]} ${day.year}';

  bool has(DateTime day) => fileFor(day).existsSync();

  /// The entry's text, without the date heading the file starts with.
  String read(DateTime day) {
    final file = fileFor(day);
    if (!file.existsSync()) return '';
    var text = file.readAsStringSync();
    if (text.startsWith('# ')) {
      final end = text.indexOf('\n');
      text = end == -1 ? '' : text.substring(end + 1);
      if (text.startsWith('\n')) text = text.substring(1);
    }
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
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
