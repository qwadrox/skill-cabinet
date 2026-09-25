import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../app/cabinet_controller.dart';
import '../app/rows.dart';
import '../domain/deployment.dart';
import '../domain/git_import.dart';
import '../domain/health.dart';
import 'dialogs.dart';
import 'git_updates_sheet.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

// The content area: the notice, the skill list for the selected view, and
// a status bar with the store's location.
class SkillPane extends StatelessWidget {
  const SkillPane({super.key, required this.scroll, required this.onImport, required this.onImportGit});

  final ScrollController scroll;
  final VoidCallback onImport;
  final VoidCallback onImportGit;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final updates = controller.gitSources.values
        .where((source) => source.state == GitTrackingState.updateAvailable)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: controller.notice.isEmpty
              ? const SizedBox(width: double.infinity)
              : _NoticeBanner(
                  controller.notice,
                  onDismiss: controller.dismissNotice,
                  onReviewUpdates: updates == 0 ? null : () => showGitUpdatesSheet(context),
                ),
        ),
        Expanded(
          child: !controller.loaded
              ? const Center(child: ProgressCircle())
              : ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: _entries(context, controller),
                ),
        ),
        const _StatusBar(),
      ],
    );
  }

  List<Widget> _entries(BuildContext context, CabinetController controller) {
    final set = controller.selectedSet;
    final entries = controller.paneEntries;

    if (controller.library.skills.isEmpty) {
      return [
        EmptyState(
          icon: CupertinoIcons.archivebox,
          title: 'Your cabinet is empty',
          message: Column(
            children: [
              const Text('Drop skill folders on the window, or import one. Each skill is a folder with a SKILL.md.'),
              const SizedBox(height: 6),
              Text(controller.library.root, style: context.mono),
            ],
          ),
          action: Column(
            children: [
              PushButton(
                controlSize: ControlSize.large,
                onPressed: onImport,
                child: const Text('Import Skill Folder…'),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: onImportGit,
                child: const Text('Import from Git…'),
              ),
            ],
          ),
        ),
        ..._health(context, controller),
        ..._foreign(context, controller),
      ];
    }

    final widgets = <Widget>[];
    if (entries.isEmpty) {
      if (controller.searching) {
        widgets.add(
          EmptyState(
            icon: CupertinoIcons.search,
            title: 'Nothing matches',
            message: Text('No skill ${set == null ? '' : 'in ${set.name} '}matches “${controller.search.trim()}”.'),
          ),
        );
      } else if (set != null) {
        widgets.add(
          EmptyState(
            icon: CupertinoIcons.tray,
            title: '${set.name} is empty',
            message: const Text('Add skills from the list below. Turning the set on links all of them at once.'),
          ),
        );
      }
    }

    for (final entry in entries) {
      widgets.add(switch (entry) {
        PaneLabel(:final text) => SectionLabel(text.toUpperCase()),
        PaneSetHeader() => _SetHeader(entry),
        PaneSkill(:final row, :final nested) => _SkillTile(row, nested: nested, inSetView: set != null),
      });
    }

    if (set != null && controller.addableTotal > 0) {
      final addable = controller.addableRows;
      // The filter sits beside the heading of the list it narrows, and
      // asks that list's usual question: what have I not filed anywhere
      // yet?
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 22, 10, 4),
          child: Row(
            children: [
              Text('ADD TO ${set.name.toUpperCase()}', style: context.sectionLabel),
              const SizedBox(width: 10),
              FilterPill(
                label: 'In no skill set',
                active: controller.looseOnly,
                count: controller.looseAddableCount,
                onPressed: controller.toggleLooseOnly,
              ),
            ],
          ),
        ),
      );
      if (addable.isEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            child: Text(
              controller.looseOnly
                  ? 'Every skill outside ${set.name} is already in another set.'
                  : 'No skill outside ${set.name} matches \u201C${controller.search.trim()}\u201D.',
              style: context.caption,
            ),
          ),
        );
      }
      for (final row in addable) {
        widgets.add(_AddableTile(row, set: set.name));
      }
    }

    widgets.addAll(_health(context, controller));
    widgets.addAll(_foreign(context, controller));
    return widgets;
  }

  // Problems reconciliation found and left alone. No fix buttons: every
  // one of these is something the cabinet does not own or cannot judge,
  // so the row points at it in Finder and stops there.
  List<Widget> _health(BuildContext context, CabinetController controller) {
    final issues = controller.healthRows;
    if (issues.isEmpty) return const [];
    return [
      SectionLabel('PROBLEMS', padding: const EdgeInsets.fromLTRB(10, 22, 10, 2)),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Text('The cabinet found these while reconciling and left them as they are.', style: context.caption),
      ),
      for (final issue in issues) _IssueTile(issue),
    ];
  }

  List<Widget> _foreign(BuildContext context, CabinetController controller) {
    final foreign = controller.foreignRows;
    if (foreign.isEmpty) return const [];
    return [
      SectionLabel('FOUND IN AGENT FOLDERS', padding: const EdgeInsets.fromLTRB(10, 22, 10, 2)),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Text(
          'Real folders the cabinet does not manage. Importing moves one into the cabinet and links it back.',
          style: context.caption,
        ),
      ),
      for (final skill in foreign) _ForeignTile(skill),
    ];
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner(this.text, {required this.onDismiss, this.onReviewUpdates});

  final String text;
  final VoidCallback onDismiss;
  final VoidCallback? onReviewUpdates;

  @override
  Widget build(BuildContext context) {
    final error = text.startsWith('Error');
    final tint = context.resolve(error ? MacosColors.systemRedColor : MacosColors.systemOrangeColor);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          MacosIcon(
            error ? CupertinoIcons.xmark_octagon : CupertinoIcons.exclamationmark_triangle,
            size: 14,
            color: tint,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.callout)),
          if (onReviewUpdates != null) ...[
            PushButton(
              controlSize: ControlSize.small,
              secondary: true,
              onPressed: onReviewUpdates,
              child: const Text('Review updates'),
            ),
            const SizedBox(width: 6),
          ],
          IconAction(icon: CupertinoIcons.xmark, tooltip: 'Dismiss', size: 12, onPressed: onDismiss),
        ],
      ),
    );
  }
}

// A skill set's header in the sectioned "All skills" view.
class _SetHeader extends StatelessWidget {
  const _SetHeader(this.entry);

  final PaneSetHeader entry;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    final agent = CabinetScope.of(context).selectedAgent;
    final set = entry.set;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HoverRow(
        semanticLabel: set.name,
        onPressed: () => controller.toggleSection(set.name),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        builder: (context, _) => Row(
          children: [
            AnimatedRotation(
              turns: entry.expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: MacosIcon(CupertinoIcons.chevron_right, size: 11, color: context.secondaryLabel),
            ),
            const SizedBox(width: 10),
            SetDot(set.color, size: 9),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      set.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.countLabel, style: context.caption),
                ],
              ),
            ),
            if (agent != null)
              MacosTooltip(
                message: entry.enabled ? 'On for ${agent.label}' : 'Turn the whole set on for ${agent.label}',
                child: MacosSwitch(
                  size: ControlSize.small,
                  value: entry.enabled,
                  onChanged: (on) => controller.setSetEnabled(set.name, on),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile(this.row, {required this.nested, required this.inSetView});

  final SkillRow row;
  final bool nested;
  final bool inSetView;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    final agent = CabinetScope.of(context).selectedAgent;
    final set = controller.selectedSet;
    final description = row.skill.description;
    // Tags only where they add something: a set view names its own set
    // already, nested rows sit under theirs.
    final tags = [
      for (final s in row.sets)
        if (!(inSetView && s.name == set?.name) && !(nested && row.sets.length == 1)) s,
    ];

    return Padding(
      padding: EdgeInsets.only(left: nested ? 22 : 0, bottom: 1),
      child: HoverRow(
        selected: row.previewed,
        semanticLabel: row.name,
        onPressed: () => controller.togglePreview(row.name),
        builder: (context, hovered) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (row.gitSource != null) ...[
                        const SizedBox(width: 5),
                        _GitStatusIcon(
                          row.gitSource!,
                          onPressed: () => showGitUpdatesSheet(context, focusSkill: row.name),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[const SizedBox(width: 6), SetTags(tags, highlighted: row.assignedSets)],
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.caption),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: hovered || row.previewed ? 1 : 0,
              child: IgnorePointer(
                ignoring: !(hovered || row.previewed),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (set != null)
                      IconAction(
                        icon: CupertinoIcons.minus_circle,
                        tooltip: 'Remove from ${set.name}',
                        onPressed: () => controller.setMembership(set.name, row.name, member: false),
                      ),
                    IconAction(
                      icon: CupertinoIcons.folder,
                      tooltip: 'Show in Finder',
                      onPressed: () => controller.revealSkill(row.name),
                    ),
                    IconAction(
                      icon: CupertinoIcons.trash,
                      tooltip: 'Delete from library',
                      onPressed: () => confirmDeleteSkill(context, row.name),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (agent != null)
              MacosTooltip(
                message: row.controlledBySet
                    ? 'On through ${row.assignedSets.map((s) => s.name).join(', ')}'
                    : row.active
                    ? 'Linked for ${agent.label}'
                    : 'Link for ${agent.label}',
                child: MacosSwitch(
                  size: ControlSize.small,
                  value: row.active,
                  onChanged: row.controlledBySet ? null : (on) => controller.setSkillEnabled(row.name, on),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddableTile extends StatelessWidget {
  const _AddableTile(this.row, {required this.set});

  final SkillRow row;
  final String set;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    return HoverRow(
      semanticLabel: 'Add ${row.name} to $set',
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      onPressed: () => controller.setMembership(set, row.name, member: true),
      builder: (context, hovered) => Row(
        children: [
          MacosIcon(CupertinoIcons.plus_circle, size: 15, color: hovered ? context.accent : context.tertiaryLabel),
          const SizedBox(width: 10),
          Text(row.name, style: context.body.copyWith(color: context.secondaryLabel)),
          if (row.gitSource != null) ...[
            const SizedBox(width: 5),
            _GitStatusIcon(row.gitSource!, onPressed: () => showGitUpdatesSheet(context, focusSkill: row.name)),
          ],
          // Where the skill already sits, so the same skill is not added
          // to a set that overlaps one it is in.
          if (row.sets.isNotEmpty) ...[const SizedBox(width: 8), SetTags(row.sets, highlighted: row.assignedSets)],
          const SizedBox(width: 10),
          Expanded(
            child: Text(row.skill.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.caption),
          ),
        ],
      ),
    );
  }
}

class _GitStatusIcon extends StatelessWidget {
  const _GitStatusIcon(this.source, {required this.onPressed});

  final GitSourceRecord source;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (source.state) {
      GitTrackingState.tracked => (CupertinoIcons.cloud, context.tertiaryLabel),
      GitTrackingState.upToDate => (CupertinoIcons.cloud, context.secondaryLabel),
      GitTrackingState.updateAvailable => (CupertinoIcons.cloud_download, context.accent),
      GitTrackingState.error => (CupertinoIcons.exclamationmark_triangle, context.resolve(CupertinoColors.systemRed)),
    };
    final detail = '${source.statusLabel}\n${source.sourceUrl}\nref: ${source.ref}\n\nClick to manage Git updates';
    return MacosTooltip(
      message: detail,
      useMousePosition: false,
      child: HoverRow(
        semanticLabel: 'Manage Git updates for ${source.skillName}',
        onPressed: onPressed,
        radius: 4,
        padding: const EdgeInsets.all(2),
        builder: (context, _) => MacosIcon(icon, size: 14, color: color),
      ),
    );
  }
}

class _ForeignTile extends StatelessWidget {
  const _ForeignTile(this.skill);

  final ForeignSkill skill;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    return HoverRow(
      semanticLabel: skill.name,
      builder: (context, hovered) => Row(
        children: [
          MacosIcon(CupertinoIcons.folder, size: 15, color: context.resolve(MacosColors.systemOrangeColor)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name, style: context.body.copyWith(fontWeight: FontWeight.w500)),
                Text('in ${skill.agent}', style: context.caption),
              ],
            ),
          ),
          Opacity(
            opacity: hovered ? 1 : 0,
            child: IconAction(
              icon: CupertinoIcons.folder,
              tooltip: 'Show in Finder',
              onPressed: () => controller.revealPath(skill.path),
            ),
          ),
          const SizedBox(width: 6),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            semanticLabel: 'Import ${skill.name}',
            onPressed: () => controller.importForeign(skill),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile(this.issue);

  final HealthIssue issue;

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.read(context);
    final tint = context.resolve(MacosColors.systemOrangeColor);
    return HoverRow(
      semanticLabel: issue.subject,
      builder: (context, hovered) => Row(
        children: [
          MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 15, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.subject, style: context.body.copyWith(fontWeight: FontWeight.w500)),
                Text(issue.message, style: context.caption),
              ],
            ),
          ),
          Opacity(
            opacity: hovered ? 1 : 0,
            child: IconAction(
              icon: CupertinoIcons.folder,
              tooltip: 'Show in Finder',
              onPressed: () => controller.revealPath(issue.path),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final count = controller.library.skills.length;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.separator)),
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: controller.openStore,
              child: MacosTooltip(
                message: 'Open the store in Finder',
                child: Row(
                  children: [
                    MacosIcon(CupertinoIcons.folder_fill, size: 12, color: context.tertiaryLabel),
                    const SizedBox(width: 6),
                    Text(controller.library.root, style: context.mono.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (controller.issueCount > 0) ...[
            MacosIcon(
              CupertinoIcons.exclamationmark_triangle,
              size: 11,
              color: context.resolve(MacosColors.systemOrangeColor),
            ),
            const SizedBox(width: 4),
            Text(
              '${controller.issueCount} problem${controller.issueCount == 1 ? '' : 's'}',
              style: context.caption.copyWith(fontSize: 11, color: context.resolve(MacosColors.systemOrangeColor)),
            ),
            const SizedBox(width: 10),
          ],
          Text('$count skill${count == 1 ? '' : 's'} in the cabinet', style: context.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
