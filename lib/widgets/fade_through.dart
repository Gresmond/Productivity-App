import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An [AnimatedSwitcher] that fades the old child out before the new one
/// fades in, so the two never show together at any real strength.
class FadeThrough extends StatelessWidget {
  const FadeThrough({
    super.key,
    required this.child,
    this.duration = Motion.morph,
    this.scaleFrom = 1.0,
    this.layoutBuilder = AnimatedSwitcher.defaultLayoutBuilder,
  });

  final Widget child;

  /// Covers both halves: fading out, then fading in.
  final Duration duration;

  /// The incoming child grows from this scale as it fades in.
  final double scaleFrom;

  final AnimatedSwitcherLayoutBuilder layoutBuilder;

  // The outgoing child runs the same animation in reverse, so the two
  // halves follow [Motion.incoming] and [Motion.outgoing].
  static final _curve = CurveTween(curve: Motion.incoming);

  /// Lays the outgoing child over the incoming one without letting it change
  /// the height, clipped to the incoming child's box. Takes the full width.
  static Widget sizeToCurrent(Widget? current, List<Widget> previous) => SizedBox(
    width: double.infinity,
    child: Stack(
      children: [
        for (final p in previous)
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(alignment: Alignment.topLeft, minHeight: 0, maxHeight: double.infinity, child: p),
            ),
          ),
        ?current,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      layoutBuilder: layoutBuilder,
      transitionBuilder: (child, anim) {
        final t = anim.drive(_curve);
        Widget faded = FadeTransition(opacity: t, child: child);
        if (scaleFrom != 1.0) {
          faded = ScaleTransition(
            scale: t.drive(Tween(begin: scaleFrom, end: 1.0)),
            child: faded,
          );
        }
        return faded;
      },
      child: child,
    );
  }
}
