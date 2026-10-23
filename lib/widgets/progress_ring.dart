import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gradient arc showing how many of today's habits are done.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.done, required this.total, this.size = 92});

  final int done;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final target = total == 0 ? 0.0 : done / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(value, p),
          child: Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$done',
                    style: TextStyle(fontFamily: Fonts.display, fontSize: size * 0.32, color: p.ink),
                  ),
                  TextSpan(
                    text: '/$total',
                    style: TextStyle(fontSize: size * 0.14, color: p.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.p);

  final double progress;
  final Palette p;

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

    // Soft, clean ambient glow under the arc
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 3
        ..strokeCap = StrokeCap.round
        ..color = p.accent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
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
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.p != p;
}
