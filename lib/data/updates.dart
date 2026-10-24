import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum UpdateStatus {
  /// Up to date, nothing to check against, or dismissed.
  none,
  available,
  updating,
  failed,
  restarting,
}

/// Tells when a newer version of Eclipse is out, for the update card.
abstract class Updater extends ChangeNotifier {
  /// The updater for this copy of the app: the folder it was built from on
  /// Linux, GitHub Releases on a Mac. Null when there's nothing to check.
  static Updater? forThisApp({Future<void> Function()? onRestart}) {
    final executable = Platform.resolvedExecutable;
    if (Platform.isMacOS) return ReleaseUpdater.forBundle(executable);
    return GitUpdater.forExecutable(executable, onRestart: onRestart);
  }

  UpdateStatus status = UpdateStatus.none;

  /// The version on offer, like 1.10.2; null when that can't be told.
  String? newVersion;

  /// What the card's button says.
  String get actionLabel;

  /// The last line the install script printed, when it fails.
  String? error;

  /// How often [check] is worth calling.
  Duration get checkEvery;

  Future<void> check();

  Future<void> update();

  /// Hides the card until there is something newer still.
  void dismiss();

  @protected
  void set(UpdateStatus s) {
    status = s;
    notifyListeners();
  }
}

/// The `version:` in a pubspec.yaml, without its build number.
String? pubspecVersion(String pubspec) {
  final match = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec);
  return match?.group(1);
}

/// Whether version [a] (like 1.10.2) is later than [b].
bool isNewer(String a, String b) {
  List<int> parts(String v) => v.split('.').map((n) => int.tryParse(n) ?? 0).toList();
  final (x, y) = (parts(a), parts(b));
  for (var i = 0; i < x.length || i < y.length; i++) {
    final (m, n) = (i < x.length ? x[i] : 0, i < y.length ? y[i] : 0);
    if (m != n) return m > n;
  }
  return false;
}

/// Notices when the folder Eclipse was built from has newer commits than
/// the running copy, and rebuilds and reopens it on request.
///
/// linux/install.sh leaves a `build-info` file beside the app saying which
/// folder and commit it was built from. Without one (`flutter run`) this
/// never reports anything.
class GitUpdater extends Updater {
  GitUpdater({required this.repo, required this.installedCommit, required this.executable, this.onRestart});

  /// Reads the `build-info` beside [executable]; null when there is none.
  static GitUpdater? forExecutable(String executable, {Future<void> Function()? onRestart}) {
    final file = File(p.join(p.dirname(executable), 'build-info'));
    if (!file.existsSync()) return null;
    final info = {
      for (final line in file.readAsLinesSync())
        if (line.indexOf('=') case final i when i > 0) line.substring(0, i): line.substring(i + 1),
    };
    final (repo, commit) = (info['repo'], info['commit']);
    if (repo == null || repo.isEmpty || commit == null || commit.isEmpty) return null;
    return GitUpdater(repo: repo, installedCommit: commit, executable: executable, onRestart: onRestart);
  }

  final String repo;
  final String installedCommit;

  /// The running app, started again once the new copy is installed.
  final String executable;

  /// Runs before the app quits to reopen (closing the database).
  final Future<void> Function()? onRestart;

  @override
  String get actionLabel => 'Update and reopen';

  @override
  Duration get checkEvery => const Duration(minutes: 2);

  /// How many commits the new version adds; null when that can't be told
  /// (the installed commit was rewritten away).
  int? newCommits;

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
  @override
  Future<void> check() async {
    if (status == UpdateStatus.updating || status == UpdateStatus.restarting) return;
    final head = await _git(['rev-parse', 'HEAD']);
    if (head == null || head == installedCommit) return;
    if (head != _newest) {
      _newest = head;
      final count = await _git(['rev-list', '--count', '$installedCommit..$head']);
      newCommits = count == null ? null : int.tryParse(count);
      final pubspec = await _git(['show', '$head:pubspec.yaml']);
      newVersion = pubspec == null ? null : pubspecVersion(pubspec);
    } else if (status == UpdateStatus.failed) {
      return; // keeps the error showing until there's something new to try
    }
    if (newCommits == 0) return; // HEAD moved back to something older
    if (head == _dismissed) return;
    set(UpdateStatus.available);
  }

  @override
  void dismiss() {
    _dismissed = _newest;
    set(UpdateStatus.none);
  }

  /// Runs the install script, then reopens the app from the new copy.
  @override
  Future<void> update() async {
    if (status == UpdateStatus.updating || status == UpdateStatus.restarting) return;
    error = null;
    set(UpdateStatus.updating);

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
      set(UpdateStatus.failed);
      return;
    }

    set(UpdateStatus.restarting);
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
}

/// Asks GitHub for the latest release of Eclipse, for a Mac copy, whose
/// card links to the new disk image to download.
class ReleaseUpdater extends Updater {
  ReleaseUpdater(this.installedVersion);

  /// Reads the app's version from the Info.plist of the bundle around
  /// [executable] (Eclipse.app/Contents/MacOS/Eclipse); null without one.
  static ReleaseUpdater? forBundle(String executable) {
    final plist = File(p.join(p.dirname(p.dirname(executable)), 'Info.plist'));
    if (!plist.existsSync()) return null;
    final match = RegExp(
      r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>',
    ).firstMatch(plist.readAsStringSync());
    return match == null ? null : ReleaseUpdater(match.group(1)!);
  }

  static final _latest = Uri.parse('https://api.github.com/repos/Gresmond/Productivity-App/releases/latest');

  final String installedVersion;

  /// The disk image (or failing that the release page) to open.
  String? _download;

  String? _dismissed;

  @override
  String get actionLabel => 'Download';

  @override
  Duration get checkEvery => const Duration(hours: 3);

  @override
  Future<void> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(_latest);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final release = jsonDecode(await utf8.decoder.bind(response).join()) as Map<String, dynamic>;
      final tag = release['tag_name'] as String? ?? '';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!isNewer(version, installedVersion) || version == _dismissed) return;
      final assets = (release['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final dmg = assets.where((a) => (a['name'] as String? ?? '').endsWith('.dmg')).firstOrNull;
      _download = (dmg?['browser_download_url'] ?? release['html_url']) as String?;
      newVersion = version;
      set(UpdateStatus.available);
    } catch (_) {
      // Offline, or GitHub didn't answer: try again next time.
    } finally {
      client.close(force: true);
    }
  }

  /// Opens the download in the browser; installing it is a drag, as before.
  @override
  Future<void> update() async {
    if (_download case final url?) await Process.run('open', [url]);
    dismiss();
  }

  @override
  void dismiss() {
    _dismissed = newVersion;
    set(UpdateStatus.none);
  }
}
