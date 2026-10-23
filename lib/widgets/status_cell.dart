import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'mark.dart';

/// A single habit-day square. Click to cycle its status; right-click to
/// clear it.
class StatusCell extends StatefulWidget {
  const StatusCell({
    super.key,
    required this.day,
    required this.habit,
    this.size = 34,
    this.enabled = true,
    this.rest = false,
  });

  final DateTime day;
  final Habit habit;
  final double size;
  final bool enabled;

  /// A rest day (a weekend, when that's turned on): greyed while blank.
  final bool rest;

  @override
  State<StatusCell> createState() => _StatusCellState();
}

class _StatusCellState extends State<StatusCell> with TickerProviderStateMixin {
  bool _hover = false;
  bool _pressed = false;

  /// A click changes a square quickly; a new month eases it in step with
  /// the grid's morph, so a whole month of colours doesn't snap in at once.
  static const _click = (Motion.click, Motion.clickCurve);
  static const _morph = (Motion.morph, Motion.morphCurve);
  var _change = _click;

  /// The mark being left and the one being moved to; [_progress] runs
  /// between them. Only the square's paint follows it, so a month of
  /// squares changing at once never rebuilds a widget per frame.
  _Look? _from;
  _Look? _to;
  late final _progress = AnimationController(vsync: this, value: 1);
  late final _curved = CurvedAnimation(parent: _progress, curve: _change.$2);
  late final _hoverAnim = AnimationController(vsync: this, duration: Motion.hover);

  @override
  void didUpdateWidget(StatusCell old) {
    super.didUpdateWidget(old);
    _change = old.day == widget.day ? _click : _morph;
  }

  @override
  void dispose() {
    _curved.dispose();
    _progress.dispose();
    _hoverAnim.dispose();
    super.dispose();
  }

  // Keeps the square's animations alive when a note's tooltip comes or goes.
  final _squareKey = GlobalKey();

  void _setHover(bool hover) {
    _hover = hover;
    if (hover) {
      _hoverAnim.forward();
    } else {
      _hoverAnim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final status = state.statusOf(widget.day, widget.habit);
    final note = state.noteOf(widget.day, widget.habit);
    final enabled = widget.enabled;

    final look = switch (status) {
      HabitStatus.none => const _Look(null, null),
      HabitStatus.done => _Look(p.done, Icons.check_rounded),
      HabitStatus.missed => _Look(p.missed, Icons.close_rounded),
      HabitStatus.other => _Look(p.other, Icons.remove_rounded),
    };
    if (_to == null) {
      _from = _to = look;
    } else if (look != _to) {
      // A theme change recolours at once; a new mark eases in.
      final themeOnly = look.icon == _to!.icon;
      _from = themeOnly ? look : _to;
      _to = look;
      if (!themeOnly) {
        _progress.duration = _change.$1;
        _curved.curve = _change.$2;
        _progress.forward(from: 0);
      }
    }

    Widget cell = RepaintBoundary(
      key: _squareKey,
      child: PressScale(
        hover: _hover && enabled,
        pressed: _pressed,
        lift: 1.04,
        dip: 0.91,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SquarePainter(
            from: _from!,
            to: _to!,
            progress: _curved,
            hover: enabled ? _hoverAnim : kAlwaysDismissedAnimation,
            palette: p,
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
      onEnter: (_) => setState(() {
        _setHover(true);
        _change = _click;
      }),
      onExit: (_) => setState(() {
        _setHover(false);
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? () => cycleStatus(context, state, widget.day, widget.habit) : null,
        onSecondaryTap: enabled && status != HabitStatus.none ? () => state.clear(widget.day, widget.habit) : null,
        child: AnimatedOpacity(
          opacity: !enabled ? 0.35 : (widget.rest && status == HabitStatus.none ? 0.45 : 1),
          duration: Motion.morph,
          curve: Motion.morphCurve,
          child: cell,
        ),
      ),
    );
  }
}

/// What a square shows for one status: its colour (none when blank) and mark.
class _Look {
  const _Look(this.base, this.icon);

  final Color? base;
  final IconData? icon;

  @override
  bool operator ==(Object other) => other is _Look && other.base == base && other.icon == icon;

  @override
  int get hashCode => Object.hash(base, icon);
}

/// Paints a square partway from one [_Look] to another. Colours blend
/// straight across; the old mark shrinks away before the new one grows in,
/// so a tick and a cross never overlap.
class _SquarePainter extends CustomPainter {
  _SquarePainter({
    required this.from,
    required this.to,
    required this.progress,
    required this.hover,
    required this.palette,
  }) : super(repaint: Listenable.merge([progress, hover]));

  final _Look from;
  final _Look to;
  final Animation<double> progress;
  final Animation<double> hover;
  final Palette palette;

  /// Drawn at this size and scaled, so every square shares its marks.
  static const _s = 34.0;

  List<Color> _fill(_Look l, Color empty) =>
      l.base == null ? [empty, empty] : [Color.lerp(l.base, Colors.white, 0.16)!, l.base!];

  Color _border(_Look l, double h) => l.base == null
      ? Color.lerp(palette.tileBorder.withValues(alpha: 0.7), palette.accent.withValues(alpha: 0.35), h)!
      : Colors.white.withValues(alpha: 0.18);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final h = hover.value;
    canvas.scale(size.width / _s);
    const rect = Rect.fromLTWH(0, 0, _s, _s);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_s * 0.28));
    final empty = palette.empty.withValues(alpha: 0.55 + 0.35 * h);

    // Shadow: only filled squares cast one, fading with their colour.
    final shadowFrom = from.base == null ? 0.0 : 1 - t;
    final shadowTo = to.base == null ? 0.0 : t;
    final shadowColor = Color.lerp(from.base ?? to.base, to.base ?? from.base, t);
    final shadowAmount = shadowFrom + shadowTo;
    if (shadowColor != null && shadowAmount > 0) {
      final shadow = BoxShadow(
        color: shadowColor.withValues(alpha: (0.24 + 0.16 * h) * shadowAmount),
        blurRadius: _s * 0.35,
        offset: const Offset(0, _s * 0.1),
      );
      canvas.drawRRect(rrect.shift(shadow.offset), shadow.toPaint());
    }

    final a = _fill(from, empty), b = _fill(to, empty);
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(a[0], b[0], t)!, Color.lerp(a[1], b[1], t)!],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(_border(from, h), _border(to, h), t)!,
    );

    // The old mark eases out, then the new one grows in.
    const centre = Offset(_s / 2, _s / 2);
    if (from.icon case final icon? when icon != to.icon) {
      paintMark(canvas, centre, icon, _s * 0.54, palette.onAccent, Motion.outgoing(t));
    }
    if (to.icon case final icon?) {
      paintMark(
        canvas,
        centre,
        icon,
        _s * 0.54,
        palette.onAccent,
        from.icon == icon ? 1 : Motion.incoming.transform(t),
      );
    }
    // A faint plus on a blank square under the pointer.
    final blank = (from.base == null ? 1 - t : 0) + (to.base == null ? t : 0);
    paintMark(canvas, centre, Icons.add_rounded, _s * 0.45, palette.inkMuted.withValues(alpha: 0.4), h * blank);
  }

  @override
  bool shouldRepaint(_SquarePainter old) =>
      old.from != from || old.to != to || old.palette != palette || old.progress != progress || old.hover != hover;
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
