import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import 'fade_through.dart';

/// The parts of the app the welcome tour points at.
enum TourSpot { rituals, sleep, todayTodos, laterTodos, journal, date, tabs, appearance }

/// Marks [child] as [spot] for the welcome tour to find. Several may share
/// a spot; the tour lights them up as one.
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.spot, required this.child});

  final TourSpot spot;
  final Widget child;

  static final _mounted = <TourSpot, Set<_TourTargetState>>{};

  /// The box round every laid-out [spot], in [ancestor]'s coordinates;
  /// null when there's none.
  static Rect? rectOf(TourSpot spot, RenderBox ancestor) {
    Rect? rect;
    for (final target in _mounted[spot] ?? const <_TourTargetState>{}) {
      final box = target.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
      rect = rect?.expandToInclude(r) ?? r;
    }
    return rect;
  }

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  @override
  void initState() {
    super.initState();
    TourTarget._mounted.putIfAbsent(widget.spot, () => {}).add(this);
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.spot == widget.spot) return;
    TourTarget._mounted[old.spot]?.remove(this);
    TourTarget._mounted.putIfAbsent(widget.spot, () => {}).add(this);
  }

  @override
  void dispose() {
    TourTarget._mounted[widget.spot]?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Step {
  const _Step(this.title, this.body, [this.spot]);

  final String title, body;

  /// What it lights up; null for a card in the middle of the window.
  final TourSpot? spot;
}

List<_Step> _steps(AppState state) => [
  const _Step(
    'Welcome to Eclipse!',
    'A calm home for your daily rituals, your to-dos and a few lines of journal. '
        'Here is a quick look round the basics.',
  ),
  const _Step(
    'Daily rituals',
    'Click a square to mark a ritual done. Click again for not done, and once more '
        'for other, which asks for a short note. Right-click clears it. Done days '
        'build each streak and fill the ring.',
    TourSpot.rituals,
  ),
  const _Step(
    'Sleep schedule',
    'Four habits for winding down, ticked the same way, with a ring of their own. '
        'Hover one to read what it asks of you.',
    TourSpot.sleep,
  ),
  const _Step(
    "Today's to-dos",
    'Type a task and press Enter, then tick it off when it is done. Anything left '
        'unfinished carries on to tomorrow, marked with the day it came from.',
    TourSpot.todayTodos,
  ),
  const _Step(
    'This week and this month',
    'For the things with a little more time. Unfinished ones carry on into the next '
        'week or month in the same way.',
    TourSpot.laterTodos,
  ),
  const _Step(
    'Journal',
    'A few lines about the day. It saves as you type, and the folder button opens '
        "the day's file.",
    TourSpot.journal,
  ),
  const _Step('Looking back', 'Click the date to open any past day and see how it went.', TourSpot.date),
  const _Step(
    'Months and the year',
    'Each month opens the full grid of every ritual and day. Edit rituals there to '
        'change the list or give a ritual a note for that month. Year puts every '
        "month's percentages side by side.",
    TourSpot.tabs,
  ),
  _Step(
    'Appearance',
    'Pick a theme; each one comes in a light and dark pair. '
        '${state.nightLightAvailable ? 'Follow night light switches to the dark one when night light comes on. ' : ''}'
        'You can also rest on weekends, and choose whether a new day starts at midnight '
        'or 4am. This tour is in here too, whenever you want it again.',
    TourSpot.appearance,
  ),
];

/// A first look round the app: dims the window and lights up one part at a
/// time, with a card beside it. Arrow keys and Enter step through; Escape
/// skips. Shown over the whole window while [AppState.touring].
class WelcomeTour extends StatefulWidget {
  const WelcomeTour({super.key});

  @override
  State<WelcomeTour> createState() => _WelcomeTourState();
}

class _WelcomeTourState extends State<WelcomeTour> {
  var _index = 0;
  var _shown = false;
  Rect? _spot;

  static const _cardWidth = 360.0, _welcomeWidth = 420.0, _margin = 24.0, _gap = 20.0;

  @override
  void initState() {
    super.initState();
    // Fades in from nothing once the first frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  void _go(int index, int count) {
    if (index < 0) return;
    if (index >= count) return _close();
    setState(() => _index = index);
  }

  void _close() => setState(() => _shown = false);

  /// Where the current step's spot is now. Measured after layout, since the
  /// window can be resized under the tour.
  void _measure(TourSpot? spot) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rect = spot == null ? null : TourTarget.rectOf(spot, box)?.inflate(8);
      if (rect != _spot) setState(() => _spot = rect);
    });
  }

  /// The card's top-left: beside the spot where there's room, else below or
  /// above it, kept inside the window.
  Offset _cardAt(Rect? spot, double width, Size size) {
    const height = 250.0;
    if (spot == null) return Offset((size.width - width) / 2, (size.height - height) / 2 - 20);
    double clampX(double x) => x.clamp(_margin, math.max(_margin, size.width - width - _margin));
    double clampY(double y) => y.clamp(_margin, math.max(_margin, size.height - height - _margin));
    if (size.height - spot.bottom >= height + _gap + _margin) {
      return Offset(clampX(spot.right - width), spot.bottom + _gap);
    }
    if (size.width - spot.right >= width + _gap + _margin) {
      return Offset(spot.right + _gap, clampY(spot.top));
    }
    if (spot.left >= width + _gap + _margin) {
      return Offset(spot.left - _gap - width, clampY(spot.top));
    }
    return Offset(clampX(spot.left), clampY(spot.top - _gap - height));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final steps = _steps(state);
    final step = steps[_index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _measure(step.spot);
        // With no spot, the light closes to a point in the middle.
        final spot = step.spot == null ? null : _spot;
        final hole = spot ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
        final width = spot == null ? _welcomeWidth : _cardWidth;
        final at = _cardAt(spot, width, size);

        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.escape) {
              _close();
            } else if (key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) {
              _go(_index + 1, steps.length);
            } else if (key == LogicalKeyboardKey.arrowLeft) {
              _go(_index - 1, steps.length);
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: AnimatedOpacity(
            opacity: _shown ? 1 : 0,
            duration: Motion.morph,
            curve: Motion.morphCurve,
            onEnd: () {
              if (!_shown) state.endTour();
            },
            child: Stack(
              children: [
                // Takes every click, so the app underneath waits for the tour.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: TweenAnimationBuilder<Rect?>(
                      tween: RectTween(end: hole),
                      duration: Motion.morph,
                      curve: Motion.morphCurve,
                      builder: (context, rect, _) => CustomPaint(
                        painter: _SpotlightPainter(
                          hole: rect!,
                          scrim: p.brightness == Brightness.dark
                              ? const Color(0xFF000000).withValues(alpha: 0.58)
                              : p.shadow.withValues(alpha: 0.55),
                          ring: p.gradient,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: Motion.morph,
                  curve: Motion.morphCurve,
                  left: at.dx,
                  top: at.dy,
                  width: width,
                  child: _Card(
                    index: _index,
                    count: steps.length,
                    child: FadeThrough(
                      layoutBuilder: FadeThrough.sizeToCurrent,
                      child: _StepBody(
                        key: ValueKey(_index),
                        step: step,
                        welcome: _index == 0,
                        last: _index == steps.length - 1,
                        onNext: () => _go(_index + 1, steps.length),
                        onBack: _index == 0 ? null : () => _go(_index - 1, steps.length),
                        onSkip: _close,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dims everything but [hole], and rings the hole in the theme's gradient.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.scrim, required this.ring});

  final Rect hole;
  final Color scrim;
  final List<Color> ring;

  @override
  void paint(Canvas canvas, Size size) {
    // The corners shrink with the hole, so it closes to a point.
    final radius = math.min(30.0, hole.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rrect)),
      Paint()..color = scrim,
    );
    if (hole.shortestSide < 4) return;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(colors: [...ring, ring.first]).createShader(hole),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.scrim != scrim || old.ring != ring;
}

/// The tour's card: a tile with the step dots along the top.
class _Card extends StatelessWidget {
  const _Card({required this.index, required this.count, required this.child});

  final int index, count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: p.tile,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.tileBorder.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: dark ? 0.45 : 0.12),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < count; i++)
                AnimatedContainer(
                  duration: Motion.morph,
                  curve: Motion.morphCurve,
                  width: i == index ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < index ? p.done : (i == index ? null : p.empty),
                    gradient: i == index ? LinearGradient(colors: p.gradient.skip(1).toList()) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    super.key,
    required this.step,
    required this.welcome,
    required this.last,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final _Step step;
  final bool welcome, last;
  final VoidCallback onNext, onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (welcome) ...[const _EclipseMark(size: 64), const SizedBox(height: 18)],
        Text(
          step.title,
          style: TextStyle(
            fontFamily: Fonts.display,
            fontSize: welcome ? 30 : 22,
            fontWeight: FontWeight.w600,
            letterSpacing: welcome ? -0.9 : -0.5,
            height: 1.1,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          step.body,
          style: TextStyle(fontFamily: Fonts.body, fontSize: 14, height: 1.5, color: p.inkMuted),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            if (!last) _TextButton(label: welcome ? 'Skip' : 'Skip tour', onTap: onSkip),
            const Spacer(),
            if (onBack != null) ...[_TextButton(label: 'Back', onTap: onBack!), const SizedBox(width: 6)],
            _PillButton(label: welcome ? 'Show me around' : (last ? 'Get started' : 'Next'), onTap: onNext),
          ],
        ),
      ],
    );
  }
}

class _TextButton extends StatefulWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.hoverCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: p.empty.withValues(alpha: _hover ? 0.8 : 0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(fontFamily: Fonts.ui, fontSize: 13, fontWeight: FontWeight.w600, color: p.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// The step forward, filled with the theme's gradient like the other pills.
class _PillButton extends StatefulWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSlide(
          offset: Offset(0, _hover ? -0.04 : 0),
          duration: Motion.hover,
          curve: Motion.hoverCurve,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: p.gradient.skip(1).toList()),
              boxShadow: [
                BoxShadow(
                  color: p.gradient.last.withValues(alpha: _hover ? 0.35 : 0.2),
                  blurRadius: _hover ? 14 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              widget.label,
              style: TextStyle(fontFamily: Fonts.ui, fontSize: 13, fontWeight: FontWeight.w600, color: p.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's diamond ring, drawn in the theme: a dark moon, its corona in
/// the gradient, and one bright bead where the sun breaks through.
class _EclipseMark extends StatelessWidget {
  const _EclipseMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      size: Size.square(size),
      painter: _EclipsePainter(corona: p.gradient, moon: p.brightness == Brightness.dark ? p.background : p.ink),
    );
  }
}

class _EclipsePainter extends CustomPainter {
  _EclipsePainter({required this.corona, required this.moon});

  final List<Color> corona;
  final Color moon;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.34;
    final ring = Rect.fromCircle(center: c, radius: r + 3);
    canvas.drawCircle(
      c,
      r + 6,
      Paint()
        ..shader = RadialGradient(colors: [corona.last.withValues(alpha: 0.45), corona.last.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r + 14)),
    );
    canvas.drawCircle(
      c,
      r + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = SweepGradient(colors: [...corona, corona.first]).createShader(ring),
    );
    canvas.drawCircle(c, r, Paint()..color = moon);
    final bead = c + Offset.fromDirection(-math.pi / 4, r + 3);
    canvas.drawCircle(
      bead,
      9,
      Paint()
        ..shader = RadialGradient(colors: [corona.last, corona.last.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: bead, radius: 9)),
    );
    canvas.drawCircle(bead, 2.6, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_EclipsePainter old) => old.corona != corona || old.moon != moon;
}
