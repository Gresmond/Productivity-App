import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum UpdateStatus {
  /// Up to date, not installed by linux/install.sh, or dismissed.
  none,
  available,
  updating,
  failed,
  restarting,
}

/// Notices when the folder Eclipse was built from has newer commits than
/// the running copy, and rebuilds and reopens it on request.
///
/// linux/install.sh leaves a `build-info` file beside the app saying which
/// folder and commit it was built from. Without one (a Mac build, or
/// `flutter run`) this never reports anything.
class Updater extends ChangeNotifier {
  Updater({required this.repo, required this.installedCommit, required this.executable, this.onRestart});

  /// Reads the `build-info` beside [executable]; null when there is none.
  static Updater? forExecutable(String executable, {Future<void> Function()? onRestart}) {
    final file = File(p.join(p.dirname(executable), 'build-info'));
    if (!file.existsSync()) return null;
    final info = {
      for (final line in file.readAsLinesSync())
        if (line.indexOf('=') case final i when i > 0) line.substring(0, i): line.substring(i + 1),
    };
    final (repo, commit) = (info['repo'], info['commit']);
    if (repo == null || repo.isEmpty || commit == null || commit.isEmpty) return null;
    return Updater(repo: repo, installedCommit: commit, executable: executable, onRestart: onRestart);
  }

  final String repo;
  final String installedCommit;

  /// The running app, started again once the new copy is installed.
  final String executable;

  /// Runs before the app quits to reopen (closing the database).
  final Future<void> Function()? onRestart;

  UpdateStatus status = UpdateStatus.none;

  /// How many commits the new version adds; null when that can't be told
  /// (the installed commit was rewritten away).
  int? newCommits;

  /// The newest commit's subject line.
  String? latest;

  /// The last line the install script printed, when it fails.
  String? error;

  String? _newest;
  String? _dismissed;

  Future<String?> _git(List<String> args) async {
    try {
      final r = await Process.run('git', ['-C', repo, ...args]);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  /// Looks for newer commits. Cheap: a few local git reads, no network.
  Future<void> check() async {
    if (status == UpdateStatus.updating || status == UpdateStatus.restarting) return;
    final head = await _git(['rev-parse', 'HEAD']);
    if (head == null || head == installedCommit) return;
    if (head != _newest) {
      _newest = head;
      final count = await _git(['rev-list', '--count', '$installedCommit..$head']);
      newCommits = count == null ? null : int.tryParse(count);
      latest = await _git(['log', '-1', '--format=%s', head]);
    } else if (status == UpdateStatus.failed) {
      return; // keeps the error showing until there's something new to try
    }
    if (newCommits == 0) return; // HEAD moved back to something older
    if (head == _dismissed) return;
    _set(UpdateStatus.available);
  }

  /// Hides the banner until there is something newer still.
  void dismiss() {
    _dismissed = _newest;
    _set(UpdateStatus.none);
  }

  /// Runs the install script, then reopens the app from the new copy.
  Future<void> update() async {
    if (status == UpdateStatus.updating || status == UpdateStatus.restarting) return;
    error = null;
    _set(UpdateStatus.updating);

    final output = <String>[];
    int code;
    try {
      final process = await Process.start('bash', [p.join(repo, 'linux', 'install.sh')], workingDirectory: repo);
      Future<void> collect(Stream<List<int>> stream) => stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((l) => l.trim().isNotEmpty)
          .forEach(output.add);
      await Future.wait([collect(process.stdout), collect(process.stderr)]);
      code = await process.exitCode;
    } on ProcessException catch (e) {
      output.add(e.message);
      code = -1;
    }

    if (code != 0) {
      error = output.lastWhere(
        (l) => l.toLowerCase().contains('error'),
        orElse: () => output.isEmpty ? 'The install script stopped (exit code $code).' : output.last,
      );
      _set(UpdateStatus.failed);
      return;
    }

    _set(UpdateStatus.restarting);
    await onRestart?.call();
    // Only one copy runs at a time, and a second one just hands over to the
    // first, so the new copy waits for this one to exit.
    await Process.start('sh', [
      '-c',
      'while kill -0 $pid 2>/dev/null; do sleep 0.1; done; exec "\$0"',
      executable,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  void _set(UpdateStatus s) {
    status = s;
    notifyListeners();
  }
}
