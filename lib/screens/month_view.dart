import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/fade_through.dart';
import '../widgets/status_cell.dart';
import '../widgets/tile.dart';

/// The spreadsheet grid: habits down the side, days across the top.
class MonthView extends StatefulWidget {
  const MonthView({super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  static const _nameWidth = 260.0;

  bool _editing = false;

  @override
  void didUpdateWidget(MonthView old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year || old.month != widget.month) _editing = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final (year, month) = (widget.year, widget.month);
    final future = state.isFutureMonth(year, month);
    final habits = state.habitsFor(year, month);
    final label = future
        ? 'PREVIEW  ·  COPIES YOUR LATEST RITUALS'
        : state.isPreviewMonth(year, month)
            ? 'PREVIEW  ·  SAVED WHEN YOU TICK OR EDIT'
            : 'RITUALS  ·  ${habits.length}';

    final Widget body;
    if (_editing) {
      body = _RitualEditor(year: year, month: month);
    } else if (habits.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No rituals yet. Add some with Edit rituals.',
            style: TextStyle(fontFamily: Fonts.body, fontSize: 16, color: p.inkMuted),
          ),
        ),
      );
    } else {
      body = _Grid(year: year, month: month, habits: habits, nameWidth: _nameWidth);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FadeThrough(
                  duration: const Duration(milliseconds: 260),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w500, color: p.inkMuted),
                  ),
                ),
                const Spacer(),
                if (!future)
                  _PillButton(
                    label: _editing ? 'Done' : 'Edit rituals',
                    icon: _editing ? Icons.check_rounded : Icons.edit_outlined,
                    filled: _editing,
                    onTap: () => setState(() => _editing = !_editing),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            // The card stays still; only what's inside fades, and its height
            // eases when the new month has a different number of rituals.
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              child: FadeThrough(
                layoutBuilder: FadeThrough.sizeToCurrent,
                child: KeyedSubtree(key: ValueKey((year, month, _editing, habits.isEmpty)), child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.year, required this.month, required this.habits, required this.nameWidth});

  final int year;
  final int month;
  final List<Habit> habits;
  final double nameWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final days = [for (var d = 1; d <= daysInMonth(year, month); d++) DateTime(year, month, d)];

    var done = 0, logged = 0;
    for (final day in days) {
      for (final h in habits) {
        final s = state.statusOf(day, h);
        if (s != HabitStatus.none) logged++;
        if (s == HabitStatus.done) done++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalDays = days.length;
        const minCol = 22.0;
        final minGridWidth = nameWidth + totalDays * minCol;
        final needsScroll = constraints.maxWidth < minGridWidth;

        final availableWidth = needsScroll ? minGridWidth : constraints.maxWidth;
        final col = ((availableWidth - nameWidth) / totalDays).clamp(20.0, 40.0);
        final cell = col - 6;

        Widget grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: nameWidth),
                for (final day in days) _DayHeader(day: day, width: col, isToday: day == state.today),
              ],
            ),
            const SizedBox(height: 10),
            for (final h in habits)
              _MonthHabitRow(
                habit: h,
                days: days,
                nameWidth: nameWidth,
                colWidth: col,
                cellSize: cell,
                today: state.today,
              ),
            const SizedBox(height: 26),
            Row(
              children: [
                _Legend(color: p.done, label: 'Done', icon: Icons.check_rounded),
                _Legend(color: p.missed, label: 'Not done', icon: Icons.close_rounded),
                _Legend(color: p.other, label: 'Other', icon: Icons.remove_rounded),
                const Spacer(),
                if (logged > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.empty.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.tileBorder.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(done * 100 / logged).round()}%',
                          style: TextStyle(
                            fontFamily: Fonts.display,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'of logged rituals done',
                          style: TextStyle(
                            fontFamily: Fonts.ui,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: p.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );

        if (needsScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minGridWidth,
              child: grid,
            ),
          );
        }

        return grid;
      },
    );
  }
}

class _MonthHabitRow extends StatefulWidget {
  const _MonthHabitRow({
    required this.habit,
    required this.days,
    required this.nameWidth,
    required this.colWidth,
    required this.cellSize,
    required this.today,
  });

  final Habit habit;
  final List<DateTime> days;
  final double nameWidth;
  final double colWidth;
  final double cellSize;
  final DateTime today;

  @override
  State<_MonthHabitRow> createState() => _MonthHabitRowState();
}

class _MonthHabitRowState extends State<_MonthHabitRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        decoration: BoxDecoration(
          color: _hover ? p.empty.withValues(alpha: 0.35) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: widget.nameWidth,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  widget.habit.name,
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
            for (final day in widget.days)
              SizedBox(
                width: widget.colWidth,
                child: Center(
                  child: StatusCell(
                    day: day,
                    habit: widget.habit,
                    size: widget.cellSize,
                    enabled: !day.isAfter(widget.today),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rename, reorder, remove and add rituals for one month.
class _RitualEditor extends StatefulWidget {
  const _RitualEditor({required this.year, required this.month});

  final int year;
  final int month;

  @override
  State<_RitualEditor> createState() => _RitualEditorState();
}

class _RitualEditorState extends State<_RitualEditor> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final (year, month) = (widget.year, widget.month);
    final habits = state.habitsFor(year, month);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => state.reorderHabit(year, month, from, to),
            proxyDecorator: (child, _, _) => Material(
              color: p.tile,
              elevation: 6,
              shadowColor: p.shadow.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
            children: [
              for (final (i, h) in habits.indexed)
                _EditableRow(key: ValueKey(h.id), index: i, year: year, month: month, habit: h),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: p.empty.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.tileBorder.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _add,
                    focusNode: _addFocus,
                    style: TextStyle(fontFamily: Fonts.body, fontSize: 14, color: p.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Add a ritual to ${monthNames[month - 1]}',
                      hintStyle: TextStyle(
                        fontFamily: Fonts.body,
                        color: p.inkMuted.withValues(alpha: 0.7),
                      ),
                    ),
                    onSubmitted: (v) {
                      state.addHabit(year, month, v);
                      _add.clear();
                      _addFocus.requestFocus();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Changes apply to ${monthNames[month - 1]} only. Each new month starts as a copy of the one before.',
            style: TextStyle(fontFamily: Fonts.body, fontSize: 13, color: p.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _EditableRow extends StatefulWidget {
  const _EditableRow({
    super.key,
    required this.index,
    required this.year,
    required this.month,
    required this.habit,
  });

  final int index;
  final int year;
  final int month;
  final Habit habit;

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  late final _controller = TextEditingController(text: widget.habit.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.empty.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.tileBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator_rounded, size: 18, color: p.inkMuted.withValues(alpha: 0.6)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(fontFamily: Fonts.body, fontSize: 14, color: p.ink),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              onChanged: (v) => state.renameHabit(widget.year, widget.month, widget.habit, v),
            ),
          ),
          IconButton(
            tooltip: 'Remove from ${monthNames[widget.month - 1]}',
            iconSize: 18,
            color: p.missed,
            onPressed: () => state.removeHabit(widget.year, widget.month, widget.habit),
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.icon, required this.onTap, this.filled = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = filled ? p.onAccent : p.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: filled ? LinearGradient(colors: p.gradient) : null,
            border: filled ? null : Border.all(color: p.tileBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.width, required this.isToday});

  final DateTime day;
  final double width;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final weekend = day.weekday >= DateTime.saturday;
    final fg = isToday ? p.onAccent : (weekend ? p.other : p.inkMuted);
    return SizedBox(
      width: width,
      child: Center(
        child: RepaintBoundary(
          child: Container(
            width: width - 4,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: isToday
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: p.gradient.take(2).toList(),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: p.gradient.first.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  )
                : null,
            child: Column(
              children: [
                Text(
                  weekdayNames[day.weekday - 1][0],
                  style: TextStyle(
                    fontFamily: Fonts.ui,
                    fontSize: 10,
                    color: fg.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontFamily: Fonts.ui,
                    fontSize: 12.5,
                    color: isToday ? p.onAccent : p.ink,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: icon == null
                ? null
                : Center(child: Icon(icon, size: 10, color: p.onAccent)),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: Fonts.ui,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: p.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
