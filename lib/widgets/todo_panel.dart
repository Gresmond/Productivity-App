import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'tile.dart';

class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.scope});

  final TodoScope scope;

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Drives every row's glide to its new place when the order changes.
  /// The glide waits for the tick to fill, so the mark lands first.
  late final _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 640), value: 1);
  late final _curved = CurvedAnimation(
    parent: _slide,
    curve: const Interval(0.3, 1, curve: Curves.easeInOutCubic),
  );
  List<int> _order = const [];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _curved.dispose();
    _slide.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(AppState state) {
    if (_controller.text.trim().isEmpty) return;
    state.addTodo(widget.scope, _controller.text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final all = state.todos[widget.scope]!;
    // Ticked items gather at the top, crossed off; what's left sits below.
    final items = [...all.where((t) => t.done), ...all.where((t) => !t.done)];
    final open = all.length - all.where((t) => t.done).length;
    final order = [for (final t in items) t.id];
    if (!_sameOrder(order, _order)) {
      if (_order.isNotEmpty) {
        _generation++;
        _slide.forward(from: 0);
      }
      _order = order;
    }

    return Tile(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TileHeader(
              title: widget.scope.label,
              caption: open == 0 && items.isNotEmpty ? 'All clear' : '$open open',
            ),
          ),
          const SizedBox(height: 10),
          // Fills the card; scrolls only if the list outgrows it.
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(color: p.empty.withValues(alpha: 0.6), shape: BoxShape.circle),
                              child: Icon(Icons.wb_sunny_outlined, size: 16, color: p.inkMuted.withValues(alpha: 0.7)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All clear',
                              style: TextStyle(
                                fontFamily: Fonts.body,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: p.inkMuted.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: _SlidingColumn(
                      progress: _curved,
                      generation: _generation,
                      lift: p.tile,
                      shadow: p.shadow,
                      children: [
                        // Each row drawn once and moved as a picture while it glides.
                        for (final item in items)
                          RepaintBoundary(
                            key: ValueKey(item.id),
                            child: _TodoRow(scope: widget.scope, item: item),
                          ),
                      ],
                    ),
                  ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 6, right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            decoration: BoxDecoration(
              color: p.empty.withValues(alpha: _focus.hasFocus ? 0.65 : 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focus.hasFocus ? p.accent.withValues(alpha: 0.45) : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: _focus.hasFocus ? p.accent : p.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: TextStyle(fontFamily: Fonts.body, fontSize: 13.5, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Add a task',
                      hintStyle: TextStyle(fontFamily: Fonts.body, color: p.inkMuted.withValues(alpha: 0.65)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onSubmitted: (_) => _submit(state),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameOrder(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Stacks its children like a Column, but when they're reordered each one
/// glides from where it was drawn to its new place. Paint-only: children
/// are laid out once at their new places and only drawn somewhere else.
class _SlidingColumn extends MultiChildRenderObjectWidget {
  const _SlidingColumn({
    required this.progress,
    required this.generation,
    required this.lift,
    required this.shadow,
    required super.children,
  });

  /// Runs 0 to 1 for each reorder.
  final Animation<double> progress;

  /// Goes up by one with each reorder, so every row restarts from where it
  /// is on screen, even one still moving from the last change.
  final int generation;

  /// The card colour under a row that's lifted while it glides, and its shadow.
  final Color lift, shadow;

  @override
  _RenderSlidingColumn createRenderObject(BuildContext context) =>
      _RenderSlidingColumn(progress, generation, lift, shadow);

  @override
  void updateRenderObject(BuildContext context, _RenderSlidingColumn renderObject) => renderObject
    ..progress = progress
    ..generation = generation
    ..lift = lift
    ..shadow = shadow;
}

class _SlideParentData extends ContainerBoxParentData<RenderBox> {
  double? target;
  double? from;
  double? painted;
}

class _RenderSlidingColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlideParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlideParentData> {
  _RenderSlidingColumn(this._progress, this._generation, this._lift, this._shadow);

  Color _lift, _shadow;
  set lift(Color value) {
    if (value == _lift) return;
    _lift = value;
    markNeedsPaint();
  }

  set shadow(Color value) {
    if (value == _shadow) return;
    _shadow = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (value == _progress) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  int _generation;
  int? _laidOutFor;
  set generation(int value) {
    if (value == _generation) return;
    _generation = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlideParentData) child.parentData = _SlideParentData();
  }

  @override
  void performLayout() {
    final restart = _laidOutFor != null && _laidOutFor != _generation;
    _laidOutFor = _generation;
    var y = 0.0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _SlideParentData;
      child.layout(BoxConstraints.tightFor(width: constraints.maxWidth), parentUsesSize: true);
      // A new row starts in place; a moved one from where it was last drawn.
      data.from = restart ? (data.painted ?? y) : (data.from ?? y);
      data.target = y;
      y += child.size.height;
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(constraints.maxWidth, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final t = _progress.value;
    // The row going furthest (the one just ticked) rides above the rest on
    // the card's colour, so rows never show through each other as they pass.
    var furthest = 0.0;
    for (var child = firstChild; child != null; child = (child.parentData! as _SlideParentData).nextSibling) {
      final data = child.parentData! as _SlideParentData;
      furthest = math.max(furthest, (data.target! - data.from!).abs());
    }
    final lifted = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _SlideParentData;
      final distance = (data.target! - data.from!).abs();
      final y = t >= 1 ? data.target! : data.from! + (data.target! - data.from!) * t;
      if (t >= 1) data.from = data.target;
      data.painted = y;
      // Hit testing and tooltips follow the row to where it's drawn.
      data.offset = Offset(0, y);
      if (t < 1 && distance > 0.5 && distance == furthest) {
        lifted.add(child);
      } else {
        context.paintChild(child, offset + data.offset);
      }
      child = data.nextSibling;
    }
    final rise = math.sin(math.pi * t);
    for (final row in lifted) {
      final rect = (offset + (row.parentData! as _SlideParentData).offset) & row.size;
      final rrect = RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(10));
      final shadow = BoxShadow(
        color: _shadow.withValues(alpha: 0.14 * rise),
        blurRadius: 12,
        offset: const Offset(0, 3),
      );
      context.canvas
        ..drawRRect(rrect.shift(shadow.offset), shadow.toPaint())
        ..drawRRect(rrect, Paint()..color = _lift);
      context.paintChild(row, rect.topLeft);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _TodoRow extends StatefulWidget {
  const _TodoRow({required this.scope, required this.item});

  final TodoScope scope;
  final TodoItem item;

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => state.toggleTodo(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _hover ? p.empty.withValues(alpha: 0.35) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _Check(done: item.done, hover: _hover, pressed: _pressed),
              const SizedBox(width: 11),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontFamily: Fonts.body,
                    fontSize: 14,
                    height: 1.35,
                    color: item.done
                        ? p.inkMuted.withValues(alpha: p.brightness == Brightness.dark ? 0.75 : 0.7)
                        : p.ink,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    decorationColor: p.inkMuted.withValues(alpha: 0.45),
                  ),
                  child: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (item.carried > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: p.missed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 11, color: p.missed),
                      const SizedBox(width: 3),
                      Text(
                        'carried ×${item.carried}',
                        style: TextStyle(
                          fontFamily: Fonts.ui,
                          fontSize: 10.5,
                          color: p.missed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Tooltip(
                  message: 'Remove',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _hover ? () => state.removeTodo(widget.scope, item) : null,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: p.empty.withValues(alpha: 0.8)),
                        child: Icon(Icons.close_rounded, size: 14, color: p.inkMuted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round tick, animated like a ritual square: the fill blends in, the
/// tick grows in after it, and it dips when pressed and lifts on hover.
class _Check extends StatefulWidget {
  const _Check({required this.done, required this.hover, required this.pressed});

  final bool done;
  final bool hover;
  final bool pressed;

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> with TickerProviderStateMixin {
  late final _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.done ? 1 : 0,
  );
  late final _hover = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));

  @override
  void didUpdateWidget(_Check old) {
    super.didUpdateWidget(old);
    if (widget.done != old.done) {
      widget.done ? _fill.forward() : _fill.reverse();
    }
    if (widget.hover != old.hover) {
      widget.hover ? _hover.forward() : _hover.reverse();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedScale(
        scale: widget.pressed ? 0.88 : (widget.hover ? 1.06 : 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          size: const Size.square(20),
          painter: _CheckPainter(fill: _fill, hover: _hover, palette: context.palette),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.fill, required this.hover, required this.palette})
    : super(repaint: Listenable.merge([fill, hover]));

  final Animation<double> fill;
  final Animation<double> hover;
  final Palette palette;

  static TextPainter? _tick;
  static Color? _tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final t = Curves.easeOutCubic.transform(fill.value);
    final h = hover.value;
    final centre = size.center(Offset.zero);
    final r = size.width / 2;

    if (t > 0) {
      final shadow = BoxShadow(
        color: p.done.withValues(alpha: (0.3 + 0.1 * h) * t),
        blurRadius: 6,
        offset: const Offset(0, 2),
      );
      canvas.drawCircle(centre + shadow.offset, r, shadow.toPaint());
    }
    // The ring fades as the fill arrives, so there's never a hard swap.
    final ring = Color.lerp(p.inkMuted.withValues(alpha: 0.38), p.accent.withValues(alpha: 0.6), h)!;
    canvas.drawCircle(
      centre,
      r - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ring.withValues(alpha: ring.a * (1 - t)),
    );
    if (t > 0) {
      canvas.drawCircle(centre, r, Paint()..color = p.done.withValues(alpha: t));
    }

    // The tick grows in over the second half, as on a ritual square.
    final into = Curves.easeInOutSine.transform(((fill.value - 0.45) / 0.55).clamp(0.0, 1.0));
    if (into > 0) {
      if (_tick == null || _tickColor != p.onAccent) {
        _tickColor = p.onAccent;
        _tick = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(Icons.check_rounded.codePoint),
            style: TextStyle(fontFamily: Icons.check_rounded.fontFamily, fontSize: 13, height: 1, color: p.onAccent),
          ),
        )..layout();
      }
      final g = _tick!;
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: into));
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(0.6 + 0.4 * into);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.palette != palette || old.fill != fill || old.hover != hover;
}
