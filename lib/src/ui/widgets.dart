import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/collections.dart';
import 'style.dart';

// An agent's round logo; agents without one show their initial.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, required this.icon, required this.label, this.size = 28});

  final String? icon;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = icon;
    if (logo != null) {
      return Image.asset(
        'assets/agent-icons/$logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: label,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6E6E78), Color(0xFF3A3A42)],
        ),
      ),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(color: MacosColors.white, fontSize: size * 0.45, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SetDot extends StatelessWidget {
  const SetDot(this.color, {super.key, this.size = 8});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: context.setColor(color), shape: BoxShape.circle),
  );
}

// A skill set label, Linear style: a quiet outlined pill with its color dot.
class SetTag extends StatelessWidget {
  const SetTag(this.set, {super.key, this.highlighted = false});

  final SkillSet set;
  // The set is assigned to the agent (and so decides the skill's switch).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = context.setColor(set.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: 0.14) : null,
        border: Border.all(color: highlighted ? color.withValues(alpha: 0.45) : context.separator),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SetDot(set.color, size: 6),
          const SizedBox(width: 4),
          Text(set.name, style: context.caption.copyWith(fontSize: 10.5, color: context.secondaryLabel)),
        ],
      ),
    );
  }
}

// A row of set tags for a skill. Two names are enough to place a skill at
// a glance, so the rest collapse into a count; past four even that reads
// as noise and only the total is left.
class SetTags extends StatelessWidget {
  const SetTags(this.sets, {super.key, this.highlighted = const [], this.maxTags = 2});

  final List<SkillSet> sets;
  // The sets assigned to the agent, drawn with their color.
  final List<SkillSet> highlighted;
  final int maxTags;

  @override
  Widget build(BuildContext context) {
    if (sets.isEmpty) return const SizedBox.shrink();
    if (sets.length > 4) return Pill('${sets.length} sets');
    final shown = sets.take(maxTags).toList();
    final rest = sets.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in shown) ...[
          if (s != shown.first) const SizedBox(width: 6),
          SetTag(s, highlighted: highlighted.contains(s)),
        ],
        if (rest > 0) ...[const SizedBox(width: 6), Pill('+$rest')],
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.secondaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: context.caption.copyWith(fontSize: 10.5, color: tint, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(10, 14, 10, 6)});

  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.sectionLabel)),
        ?trailing,
      ],
    ),
  );
}

// A pill that switches a list filter on and off. Filled with the accent
// while it is on: a list narrowed by something other than the search
// field has to say so where the rows are.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.active, required this.onPressed, this.count});

  final String label;
  final bool active;
  final VoidCallback onPressed;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final tint = active ? accent : context.secondaryLabel;
    return HoverRow(
      semanticLabel: label,
      onPressed: onPressed,
      selected: active,
      selectedColor: accent.withValues(alpha: context.isDark ? 0.24 : 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      radius: 20,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MacosIcon(active ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 12, color: tint),
          const SizedBox(width: 6),
          Text(label, style: context.caption.copyWith(color: tint, fontWeight: FontWeight.w500)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: context.caption.copyWith(color: tint.withValues(alpha: 0.7))),
          ],
        ],
      ),
    );
  }
}

// A pressable row with hover and selection washes. `builder` gets the
// hover state so rows can reveal their secondary actions on hover.
class HoverRow extends StatefulWidget {
  const HoverRow({
    super.key,
    required this.builder,
    this.onPressed,
    this.selected = false,
    this.selectedColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.radius = 8,
    this.background,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? selectedColor;
  final EdgeInsets padding;
  final double radius;
  final Color? background;
  final String? semanticLabel;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.selected
        ? (widget.selectedColor ?? context.selectedFill)
        : _hovered && widget.onPressed != null
        ? context.hoverFill
        : widget.background;
    return Semantics(
      button: widget.onPressed != null,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: fill ?? const Color(0x00000000),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: widget.builder(context, _hovered),
          ),
        ),
      ),
    );
  }
}

// A small borderless icon button with a tooltip, for row and pane actions.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.size = 15,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => MacosTooltip(
    message: tooltip,
    useMousePosition: false,
    child: MacosIconButton(
      semanticLabel: tooltip,
      icon: MacosIcon(icon, size: size, color: color ?? context.secondaryLabel),
      backgroundColor: const Color(0x00000000),
      hoverColor: context.hoverFill,
      padding: const EdgeInsets.all(5),
      boxConstraints: const BoxConstraints(minWidth: 26, minHeight: 26, maxWidth: 26, maxHeight: 26),
      borderRadius: BorderRadius.circular(6),
      onPressed: onPressed,
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final Widget message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        MacosIcon(icon, size: 34, color: context.tertiaryLabel),
        const SizedBox(height: 12),
        Text(title, style: context.macos.typography.headline),
        const SizedBox(height: 6),
        DefaultTextStyle(style: context.caption.copyWith(fontSize: 12), textAlign: TextAlign.center, child: message),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
