import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backups.dart';
import '../data/data_folder.dart';
import '../data/sync_service.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// Lists the saved copies; restoring one asks first, inline on its row.
/// Pops with the restored [Backup], or nothing.
class BackupsDialog extends StatefulWidget {
  const BackupsDialog({super.key});

  @override
  State<BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<BackupsDialog> {
  late final List<Backup> _backups = AppScope.of(context).backups?.list() ?? [];
  Backup? _confirming;
  bool _restoring = false;
  String? _error;

  /// rclone's remotes, once looked up; null while looking.
  List<String>? _remotes;
  String? _remote;

  /// Looking in the remote before turning sync on.
  bool _looking = false;

  /// The remote has another computer's data: waiting for a yes to use it.
  bool _confirmJoin = false;

  @override
  void initState() {
    super.initState();
    _findRemotes();
  }

  Future<void> _findRemotes() async {
    setState(() => _remotes = null);
    final remotes = await SyncService.remotes();
    if (!mounted) return;
    setState(() {
      _remotes = remotes;
      _remote = remotes.contains(_remote) ? _remote : remotes.firstOrNull;
    });
  }

  void _cancelJoin() => setState(() => _confirmJoin = false);

  void _pickRemote(String? remote) => setState(() => _remote = remote);

  String get _target => '${_remote!}Eclipse';

  Future<void> _lookThenTurnOn(SyncService sync) async {
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      final others = await sync.look(_target);
      if (!mounted) return;
      if (others && !sync.hasSynced) {
        setState(() {
          _looking = false;
          _confirmJoin = true;
        });
        return;
      }
      await sync.turnOn(_target, join: false);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach $_target: $e');
    }
    if (mounted) setState(() => _looking = false);
  }

  Future<void> _join(SyncService sync) async {
    setState(() {
      _confirmJoin = false;
      _looking = true;
    });
    try {
      await sync.turnOn(_target, join: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not use $_target: $e');
    }
    if (mounted) setState(() => _looking = false);
  }

  /// A folder picked to keep everything in, waiting for a yes.
  Directory? _newFolder;
  bool _moving = false;

  Future<void> _pickFolder() async {
    final state = AppScope.of(context);
    final folder = await DataFolder.pick(start: state.dataFolder!.root.parent.path);
    if (folder == null || !mounted) return;
    setState(() {
      _newFolder = folder.path == state.dataFolder!.root.path ? null : folder;
      _error = null;
    });
  }

  void _cancelMove() => setState(() => _newFolder = null);

  Future<void> _move() async {
    setState(() => _moving = true);
    try {
      await AppScope.of(context).useDataFolder(_newFolder!);
    } catch (e) {
      setState(() {
        _moving = false;
        _error = 'Could not use that folder: $e';
      });
    }
  }

  Future<void> _restore(Backup b) async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await AppScope.of(context).restore(b);
      if (mounted) Navigator.pop(context, b);
    } catch (e) {
      setState(() {
        _restoring = false;
        _error = 'That copy could not be restored. Nothing was changed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Dialog(
      backgroundColor: p.tile,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 480,
        // Scrolls when the window is too short for all of it.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BACKUPS',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: p.accent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Restore a copy',
                style: TextStyle(fontFamily: Fonts.display, fontSize: 28, color: p.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'A copy of everything is saved each day you use the app, and the last 30 are kept.',
                style: TextStyle(fontFamily: Fonts.body, fontSize: 14, height: 1.45, color: p.inkMuted),
              ),
              const SizedBox(height: 18),
              if (_backups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No backups yet.',
                      style: TextStyle(fontFamily: Fonts.body, fontSize: 15, color: p.inkMuted),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _backups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _BackupRow(
                      backup: _backups[i],
                      today: state.today,
                      confirming: _confirming == _backups[i],
                      restoring: _restoring && _confirming == _backups[i],
                      enabled: !_restoring,
                      onAsk: () => setState(() => _confirming = _backups[i]),
                      onCancel: () => setState(() => _confirming = null),
                      onConfirm: () => _restore(_backups[i]),
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(fontFamily: Fonts.body, fontSize: 13.5, color: p.missed),
                ),
              ],
              if (state.dataFolder != null) ...[const SizedBox(height: 18), _dataFolder(p, state.dataFolder!)],
              if (state.sync != null) ...[
                const SizedBox(height: 10),
                ListenableBuilder(listenable: state.sync!, builder: (context, _) => _sync(p, state.sync!)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _restoring ? null : () => Navigator.pop(context),
                    child: Text('Close', style: TextStyle(color: p.inkMuted)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _BackupsDialogState {
  /// Where everything lives, and a way to keep it somewhere else (a synced
  /// folder, say) so it follows you to a new computer.
  Widget _dataFolder(Palette p, DataFolder data) {
    final folder = _newFolder;
    final small = TextStyle(fontFamily: Fonts.body, fontSize: 13, height: 1.45, color: p.inkMuted);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(color: p.empty.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your data',
                  style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              if (folder == null)
                TextButton(
                  onPressed: _restoring || _moving ? null : _pickFolder,
                  child: Text('Keep it elsewhere…', style: TextStyle(color: p.accent)),
                ),
            ],
          ),
          SelectableText(
            _shortPath(data.root.path),
            maxLines: 1,
            style: TextStyle(fontFamily: Fonts.ui, fontSize: 12, color: p.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Every day, ritual, to-do and journal entry since you started is kept here'
            '${data.chosen == null ? ' (the journal in ${_shortPath(data.journal.path)})' : ''}. '
            'Uninstalling the app leaves it in place.',
            style: small,
          ),
          if (folder != null) ...[
            const SizedBox(height: 12),
            Text(
              DataFolder.hasData(folder)
                  ? '${_shortPath(folder.path)} already has Eclipse data. Use it instead of what\'s here? '
                        'What\'s here stays where it is. Eclipse reopens.'
                  : 'Copy everything to ${_shortPath(folder.path)} and keep it there from now on? '
                        'The copy here stays as a spare. Eclipse reopens. In a synced folder, have Eclipse '
                        'open on one computer at a time.',
              style: small.copyWith(color: p.ink),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _moving ? null : _cancelMove,
                  child: Text('Cancel', style: TextStyle(color: p.inkMuted)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
                  onPressed: _moving ? null : _move,
                  child: Text(DataFolder.hasData(folder) ? 'Use that folder' : 'Copy and reopen'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Keeping everything the same on your other computers, through Google
  /// Drive by rclone.
  Widget _sync(Palette p, SyncService sync) {
    final small = TextStyle(fontFamily: Fonts.body, fontSize: 13, height: 1.45, color: p.inkMuted);
    final code = TextStyle(fontFamily: Fonts.time, fontSize: 12, height: 1.6, color: p.ink);
    final rclone = SyncService.findRclone() != null;
    final remotes = _remotes;

    Widget button(String label, VoidCallback? onTap, {bool filled = false}) => filled
        ? FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
            onPressed: onTap,
            child: Text(label),
          )
        : TextButton(
            onPressed: onTap,
            child: Text(label, style: TextStyle(color: onTap == null ? p.inkMuted : p.accent)),
          );

    final List<Widget> body;
    Widget? action;
    if (sync.isOn) {
      final last = sync.lastSynced;
      final status = sync.busy
          ? 'Syncing…'
          : sync.error != null
          ? 'Couldn\'t sync: ${sync.error}'
          : last == null
          ? 'Waiting to sync.'
          : 'Last synced ${_ago(last)}.';
      action = button('Sync now', sync.busy ? null : () => sync.run());
      body = [
        SelectableText(
          sync.remote!,
          maxLines: 1,
          style: TextStyle(fontFamily: Fonts.ui, fontSize: 12, color: p.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Changes made here go up within a minute, and changes from your other computers come down every few '
          'minutes. $status',
          style: sync.error != null && !sync.busy ? small.copyWith(color: p.missed) : small,
        ),
        Align(alignment: Alignment.centerRight, child: button('Turn off', sync.busy ? null : sync.turnOff)),
      ];
    } else if (!rclone || remotes != null && remotes.isEmpty) {
      action = button('Check again', remotes == null ? null : _findRemotes);
      body = [
        Text(
          'Keep everything the same on your laptop or another computer, through Google Drive. '
          '${rclone ? 'Connect' : 'Install rclone, then connect'} it to Google Drive once, in a terminal:',
          style: small,
        ),
        const SizedBox(height: 8),
        SelectableText(
          '${rclone
              ? ''
              : Platform.isMacOS
              ? 'brew install rclone\n'
              : 'sudo pacman -S rclone\n'}rclone config',
          style: code,
        ),
        const SizedBox(height: 4),
        Text('In rclone config, make a new remote of type "drive" and sign in to Google.', style: small),
      ];
    } else if (_confirmJoin) {
      body = [
        Text(
          '$_target already has Eclipse data from another computer. Replace everything on this computer with it? '
          'This computer\'s data stays in today\'s backup above.',
          style: small.copyWith(color: p.ink),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            button('Cancel', _cancelJoin),
            const SizedBox(width: 4),
            button('Use it', () => _join(sync), filled: true),
          ],
        ),
      ];
    } else {
      body = [
        Text(
          'Keep everything the same on your laptop or another computer, through a folder in Google Drive. '
          'Each computer sends its own changes, so both can be open at once.',
          style: small,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (remotes != null && remotes.length > 1)
              DropdownButton<String>(
                value: _remote,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontFamily: Fonts.ui, fontSize: 13, color: p.ink),
                dropdownColor: p.tile,
                items: [for (final r in remotes) DropdownMenuItem(value: r, child: Text('${r}Eclipse'))],
                onChanged: _looking ? null : _pickRemote,
              )
            else if (_remote != null)
              Text(
                _target,
                style: TextStyle(fontFamily: Fonts.ui, fontSize: 12, color: p.ink),
              ),
            const Spacer(),
            if (_looking)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.done)),
              )
            else
              button('Turn on', _remote == null ? null : () => _lookThenTurnOn(sync), filled: true),
          ],
        ),
      ];
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(color: p.empty.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sync',
                  style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              ?action,
            ],
          ),
          ...body,
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final minutes = DateTime.now().difference(t).inMinutes;
    return switch (minutes) {
      < 1 => 'just now',
      1 => 'a minute ago',
      < 60 => '$minutes minutes ago',
      _ => 'at ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    };
  }

  static String _shortPath(String path) {
    final home = Platform.environment['HOME'];
    return home != null && path.startsWith(home) ? '~${path.substring(home.length)}' : path;
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.backup,
    required this.today,
    required this.confirming,
    required this.restoring,
    required this.enabled,
    required this.onAsk,
    required this.onCancel,
    required this.onConfirm,
  });

  final Backup backup;
  final DateTime today;
  final bool confirming;
  final bool restoring;
  final bool enabled;
  final VoidCallback onAsk;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (title, subtitle) = _describe(backup, today);

    return AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.hoverCurve,
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: confirming ? p.accent.withValues(alpha: 0.08) : p.empty.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: confirming ? p.accent.withValues(alpha: 0.35) : p.tileBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  confirming ? 'Replaces everything you have now.' : subtitle,
                  style: TextStyle(fontFamily: Fonts.body, fontSize: 12.5, color: p.inkMuted),
                ),
              ],
            ),
          ),
          if (restoring)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.done)),
            )
          else if (confirming) ...[
            TextButton(
              onPressed: onCancel,
              child: Text('Cancel', style: TextStyle(color: p.inkMuted)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
              onPressed: onConfirm,
              child: const Text('Restore'),
            ),
          ] else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.4)),
              ),
              onPressed: enabled ? onAsk : null,
              child: const Text('Restore'),
            ),
        ],
      ),
    );
  }

  static (String, String) _describe(Backup b, DateTime today) {
    if (b.isBeforeRestore) {
      final t = b.modified;
      final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return ('Before your last restore', 'Saved ${t.day} ${monthNames[t.month - 1]}, $time');
    }
    final d = b.day!;
    final year = d.year == today.year ? '' : ' ${d.year}';
    final title = '${weekdayNames[d.weekday - 1]} ${d.day} ${monthNames[d.month - 1]}$year';
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
    final ago = switch (days) {
      0 => 'Today, as it was when you opened the app',
      1 => 'Yesterday',
      _ => '$days days ago',
    };
    return (title, ago);
  }
}
