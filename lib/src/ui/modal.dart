import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialLocalizations;
import 'style.dart';
import 'widgets.dart';

// macos_ui's own dialog/sheet routes animate with a spring curve that
// overshoots, which reads as a bounce. Real macOS modals just fade in with a
// barely-there scale, so we push our own route instead.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0x33000000),
  bool scale = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _AppModalRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      scale: scale,
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
    required this.scale,
  });

  final WidgetBuilder builder;
  final bool scale;

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
    if (!scale || animation.status == AnimationStatus.reverse) {
      return FadeTransition(opacity: fade, child: child);
    }
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1.0).animate(fade), child: child),
    );
  }
}

class ContextMenuEntry {
  const ContextMenuEntry(this.label, {required this.onSelected, this.destructive = false, this.enabled = true});

  final String label;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
}

// A menu at the pointer or under a toolbar button. Unlike macos_ui's
// pull-downs it has no backdrop blur, which would switch the window's
// wallpaper tinting off while it is open.
Future<void> showContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuEntry> entries,
}) async {
  final chosen = await showAppModal<ContextMenuEntry>(
    context: context,
    barrierColor: const Color(0x00000000),
    scale: false,
    builder: (_) => _ContextMenu(position: position, entries: entries),
  );
  chosen?.onSelected();
}

class _ContextMenu extends StatelessWidget {
  const _ContextMenu({required this.position, required this.entries});

  final Offset position;
  final List<ContextMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    const width = 190.0;
    final height = entries.length * 26 + 8;
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          left: position.dx.clamp(6, size.width - width - 6),
          top: position.dy.clamp(6, size.height - height - 6),
          width: width,
          child: Container(
            decoration: BoxDecoration(
              color: context.macos.canvasColor,
              border: Border.all(color: context.separator),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 6))],
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  HoverRow(
                    radius: 5,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    semanticLabel: entry.label,
                    onPressed: entry.enabled ? () => Navigator.of(context).pop(entry) : null,
                    builder: (context, _) => Text(
                      entry.label,
                      style: !entry.enabled
                          ? context.body.copyWith(color: context.tertiaryLabel)
                          : entry.destructive
                          ? context.body.copyWith(color: context.resolve(CupertinoColors.systemRed))
                          : context.body,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// A small centered modal card, sized to its content. MacosSheet stretches
// to whatever inset it is given, which leaves a short form floating in a
// mostly empty box; this one is as tall as what it holds and uses the same
// canvas color, hairline and radius as the rest of the app.
class AppDialogCard extends StatelessWidget {
  const AppDialogCard({super.key, required this.child, this.width = 460, this.maxHeight = 560});

  final Widget child;
  final double width;
  // Lists inside a dialog stop growing here and scroll instead, so a big
  // repository cannot push the dialog off the window.
  final double maxHeight;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          // MacosColors.windowBackgroundColor is a fixed dark purple-grey with
          // no light variant; the theme's canvas is what the panes are painted
          // with, in both modes.
          color: context.macos.canvasColor,
          border: Border.all(color: context.separator),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Flexible(child: child)],
        ),
      ),
    ),
  );
}

// The footer that holds a dialog's buttons: a hairline and the card wash,
// so the actions read as a separate band in every dialog.
class AppDialogActions extends StatelessWidget {
  const AppDialogActions({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(22, 12, 22, 12)});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(height: 1, color: context.separator),
      Container(
        color: context.cardFill,
        padding: padding,
        child: Row(children: children),
      ),
    ],
  );
}
