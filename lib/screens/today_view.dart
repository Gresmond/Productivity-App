import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/progress_ring.dart';
import '../widgets/status_cell.dart';
import '../widgets/tile.dart';
import '../widgets/todo_panel.dart';

/// Three columns that exactly fill the window: rituals over the sleep
/// schedule, today's to-dos, and week / month / journal. Only a card whose list outgrows it scrolls.
class TodayView extends StatelessWidget {
  const TodayView({super.key});

  static const _gap = 20.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // When width is tight (e.g. a tiled window under 860px), scroll sideways
        // so columns maintain their clean proportions instead of getting squished.
        const minContentWidth = 860.0;
        final needsScroll = constraints.maxWidth < minContentWidth;

        Widget content = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(flex: 11, child: _HabitColumn()),
            const SizedBox(width: _gap),
            const Expanded(flex: 9, child: TodoPanel(scope: TodoScope.today)),
            const SizedBox(width: _gap),
            Expanded(
              flex: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: TodoPanel(scope: TodoScope.week)),
                  const SizedBox(height: _gap),
                  const Expanded(child: TodoPanel(scope: TodoScope.month)),
                  const SizedBox(height: _gap),
                  Expanded(
                    child: _JournalCard(
                      key: ValueKey((dateKey(AppScope.of(context).today), AppScope.of(context).restores)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (needsScroll) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minContentWidth,
              height: constraints.maxHeight,
              child: content,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: content,
        );
      },
    );
  }
}

/// The rituals' card with the sleep schedule's below it. Their rows share
/// the column's height evenly, so rows are the same height in both.
class _HabitColumn extends StatelessWidget {
  const _HabitColumn();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rituals = state.habits, sleep = state.sleepHabits;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = constraints.maxHeight - 2 * _HabitsCard.chrome - TodayView._gap;
        final count = rituals.length + sleep.length;
        final share = count == 0 ? _HabitsCard._maxRow : rows / count;
        final sleepHeight = _HabitsCard.chrome + sleep.length * share.clamp(_HabitsCard._minRow, _HabitsCard._maxRow);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _HabitsCard(title: 'Daily rituals', habits: rituals, allDone: 'Every ritual done. Beautiful.'),
            ),
            const SizedBox(height: TodayView._gap),
            SizedBox(
              height: sleepHeight,
              child: _HabitsCard(title: 'Sleep schedule', habits: sleep, allDone: 'Schedule kept. Sleep well.'),
            ),
          ],
        );
      },
    );
  }
}

class _HabitsCard extends StatelessWidget {
  const _HabitsCard({required this.title, required this.habits, required this.allDone});

  final String title;
  final List<Habit> habits;

  /// The line under the title once every one is done.
  final String allDone;

  /// The card's height less its rows: padding, header and gap.
  static const chrome = 22.0 + 60 + 10 + 12;

  static const _minRow = 34.0, _maxRow = 52.0;

  /// Rows share the card's height, 34 to 52px each, and scroll only below
  /// that. A name too long for one line wraps, and its row grows to fit,
  /// taking the space from the others. If that would make the list scroll,
  /// the week trails make way to give the names more room.
  static ({List<double> heights, double cell, bool trail}) _layOutRows(
    BuildContext context,
    List<Habit> habits,
    BoxConstraints constraints,
  ) {
    if (habits.isEmpty) return (heights: const [], cell: 32, trail: false);
    final width = constraints.maxWidth, height = constraints.maxHeight;
    final cell = (height / habits.length).clamp(_minRow, _maxRow) - 10;
    final scaler = MediaQuery.textScalerOf(context);

    ({List<double> heights, double cell, bool trail}) layOut({required bool trail}) {
      // Everything else in a row is a fixed width; the name gets the rest.
      final nameWidth = width - _HabitRow.fixedWidth - (trail ? _HabitRow.weekTrailWidth : 0) - cell.clamp(24, 32);
      double rowFor(String name) {
        final painter = TextPainter(
          text: TextSpan(text: name, style: _HabitRow.nameStyle),
          maxLines: _HabitRow.nameLines,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: nameWidth.clamp(0, double.infinity));
        final textHeight = painter.height;
        painter.dispose();
        return textHeight + 14;
      }

      final needed = [for (final h in habits) rowFor(h.name)];
      // Tall rows take what they need; the rest share what's left. Each
      // round can only shrink the share, so a few rounds settle it.
      var extent = (height / habits.length).clamp(_minRow, _maxRow);
      for (var round = 0; round < 3; round++) {
        final tall = [
          for (final n in needed)
            if (n > extent) n,
        ];
        if (tall.length == habits.length) break;
        final left = height - tall.fold(0.0, (a, b) => a + b);
        final share = (left / (habits.length - tall.length)).clamp(_minRow, _maxRow);
        if (share == extent) break;
        extent = share;
      }
      return (
        heights: [for (final n in needed) n > extent ? n : extent],
        cell: (extent - 10).clamp(24.0, 32.0),
        trail: trail,
      );
    }

    final withTrail = layOut(trail: width >= _HabitRow.weekTrailFrom);
    if (!withTrail.trail || withTrail.heights.fold(0.0, (a, b) => a + b) <= height + 0.5) return withTrail;
    return layOut(trail: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final day = state.today;
    final done = state.doneOn(day, habits);
    final total = habits.length;
    final subtitle = done == total && total > 0
        ? allDone
        : state.isRestDay(day)
        ? 'Rest day. Nothing you have to do.'
        : '${total - done} still to go today';

    return Tile(
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TileHeader(title: title),
                    const SizedBox(height: 6),
                    // Cross-fades when the line changes, left-aligned so the
                    // old and new lines share their start.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      child: Text(
                        subtitle,
                        key: ValueKey(subtitle),
                        style: TextStyle(fontFamily: Fonts.body, fontSize: 13, color: p.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              ProgressRing(done: done, total: total, size: 60),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rows = _layOutRows(context, habits, constraints);
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtentBuilder: (i, _) => i < total ? rows.heights[i] : null,
                  itemCount: total,
                  itemBuilder: (context, i) =>
                      _HabitRow(habit: habits[i], day: day, cellSize: rows.cell, weekTrail: rows.trail, divider: i > 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades a highlight in behind [child] on hover, as the month grid's rows
/// do. Only the highlight and divider repaint; [child] is never rebuilt.
class _HoverHighlight extends StatefulWidget {
  const _HoverHighlight({required this.divider, required this.child});

  final bool divider;
  final Widget child;

  @override
  State<_HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<_HoverHighlight> {
  static const _fade = Duration(milliseconds: 140);

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        // The list gives each row a fixed height; the row fills it.
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: _fade,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.empty.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
          // The divider fades out as the highlight fades in, rather than
          // swapping borders mid-animation.
          if (widget.divider)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 0 : 1,
                  duration: _fade,
                  child: ColoredBox(color: p.tileBorder.withValues(alpha: 0.5), child: const SizedBox(height: 1)),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.habit,
    required this.day,
    required this.cellSize,
    required this.weekTrail,
    required this.divider,
  });

  static const nameStyle = TextStyle(fontFamily: Fonts.body, fontSize: 13.5, fontWeight: FontWeight.w500);

  /// Long names wrap onto up to this many lines before they're cut short.
  static const nameLines = 3;

  /// Rows at least this wide show the last week's marks.
  static const weekTrailFrom = 240.0;
  static const weekTrailWidth = 10.0 + 7 * (6 + 3);

  /// Padding, gaps and the streak badge: the row less its name, week trail
  /// and square.
  static const fixedWidth = 2 * 8.0 + 8 + 44 + 8;

  final Habit habit;
  final DateTime day;
  final double cellSize;

  /// Whether to show the last week's marks (the card decides, for all rows).
  final bool weekTrail;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final streak = state.currentStreak(habit);
    final best = state.bestStreak(habit);

    return _HoverHighlight(
      divider: divider,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: habit.description ?? habit.name,
                waitDuration: const Duration(milliseconds: 300),
                // The whole height of the row, not just the line of text,
                // so the tooltip is easy to catch.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    habit.name,
                    maxLines: nameLines,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle.copyWith(color: p.ink),
                  ),
                ),
              ),
            ),
            if (weekTrail) ...[
              const SizedBox(width: 10),
              _WeekTrail(habit: habit, day: day),
            ],
            const SizedBox(width: 8),
            Tooltip(
              message: streak == 0
                  ? (best > 0 ? 'Best streak: $best days' : 'No streak yet')
                  : '$streak day streak${best > streak ? '  ·  best $best' : ''}',
              child: SizedBox(
                width: 44,
                // A new streak count (or none) cross-fades with a slight pop.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(anim), child: child),
                  ),
                  child: streak > 0
                      ? Container(
                          key: ValueKey(streak),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_fire_department_rounded, size: 12, color: p.accent),
                              const SizedBox(width: 1.5),
                              Text(
                                '$streak',
                                style: TextStyle(
                                  fontFamily: Fonts.ui,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          '–',
                          key: const ValueKey(0),
                          style: TextStyle(
                            fontSize: 13,
                            color: p.inkMuted.withValues(alpha: 0.4),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            StatusCell(day: day, habit: habit, size: cellSize, rest: state.isRestDay(day)),
          ],
        ),
      ),
    );
  }
}

/// Seven small marks for the last week, oldest first.
class _WeekTrail extends StatelessWidget {
  const _WeekTrail({required this.habit, required this.day});

  final Habit habit;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Row(
      children: [
        for (var i = 7; i >= 1; i--) _mark(p, state, DateTime(day.year, day.month, day.day - i)),
      ],
    );
  }

  // A rest day's blank mark fades rather than snapping; the colour itself
  // is read from the palette every frame, so it follows a theme change.
  Widget _mark(Palette p, AppState state, DateTime past) {
    final status = state.statusOf(past, habit);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: state.isRestDay(past) ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, r, _) => Container(
        margin: const EdgeInsets.only(left: 3),
        width: 6,
        height: 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2.5),
          color: switch (status) {
            HabitStatus.none => p.empty.withValues(alpha: 1 - 0.55 * r),
            HabitStatus.done => p.done,
            HabitStatus.missed => p.missed.withValues(alpha: 0.75),
            HabitStatus.other => p.other,
          },
        ),
      ),
    );
  }
}

class _JournalCard extends StatefulWidget {
  const _JournalCard({super.key});

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  TextEditingController? _controller;
  late AppState _state;

  /// The day this card writes to. A new card takes over at midnight; words
  /// typed just before it still land on the day they were typed.
  late DateTime _day;

  /// Saves a moment after typing stops, rather than writing the database
  /// and the day's file on every keystroke.
  Timer? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
    if (_controller == null) {
      _day = _state.today;
      _controller = TextEditingController(text: _state.journalOf(_day));
    }
  }

  void _changed(String _) {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 400), _save);
  }

  void _save() {
    _pending?.cancel();
    _pending = null;
    _state.setJournal(_day, _controller!.text);
  }

  @override
  void dispose() {
    if (_pending != null) _save();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);

    return Tile(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileHeader(
            title: 'Journal',
            trailing: state.journalFiles == null ? null : _OpenFolderButton(state.journalFiles!.fileFor(_day)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: Fonts.body,
                fontSize: 14,
                height: 1.35,
                color: p.ink,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
              onChanged: _changed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the journal's folder in Dolphin (Finder on a Mac), with the day's
/// file selected once it exists. Each day is a Markdown file there, so
/// entries can be read and kept without the app.
class _OpenFolderButton extends StatelessWidget {
  const _OpenFolderButton(this.file);

  final File file;

  Future<void> _open() async {
    final folder = file.parent;
    await folder.create(recursive: true);
    final exists = file.existsSync();
    if (Platform.isMacOS) {
      await Process.run('open', exists ? ['-R', file.path] : [folder.path]);
    } else {
      // Detached: Dolphin keeps running after it opens, and on its own.
      await Process.start('dolphin', exists ? ['--select', file.path] : [folder.path], mode: ProcessStartMode.detached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final home = Platform.environment['HOME'];
    final shown = home != null && file.path.startsWith(home) ? '~${file.path.substring(home.length)}' : file.path;
    return Tooltip(
      message: 'Saved as $shown\nClick to show it in its folder',
      child: IconButton(
        // Small enough not to make this card's header taller than the others.
        constraints: BoxConstraints.tight(const Size.square(24)),
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: p.inkMuted.withValues(alpha: 0.8),
        onPressed: _open,
        icon: const Icon(Icons.folder_open_rounded),
      ),
    );
  }
}
