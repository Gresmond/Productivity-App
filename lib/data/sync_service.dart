import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'store.dart';
import 'sync.dart';

/// Runs sync: copies this computer's change files up to Google Drive (or
/// any rclone remote) and everyone else's down, and merges them in.
///
/// Set up once per computer: it lives in the app's own folder, as
/// sync.json, so a restored backup or a moved data folder doesn't change it.
class SyncService extends ChangeNotifier {
  SyncService._(this.home, this.store, this._config) {
    engine = SyncEngine(store, machine);
    folder = SyncFolder(Directory(p.join(home.path, 'sync')), machine, Platform.localHostname);
  }

  static SyncService load(Directory home, Store store) {
    final file = File(p.join(home.path, 'sync.json'));
    var config = <String, dynamic>{};
    try {
      if (file.existsSync()) config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException {
      // A damaged file: set up again.
    }
    if (config['machine'] is! String) {
      final random = Random.secure();
      config['machine'] = List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    }
    return SyncService._(home, store, config);
  }

  final Directory home;
  final Store store;
  final Map<String, dynamic> _config;

  late final SyncEngine engine;
  late final SyncFolder folder;

  String get machine => _config['machine'] as String;

  /// Where the files go, like gdrive:Eclipse; null while sync is off.
  String? get remote => _config['remote'] as String?;
  bool get isOn => remote != null;

  /// Time of the newest edit already copied up.
  int get _pushed => _config['pushed'] as int? ?? 0;

  void _save() {
    final file = File(p.join(home.path, 'sync.json'));
    final part = File('${file.path}.part');
    part.writeAsStringSync(jsonEncode(_config), flush: true);
    part.renameSync(file.path);
  }

  /// Called with each round's changes from other computers, after they're
  /// in the database: to redraw, and write journal files.
  void Function(Incoming)? onIncoming;

  /// Called before joining with the journal days that were here, to remove
  /// their files.
  void Function(List<String> days)? onClear;

  bool busy = false;
  DateTime? lastSynced;
  String? error;

  /// The last changes that came in, for the banner; bumped with each.
  Incoming? lastIncoming;
  int incomingCount = 0;

  Timer? _timer;
  DateTime _lastFull = DateTime.fromMillisecondsSinceEpoch(0);

  /// Looks every half minute: syncs at once when something changed here,
  /// and every few minutes regardless, to hear from the other computers.
  void start() {
    _timer?.cancel();
    if (!isOn) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final changed = store.raw.select('SELECT 1 FROM sync_dirty LIMIT 1').isNotEmpty;
      if (changed || DateTime.now().difference(_lastFull) > const Duration(minutes: 3)) unawaited(run());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // rclone

  static String? _rclone;

  /// The rclone command, if it's installed. Apps opened from a launcher may
  /// not have the shell's PATH, so the usual places are looked in too.
  static String? findRclone() {
    if (_rclone != null) return _rclone;
    final dirs = [
      ...(Platform.environment['PATH'] ?? '').split(':'),
      '/usr/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
      p.join(Platform.environment['HOME'] ?? '', '.local', 'bin'),
    ];
    for (final d in dirs) {
      if (d.isEmpty) continue;
      final f = File(p.join(d, 'rclone'));
      if (f.existsSync()) return _rclone = f.path;
    }
    return null;
  }

  /// rclone's configured remotes, like gdrive:
  static Future<List<String>> remotes() async {
    final rclone = findRclone();
    if (rclone == null) return [];
    final r = await Process.run(rclone, ['listremotes']);
    if (r.exitCode != 0) return [];
    return [
      for (final line in (r.stdout as String).split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  Future<void> _rcloneRun(List<String> args) async {
    final rclone = findRclone();
    if (rclone == null) throw const SyncError('rclone isn\'t installed.');
    final r = await Process.run(rclone, args).timeout(const Duration(minutes: 5));
    // 3: the folder isn't there yet, which is fine on the way down.
    if (r.exitCode == 0 || (r.exitCode == 3 && args.first == 'copy' && args[1] == remote)) return;
    final lines = (r.stderr as String).trim().split('\n').where((l) => l.trim().isNotEmpty);
    throw SyncError(lines.isEmpty ? 'rclone stopped (code ${r.exitCode}).' : _tidy(lines.last));
  }

  static String _tidy(String line) =>
      line.replaceFirst(RegExp(r'^\d{4}/\d\d/\d\d \d\d:\d\d:\d\d (ERROR|NOTICE|CRITICAL) ?:? ?'), '').trim();

  Future<void> _pull(String remote) =>
      _rcloneRun(['copy', remote, folder.dir.path, '--exclude', '/$machine/**', '--exclude', '*.part']);

  Future<void> _push(String remote) =>
      _rcloneRun(['copy', folder.mine.path, '$remote/$machine', '--exclude', '*.part']);

  // Turning on

  /// Looks at [remote] before turning sync on: true if another computer
  /// already keeps its data there, to join rather than start it.
  Future<bool> look(String remote) async {
    if (folder.dir.existsSync()) folder.dir.deleteSync(recursive: true);
    _config['remote'] = remote; // for _pull's not-there-yet check
    try {
      await _pull(remote);
    } finally {
      _config.remove('remote');
    }
    return folder.hasOthers;
  }

  /// Turns sync on with [remote], after [look]. Joining replaces what's on
  /// this computer with what the others have. Otherwise this computer's
  /// data is merged with theirs (when it has synced before) or goes up as
  /// the start of it all.
  Future<void> turnOn(String remote, {required bool join}) async {
    if (join) {
      onClear?.call(engine.clearForJoining());
      _deliver(folder.read(engine));
    } else {
      engine.claimAll();
    }
    _config['remote'] = remote;
    _config['pushed'] = 0;
    _save();
    notifyListeners();
    start();
    await run();
  }

  /// Whether this computer has synced before: it then merges on turning
  /// back on, rather than joining afresh.
  bool get hasSynced => store.raw.select('SELECT 1 FROM sync_reg LIMIT 1').isNotEmpty;

  void turnOff() {
    _timer?.cancel();
    _config.remove('remote');
    _save();
    error = null;
    notifyListeners();
  }

  // Each round

  Future<void>? _running;

  /// One round: everyone else's changes down and merged, ours up.
  Future<void> run() => _running ??= _round().whenComplete(() => _running = null);

  Future<void> _round() async {
    final remote = this.remote;
    if (remote == null) return;
    _lastFull = DateTime.now();
    busy = true;
    notifyListeners();
    try {
      await _pull(remote);
      _deliver(folder.read(engine));
      engine.flush();
      final latest = engine.latest;
      if (folder.write(engine, _pushed) || latest > _pushed) {
        await _push(remote);
        _config['pushed'] = latest;
        _save();
      }
      lastSynced = DateTime.now();
      error = null;
    } catch (e) {
      error = e is SyncError ? e.message : '$e';
      debugPrint('Sync failed: $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _deliver(Incoming incoming) {
    if (incoming.isEmpty) return;
    onIncoming?.call(incoming);
    lastIncoming = incoming;
    incomingCount++;
  }
}

class SyncError implements Exception {
  const SyncError(this.message);

  final String message;

  @override
  String toString() => message;
}
