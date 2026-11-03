// View rows: the one place where contexts are joined for display.
// Everything here is derived from the controller's slices on demand.

import '../domain/collections.dart';
import '../domain/deployment.dart';
import '../domain/health.dart';
import '../domain/git_import.dart';
import '../domain/library.dart';
import '../domain/projects.dart';
import 'cabinet_controller.dart';

class SkillRow {
  const SkillRow({
    required this.skill,
    required this.sets,
    required this.assignedSets,
    required this.active,
    required this.previewed,
    required this.gitSource,
  });

  final LibrarySkill skill;
  // The skill sets holding the skill, shown as tags.
  final List<SkillSet> sets;
  // Those of them assigned to the agent. Any one decides: the switch is
  // locked on. Otherwise the switch is the skill's own standalone
  // assignment, even for set members.
  final List<SkillSet> assignedSets;
  final bool active;
  final bool previewed;
  final GitSourceRecord? gitSource;

  String get name => skill.name;
  bool get inSet => sets.isNotEmpty;
  bool get controlledBySet => assignedSets.isNotEmpty;
}

// A row of the skill pane. The "All skills" view is sectioned: skills in
// no set first, then one collapsible header per set followed by its
// members while it is expanded.
sealed class PaneEntry {
  const PaneEntry();
}

class PaneLabel extends PaneEntry {
  const PaneLabel(this.text);
  final String text;
}

class PaneSetHeader extends PaneEntry {
  const PaneSetHeader({
    required this.set,
    required this.total,
    required this.matching,
    required this.enabled,
    required this.expanded,
  });

  final SkillSet set;
  // Members the store holds.
  final int total;
  // Those of them the search left, listed under the header.
  final int matching;
  // Assigned to the selected agent.
  final bool enabled;
  final bool expanded;

  // While a search hides members, the header says how many of them are
  // left, so the count can never disagree with the rows beneath it.
  String get countLabel => matching == total ? '$total skill${total == 1 ? '' : 's'}' : '$matching of $total skills';
}

class PaneSkill extends PaneEntry {
  const PaneSkill(this.row, {this.nested = false});

  final SkillRow row;
  // Listed under a set header.
  final bool nested;
}

class SetRow {
  const SetRow({
    required this.set,
    required this.total,
    required this.active,
    required this.enabled,
    required this.current,
    required this.projects,
  });

  final SkillSet set;
  final int total;
  // Members the selected agent receives, whether through this set, another
  // one, or their own switch.
  final int active;
  final bool enabled;
  final bool current;
  // Projects the set is on for.
  final int projects;
}

// A project: what was found about its folder, joined with the sets the
// deployment gives it.
class ProjectRow {
  const ProjectRow({
    required this.path,
    required this.name,
    required this.display,
    required this.sets,
    required this.linked,
    required this.exists,
    required this.listed,
    this.icon,
    this.activity,
    this.sources = const [],
  });

  final String path;
  final String name;
  final String display;
  // Skill sets on for the project, in sidebar order.
  final List<SkillSet> sets;
  final int linked;
  final bool exists;
  // The deployment has an entry for it (sets, or added by hand).
  final bool listed;
  final String? icon;
  final DateTime? activity;
  final List<String> sources;

  bool hasSet(String name) => sets.any((s) => s.name == name);
}

// One set in a project's view.
class ProjectSetRow {
  const ProjectSetRow({required this.set, required this.total, required this.enabled, required this.globalFor});

  final SkillSet set;
  final int total;
  // On for the project.
  final bool enabled;
  // Enabled agents that have the whole set everywhere already.
  final List<String> globalFor;
}

extension CabinetRows on CabinetController {
  bool get searching => search.trim().isNotEmpty;

  bool _matches(LibrarySkill skill) {
    final query = search.trim().toLowerCase();
    return query.isEmpty || skill.name.toLowerCase().contains(query) || skill.description.toLowerCase().contains(query);
  }

  SkillRow _row(LibrarySkill skill, Agent? agent) {
    final sets = collections.sets.where((s) => s.has(skill.name)).toList();
    final assigned = agent == null ? const <SkillSet>[] : sets.where((s) => agent.hasSet(s.name)).toList();
    return SkillRow(
      skill: skill,
      sets: sets,
      assignedSets: assigned,
      active: assigned.isNotEmpty || (agent?.hasSkill(skill.name) ?? false),
      previewed: skill.name == previewName,
      gitSource: gitSources[skill.name],
    );
  }

  List<SkillRow> get _allRows {
    final agent = selectedAgent;
    return [for (final skill in library.skills) _row(skill, agent)];
  }

  // Every matching skill in the "All" view, the members in a set view.
  List<SkillRow> get skillRows {
    final set = selectedSet;
    return _allRows.where((r) => (set == null || set.has(r.name)) && _matches(r.skill)).toList();
  }

  // The skill pane's list. Empty sets are left out of the "All" view (the
  // sidebar still lists them). While searching, sets without a match are
  // hidden and the rest open, so matches inside sets stay visible.
  List<PaneEntry> get paneEntries {
    final rows = skillRows;
    if (selectedSet != null) return [for (final r in rows) PaneSkill(r)];
    final agent = selectedAgent;
    final loose = rows.where((r) => !r.inSet).toList();
    final entries = <PaneEntry>[
      if (loose.isNotEmpty && loose.length < rows.length) const PaneLabel('Not in a skill set'),
      for (final r in loose) PaneSkill(r),
    ];
    for (final set in collections.sets) {
      final members = rows.where((r) => set.has(r.name)).toList();
      if (members.isEmpty) continue;
      final expanded = searching || expandedSets.contains(set.name);
      entries.add(
        PaneSetHeader(
          set: set,
          total: _total(set),
          matching: members.length,
          enabled: agent?.hasSet(set.name) ?? false,
          expanded: expanded,
        ),
      );
      if (expanded) entries.addAll([for (final r in members) PaneSkill(r, nested: true)]);
    }
    return entries;
  }

  // In a set view: the skills that can still be added, narrowed by the
  // search and, when the pill is on, to the ones no set holds.
  List<SkillRow> get addableRows {
    final rows = _notInSet;
    return looseOnly ? rows.where((r) => !r.inSet).toList() : rows;
  }

  // What the pill would leave: skills filed in no set at all.
  int get looseAddableCount => _notInSet.where((r) => !r.inSet).length;

  List<SkillRow> get _notInSet {
    final set = selectedSet;
    if (set == null) return const [];
    return _allRows.where((r) => !set.has(r.name) && _matches(r.skill)).toList();
  }

  // Everything the set does not hold, search and pill aside: the section
  // stays on screen while they hide all of it, so the pill that hid the
  // rows can still be turned off.
  int get addableTotal {
    final set = selectedSet;
    if (set == null) return 0;
    return library.skills.where((s) => !set.has(s.name)).length;
  }

  int _total(SkillSet set) => library.skills.where((s) => set.has(s.name)).length;

  List<SetRow> get setRows {
    final agent = selectedAgent;
    final current = selectedSet?.name;
    final rows = _allRows;
    return [
      for (final set in collections.sets)
        SetRow(
          set: set,
          total: _total(set),
          active: rows.where((r) => set.has(r.name) && r.active).length,
          enabled: agent?.hasSet(set.name) ?? false,
          current: set.name == current,
          projects: deployment.projects.where((p) => p.hasSet(set.name)).length,
        ),
    ];
  }

  // ---- projects -------------------------------------------------------------

  ProjectRow _projectRow(String path, ProjectInfo? info) {
    final assignment = deployment.project(path);
    final on = assignment?.sets ?? const <String>[];
    return ProjectRow(
      path: path,
      name: info?.name ?? path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? path,
      display: info?.display ?? assignment?.display ?? path,
      sets: [
        for (final set in collections.sets)
          if (on.contains(set.name)) set,
      ],
      linked: assignment?.linked ?? 0,
      exists: assignment?.exists ?? true,
      listed: assignment != null,
      icon: info?.icon,
      activity: info?.activity,
      sources: info?.sources ?? const [],
    );
  }

  // Every project: found ones by recent activity, then listed ones whose
  // folder could not be described (moved or deleted).
  List<ProjectRow> get allProjectRows {
    final found = {for (final info in discoveredProjects) info.path: info};
    return [
      for (final info in discoveredProjects) _projectRow(info.path, info),
      for (final project in deployment.projects)
        if (!found.containsKey(project.path)) _projectRow(project.path, null),
    ];
  }

  // The overview: projects with sets first, the search applied.
  List<ProjectRow> get projectRows {
    final query = search.trim().toLowerCase();
    final rows = allProjectRows
        .where((r) => query.isEmpty || r.name.toLowerCase().contains(query) || r.display.toLowerCase().contains(query))
        .toList();
    return [...rows.where((r) => r.sets.isNotEmpty), ...rows.where((r) => r.sets.isEmpty)];
  }

  // Projects with at least one set on, for the sidebar.
  List<ProjectRow> get activeProjectRows => [
    for (final project in deployment.projects)
      if (project.sets.isNotEmpty) _projectRow(project.path, _info(project.path)),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  ProjectInfo? _info(String path) {
    for (final info in discoveredProjects) {
      if (info.path == path) return info;
    }
    return null;
  }

  ProjectRow? get selectedProject {
    final path = selectedProjectPath;
    if (path == null) return null;
    final info = _info(path);
    if (info == null && deployment.project(path) == null) return null;
    return _projectRow(path, info);
  }

  List<ProjectRow> projectsWithSet(String name) => [
    for (final row in allProjectRows)
      if (row.hasSet(name)) row,
  ];

  // The selected project's sets, with the agents that have them globally.
  List<ProjectSetRow> get projectSetRows {
    final project = selectedProject;
    final agents = deployment.agents.where((a) => a.enabled).toList();
    return [
      for (final set in collections.sets)
        ProjectSetRow(
          set: set,
          total: _total(set),
          enabled: project?.hasSet(set.name) ?? false,
          globalFor: [
            for (final a in agents)
              if (a.hasSet(set.name)) a.label,
          ],
        ),
    ];
  }

  // Skills the selected agent receives, over the whole library.
  int get activeCount => _allRows.where((r) => r.active).length;

  // Foreign skills are offered only in the "All" view.
  List<ForeignSkill> get foreignRows => selectedSet == null ? deployment.foreign : const [];

  // Health issues from both contexts, in one list. Store problems come
  // first — they are usually the cause of the deployment ones. Unlike
  // foreign skills, these are shown in every view: a problem the user
  // cannot see is the thing this whole list exists to prevent.
  List<HealthIssue> get healthRows => [...library.issues, ...deployment.issues]..sort((a, b) => a.compareTo(b));

  int get issueCount => library.issues.length + deployment.issues.length;
}
