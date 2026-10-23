import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gradient arc showing how many of today's habits are done. When the last
/// one is ticked, the closed ring is washed in the done colour from the top
/// while it gives a small bounce, and stays that colour until one is unticked.
class ProgressRing extends StatefulWidget {
  const ProgressRing({super.key, required this.done, required this.total, this.size = 92});

  final int done;
  final int total;
  final double size;

  bool get complete => total > 0 && done == total;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing> with TickerProviderStateMixin {
  /// The celebration: the arc closes over the first half, then the wash and
  /// bounce play over the second.
  late final _celebrate = AnimationController(vsync: this, duration: Motion.morph * 2);

  /// How strongly the done colour shows; eases out when one is unticked.
  late final _solid = AnimationController(vsync: this, duration: Motion.click);

  static const _wash = Interval(0.5, 0.95, curve: Curves.easeInOutCubic);
  static const _bounce = Interval(0.5, 1.0, curve: Curves.easeInOutSine);

  @override
  void initState() {
    super.initState();
    // Already complete when it first appears: just show it, no celebration.
    if (widget.complete) {
      _celebrate.value = 1;
      _solid.value = 1;
    }
  }

  @override
  void didUpdateWidget(ProgressRing old) {
    super.didUpdateWidget(old);
    if (widget.complete == old.complete) return;
    if (widget.complete) {
      _solid.value = 1;
      _celebrate.forward(from: 0);
    } else {
      _solid.animateBack(0, curve: Motion.clickCurve);
    }
  }

  @override
  void dispose() {
    _celebrate.dispose();
    _solid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = widget.size;
    final target = widget.total == 0 ? 0.0 : widget.done / widget.total;
    final label = Center(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${widget.done}',
              style: TextStyle(fontFamily: Fonts.display, fontSize: size * 0.32, color: p.ink),
            ),
            TextSpan(
              text: '/${widget.total}',
              style: TextStyle(fontSize: size * 0.14, color: p.inkMuted),
            ),
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: Motion.morph,
      curve: Motion.morphCurve,
      child: label,
      builder: (context, value, label) => AnimatedBuilder(
        animation: Listenable.merge([_celebrate, _solid]),
        child: label,
        builder: (context, label) {
          final t = _celebrate.value;
          final bump = math.sin(math.pi * _bounce.transform(t));
          return Transform.scale(
            scale: 1 + 0.07 * bump,
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _RingPainter(value, p, wash: _wash.transform(t), solid: _solid.value, flare: bump),
                child: label,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.p, {required this.wash, required this.solid, required this.flare});

  final double progress;
  final Palette p;

  /// How far round from the top the done colour has swept, 0 to 1.
  final double wash;

  /// Opacity of that done colour.
  final double solid;

  /// Extra glow at the peak of the bounce, 0 to 1.
  final double flare;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 2);

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = p.empty,
    );

    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    // The gradient spans just the arc, so however far it's got it ends on
    // done. It starts a cap's width early so the round start cap is
    // coloured too.
    final cap = stroke / 2 / (arcRect.width / 2);
    final shader = SweepGradient(
      endAngle: math.min(sweep + 2 * cap, math.pi * 2),
      colors: p.gradient,
      transform: GradientRotation(-math.pi / 2 - cap),
    ).createShader(rect);

    // Soft, clean ambient glow under the arc; it takes on the done colour
    // as the ring does, and flares with the bounce.
    final doneness = wash * solid;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 3 + 4 * flare
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(p.accent, p.done, doneness)!.withValues(alpha: 0.18 + 0.27 * flare)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 4 * flare),
    );

    // Crisp foreground gradient arc
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    // The done colour washing round over it, its round leading cap the
    // crest of the wave.
    if (wash > 0 && solid > 0) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        sweep * wash,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = p.done.withValues(alpha: solid),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.p != p || old.wash != wash || old.solid != solid || old.flare != flare;
}
