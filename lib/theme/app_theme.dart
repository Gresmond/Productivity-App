import 'package:flutter/material.dart';

import 'palette_recipe.dart';

export 'motion.dart';

/// Font families registered in pubspec.yaml.
abstract final class Fonts {
  /// Page titles, card headings and big numbers.
  static const display = 'Gellix';

  /// To-dos, ritual names, labels.
  static const body = 'Matter';

  /// Labels, day numerals, stats. Same as [body] for now.
  static const ui = body;
}

/// Every colour the app draws with. Each theme is one instance of this.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.name,
    required this.brightness,
    required this.background,
    required this.tile,
    required this.tileBorder,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.onAccent,
    required this.gradient,
    required this.today,
    required this.onToday,
    required this.done,
    required this.missed,
    required this.other,
    required this.empty,
    required this.shadow,
  });

  final String name;
  final Brightness brightness;

  final Color background;

  /// Card surfaces (the "white tiles" of the spreadsheet).
  final Color tile;
  final Color tileBorder;

  final Color ink;
  final Color inkMuted;
  final Color accent;

  /// Text and icons drawn on the gradient or a status colour.
  final Color onAccent;

  /// Signature gradient for selected tabs, headers and the progress ring:
  /// missed, other, then done, so it always ends on done.
  /// Always three stops, so themes can blend into each other.
  final List<Color> gradient;

  /// Solid fill for the current day's tab in the month view: a fourth hue
  /// of the status harmony, lighter than done, so it never reads as a
  /// ticked box.
  final Color today;

  /// The day letter and number drawn on [today].
  final Color onToday;

  /// Habit status colours.
  final Color done;
  final Color missed;
  final Color other;
  final Color empty;

  final Color shadow;

  @override
  Palette copyWith() => this;

  /// Blends every colour, so switching themes cross-fades.
  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      name: t < 0.5 ? name : other.name,
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      tile: c(tile, other.tile),
      tileBorder: c(tileBorder, other.tileBorder),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      gradient: [for (var i = 0; i < gradient.length; i++) c(gradient[i], other.gradient[i])],
      today: c(today, other.today),
      onToday: c(onToday, other.onToday),
      done: c(done, other.done),
      missed: c(missed, other.missed),
      other: c(this.other, other.other),
      empty: c(empty, other.empty),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Every theme, generated in OKLCH by [PaletteRecipe]. Each dark theme
/// shares its light partner's key hue and harmony.
final solarEclipsePalette = const PaletteRecipe(
  name: 'Solar Eclipse',
  brightness: Brightness.light,
  // Near-colourless cool silver, like the corona.
  neutralHue: 255,
  neutralChroma: 0.006,
  keyHue: 255,
  statusChroma: 0.085,
  statusLightness: 0.57,
  harmony: Harmony.analogous,
).build();

final lunarEclipsePalette = const PaletteRecipe(
  name: 'Lunar Eclipse',
  brightness: Brightness.dark,
  // The app icon's deep violet sky.
  neutralHue: 290,
  neutralChroma: 0.06,
  keyHue: 255,
  statusChroma: 0.12,
  statusLightness: 0.58,
  harmony: Harmony.analogous,
).build();

final morningPastelPalette = const PaletteRecipe(
  name: 'Morning Pastel',
  brightness: Brightness.light,
  neutralHue: 300,
  neutralChroma: 0.018,
  keyHue: 265,
  statusChroma: 0.095,
  statusLightness: 0.78,
  harmony: Harmony.triadic,
).build();

final eveningPastelPalette = const PaletteRecipe(
  name: 'Evening Pastel',
  brightness: Brightness.dark,
  // Midnight blue.
  neutralHue: 265,
  neutralChroma: 0.03,
  keyHue: 265,
  statusChroma: 0.09,
  statusLightness: 0.76,
  harmony: Harmony.triadic,
).build();

final sunrisePalette = const PaletteRecipe(
  name: 'Sunrise',
  brightness: Brightness.light,
  // Blush.
  neutralHue: 15,
  neutralChroma: 0.02,
  // A fire sky, soft: apricot, coral-pink and orchid.
  keyHue: 55,
  statusChroma: 0.10,
  statusLightness: 0.58,
  harmony: Harmony.sky,
  vivid: true,
  softness: 0.5,
).build();

final sunsetPalette = const PaletteRecipe(
  name: 'Sunset',
  brightness: Brightness.dark,
  // Dark wine.
  neutralHue: 350,
  neutralChroma: 0.04,
  // A fire sky, soft: apricot, coral-pink and orchid.
  keyHue: 55,
  statusChroma: 0.10,
  statusLightness: 0.58,
  harmony: Harmony.sky,
  vivid: true,
  softness: 0.5,
).build();

final orchardDawnPalette = const PaletteRecipe(
  name: 'Orchard Dawn',
  brightness: Brightness.light,
  // Faint cream yellow.
  neutralHue: 100,
  neutralChroma: 0.02,
  // Pastel apples: green done, orange other, red missed.
  keyHue: 135,
  statusChroma: 0.095,
  statusLightness: 0.78,
  harmony: Harmony.orchard,
).build();

final orchardDuskPalette = const PaletteRecipe(
  name: 'Orchard Dusk',
  brightness: Brightness.dark,
  // A coral late sunset, just short of the orange apple's hue, and
  // lighter than the other night themes.
  neutralHue: 45,
  neutralChroma: 0.10,
  surfaceLift: 0.17,
  // Pastel apples: green done, orange other, red missed.
  keyHue: 135,
  statusChroma: 0.095,
  statusLightness: 0.78,
  harmony: Harmony.orchard,
).build();

/// Each light theme and its dark partner, in menu order.
final palettePairs = [
  (sunrisePalette, sunsetPalette),
  (orchardDawnPalette, orchardDuskPalette),
  (morningPastelPalette, eveningPastelPalette),
  (solarEclipsePalette, lunarEclipsePalette),
];

final palettes = [for (final (light, dark) in palettePairs) ...[light, dark]];

/// The light or dark theme of [name]'s pair.
Palette partnerOf(String? name, {required bool dark}) {
  final p = paletteNamed(name);
  final pair = palettePairs.firstWhere((pair) => pair.$1 == p || pair.$2 == p);
  return dark ? pair.$2 : pair.$1;
}

Palette paletteNamed(String? name) =>
    palettes.firstWhere((p) => p.name == name, orElse: () => solarEclipsePalette);

final _themes = {for (final p in palettes) p.name: buildTheme(p)};

/// The cached ThemeData for a palette name (Solar Eclipse when unknown).
ThemeData themeNamed(String? name) => _themes[paletteNamed(name).name]!;

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  ).copyWith(surface: p.tile, primary: p.accent, onSurface: p.ink);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    fontFamily: Fonts.ui,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.other.withValues(alpha: 0.3),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(fontFamily: Fonts.body, color: p.tile, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    extensions: [p],
  );
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}
