import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' show OverflowBoxFit;

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
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => _build(context, c.maxHeight));

  Widget _build(BuildContext context, double height) {
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
      body = _Grid(year: year, month: month, habits: habits, nameWidth: _nameWidth, height: height);
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
                // Kept in place for future months, just faded, so the header
                // row doesn't change height between months.
                IgnorePointer(
                  ignoring: future,
                  child: AnimatedOpacity(
                    opacity: future ? 0 : 1,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    child: _PillButton(
                      label: _editing ? 'Done' : 'Edit rituals',
                      icon: _editing ? Icons.check_rounded : Icons.edit_outlined,
                      filled: _editing,
                      onTap: () => setState(() => _editing = !_editing),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // The card stays still. Moving between months morphs the grid in
            // place (see [_Grid]); only switching to the editor fades. The
            // height eases when the new month has a different number of rituals.
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              child: FadeThrough(
                layoutBuilder: FadeThrough.sizeToCurrent,
                child: KeyedSubtree(key: ValueKey((_editing, habits.isEmpty)), child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stays on screen from month to month and morphs: columns spread or close
/// up to the new number of days, squares ease to their new colours, and a
/// ritual new to this month fades in.
///
/// The morph is paint-only: each square is laid out once per change and
/// then just drawn at a new place each frame (see [_ColumnsDelegate]), so
/// even a 14 x 31 grid moves at the display's full frame rate.
class _Grid extends StatefulWidget {
  const _Grid({
    required this.year,
    required this.month,
    required this.habits,
    required this.nameWidth,
    required this.height,
  });

  final int year;
  final int month;
  final List<Habit> habits;
  final double nameWidth;

  /// The page's height: squares grow until the grid would need scrolling.
  final double height;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> with TickerProviderStateMixin {
  static const _morph = Duration(milliseconds: 420);
  static const _minCol = 22.0;
  static const _maxCell = 64.0;

  /// The page's height not taken by the grid's rows: the card's padding and
  /// header, the day headers and the legend.
  static const _chrome = 290.0;

  /// How many day columns are showing, easing between whole numbers. Column
  /// d is (shown - d + 1) of a column wide, between none and all of one.
  late final _shown = AnimationController.unbounded(
    vsync: this,
    value: daysInMonth(widget.year, widget.month).toDouble(),
  );

  /// The month shown before this one: columns it had that this month lacks
  /// keep showing its days while they close up.
  (int, int)? _previous;

  /// Rituals already on screen; any others fade in.
  Set<int> _known = {};

  /// The month the weekend bands are fading from, and the fade into this
  /// month's bands.
  (int, int)? _bandsFrom;
  late final _bands = AnimationController(vsync: this, duration: _morph, value: 1);
  late final _bandsCurved = CurvedAnimation(parent: _bands, curve: Curves.easeInOutCubic);

  @override
  void didUpdateWidget(_Grid old) {
    super.didUpdateWidget(old);
    _known = {for (final h in old.habits) h.id};
    if ((old.year, old.month) == (widget.year, widget.month)) return;
    _previous = (old.year, old.month);
    _bandsFrom = (old.year, old.month);
    _bands.forward(from: 0);
    _shown
        .animateTo(daysInMonth(widget.year, widget.month).toDouble(), duration: _morph, curve: Curves.easeInOutCubic)
        .whenCompleteOrCancel(() {
          if (mounted && _shown.value == daysInMonth(widget.year, widget.month)) setState(() => _previous = null);
        });
  }

  @override
  void dispose() {
    _bandsCurved.dispose();
    _bands.dispose();
    _shown.dispose();
    super.dispose();
  }

  /// The date in column [d] (1-based), or null when there is no column d.
  DateTime? _dayAt(int d) {
    if (d <= daysInMonth(widget.year, widget.month)) return DateTime(widget.year, widget.month, d);
    final prev = _previous;
    if (prev == null || d > daysInMonth(prev.$1, prev.$2)) return null;
    return DateTime(prev.$1, prev.$2, d);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final (year, month, habits, nameWidth) = (widget.year, widget.month, widget.habits, widget.nameWidth);
    final dayCount = daysInMonth(year, month);

    var done = 0, logged = 0;
    for (var d = 1; d <= dayCount; d++) {
      for (final h in habits) {
        final s = state.statusOf(DateTime(year, month, d), h);
        if (s != HabitStatus.none) logged++;
        if (s == HabitStatus.done) done++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double gridWidth(double days) => (nameWidth + days * _minCol).clamp(constraints.maxWidth, double.infinity);
        // Columns spread across the card. Squares are sized for a 31-day
        // month and as tall as the page allows, so they keep one size from
        // month to month and only their places animate.
        double colFor(double days) => (gridWidth(days) - nameWidth) / days;
        final width = gridWidth(dayCount.toDouble());
        final byHeight = habits.isEmpty ? _maxCell : (widget.height - _chrome) / habits.length - 5;
        final cell = [colFor(31) - 6, byHeight, _maxCell].reduce((a, b) => a < b ? a : b).clamp(_minCol - 6, _maxCell);
        final columns = [
          for (var d = 1; d <= 31; d++)
            if (_dayAt(d) case final day?) (number: d, day: day, leaving: d > dayCount),
        ];
        final layout = _ColumnLayout(shown: _shown, colFor: colFor, days: [for (final c in columns) c.number]);

        final days = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The headers are a plain row of 31 boxes, cheap enough to lay
            // out each frame, so their width follows the columns'.
            AnimatedBuilder(
              animation: _shown,
              builder: (context, _) {
                final shown = _shown.value;
                final col = colFor(shown);
                return Row(
                  children: [
                    SizedBox(width: nameWidth),
                    for (final c in columns)
                      if (shown > c.number - 1)
                        _Column(
                          width: col * (shown - c.number + 1).clamp(0.0, 1.0),
                          full: col,
                          child: _DayHeader(day: c.day, isToday: c.day == state.today, rest: state.isRestDay(c.day)),
                        ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            for (final h in habits)
              _FadeIn(
                key: ValueKey(h.id),
                animate: _known.isNotEmpty && !_known.contains(h.id),
                child: _MonthHabitRow(
                  habit: h,
                  nameWidth: nameWidth,
                  cellSize: cell,
                  layout: layout,
                  clickableDays: columns.where((c) => !c.leaving && !c.day.isAfter(state.today)).length,
                  cells: [
                    for (final c in columns)
                      IgnorePointer(
                        ignoring: c.leaving,
                        child: StatusCell(
                          day: c.day,
                          habit: h,
                          size: cell,
                          enabled: !c.leaving && !c.day.isAfter(state.today),
                          rest: state.isRestDay(c.day),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );

        Widget grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Positioned.fill(
                  left: nameWidth,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: state.restWeekends ? 1 : 0,
                      duration: _morph,
                      curve: Curves.easeInOutCubic,
                      child: CustomPaint(
                        painter: _RestBandPainter(
                          layout: layout,
                          weekend: [for (final c in columns) c.day.weekday >= DateTime.saturday],
                          was: [
                            for (final c in columns)
                              if (_bandsFrom case (final y, final m) when c.number <= daysInMonth(y, m))
                                DateTime(y, m, c.number).weekday >= DateTime.saturday
                              else
                                false,
                          ],
                          fade: _bandsCurved,
                          color: p.inkMuted.withValues(alpha: p.brightness == Brightness.dark ? 0.09 : 0.06),
                        ),
                      ),
                    ),
                  ),
                ),
                days,
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                _Legend(color: p.done, label: 'Done', icon: Icons.check_rounded),
                _Legend(color: p.missed, label: 'Not done', icon: Icons.close_rounded),
                _Legend(color: p.other, label: 'Other', icon: Icons.remove_rounded),
                const Spacer(),
                AnimatedOpacity(
                  opacity: logged > 0 ? 1 : 0,
                  duration: _morph,
                  curve: Curves.easeInOutCubic,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.empty.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.tileBorder.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: logged == 0 ? 0 : done * 100 / logged),
                          duration: _morph,
                          curve: Curves.easeInOutCubic,
                          builder: (context, percent, _) => Text(
                            '${percent.round()}%',
                            style: TextStyle(
                              fontFamily: Fonts.display,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: p.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
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
                ),
              ],
            ),
          ],
        );

        if (width > constraints.maxWidth) {
          grid = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: grid),
          );
        }
        return grid;
      },
    );
  }
}

/// Where the day columns are at this moment of a morph.
class _ColumnLayout {
  const _ColumnLayout({required this.shown, required this.colFor, required this.days});

  final Animation<double> shown;

  /// Column width for a (fractional) number of columns.
  final double Function(double days) colFor;

  /// The day number (1-31) of each column, in order.
  final List<int> days;

  double get col => colFor(shown.value);

  /// How much of column [d] is showing, 0 to 1.
  double fraction(int d) => (shown.value - d + 1).clamp(0.0, 1.0);
}

/// One day's header box at [width], drawn at its [full] width and clipped,
/// so a column closing up hides its header rather than squashing it.
class _Column extends StatelessWidget {
  const _Column({required this.width, required this.full, required this.child});

  final double width;
  final double full;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fraction = width / full;
    return SizedBox(
      width: width,
      child: ClipRect(
        clipBehavior: fraction < 1 ? Clip.hardEdge : Clip.none,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: full,
          maxWidth: full,
          fit: OverflowBoxFit.deferToChild,
          child: Opacity(opacity: Curves.easeIn.transform(fraction.clamp(0.0, 1.0)), child: child),
        ),
      ),
    );
  }
}

/// Draws one row's squares in their columns. Laid out once; each frame of
/// a morph only moves them, so nothing is rebuilt or measured again.
class _ColumnsDelegate extends FlowDelegate {
  _ColumnsDelegate(this.layout, this.height) : super(repaint: layout.shown);

  final _ColumnLayout layout;
  final double height;

  @override
  Size getSize(BoxConstraints constraints) => Size(constraints.maxWidth, height);

  // The same loose box every time, so a square never needs laying out
  // again while its column moves.
  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.loose(const Size.square(_GridState._maxCell));

  @override
  void paintChildren(FlowPaintingContext context) {
    final col = layout.col;
    for (var i = 0; i < context.childCount; i++) {
      final d = layout.days[i];
      final fraction = layout.fraction(d);
      if (fraction == 0) continue;
      final size = context.getChildSize(i)!;
      context.paintChild(
        i,
        transform: Matrix4.translationValues(
          (d - 1) * col + (col - size.width) / 2,
          (height - size.height) / 2,
          0,
        ),
        opacity: Curves.easeIn.transform(fraction),
      );
    }
  }

  @override
  bool shouldRelayout(_ColumnsDelegate old) => old.height != height;

  @override
  bool shouldRepaint(_ColumnsDelegate old) => true;
}

/// The hover highlight behind a row's squares, from the first square to
/// the last one that can be clicked, following the columns as they move.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.layout,
    required this.clickableDays,
    required this.cellSize,
    required this.color,
  }) : super(repaint: layout.shown);

  static const pad = 3.0;

  final _ColumnLayout layout;
  final int clickableDays;
  final double cellSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (clickableDays == 0) return;
    final col = layout.col;
    final inset = (col - cellSize) / 2;
    final clickable = clickableDays.clamp(0, layout.shown.value) * col;
    final rect = Rect.fromLTWH(inset - pad, 0, clickable - 2 * inset + 2 * pad, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.28 + pad)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.clickableDays != clickableDays || old.cellSize != cellSize || old.color != color || old.layout != layout;
}

/// A soft band down each run of weekend columns, behind the day headers and
/// squares, marking them as rest days. Follows the columns through a morph.
class _RestBandPainter extends CustomPainter {
  _RestBandPainter({
    required this.layout,
    required this.weekend,
    required this.was,
    required this.fade,
    required this.color,
  }) : super(repaint: Listenable.merge([layout.shown, fade]));

  final _ColumnLayout layout;

  /// Whether each of the layout's columns falls on a weekend, this month
  /// and in the month being left; [fade] runs from the old bands to these.
  final List<bool> weekend;
  final List<bool> was;
  final Animation<double> fade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = fade.value;
    if (t < 1) _bands(canvas, size, was, color.withValues(alpha: color.a * (1 - t)));
    if (t > 0) _bands(canvas, size, weekend, color.withValues(alpha: color.a * t));
  }

  void _bands(Canvas canvas, Size size, List<bool> weekend, Color color) {
    final col = layout.col;
    final paint = Paint()..color = color;
    double? start;
    var end = 0.0;
    void band() {
      if (start == null || end - start < 4) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(start + 1, -4, end - 1, size.height + 4), const Radius.circular(12)),
        paint,
      );
    }

    for (final (i, d) in layout.days.indexed) {
      final width = col * layout.fraction(d);
      if (weekend[i] && width > 0) {
        start ??= (d - 1) * col;
        end = (d - 1) * col + width;
      } else {
        band();
        start = null;
      }
    }
    band();
  }

  @override
  bool shouldRepaint(_RestBandPainter old) =>
      old.layout != layout ||
      old.color != color ||
      old.fade != fade ||
      !listEquals(old.weekend, weekend) ||
      !listEquals(old.was, was);
}

/// Fades and grows its child in when first built, if [animate].
class _FadeIn extends StatefulWidget {
  const _FadeIn({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.animate ? 0 : 1,
  )..forward();
  late final _curved = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _curved, child: widget.child),
    );
  }
}

class _MonthHabitRow extends StatefulWidget {
  const _MonthHabitRow({
    required this.habit,
    required this.cells,
    required this.layout,
    required this.clickableDays,
    required this.nameWidth,
    required this.cellSize,
  });

  final Habit habit;

  /// This ritual's square in each column of [layout].
  final List<Widget> cells;
  final _ColumnLayout layout;

  /// How many squares, from the first, can be clicked (days after today can't).
  final int clickableDays;
  final double nameWidth;
  final double cellSize;

  @override
  State<_MonthHabitRow> createState() => _MonthHabitRowState();
}

class _MonthHabitRowState extends State<_MonthHabitRow> {
  bool _hover = false;

  /// Lit only while the pointer is over the squares that can be clicked,
  /// not the empty part of the row past them.
  void _setHover(double? x) {
    final layout = widget.layout;
    final hover = x != null && x < widget.clickableDays.clamp(0, layout.shown.value) * layout.col;
    if (hover != _hover) setState(() => _hover = hover);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const pad = _HighlightPainter.pad;
    final height = widget.cellSize + 5;

    return Row(
      children: [
        SizedBox(
          width: widget.nameWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            // A long name wraps onto a second line, set a little tighter so
            // the row barely grows.
            child: Tooltip(
              message: widget.habit.name,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(
                widget.habit.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Fonts.body,
                  fontSize: 13.5,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                ),
              ),
            ),
          ),
        ),
        // Only the squares light up on hover, not the ritual's name.
        Expanded(
          child: MouseRegion(
            onHover: (e) => _setHover(e.localPosition.dx),
            onExit: (_) => _setHover(null),
            child: Stack(
              children: [
                Positioned.fill(
                  top: 2.5 - pad + 1,
                  bottom: 2.5 - pad + 1,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 140),
                      child: CustomPaint(
                        painter: _HighlightPainter(
                          layout: widget.layout,
                          clickableDays: widget.clickableDays,
                          cellSize: widget.cellSize,
                          color: p.empty.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                Flow(
                  delegate: _ColumnsDelegate(widget.layout, height),
                  clipBehavior: Clip.none,
                  children: widget.cells,
                ),
              ],
            ),
          ),
        ),
      ],
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
  late String _before = widget.habit.name;

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
            // Renames as you type, but a ritual can't be blank: leaving the
            // field empty puts back the name it had before you started.
            child: Focus(
              onFocusChange: (focused) {
                if (focused) {
                  _before = _controller.text;
                } else if (_controller.text.trim().isEmpty) {
                  _controller.text = _before;
                  state.renameHabit(widget.year, widget.month, widget.habit, _before);
                }
              },
              child: TextField(
                controller: _controller,
                style: TextStyle(fontFamily: Fonts.body, fontSize: 14, color: p.ink),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                onChanged: (v) => state.renameHabit(widget.year, widget.month, widget.habit, v),
              ),
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
  const _DayHeader({required this.day, required this.isToday, required this.rest});

  final DateTime day;
  final bool isToday;

  /// A weekend shown as a rest day: greyed.
  final bool rest;

  static const _morph = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final weekend = day.weekday >= DateTime.saturday;
    final letter = weekdayNames[day.weekday - 1][0];
    // Fills its column (less a small gap), so it follows the column's
    // width through a morph without being rebuilt.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: RepaintBoundary(
          // Each column keeps its day number from month to month; only the
          // weekday letter and the today marker change, and both ease.
          // Only whether this is today, and whether it's a rest day, are
          // animated; the colours are read from the palette every frame, so
          // they follow a theme cross-fade exactly instead of trailing it.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: rest ? 1 : 0),
            duration: _morph,
            curve: Curves.easeInOutCubic,
            builder: (context, r, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: isToday ? 1 : 0),
              duration: _morph,
              curve: Curves.easeInOutCubic,
              builder: (context, t, _) {
                final letterFg = Color.lerp(weekend ? p.other : p.inkMuted, p.inkMuted.withValues(alpha: 0.6), r)!;
                final numberFg = Color.lerp(p.ink, p.inkMuted.withValues(alpha: 0.75), r)!;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: p.today.withValues(alpha: t),
                    boxShadow: [
                      BoxShadow(
                        color: p.today.withValues(alpha: 0.35 * t),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // The new letter rolls up into place as the old one rolls
                      // out above it, rather than every letter blinking out at once.
                      // Clipped to one line, so the two never show stacked.
                      AnimatedSwitcher(
                        duration: _morph,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        layoutBuilder: (current, previous) =>
                            ClipRect(child: Stack(alignment: Alignment.center, children: [...previous, ?current])),
                        transitionBuilder: (child, anim) => SlideTransition(
                          position: Tween(
                            begin: Offset(0, child.key == ValueKey(letter) ? 1 : -1),
                            end: Offset.zero,
                          ).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Text(
                          letter,
                          key: ValueKey(letter),
                          style: TextStyle(
                            fontFamily: Fonts.ui,
                            fontSize: 10,
                            color: Color.lerp(letterFg, p.onAccent, t)!.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontFamily: Fonts.ui,
                          fontSize: 12.5,
                          color: Color.lerp(numberFg, p.onAccent, t),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              },
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
