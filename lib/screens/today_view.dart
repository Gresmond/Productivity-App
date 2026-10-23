import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/progress_ring.dart';
import '../widgets/status_cell.dart';
import '../widgets/tile.dart';
import '../widgets/todo_panel.dart';

/// Three columns that exactly fill the window: rituals, today's to-dos, and
/// week / month / journal. Only a card whose list outgrows it scrolls.
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
            const Expanded(flex: 11, child: _HabitsCard()),
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

class _HabitsCard extends StatelessWidget {
  const _HabitsCard();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final day = state.today;
    final habits = state.habits;
    final done = state.doneOn(day);
    final total = habits.length;

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
                    const TileHeader(title: 'Daily rituals'),
                    const SizedBox(height: 6),
                    Text(
                      done == total && total > 0 ? 'Every ritual done. Beautiful.' : '${total - done} still to go today',
                      style: TextStyle(fontFamily: Fonts.body, fontSize: 13, color: p.inkMuted),
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
                // Share the height between rows; scroll only below 34px each.
                final extent = total == 0 ? 44.0 : (constraints.maxHeight / total).clamp(34.0, 52.0);
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: extent,
                  itemCount: total,
                  itemBuilder: (context, i) => _HabitRow(
                    habit: habits[i],
                    day: day,
                    cellSize: (extent - 10).clamp(24.0, 32.0),
                    divider: i > 0,
                  ),
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
  const _HabitRow({required this.habit, required this.day, required this.cellSize, required this.divider});

  final Habit habit;
  final DateTime day;
  final double cellSize;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final streak = state.currentStreak(habit);
    final best = state.bestStreak(habit);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showWeekTrail = constraints.maxWidth >= 240;

        return _HoverHighlight(
          divider: divider,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: habit.name,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      habit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Fonts.body,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: p.ink,
                      ),
                    ),
                  ),
                ),
                if (showWeekTrail) ...[
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
                    child: Center(
                      child: streak > 0
                          ? Container(
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
                              style: TextStyle(
                                fontSize: 13,
                                color: p.inkMuted.withValues(alpha: 0.4),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusCell(day: day, habit: habit, size: cellSize),
              ],
            ),
          ),
        );
      },
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
        for (var i = 7; i >= 1; i--)
          Container(
            margin: const EdgeInsets.only(left: 3),
            width: 6,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2.5),
              color: switch (state.statusOf(DateTime(day.year, day.month, day.day - i), habit)) {
                HabitStatus.none => p.empty,
                HabitStatus.done => p.done,
                HabitStatus.missed => p.missed.withValues(alpha: 0.75),
                HabitStatus.other => p.other,
              },
            ),
          ),
      ],
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final state = AppScope.of(context);
      _controller = TextEditingController(text: state.journalOf(state.today));
    }
  }

  @override
  void dispose() {
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
            trailing: state.journalFiles == null ? null : _OpenFolderButton(state.journalFiles!.fileFor(state.today)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: Fonts.serif,
                fontSize: 14.5,
                height: 1.6,
                letterSpacing: 0.1,
                color: p.ink,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
              onChanged: (v) => state.setJournal(state.today, v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the journal's folder in the file manager. Each day is a Markdown
/// file there, so entries can be read and kept without the app.
class _OpenFolderButton extends StatelessWidget {
  const _OpenFolderButton(this.file);

  final File file;

  Future<void> _open() async {
    final folder = file.parent;
    await folder.create(recursive: true);
    await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [folder.path]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final home = Platform.environment['HOME'];
    final shown = home != null && file.path.startsWith(home) ? '~${file.path.substring(home.length)}' : file.path;
    return Tooltip(
      message: 'Saved as $shown\nClick to open the folder',
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
