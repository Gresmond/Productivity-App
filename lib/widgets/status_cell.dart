import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'fade_through.dart';

/// A single habit-day square. Click to cycle its status; right-click to
/// clear it.
class StatusCell extends StatefulWidget {
  const StatusCell({
    super.key,
    required this.day,
    required this.habit,
    this.size = 34,
    this.enabled = true,
  });

  final DateTime day;
  final Habit habit;
  final double size;
  final bool enabled;

  @override
  State<StatusCell> createState() => _StatusCellState();
}

class _StatusCellState extends State<StatusCell> {
  static const _base = 34.0;

  bool _hover = false;
  bool _pressed = false;

  // Keeps the square's animations alive when a note's tooltip comes or goes.
  final _squareKey = GlobalKey();

  Widget _buildIcon(IconData? icon, double s, Palette p) {
    // The old mark leaves before the new one arrives, so a tick and a cross
    // never overlap mid-change.
    return FadeThrough(
      duration: const Duration(milliseconds: 220),
      scaleFrom: 0.6,
      child: icon == null
          ? (_hover && widget.enabled
              ? Icon(
                  Icons.add_rounded,
                  key: const ValueKey('hover_add'),
                  size: s * 0.45,
                  color: p.inkMuted.withValues(alpha: 0.4),
                )
              : const SizedBox.shrink())
          : Icon(icon, key: ValueKey(icon), size: s * 0.54, color: p.onAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final status = state.statusOf(widget.day, widget.habit);
    final note = state.noteOf(widget.day, widget.habit);
    // Drawn at one size and scaled to [widget.size], so a square that
    // changes size (the month grid's columns differ by month) doesn't
    // restart its colour animation, or redo it for every square at once.
    const s = _base;
    final enabled = widget.enabled;

    final (Color? base, IconData? icon) = switch (status) {
      HabitStatus.none => (null, null),
      HabitStatus.done => (p.done, Icons.check_rounded),
      HabitStatus.missed => (p.missed, Icons.close_rounded),
      HabitStatus.other => (p.other, Icons.remove_rounded),
    };

    final borderRadius = BorderRadius.circular(s * 0.28);

    final decoration = BoxDecoration(
      borderRadius: borderRadius,
      color: base == null
          ? (_hover && enabled
              ? p.empty.withValues(alpha: 0.9)
              : p.empty.withValues(alpha: 0.55))
          : null,
      gradient: base == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(base, Colors.white, 0.16)!, base],
            ),
      border: base == null
          ? Border.all(
              color: _hover && enabled
                  ? p.accent.withValues(alpha: 0.35)
                  : p.tileBorder.withValues(alpha: 0.7),
              width: 1.0,
            )
          : Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.0,
            ),
      boxShadow: base == null
          ? null
          : [
              BoxShadow(
                color: base.withValues(alpha: _hover ? 0.40 : 0.24),
                blurRadius: s * 0.35,
                offset: Offset(0, s * 0.1),
              ),
            ],
    );

    Widget cell = RepaintBoundary(
      key: _squareKey,
      child: AnimatedScale(
        scale: _pressed ? 0.91 : (_hover && enabled ? 1.04 : 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: SizedBox.square(
          dimension: widget.size,
          child: FittedBox(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: s,
              height: s,
              decoration: decoration,
              child: _buildIcon(icon, s, p),
            ),
          ),
        ),
      ),
    );

    if (note != null) {
      cell = Tooltip(message: note, child: cell);
    }

    // The same widgets whether enabled or not, so a square that becomes a
    // future day (when the month changes) fades instead of jumping.
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? () => cycleStatus(context, state, widget.day, widget.habit) : null,
        onSecondaryTap: enabled && status != HabitStatus.none ? () => state.clear(widget.day, widget.habit) : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.35,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          child: cell,
        ),
      ),
    );
  }
}

Future<void> cycleStatus(
  BuildContext context,
  AppState state,
  DateTime day,
  Habit habit,
) async {
  if (state.cycle(day, habit) != HabitStatus.other) return;
  final note = await showDialog<String>(
    context: context,
    builder: (_) => _NoteDialog(habit: habit, initial: state.noteOf(day, habit)),
  );
  if (note != null) state.setNote(day, habit, note);
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.habit, this.initial});

  final Habit habit;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: p.tile,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.habit.name.toUpperCase(),
                style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: p.other, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'What happened?',
                style: TextStyle(fontFamily: Fonts.display, fontSize: 28, color: p.ink),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                // Enter saves; long notes still wrap onto more lines.
                textInputAction: TextInputAction.done,
                style: TextStyle(fontFamily: Fonts.body, fontSize: 15, color: p.ink),
                decoration: InputDecoration(
                  hintText: 'Optional note',
                  hintStyle: TextStyle(color: p.inkMuted),
                  filled: true,
                  fillColor: p.empty,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Skip', style: TextStyle(color: p.inkMuted)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: p.other),
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text('Save note'),
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
