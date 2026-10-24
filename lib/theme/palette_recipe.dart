import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'oklch.dart';

/// How the three status hues, and today's, sit around the key hue on the
/// colour wheel.
enum Harmony {
  /// Neighbours 45° either side: calm and cohesive. Today carries the run
  /// on one more step.
  analogous(45, -45, -90),

  /// The two hues either side of the key's opposite: lively, well apart.
  /// Today takes the opposite itself.
  splitComplementary(150, 210, 180),

  /// Three hues 120° apart: the most separation. Today sits halfway
  /// between the key and its neighbour, on the same 60° grid.
  triadic(120, 240, 300),

  /// Neighbours along a fifth of the wheel, in the order a sky fades at
  /// dusk: orange, then crimson, then magenta, and today the violet after.
  sky(-40, -75, -110),

  /// An apple orchard: from a green apple round to an orange and a red
  /// one, on the same 35° steps as [sky] once past the orange, and today
  /// the apple-blossom pink one step further.
  orchard(-75, -110, -145);

  const Harmony(this.first, this.second, this.today);

  final double first, second, today;
}

/// A theme as a few numbers; [build] turns it into a [Palette].
///
/// Surfaces and text sit on a fixed OKLCH lightness ladder, tinted by
/// [neutralHue]/[neutralChroma], so every theme has the same perceived
/// depth and text contrast. The three status colours share one chroma, so
/// none looks more vivid than the others. Their hues are set by [harmony]
/// around [keyHue], and a lightness step ([lightnessSpread]) puts done
/// above [statusLightness] and missed below, so they stay apart for
/// colour-blind eyes, which mostly see lightness.
/// Done takes the key hue and missed the other hue nearest red, so it
/// still reads as a warning. Today is a fourth hue of the same harmony,
/// one lightness step above done, so it belongs to the set without
/// passing for any status.
@immutable
class PaletteRecipe {
  const PaletteRecipe({
    required this.name,
    required this.brightness,
    required this.neutralHue,
    required this.neutralChroma,
    required this.keyHue,
    required this.statusChroma,
    required this.statusLightness,
    this.harmony = Harmony.splitComplementary,
    this.lightnessSpread = 0.12,
    this.vivid = false,
    this.softness = 0,
    this.surfaceLift = 0,
    this.todayChroma,
  });

  final String name;
  final Brightness brightness;
  final double neutralHue, neutralChroma;
  final double keyHue, statusChroma, statusLightness;
  final Harmony harmony;
  final double lightnessSpread;

  /// Each status at its hue's cusp (see [Oklch.cusp]) with 85% of the
  /// chroma it can have there, instead of one shared lightness and chroma.
  /// Warm hues at a shared mid lightness turn brown (orange) and olive
  /// (yellow); at their cusps they stay as bright as a sky. All three are
  /// still equally vivid, relative to what each hue can reach.
  final bool vivid;

  /// How far a [vivid] theme's statuses move from their cusps toward
  /// pastel, 0-1: lighter, and with less of the chroma they could have.
  final double softness;

  /// How far a dark theme's surfaces sit above the usual night-time ladder,
  /// in OKLCH lightness: a dusk rather than a midnight.
  final double surfaceLift;

  /// Today's chroma, when it shouldn't share [statusChroma]: cyan can hold
  /// far more colour than blue or pink at a pastel's lightness, so the
  /// shared chroma that is gentle on them turns it neon.
  final double? todayChroma;

  PaletteRecipe withHarmony(Harmony harmony) => PaletteRecipe(
        name: name,
        brightness: brightness,
        neutralHue: neutralHue,
        neutralChroma: neutralChroma,
        keyHue: keyHue,
        statusChroma: statusChroma,
        statusLightness: statusLightness,
        harmony: harmony,
        lightnessSpread: lightnessSpread,
        vivid: vivid,
        softness: softness,
        surfaceLift: surfaceLift,
        todayChroma: todayChroma,
      );

  bool get _dark => brightness == Brightness.dark;

  /// Hues of done, missed and other.
  (double, double, double) get statusHues {
    final a = turn(keyHue, harmony.first), b = turn(keyHue, harmony.second);
    // Red sits near 25° in OKLCH.
    return hueDistance(a, 25) <= hueDistance(b, 25) ? (keyHue, a, b) : (keyHue, b, a);
  }

  Color _neutral(double l, [double chromaScale = 1]) => Oklch(l, neutralChroma * chromaScale, neutralHue).toColor();

  /// A surface on the dark ladder, raised by [surfaceLift].
  double _night(double l) => l + surfaceLift;

  Palette build() {
    final (doneHue, missedHue, otherHue) = statusHues;
    Color status(double hue, double step, [double? chroma]) {
      if (!vivid) return Oklch(statusLightness + step * lightnessSpread / 2, chroma ?? statusChroma, hue).toColor();
      final cusp = Oklch.cusp(hue);
      // Softening pulls the cusps together, so the lightness step still
      // applies.
      final l = cusp.l + (0.88 - cusp.l) * softness + step * lightnessSpread / 2;
      return Oklch(l, Oklch.maxChroma(l, hue) * 0.85 * (1 - 0.5 * softness), hue).toColor();
    }

    final done = status(doneHue, 1), missed = status(missedHue, -1), other = status(otherHue, 0);

    final ink = _neutral(_dark ? 0.955 : 0.24, 2);
    // Marks drawn on the status colours: white when it clears 3:1 on all
    // three, else the darkest ink.
    final white = const Color(0xFFFFFFFF);
    final onAccent = [done, missed, other].every((c) => contrast(white, c) >= 3) ? white : _neutral(0.22, 2);
    final today = status(turn(keyHue, harmony.today), 2, todayChroma);
    final darkInk = _neutral(0.22, 2);
    // A vivid theme's accent takes whichever status hue keeps the most
    // chroma at the accent's lightness, so dark gold text never turns brown.
    final accentL = _dark ? 0.80 : 0.50;
    final accentHue = !vivid
        ? keyHue
        : ([doneHue, missedHue, otherHue]..sort((a, b) =>
                Oklch.maxChroma(accentL, b).compareTo(Oklch.maxChroma(accentL, a))))
            .first;
    final accentC = vivid
        ? Oklch.maxChroma(accentL, accentHue) * 0.85
        : statusChroma * (_dark ? 0.8 : 1);
    final onToday = contrast(white, today) >= contrast(darkInk, today) ? white : darkInk;

    return Palette(
      name: name,
      brightness: brightness,
      background: _neutral(_dark ? _night(0.165) : 0.965),
      tile: _neutral(_dark ? _night(0.205) : 0.992, _dark ? 1 : 0.5),
      tileBorder: _neutral(_dark ? _night(0.285) : 0.905),
      ink: ink,
      // Lifted surfaces need lighter muted text to keep its contrast.
      inkMuted: _neutral(_dark ? 0.73 + surfaceLift / 2 : 0.52, 2),
      accent: Oklch(accentL, accentC, accentHue).toColor(),
      onAccent: onAccent,
      // Runs from missed through other to done, so it ends on the goal.
      gradient: [missed, other, done].map((c) {
        final o = Oklch.of(c);
        return Oklch(o.l, o.c * 1.1, o.h).toColor();
      }).toList(),
      today: today,
      onToday: onToday,
      done: done,
      missed: missed,
      other: other,
      empty: _neutral(_dark ? _night(0.255) : 0.94),
      shadow: _dark ? const Color(0xFF000000) : _neutral(0.35, 4),
    );
  }
}
