import 'package:flutter/material.dart';

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

  /// Signature gradient for selected tabs, headers and the progress ring.
  /// Always three stops, so themes can blend into each other.
  final List<Color> gradient;

  /// Solid fill for the current day's tab in the month view; kept apart
  /// from the status colours so it never reads as a ticked box.
  final Color today;

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
      done: c(done, other.done),
      missed: c(missed, other.missed),
      other: c(this.other, other.other),
      empty: c(empty, other.empty),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Blues, reds and purples on luminous white cards.
const mainPalette = Palette(
  name: 'Main',
  brightness: Brightness.light,
  background: Color(0xFFF0F4FA),
  tile: Color(0xFFFFFFFF),
  tileBorder: Color(0xFFE1E8F2),
  ink: Color(0xFF191D34),
  inkMuted: Color(0xFF63708D),
  accent: Color(0xFF405BF0),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFF3256ED), Color(0xFF6C4EE8), Color(0xFFD44B74)],
  today: Color(0xFF2F3A78),
  done: Color(0xFF3B66F5),
  missed: Color(0xFFE85372),
  other: Color(0xFF8E6FE6),
  empty: Color(0xFFEDF2F9),
  shadow: Color(0xFF283868),
);

/// The Main palette at night: deep obsidian navy with luminescent accents.
const darkPalette = Palette(
  name: 'Dark',
  brightness: Brightness.dark,
  background: Color(0xFF0D101E),
  tile: Color(0xFF161A2B),
  tileBorder: Color(0xFF262C46),
  ink: Color(0xFFF1F4FD),
  inkMuted: Color(0xFF8B95B8),
  accent: Color(0xFF8298FF),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFF4F6EF0), Color(0xFF8E62F0), Color(0xFFF0668C)],
  today: Color(0xFF4552A6),
  done: Color(0xFF5B7FFF),
  missed: Color(0xFFF05D82),
  other: Color(0xFFA582F7),
  empty: Color(0xFF20263E),
  shadow: Color(0xFF000000),
);

/// Dreamy lavender mist, lilac and soft rose.
const pastelPalette = Palette(
  name: 'Soft Pastel',
  brightness: Brightness.light,
  background: Color(0xFFF6F3FC),
  tile: Color(0xFFFFFFFF),
  tileBorder: Color(0xFFEAE3F5),
  ink: Color(0xFF322A4A),
  inkMuted: Color(0xFF8880A5),
  accent: Color(0xFF7E6CD9),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFF7F9DF2), Color(0xFFAD8DEB), Color(0xFFF08DA8)],
  today: Color(0xFF7E6CD9),
  done: Color(0xFF6F93EB),
  missed: Color(0xFFEB7E9A),
  other: Color(0xFFA98CE8),
  empty: Color(0xFFEFE9F8),
  shadow: Color(0xFF6F5C9E),
);

/// Earthy Nordic sage with citrus amber and terracotta.
const citrusPalette = Palette(
  name: 'Citrus',
  brightness: Brightness.light,
  background: Color(0xFFEFF2EB),
  tile: Color(0xFFFBFCFA),
  tileBorder: Color(0xFFDCE2D5),
  ink: Color(0xFF222B20),
  inkMuted: Color(0xFF6C7A68),
  accent: Color(0xFF4D754A),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFF527E4E), Color(0xFFD49250), Color(0xFFD15F4E)],
  today: Color(0xFF3F7A74),
  done: Color(0xFF5D8C57),
  missed: Color(0xFFCF6554),
  other: Color(0xFFDB9746),
  empty: Color(0xFFE2E7DC),
  shadow: Color(0xFF394A36),
);

/// Warm peach blush, coral rose and dusk plum.
const sunsetPalette = Palette(
  name: 'Sunset',
  brightness: Brightness.light,
  background: Color(0xFFFDF2EC),
  tile: Color(0xFFFFFFFF),
  tileBorder: Color(0xFFF3DED3),
  ink: Color(0xFF381F2C),
  inkMuted: Color(0xFF8E6F7C),
  accent: Color(0xFFDC4D6B),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFFF28F42), Color(0xFFE54E70), Color(0xFF7A4BAE)],
  today: Color(0xFF6A4AB0),
  done: Color(0xFFE86B40),
  missed: Color(0xFF944F8E),
  other: Color(0xFFDD6588),
  empty: Color(0xFFF6E7DE),
  shadow: Color(0xFF7E3B4B),
);

/// The app icon: a deep violet sky, a slate-blue moon and a white corona.
const eclipsePalette = Palette(
  name: 'Eclipse',
  brightness: Brightness.dark,
  background: Color(0xFF170E33),
  tile: Color(0xFF22164A),
  tileBorder: Color(0xFF35286A),
  ink: Color(0xFFF5F3FC),
  inkMuted: Color(0xFF9DA4C4),
  accent: Color(0xFFB7AEF5),
  onAccent: Color(0xFFFFFFFF),
  gradient: [Color(0xFF5B3FC0), Color(0xFF6A62B4), Color(0xFF6F7B99)],
  today: Color(0xFF5B3FC0),
  done: Color(0xFF8E9CDB),
  missed: Color(0xFFD8709F),
  other: Color(0xFF9C7FEA),
  empty: Color(0xFF2B1F57),
  shadow: Color(0xFF000000),
);

const palettes = [mainPalette, darkPalette, pastelPalette, citrusPalette, sunsetPalette, eclipsePalette];

Palette paletteNamed(String? name) =>
    palettes.firstWhere((p) => p.name == name, orElse: () => mainPalette);

final _themes = {for (final p in palettes) p.name: buildTheme(p)};

/// The cached ThemeData for a palette name (Main when unknown).
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
