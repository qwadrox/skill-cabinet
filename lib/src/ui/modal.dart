import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialLocalizations;

// macos_ui's own dialog/sheet routes animate with a spring curve that
// overshoots, which reads as a bounce. Real macOS modals just fade in with a
// barely-there scale, so we push our own route instead.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0x33000000),
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _AppModalRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _AppModalRoute<T> extends PopupRoute<T> {
  _AppModalRoute({
    required this.builder,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.barrierLabel,
  });

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  @override
  final Color barrierColor;

  @override
  final String barrierLabel;

  @override
  Curve get barrierCurve => Curves.easeOutCubic;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 110);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return Semantics(scopesRoute: true, explicitChildNodes: true, child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    // Dismissal is a straight fade; scaling on the way out looks like a recoil.
    if (animation.status == AnimationStatus.reverse) {
      return FadeTransition(opacity: fade, child: child);
    }
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1.0).animate(fade), child: child),
    );
  }
}
