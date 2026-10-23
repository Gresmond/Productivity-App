import 'package:flutter/animation.dart';

/// Every animation in the app runs at one of three speeds.
abstract final class Motion {
  /// Hover and press: highlights, lifts and dips.
  static const hover = Duration(milliseconds: 140);
  static const hoverCurve = Curves.easeOutCubic;

  /// A click's result: a tick, a toggle, a swapped word.
  static const click = Duration(milliseconds: 220);
  static const clickCurve = Curves.easeOutCubic;

  /// Things that move or arrive: month changes, gliding pills, new items,
  /// rest days, theme changes.
  static const morph = Duration(milliseconds: 420);
  static const morphCurve = Curves.easeInOutCubic;

  /// A fade-through, split in two: the old thing eases out over the first
  /// ~55% of [t] and the new one eases in over the last ~55%, so the two
  /// never show together at any real strength. Both ends are gentle: a
  /// sharp easeOut here blinked to the bare background in about two frames.
  static const incoming = Interval(0.45, 1.0, curve: Curves.easeInOutSine);
  static double outgoing(double t) => incoming.transform(1 - t);
}
