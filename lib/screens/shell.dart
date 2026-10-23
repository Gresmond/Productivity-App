import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backups.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/backups_dialog.dart';
import '../widgets/fade_through.dart';
import 'month_view.dart';
import 'today_view.dart';

/// Window chrome: title, year switcher and month tabs.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final month = state.viewMonth;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          Expanded(
            // Months share one MonthView, which fades only its grid, so the
            // card stays put when you move between months.
            child: FadeThrough(
              layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
              child: month == null
                  ? const TodayView(key: ValueKey('today'))
                  : MonthView(key: const ValueKey('month'), year: state.viewYear, month: month),
            ),
          ),
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
    final (String kicker, String title) = month == null
        ? (weekdayNames[today.weekday - 1], todayTitle)
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
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 22),
      child: Row(
        children: [
          // Sized to the widest possible title, so the tab bar beside it
          // keeps its width when the month changes.
          Stack(
            children: [
              for (final t in [...monthNames, todayTitle])
                Visibility.maintain(visible: false, child: Text(t, style: titleStyle)),
              Column(
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
                    child: Row(
                      children: [
                        _Tab(label: 'Today', selected: month == null, onTap: state.showToday),
                        Container(
                          width: 1,
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: p.tileBorder.withValues(alpha: 0.8),
                        ),
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

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          // A rounded rect, not a StadiumBorder: Impeller on Linux draws
          // shape paths without anti-aliasing, but rounded rects smoothly.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: selected ? LinearGradient(colors: p.gradient) : null,
              color: selected ? null : (_hover ? p.empty : Colors.transparent),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: p.gradient[1].withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Reserves the bold width, so selecting a tab never resizes the bar.
                Visibility.maintain(visible: false, child: Text(widget.label, style: style(FontWeight.w600))),
                Text(widget.label, style: style(selected || widget.isCurrent ? FontWeight.w600 : FontWeight.w500)),
              ],
            ),
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

/// Round swatch of the current theme; opens a menu of all themes.
class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Theme',
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
      onSelected: state.setTheme,
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
