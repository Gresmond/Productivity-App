import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'oklch.dart';

/// How the three status hues sit around the key hue on the colour wheel.
enum Harmony {
  /// Neighbours 45° either side: calm and cohesive.
  analogous(45, -45),

  /// The two hues either side of the key's opposite: lively, well apart.
  splitComplementary(150, 210),

  /// Three hues 120° apart: the most separation.
  triadic(120, 240);

  const Harmony(this.first, this.second);

  final double first, second;
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
/// still reads as a warning.
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
  });

  final String name;
  final Brightness brightness;
  final double neutralHue, neutralChroma;
  final double keyHue, statusChroma, statusLightness;
  final Harmony harmony;
  final double lightnessSpread;

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
      );

  bool get _dark => brightness == Brightness.dark;

  /// Hues of done, missed and other.
  (double, double, double) get statusHues {
    final a = turn(keyHue, harmony.first), b = turn(keyHue, harmony.second);
    // Red sits near 25° in OKLCH.
    return hueDistance(a, 25) <= hueDistance(b, 25) ? (keyHue, a, b) : (keyHue, b, a);
  }

  Color _neutral(double l, [double chromaScale = 1]) => Oklch(l, neutralChroma * chromaScale, neutralHue).toColor();

  Palette build() {
    final (doneHue, missedHue, otherHue) = statusHues;
    Color status(double hue, double step) =>
        Oklch(statusLightness + step * lightnessSpread / 2, statusChroma, hue).toColor();
    final done = status(doneHue, 1), missed = status(missedHue, -1), other = status(otherHue, 0);

    final ink = _neutral(_dark ? 0.955 : 0.24, 2);
    // Marks drawn on the status colours: white when it clears 3:1 on all
    // three, else the darkest ink.
    final white = const Color(0xFFFFFFFF);
    final onAccent = [done, missed, other].every((c) => contrast(white, c) >= 3) ? white : _neutral(0.22, 2);
    // Light themes mark today with a soft wash of the key hue under dark
    // text; dark themes with the key hue itself.
    final today = _dark
        ? Oklch(onAccent == white ? 0.50 : 0.84, statusChroma, keyHue).toColor()
        : Oklch(0.89, statusChroma * 0.5, keyHue).toColor();
    final darkInk = _neutral(0.22, 2);
    final onToday = contrast(white, today) >= contrast(darkInk, today) ? white : darkInk;

    return Palette(
      name: name,
      brightness: brightness,
      background: _neutral(_dark ? 0.165 : 0.965),
      tile: _neutral(_dark ? 0.205 : 0.992, _dark ? 1 : 0.5),
      tileBorder: _neutral(_dark ? 0.285 : 0.905),
      ink: ink,
      inkMuted: _neutral(_dark ? 0.73 : 0.52, 2),
      accent: Oklch(_dark ? 0.80 : 0.50, statusChroma * (_dark ? 0.8 : 1), keyHue).toColor(),
      onAccent: onAccent,
      gradient: [done, other, missed].map((c) {
        final o = Oklch.of(c);
        return Oklch(o.l, o.c * 1.1, o.h).toColor();
      }).toList(),
      today: today,
      onToday: onToday,
      done: done,
      missed: missed,
      other: other,
      empty: _neutral(_dark ? 0.255 : 0.94),
      shadow: _dark ? const Color(0xFF000000) : _neutral(0.35, 4),
    );
  }
}
