import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../app/rows.dart';
import 'modal.dart';
import 'scope.dart';
import 'skill_pane.dart';
import 'style.dart';
import 'widgets.dart';

// Where a set is on: globally for the agents, and per project. Shown on
// top of a set's skill list, so the answer to "where does this reach?"
// sits next to the set itself.
class SetReach extends StatelessWidget {
  const SetReach({super.key, required this.set});

  final String set;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final global = controller.deployment.agents.where((a) => a.hasSet(set)).toList();
    final projects = controller.projectsWithSet(set);
    final addable = controller.allProjectRows.where((r) => r.exists && !r.hasSet(set)).take(14).toList();

    Widget label(String text) => SizedBox(
      width: 74,
      child: Text(text, style: context.caption.copyWith(fontWeight: FontWeight.w600)),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.cardFill,
        border: Border.all(color: context.separator),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              label('Everywhere'),
              Expanded(
                child: global.isEmpty
                    ? Text('Off for every agent', style: context.caption)
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final agent in global)
                            _Chip(
                              leading: Opacity(
                                opacity: agent.enabled ? 1 : 0.45,
                                child: AgentAvatar(icon: agent.icon, label: agent.label, size: 15),
                              ),
                              text: agent.enabled ? agent.label : '${agent.label} (off)',
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 3), child: label('Projects')),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final project in projects)
                      _Chip(
                        leading: ProjectAvatar(icon: project.icon, name: project.name, size: 15),
                        text: project.name,
                        onPressed: () => controller.selectProject(project.path),
                        onRemove: () => controller.setProjectSet(project.path, set, false),
                        removeTooltip: 'Turn $set off for ${project.name}',
                      ),
                    Builder(
                      builder: (context) => _Chip(
                        leading: MacosIcon(CupertinoIcons.plus, size: 11, color: context.secondaryLabel),
                        text: projects.isEmpty ? 'Turn on for a project' : 'Add',
                        dashed: true,
                        onPressed: () {
                          final box = context.findRenderObject()! as RenderBox;
                          showContextMenu(
                            context: context,
                            position: box.localToGlobal(Offset(0, box.size.height + 4)),
                            entries: [
                              for (final project in addable)
                                ContextMenuEntry(
                                  project.name,
                                  onSelected: () => controller.setProjectSet(project.path, set, true),
                                ),
                              ContextMenuEntry('All projects…', onSelected: controller.selectProjects),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.leading,
    required this.text,
    this.onPressed,
    this.onRemove,
    this.removeTooltip = '',
    this.dashed = false,
  });

  final Widget leading;
  final String text;
  final VoidCallback? onPressed;
  final VoidCallback? onRemove;
  final String removeTooltip;
  final bool dashed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: dashed ? null : context.hoverFill,
      border: Border.all(color: context.separator),
      borderRadius: BorderRadius.circular(6),
    ),
    child: HoverRow(
      radius: 6,
      padding: EdgeInsets.fromLTRB(6, 3, onRemove == null ? 8 : 3, 3),
      semanticLabel: text,
      onPressed: onPressed,
      builder: (context, hovered) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 5),
          Text(text, style: context.caption.copyWith(color: dashed ? context.secondaryLabel : context.label)),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            Opacity(
              opacity: hovered ? 1 : 0.4,
              child: MacosTooltip(
                message: removeTooltip,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: MacosIcon(CupertinoIcons.xmark, size: 9, color: context.secondaryLabel),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// The projects overview (a grid of cards, as bb shows them) or one
// project's sets.
class ProjectsPane extends StatelessWidget {
  const ProjectsPane({super.key, required this.scroll, required this.onAddProject});

  final ScrollController scroll;
  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final project = controller.selectedProject;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.notice.isNotEmpty) NoticeBanner(controller.notice, onDismiss: controller.dismissNotice),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: project == null
                ? _overview(context, controller.projectRows, controller.searching, onAddProject)
                : _detail(context, project),
          ),
        ),
      ],
    );
  }
}

List<Widget> _overview(BuildContext context, List<ProjectRow> rows, bool searching, VoidCallback onAddProject) {
  final controller = CabinetScope.read(context);
  if (rows.isEmpty) {
    return [
      EmptyState(
        icon: searching ? CupertinoIcons.search : CupertinoIcons.folder,
        title: searching ? 'Nothing matches' : 'No projects found',
        message: Text(
          searching
              ? 'No project matches “${controller.search.trim()}”.'
              : 'Projects are found in bb, Claude Code and Codex. Add any folder by hand, or drop it here.',
        ),
        action: searching
            ? null
            : PushButton(controlSize: ControlSize.large, onPressed: onAddProject, child: const Text('Add Project…')),
      ),
    ];
  }
  final active = rows.where((r) => r.sets.isNotEmpty).toList();
  final rest = rows.where((r) => r.sets.isEmpty).toList();
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        'Turn skill sets on for a single project instead of everywhere. They are linked into the project’s own '
        'skills folders, so your agents only see them while they work there.',
        style: context.caption.copyWith(fontSize: 12),
      ),
    ),
    if (active.isNotEmpty) ...[
      const SectionLabel('WITH SKILL SETS', padding: EdgeInsets.fromLTRB(4, 6, 4, 8)),
      _Grid([for (final r in active) _ProjectCard(r)]),
    ],
    if (rest.isNotEmpty) ...[
      SectionLabel(active.isEmpty ? 'PROJECTS' : 'OTHER PROJECTS', padding: const EdgeInsets.fromLTRB(4, 16, 4, 8)),
      _Grid([for (final r in rest) _ProjectCard(r)]),
    ],
    Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Center(
        child: PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: onAddProject,
          child: const Text('Add a Folder by Hand…'),
        ),
      ),
    ),
  ];
}

// Two columns, three on a wide window.
class _Grid extends StatelessWidget {
  const _Grid(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 10.0;
      final columns = constraints.maxWidth > 1050 ? 3 : (constraints.maxWidth > 520 ? 2 : 1);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    },
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard(this.row);

  final ProjectRow row;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cardFill,
        border: Border.all(color: row.sets.isEmpty ? context.separator : context.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: HoverRow(
        radius: 10,
        padding: const EdgeInsets.all(12),
        semanticLabel: row.name,
        onPressed: () => controller.selectProject(row.path),
        builder: (context, _) => SizedBox(
          height: 54,
          child: Row(
            children: [
              ProjectAvatar(icon: row.icon, name: row.name, size: 40, dimmed: !row.exists),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!row.exists) ...[
                          const SizedBox(width: 6),
                          Pill('Missing', color: context.resolve(MacosColors.systemOrangeColor)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (row.sets.isNotEmpty) '${row.linked} linked',
                        _ago(row.activity),
                      ].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.caption,
                    ),
                    const SizedBox(height: 5),
                    if (row.sets.isEmpty)
                      Text(
                        row.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mono.copyWith(fontSize: 10.5, color: context.tertiaryLabel),
                      )
                    else
                      ClipRect(child: SetTags(row.sets, highlighted: row.sets, maxTags: 3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _ago(DateTime? time) {
  if (time == null) return null;
  final age = DateTime.now().difference(time);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes}m ago';
  if (age.inDays < 1) return '${age.inHours}h ago';
  if (age.inDays < 30) return '${age.inDays}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[time.month - 1]} ${time.year}';
}

List<Widget> _detail(BuildContext context, ProjectRow project) {
  final controller = CabinetScope.read(context);
  final sets = controller.projectSetRows;
  final targets = controller.deployment.projectTargets;
  final skills = [
    for (final skill in controller.library.skills)
      if (project.sets.any((s) => s.has(skill.name))) skill,
  ];

  return [
    // Header: who the project is and where it lives.
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardFill,
        border: Border.all(color: context.separator),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ProjectAvatar(icon: project.icon, name: project.name, size: 52, dimmed: !project.exists),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.name, style: context.macos.typography.title3.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(project.display, style: context.mono),
                const SizedBox(height: 3),
                Text(
                  [
                    if (project.sources.isNotEmpty) 'Found in ${project.sources.join(', ')}',
                    if (project.sources.isEmpty && project.listed) 'Added by hand',
                    ?_ago(project.activity),
                  ].join(' · '),
                  style: context.caption,
                ),
              ],
            ),
          ),
          if (project.exists)
            IconAction(
              icon: CupertinoIcons.folder,
              tooltip: 'Show in Finder',
              onPressed: () => controller.revealPath(project.path),
            ),
          if (project.listed) ...[
            const SizedBox(width: 6),
            MacosTooltip(
              message: 'Turn every set off here and unlink them',
              child: PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () => controller.removeProject(project.path),
                child: const Text('Remove'),
              ),
            ),
          ],
        ],
      ),
    ),
    if (!project.exists)
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text(
          'This folder is gone. Its sets are kept until you remove the project, in case it comes back.',
          style: context.caption.copyWith(color: context.resolve(MacosColors.systemOrangeColor)),
        ),
      ),
    const SectionLabel('SKILL SETS IN THIS PROJECT', padding: EdgeInsets.fromLTRB(10, 20, 10, 2)),
    Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: targets.isEmpty
          ? Text(
              'None of your agents reads skills from a project folder that the cabinet knows. '
              'Add Claude Code, Codex or Cursor in Manage agents.',
              style: context.caption.copyWith(color: context.resolve(MacosColors.systemOrangeColor)),
            )
          : Text(
              'Linked into ${[for (final t in targets) '${t.folder} (${t.agents.join(', ')})'].join(', ')} '
              'inside the project, and kept out of Git.',
              style: context.caption,
            ),
    ),
    if (sets.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text('No skill sets yet. Create one in the sidebar.', style: context.caption),
      ),
    for (final row in sets) _ProjectSetTile(row, project: project),
    if (skills.isNotEmpty) ...[
      SectionLabel('WHAT AGENTS GET HERE · ${skills.length}', padding: const EdgeInsets.fromLTRB(10, 22, 10, 4)),
      for (final skill in skills)
        HoverRow(
          selected: skill.name == controller.previewName,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          semanticLabel: skill.name,
          onPressed: () => controller.togglePreview(skill.name),
          builder: (context, _) => Row(
            children: [
              for (final set in project.sets.where((s) => s.has(skill.name))) ...[
                SetDot(set.color, size: 7),
                const SizedBox(width: 3),
              ],
              const SizedBox(width: 6),
              Text(skill.name, style: context.body.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(skill.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.caption),
              ),
            ],
          ),
        ),
    ],
  ];
}

class _ProjectSetTile extends StatelessWidget {
  const _ProjectSetTile(this.row, {required this.project});

  final ProjectSetRow row;
  final ProjectRow project;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    final set = row.set;
    return HoverRow(
      semanticLabel: set.name,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      onPressed: project.exists ? () => controller.setProjectSet(project.path, set.name, !row.enabled) : null,
      builder: (context, _) => Row(
        children: [
          SetDot(set.color, size: 9),
          const SizedBox(width: 10),
          Text(set.name, style: context.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('${row.total} skill${row.total == 1 ? '' : 's'}', style: context.caption),
          const Spacer(),
          if (row.globalFor.isNotEmpty) ...[
            MacosTooltip(
              message:
                  'Already on everywhere for ${row.globalFor.join(', ')}. To keep it to projects, '
                  'turn it off in the sidebar for that agent.',
              child: Pill('Everywhere for ${row.globalFor.join(', ')}', color: context.accent),
            ),
            const SizedBox(width: 10),
          ],
          MacosSwitch(
            size: ControlSize.small,
            value: row.enabled,
            onChanged: project.exists ? (on) => controller.setProjectSet(project.path, set.name, on) : null,
          ),
        ],
      ),
    );
  }
}
