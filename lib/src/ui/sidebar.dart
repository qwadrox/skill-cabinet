import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../app/rows.dart';
import 'agents_sheet.dart';
import 'dialogs.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

Sidebar buildSidebar() => Sidebar(
  minWidth: 220,
  startWidth: 250,
  maxWidth: 340,
  topOffset: 44,
  top: const _AgentSwitcher(),
  builder: (context, scroll) => _SidebarList(scroll: scroll),
  bottom: const _NewSetField(),
);

// The agent the switches edit, Raycast style: a card that unfolds into the
// list of agents in place.
class _AgentSwitcher extends StatefulWidget {
  const _AgentSwitcher();

  @override
  State<_AgentSwitcher> createState() => _AgentSwitcherState();
}

class _AgentSwitcherState extends State<_AgentSwitcher> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final agent = controller.selectedAgent;
    final agents = controller.deployment.agents;

    return Container(
      decoration: BoxDecoration(
        color: context.cardFill,
        border: Border.all(color: context.separator),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HoverRow(
            radius: 10,
            padding: const EdgeInsets.all(8),
            semanticLabel: 'Choose agent',
            onPressed: () => agent == null ? showAgentsSheet(context) : setState(() => _open = !_open),
            builder: (context, _) => Row(
              children: [
                if (agent == null)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: context.hoverFill),
                    child: MacosIcon(CupertinoIcons.plus, size: 15, color: context.secondaryLabel),
                  )
                else
                  AgentAvatar(icon: agent.icon, label: agent.label, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent?.label ?? 'Add an agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        agent == null
                            ? 'Choose where skills go'
                            : agent.enabled
                            ? '${agent.linked} skill${agent.linked == 1 ? '' : 's'} linked'
                            : 'Turned off',
                        style: context.caption,
                      ),
                    ],
                  ),
                ),
                if (agent != null)
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: MacosIcon(CupertinoIcons.chevron_down, size: 12, color: context.secondaryLabel),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Column(
                      children: [
                        Container(height: 1, color: context.separator, margin: const EdgeInsets.only(bottom: 4)),
                        for (final a in agents)
                          HoverRow(
                            radius: 6,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                            selected: a.key == agent?.key,
                            selectedColor: context.sidebarSelectedFill,
                            semanticLabel: a.label,
                            onPressed: () {
                              controller.selectAgent(a.key);
                              setState(() => _open = false);
                            },
                            builder: (context, _) => Row(
                              children: [
                                Opacity(
                                  opacity: a.enabled ? 1 : 0.45,
                                  child: AgentAvatar(icon: a.icon, label: a.label, size: 20),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    a.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.body,
                                  ),
                                ),
                                if (a.enabled) Text('${a.linked}', style: context.caption) else const Pill('Off'),
                              ],
                            ),
                          ),
                        HoverRow(
                          radius: 6,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                          onPressed: () {
                            setState(() => _open = false);
                            showAgentsSheet(context);
                          },
                          builder: (context, _) => Row(
                            children: [
                              SizedBox(
                                width: 20,
                                child: MacosIcon(CupertinoIcons.gear_alt, size: 14, color: context.secondaryLabel),
                              ),
                              const SizedBox(width: 8),
                              Text('Manage agents…', style: context.body.copyWith(color: context.secondaryLabel)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarList extends StatelessWidget {
  const _SidebarList({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final sets = controller.setRows;
    final agent = controller.selectedAgent;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: [
        const SectionLabel('LIBRARY', padding: EdgeInsets.fromLTRB(8, 8, 8, 4)),
        _SidebarItem(
          selected: controller.selectedSet == null,
          onPressed: controller.selectAll,
          leading: MacosIcon(CupertinoIcons.square_stack_3d_up, size: 15, color: context.accent),
          label: 'All skills',
          trailing: Text(
            agent == null
                ? '${controller.library.skills.length}'
                : '${controller.activeCount}/${controller.library.skills.length}',
            style: context.caption,
          ),
        ),
        const SectionLabel('SKILL SETS', padding: EdgeInsets.fromLTRB(8, 16, 8, 4)),
        if (sets.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: Text(
              'Group skills that belong together, then turn the whole set on for an agent.',
              style: context.caption,
            ),
          ),
        for (final row in sets)
          _SidebarItem(
            selected: row.current,
            onPressed: () => controller.selectSet(row.set.name),
            onSecondaryTap: (position) => showContextMenu(
              context: context,
              position: position,
              entries: [
                ContextMenuEntry('Rename…', onSelected: () => renameSetDialog(context, row.set.name)),
                ContextMenuEntry(
                  'Delete “${row.set.name}”',
                  destructive: true,
                  onSelected: () => confirmDeleteSet(context, row.set.name),
                ),
              ],
            ),
            leading: SizedBox(width: 15, child: Center(child: SetDot(row.set.color, size: 9))),
            label: row.set.name,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(agent == null ? '${row.total}' : '${row.active}/${row.total}', style: context.caption),
                if (agent != null) ...[
                  const SizedBox(width: 8),
                  MacosTooltip(
                    message: row.enabled
                        ? 'On for ${agent.label}: every skill in the set is linked'
                        : '${row.active} of ${row.total} linked for ${agent.label} — turn on the whole set',
                    child: MacosSwitch(
                      size: ControlSize.mini,
                      value: row.enabled,
                      onChanged: (on) => controller.setSetEnabled(row.set.name, on),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// Finder-style source list row: a neutral pill marks the selection.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.selected,
    required this.onPressed,
    required this.leading,
    required this.label,
    required this.trailing,
    this.onSecondaryTap,
  });

  final bool selected;
  final VoidCallback onPressed;
  final Widget leading;
  final String label;
  final Widget trailing;
  final void Function(Offset position)? onSecondaryTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 1),
    child: GestureDetector(
      onSecondaryTapUp: onSecondaryTap == null ? null : (details) => onSecondaryTap!(details.globalPosition),
      child: HoverRow(
        selected: selected,
        selectedColor: context.sidebarSelectedFill,
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        semanticLabel: label,
        onPressed: onPressed,
        builder: (context, _) => Row(
          children: [
            leading,
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body.copyWith(fontWeight: selected ? FontWeight.w500 : null),
              ),
            ),
            trailing,
          ],
        ),
      ),
    ),
  );
}

class _NewSetField extends StatefulWidget {
  const _NewSetField();

  @override
  State<_NewSetField> createState() => _NewSetFieldState();
}

class _NewSetFieldState extends State<_NewSetField> {
  final _name = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    CabinetScope.read(context).createSet(name);
    _name.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: MacosTextField(
      controller: _name,
      focusNode: _focus,
      placeholderStyle: context.placeholder,
      placeholder: 'New skill set',
      prefix: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: MacosIcon(CupertinoIcons.plus, size: 13, color: context.secondaryLabel),
      ),
      suffix: _name.text.trim().isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('↩', style: context.caption),
            ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        _submit();
        _focus.requestFocus();
      },
    ),
  );
}
