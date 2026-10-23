import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backups.dart';
import '../data/updates.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/backups_dialog.dart';
import '../widgets/fade_through.dart';
import '../widgets/update_banner.dart';
import 'month_view.dart';
import 'today_view.dart';

/// Window chrome: title, year switcher and month tabs.
class Shell extends StatelessWidget {
  const Shell({super.key, this.updater});

  /// Null when the app can't update itself (not installed by linux/install.sh).
  final Updater? updater;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final month = state.viewMonth;

    final updater = this.updater;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        Expanded(
          // Months share one MonthView, whose grid morphs in place, so the
          // card stays put when you move between months.
          child: FadeThrough(
            layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: month == null
                ? const TodayView(key: ValueKey('today'))
                : MonthView(key: const ValueKey('month'), year: state.viewYear, month: month),
          ),
        ),
      ],
    );

    return Scaffold(
      body: updater == null
          ? page
          : Stack(
              children: [
                Positioned.fill(child: page),
                Positioned(right: 32, bottom: 28, child: UpdateBanner(updater: updater)),
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final today = state.today;
    final month = state.viewMonth;

    final todayTitle = '${today.day} ${monthNames[today.month - 1]}';
    // After midnight but before the day starts, say so: the date shown is
    // the day you're still finishing.
    final weekday = weekdayNames[today.weekday - 1];
    final (String kicker, String title) = month == null
        ? (state.lateNight ? '$weekday  ·  until ${hourLabel(state.dayStartHour)}' : weekday, todayTitle)
        : ('${state.viewYear}', monthNames[month - 1]);
    final titleStyle = TextStyle(
      fontFamily: Fonts.display,
      fontSize: 38,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.3,
      height: 1.05,
      color: p.ink,
    );

    return Padding(
      // On macOS the window buttons float over the top of the content.
      padding: EdgeInsets.fromLTRB(32, Platform.isMacOS ? 38 : 26, 32, 22),
      child: Row(
        children: [
          // Sized to the widest possible title, so the tab bar beside it
          // keeps its width when the month changes.
          Stack(
            children: [
              for (final t in [...monthNames, todayTitle])
                Visibility.maintain(visible: false, child: Text(t, style: titleStyle)),
              // Fades with the page below it, rather than snapping first.
              FadeThrough(
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                child: Column(
                  key: ValueKey((kicker, title)),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kicker.toUpperCase(),
                      style: TextStyle(
                        fontFamily: Fonts.ui,
                        fontSize: 11,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w700,
                        color: p.inkMuted.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(title, style: titleStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Takes all the free space (a Spacer beside a Flexible would halve
          // it), right-aligned, scrolling only when the window is too narrow.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: p.tile.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: p.tileBorder.withValues(alpha: 0.85)),
                  boxShadow: [
                    BoxShadow(
                      color: p.shadow.withValues(alpha: p.brightness == Brightness.dark ? 0.3 : 0.03),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: _TabBar(
                      selected: month ?? 0,
                      tabs: [
                        _Tab(label: 'Today', selected: month == null, onTap: state.showToday),
                        for (var m = 1; m <= 12; m++)
                          _Tab(
                            label: monthNames[m - 1].substring(0, 3),
                            selected: month == m,
                            isCurrent: state.viewYear == today.year && m == today.month,
                            future: DateTime(state.viewYear, m).isAfter(today),
                            onTap: () => state.showMonth(m),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _YearSwitcher(year: state.viewYear),
          const SizedBox(width: 10),
          const _BackupsButton(),
          const SizedBox(width: 10),
          const _ThemeButton(),
        ],
      ),
    );
  }
}

/// The tabs in a row, with one highlight pill that glides to the selected
/// tab instead of each tab lighting up on its own.
class _TabBar extends StatefulWidget {
  const _TabBar({required this.tabs, required this.selected});

  /// Today first, then January to December.
  final List<Widget> tabs;

  /// Index into [tabs].
  final int selected;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  final _stackKey = GlobalKey();
  late final _keys = [for (final _ in widget.tabs) GlobalKey()];

  Rect? _pill;
  int? _pillFor;
  bool _glide = false;

  /// Moves the pill under the selected tab once it has been laid out.
  /// Only a change of tab glides; resizing the window just follows along.
  void _measure(Duration _) {
    if (!mounted) return;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final tab = _keys[widget.selected].currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || tab == null || !tab.hasSize) return;
    final rect = tab.localToGlobal(Offset.zero, ancestor: stack) & tab.size;
    if (rect == _pill) return;
    setState(() {
      _glide = _pillFor != null && _pillFor != widget.selected;
      _pillFor = widget.selected;
      _pill = rect;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    final pill = _pill;

    return Stack(
      key: _stackKey,
      children: [
        if (pill != null)
          AnimatedPositioned(
            duration: _glide ? Motion.morph : Duration.zero,
            curve: Motion.morphCurve,
            left: pill.left,
            top: pill.top,
            width: pill.width,
            height: pill.height,
            // A rounded rect, not a StadiumBorder: Impeller on Linux draws
            // shape paths without anti-aliasing, but rounded rects smoothly.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(colors: p.gradient),
                boxShadow: [
                  BoxShadow(color: p.gradient[1].withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
            ),
          ),
        Row(
          children: [
            for (final (i, tab) in widget.tabs.indexed) ...[
              // The gap sits outside the measured tab, so the pill centres on
              // the label.
              KeyedSubtree(key: _keys[i], child: tab),
              const SizedBox(width: 2),
              if (i == 0)
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: p.tileBorder.withValues(alpha: 0.8),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isCurrent = false,
    this.future = false,
  });

  final String label;
  final bool selected;
  final bool isCurrent;
  final bool future;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    final fg = selected
        ? p.onAccent
        : widget.isCurrent
        ? p.accent
        : widget.future
        ? p.inkMuted.withValues(alpha: 0.4)
        : p.ink;
    TextStyle style(FontWeight weight) =>
        TextStyle(fontFamily: Fonts.ui, fontSize: 12.5, fontWeight: weight, color: fg, letterSpacing: 0.2);

    // The selected background is the bar's gliding pill; a tab only draws
    // its hover shade, and its text colour eases as the pill arrives.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.hoverCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: !selected && _hover ? p.empty : p.empty.withValues(alpha: 0),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Reserves the bold width, so selecting a tab never resizes the bar.
              Visibility.maintain(visible: false, child: Text(widget.label, style: style(FontWeight.w600))),
              AnimatedDefaultTextStyle(
                duration: Motion.morph,
                curve: Motion.morphCurve,
                style: style(selected || widget.isCurrent ? FontWeight.w600 : FontWeight.w500),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearSwitcher extends StatelessWidget {
  const _YearSwitcher({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: p.tile.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: p.tileBorder.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: p.brightness == Brightness.dark ? 0.3 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            color: p.inkMuted,
            onPressed: () => state.shiftYear(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            '$year',
            style: TextStyle(
              fontFamily: Fonts.ui,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.ink,
              letterSpacing: 0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            iconSize: 18,
            color: p.inkMuted,
            onPressed: () => state.shiftYear(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// Opens the backups list; confirms a restore once it's done.
class _BackupsButton extends StatelessWidget {
  const _BackupsButton();

  Future<void> _open(BuildContext context) async {
    final p = context.palette;
    final restored = await showDialog<Backup>(context: context, builder: (_) => const BackupsDialog());
    if (restored == null || !context.mounted) return;
    final from = restored.isBeforeRestore
        ? 'how things were before your last restore'
        : '${restored.day!.day} ${monthNames[restored.day!.month - 1]}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 520,
        backgroundColor: p.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          'Restored $from. What you had before is saved as a backup too.',
          style: TextStyle(fontFamily: Fonts.ui, fontSize: 13.5, color: p.tile),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: 'Backups',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _open(context),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: p.tile.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(color: p.tileBorder.withValues(alpha: 0.85)),
              boxShadow: [
                BoxShadow(
                  color: p.shadow.withValues(alpha: p.brightness == Brightness.dark ? 0.3 : 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.history_rounded, size: 21, color: p.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// Round swatch of the current theme; opens a menu of all themes, the
/// rest-weekends switch and when a new day starts.
class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  /// Menu values of the switches; the others are theme names.
  static const _restWeekends = '#restWeekends';
  static const _followNightLight = '#followNightLight';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Appearance',
      offset: const Offset(0, 54),
      color: p.tile,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: p.shadow.withValues(alpha: 0.15),
      constraints: const BoxConstraints(minWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.tileBorder),
      ),
      onSelected: (value) => switch (value) {
        _restWeekends => state.setRestWeekends(!state.restWeekends),
        _followNightLight => state.setFollowNightLight(!state.followNightLight),
        _ => state.setTheme(value),
      },
      itemBuilder: (_) => [
        for (final option in palettes)
          PopupMenuItem(
            value: option.name,
            height: 50,
            child: Row(
              children: [
                _Swatch(palette: option, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    option.name,
                    style: TextStyle(
                      fontFamily: Fonts.ui,
                      fontSize: 14,
                      fontWeight: option.name == p.name ? FontWeight.w600 : FontWeight.w500,
                      color: p.ink,
                    ),
                  ),
                ),
                for (final c in [option.done, option.missed, option.other])
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5)),
                  ),
                SizedBox(
                  width: 32,
                  child: option.name == p.name ? Icon(Icons.check_rounded, size: 18, color: p.accent) : null,
                ),
              ],
            ),
          ),
        if (state.nightLightAvailable) ...[
          const PopupMenuDivider(),
          _switchItem(
            p,
            value: _followNightLight,
            title: 'Follow night light',
            subtitle: 'Its dark partner while night light is on.',
            on: state.followNightLight,
          ),
        ],
        const PopupMenuDivider(),
        _switchItem(
          p,
          value: _restWeekends,
          title: 'Weekends as rest days',
          subtitle: "Greyed out. A blank one won't break a streak.",
          on: state.restWeekends,
        ),
        const PopupMenuDivider(),
        const _DayStartEntry(),
      ],
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.tile.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: p.tileBorder.withValues(alpha: 0.85)),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: p.brightness == Brightness.dark ? 0.3 : 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _Swatch(palette: p, size: 36),
      ),
    );
  }

  PopupMenuItem<String> _switchItem(
    Palette p, {
    required String value,
    required String title,
    required String subtitle,
    required bool on,
  }) {
    return PopupMenuItem(
      value: value,
      height: 60,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontFamily: Fonts.ui, fontSize: 12, color: p.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Toggle(on: on),
        ],
      ),
    );
  }
}

/// Picks the hour a new day starts. Stays open while you choose, since
/// picking just moves the highlight.
class _DayStartEntry extends PopupMenuEntry<String> {
  const _DayStartEntry();

  static const hours = [0, 2, 3, 4, 5];

  /// Midnight's button is wider, to fit its label.
  static int flex(int hour) => hour == 0 ? 7 : 4;

  @override
  double get height => 96;

  @override
  bool represents(String? value) => false;

  @override
  State<_DayStartEntry> createState() => _DayStartEntryState();
}

class _DayStartEntryState extends State<_DayStartEntry> {
  /// Where the pill sits for [hour]: its left edge and width, as fractions.
  static Offset _pillAt(int hour) {
    const hours = _DayStartEntry.hours;
    final total = hours.fold(0, (sum, h) => sum + _DayStartEntry.flex(h));
    final before = hours.takeWhile((h) => h != hour).fold(0, (sum, h) => sum + _DayStartEntry.flex(h));
    return Offset(before / total, _DayStartEntry.flex(hour) / total);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New day starts at',
            style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'Before then, ticks count for the day before.',
            style: TextStyle(fontFamily: Fonts.ui, fontSize: 12, color: p.inkMuted),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: p.empty.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
            // One pill glides to the chosen hour, like the tab bar's.
            child: Stack(
              children: [
                if (_DayStartEntry.hours.contains(state.dayStartHour))
                  Positioned.fill(
                    child: TweenAnimationBuilder<Offset>(
                      tween: Tween(end: _pillAt(state.dayStartHour)),
                      duration: Motion.morph,
                      curve: Motion.morphCurve,
                      builder: (context, pill, _) => Align(
                        // pill.dx is the left edge and pill.dy the width, as
                        // fractions of the row.
                        alignment: Alignment(pill.dy >= 1 ? 0 : 2 * pill.dx / (1 - pill.dy) - 1, 0),
                        child: FractionallySizedBox(
                          widthFactor: pill.dy,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(17),
                              gradient: LinearGradient(colors: p.gradient.skip(1).toList()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final hour in _DayStartEntry.hours)
                      Expanded(
                        flex: _DayStartEntry.flex(hour),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => state.setDayStartHour(hour),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: Motion.morph,
                                  curve: Motion.morphCurve,
                                  style: TextStyle(
                                    fontFamily: Fonts.ui,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: hour == state.dayStartHour ? p.onAccent : p.inkMuted,
                                  ),
                                  child: Text(hourLabel(hour)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small switch, drawn to match the app rather than Material's.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Slides and fills as it flips; colours come from the palette each
    // frame, so a theme change recolours it in step with everything else.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1 : 0),
      duration: Motion.click,
      curve: Motion.clickCurve,
      builder: (context, t, _) => Container(
        width: 36,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: Alignment.lerp(Alignment.centerLeft, Alignment.centerRight, t),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: LinearGradient(colors: [for (final c in p.gradient.skip(1)) Color.lerp(p.empty, c, t)!]),
          border: Border.all(color: p.tileBorder.withValues(alpha: 1 - t)),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Color.lerp(p.tile, p.onAccent, t),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: p.shadow.withValues(alpha: 0.2), blurRadius: 3, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}

/// A theme's gradient as a disc, ringed by its tile colour.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.size});

  final Palette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.tile, width: size * 0.08),
        gradient: SweepGradient(colors: [...palette.gradient, palette.gradient.first]),
        boxShadow: [BoxShadow(color: palette.background, spreadRadius: 1)],
      ),
    );
  }
}
