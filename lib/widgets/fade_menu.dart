import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Opens [builder]'s panel under [anchor], right edges lined up. It fades
/// in as one piece with a slight grow from its corner, at the speed of
/// everything else that arrives, rather than Material's row-by-row reveal.
/// A click outside, or Escape, closes it.
Future<void> showFadeMenu(BuildContext anchor, {required WidgetBuilder builder, double gap = 8, double width = 330}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return Navigator.of(anchor).push(
    _FadeMenuRoute(
      top: rect.bottom + gap,
      right: overlay.size.width - rect.right,
      width: width,
      builder: builder,
      barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
    ),
  );
}

class _FadeMenuRoute extends PopupRoute<void> {
  _FadeMenuRoute({
    required this.top,
    required this.right,
    required this.width,
    required this.builder,
    required this.barrierLabel,
  });

  final double top, right, width;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => Motion.morph;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final p = context.palette;
    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          width: width,
          child: Material(
            color: p.tile,
            elevation: 4,
            shadowColor: p.shadow.withValues(alpha: 0.15),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: p.tileBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: builder(context)),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final t = CurvedAnimation(parent: animation, curve: Motion.morphCurve);
    return FadeTransition(
      opacity: t,
      child: ScaleTransition(
        scale: t.drive(Tween(begin: 0.96, end: 1.0)),
        alignment: Alignment(1 - 2 * right / MediaQuery.sizeOf(context).width, -1 + 2 * top / MediaQuery.sizeOf(context).height),
        child: child,
      ),
    );
  }
}

/// A row in a [showFadeMenu] panel, shaded on hover.
class FadeMenuRow extends StatefulWidget {
  const FadeMenuRow({super.key, required this.onTap, required this.height, required this.child});

  final VoidCallback onTap;
  final double height;
  final Widget child;

  @override
  State<FadeMenuRow> createState() => _FadeMenuRowState();
}

class _FadeMenuRowState extends State<FadeMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.hoverCurve,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: _hover ? p.empty.withValues(alpha: 0.6) : p.empty.withValues(alpha: 0),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A thin line between groups in a [showFadeMenu] panel.
class FadeMenuDivider extends StatelessWidget {
  const FadeMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ColoredBox(color: context.palette.tileBorder, child: const SizedBox(height: 1, width: double.infinity)),
  );
}
