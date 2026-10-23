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

class _HabitRow extends StatefulWidget {
  const _HabitRow({required this.habit, required this.day, required this.cellSize, required this.divider});

  final Habit habit;
  final DateTime day;
  final double cellSize;
  final bool divider;

  @override
  State<_HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends State<_HabitRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final streak = state.currentStreak(widget.habit);
    final best = state.bestStreak(widget.habit);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showWeekTrail = constraints.maxWidth >= 240;

        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hover ? p.empty.withValues(alpha: 0.4) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: widget.divider && !_hover
                  ? Border(top: BorderSide(color: p.tileBorder.withValues(alpha: 0.5)))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: widget.habit.name,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      widget.habit.name,
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
                  _WeekTrail(habit: widget.habit, day: widget.day),
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
                StatusCell(day: widget.day, habit: widget.habit, size: widget.cellSize),
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
          const TileHeader(title: 'Journal'),
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
