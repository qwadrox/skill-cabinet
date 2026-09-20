// Deployment service: owns per-agent assignments, agents, and symlinks.
//
//   ~/.skill-cabinet/deployment.json   { "providers": [keys], "assignments": { ... }, "disabledProviders": [keys],
//                                        "custom": [{key,label,dir}], "paths": { key: dir } }
//   <agent dir>/<name> -> <store>/<name>   one symlink per effective skill
//
// An agent is either one of agentCatalog's or one the user wrote down in
// "custom"; "paths" overrides a catalog agent's folder. Either way the
// rest of the service sees one AgentDefinition per added agent.
//
// agentCatalog lists every agent the cabinet knows; "providers" are the
// ones the user added, in the order they were added. Only those are shown,
// reconciled, and scanned for foreign skills. A file without "providers"
// (older versions) keeps the agents it has assignments for; a missing
// file starts with the agents installed on this machine.
//
// Every operation writes its state, reconciles the agent folders against
// it, and returns a fresh snapshot. It reads the Library's store layout and
// the Collections file (published conventions) but never writes either.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/agent_catalog.dart';
import '../domain/deployment.dart';
import '../domain/health.dart';
import 'cabinet_paths.dart';
import 'fs_util.dart';

class _Assignment {
  _Assignment({List<String>? sets, List<String>? skills}) : sets = sets ?? [], skills = skills ?? [];

  List<String> sets;
  List<String> skills;

  Map<String, Object> toJson() => {'sets': sets, 'skills': skills};
}

class _State {
  // Version-one state: one global list of active skills.
  List<String> active = [];
  List<String> providers = [];
  List<String> disabledProviders = [];
  Map<String, _Assignment> assignments = {};
  // Agents the user added by hand, by key.
  Map<String, AgentDefinition> custom = {};
  // Folder overrides for catalog agents, by key.
  Map<String, String> overrides = {};

  _Assignment assignmentOf(String key) => assignments[key] ?? _Assignment();

  // The agent behind a key: a custom one as written, else the catalog
  // entry with its folder override applied.
  AgentDefinition? definition(String key) {
    final own = custom[key];
    if (own != null) return own;
    final entry = catalogEntry(key);
    if (entry == null) return null;
    final dir = overrides[key];
    if (dir == null) return entry;
    return AgentDefinition(key: entry.key, label: entry.label, dir: dir, detect: entry.detect, icon: entry.icon);
  }

  Map<String, Object> toJson() => {
    'active': active,
    'providers': providers,
    'disabledProviders': disabledProviders,
    'assignments': {for (final e in assignments.entries) e.key: e.value.toJson()},
    'custom': [
      for (final key in providers)
        if (custom[key] case final a?) {'key': a.key, 'label': a.label, 'dir': a.dir},
    ],
    'paths': {
      for (final e in overrides.entries)
        if (providers.contains(e.key)) e.key: e.value,
    },
  };
}

class DeploymentService {
  const DeploymentService(this.paths);

  final CabinetPaths paths;

  DeploymentSnapshot sync() {
    try {
      return _snapshot(_read(), '');
    } catch (e) {
      return DeploymentSnapshot(agents: const [], catalog: const [], foreign: const [], notice: 'Error: $e');
    }
  }

  DeploymentSnapshot setAgentSet(String agent, String set, {required bool enabled}) {
    final state = _read();
    if (!state.providers.contains(agent)) return _snapshot(state, 'Unknown agent');
    final assignment = state.assignmentOf(agent);
    assignment.sets = [...assignment.sets.where((name) => name != set), if (enabled) set];
    state.assignments[agent] = assignment;
    return _commit(state);
  }

  DeploymentSnapshot setAgentSkill(String agent, String skill, {required bool enabled}) {
    final state = _read();
    if (!state.providers.contains(agent)) return _snapshot(state, 'Unknown agent');
    final assignment = state.assignmentOf(agent);
    assignment.skills = [...assignment.skills.where((name) => name != skill), if (enabled) skill];
    state.assignments[agent] = assignment;
    return _commit(state);
  }

  DeploymentSnapshot setAgentEnabled(String key, {required bool enabled}) {
    final state = _read();
    if (!state.providers.contains(key)) return _snapshot(state, 'Unknown agent');
    state.disabledProviders = [...state.disabledProviders.where((k) => k != key), if (!enabled) key];
    return _commit(state);
  }

  // Drops a skill from every agent's standalone assignments, e.g. after it
  // was deleted from the Library. Reconcile then removes its links, which
  // now dangle into the store.
  DeploymentSnapshot unassignSkill(String skill) {
    final state = _read();
    state.active = state.active.where((name) => name != skill).toList();
    for (final assignment in state.assignments.values) {
      assignment.skills = assignment.skills.where((name) => name != skill).toList();
    }
    return _commit(state);
  }

  // Adds an agent from the catalog. Two agents that share a skills folder
  // would undo each other's links, so the second one is refused.
  DeploymentSnapshot addAgent(String key) {
    final state = _read();
    final agent = state.definition(key);
    if (agent == null) return _snapshot(state, 'Unknown agent');
    if (state.providers.contains(agent.key)) return _snapshot(state, '');
    final clash = _folderClash(state, agent.label, agent.dir);
    if (clash.isNotEmpty) return _snapshot(state, clash);
    state.providers.add(agent.key);
    state.assignments.putIfAbsent(agent.key, _Assignment.new);
    return _commit(state);
  }

  // Adds an agent the catalog does not know: a label and the folder its
  // skills go into (~/..., absolute, or relative to home).
  DeploymentSnapshot addCustomAgent(String rawLabel, String rawDir) {
    final state = _read();
    final label = rawLabel.trim();
    final dir = rawDir.trim();
    if (label.isEmpty) return _snapshot(state, 'Give the agent a name.');
    final bad = _badFolder(dir);
    if (bad.isNotEmpty) return _snapshot(state, bad);
    final clash = _folderClash(state, label, dir);
    if (clash.isNotEmpty) return _snapshot(state, clash);
    final key = _freeKey(state, label);
    state.custom[key] = AgentDefinition(key: key, label: label, dir: dir, detect: dir);
    state.providers.add(key);
    state.assignments.putIfAbsent(key, _Assignment.new);
    return _commit(state);
  }

  // Points an added agent at another folder. Its links move with it: the
  // old folder is emptied of cabinet links before the new one is filled.
  // An empty folder restores a catalog agent's default.
  DeploymentSnapshot setAgentPath(String key, String rawDir) {
    final state = _read();
    final agent = state.definition(key);
    if (agent == null || !state.providers.contains(key)) return _snapshot(state, 'Unknown agent');
    final own = state.custom[key];
    final dir = rawDir.trim();
    if (dir.isEmpty && own != null) return _snapshot(state, 'Give ${agent.label} a folder.');
    final reset = own == null && (dir.isEmpty || dir == catalogEntry(key)?.dir);
    if (!reset) {
      final bad = _badFolder(dir);
      if (bad.isNotEmpty) return _snapshot(state, bad);
    }
    final target = reset ? catalogEntry(key)!.dir : dir;
    if (target == agent.dir) return _snapshot(state, '');
    final clash = _folderClash(state, agent.label, target, except: key);
    if (clash.isNotEmpty) return _snapshot(state, clash);
    try {
      _unlinkAll(agent);
    } catch (e) {
      return _snapshot(_read(), 'Error: $e');
    }
    if (own != null) {
      state.custom[key] = AgentDefinition(key: key, label: own.label, dir: target, detect: target);
    } else if (reset) {
      state.overrides.remove(key);
    } else {
      state.overrides[key] = target;
    }
    return _commit(state);
  }

  // Removes an agent and its cabinet links from its folder. A catalog
  // agent's assignments are kept, so adding it back restores them; a
  // custom agent is gone for good, so its assignments go with it.
  DeploymentSnapshot removeAgent(String key) {
    final state = _read();
    final agent = state.definition(key);
    if (agent == null || !state.providers.contains(key)) return _snapshot(state, 'Unknown agent');
    state.providers.remove(key);
    state.disabledProviders.remove(key);
    try {
      _unlinkAll(agent);
    } catch (e) {
      return _snapshot(_read(), 'Error: $e');
    }
    if (state.custom.remove(key) != null) state.assignments.remove(key);
    state.overrides.remove(key);
    return _commit(state);
  }

  // ---- folders --------------------------------------------------------------

  // What makes a folder unusable as an agent's skills folder, said to the
  // user; empty when it is fine.
  String _badFolder(String dir) {
    if (dir.isEmpty) return 'Give the agent a folder.';
    final full = paths.resolveUser(dir);
    if (full == paths.storeDir || p.isWithin(paths.storeDir, full)) {
      return 'That folder is inside the library itself (${paths.tilde(paths.storeDir)}). Pick another one.';
    }
    if (entryKind(full) == EntryKind.file) return '${paths.tilde(full)} is a file, not a folder.';
    return '';
  }

  // Two agents sharing a folder would undo each other's links, so the
  // second one is refused.
  String _folderClash(_State state, String label, String dir, {String? except}) {
    final full = paths.resolveUser(dir);
    for (final other in _configured(state)) {
      if (other.key == except) continue;
      if (paths.resolveUser(other.dir) != full) continue;
      return '$label uses the same folder as ${other.label} (${paths.tilde(full)}). Remove ${other.label} first.';
    }
    return '';
  }

  // A stable key for a custom agent, from its label. The prefix keeps it
  // clear of every catalog key, now and later.
  String _freeKey(_State state, String label) {
    final slug = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final base = 'custom:${slug.isEmpty ? 'agent' : slug}';
    if (!state.custom.containsKey(base)) return base;
    for (var n = 2; ; n++) {
      if (!state.custom.containsKey('$base-$n')) return '$base-$n';
    }
  }

  // ---- state file -----------------------------------------------------------

  _State _read() {
    final state = _State();
    final exists = File(paths.deploymentFile).existsSync();
    var listed = false;
    final raw = exists ? readJson(paths.deploymentFile) : null;
    if (raw is Map) {
      state.active = stringList(raw['active']);
      state.disabledProviders = stringList(raw['disabledProviders']);
      final custom = raw['custom'];
      if (custom is List) {
        for (final entry in custom) {
          if (entry is! Map) continue;
          final key = entry['key'];
          final label = entry['label'];
          final dir = entry['dir'];
          if (key is! String || label is! String || dir is! String) continue;
          if (key.isEmpty || dir.isEmpty || catalogEntry(key) != null) continue;
          state.custom[key] = AgentDefinition(key: key, label: label, dir: dir, detect: dir);
        }
      }
      final overrides = raw['paths'];
      if (overrides is Map) {
        for (final e in overrides.entries) {
          final key = e.key;
          final dir = e.value;
          if (key is String && dir is String && dir.trim().isNotEmpty && catalogEntry(key) != null) {
            state.overrides[key] = dir.trim();
          }
        }
      }
      if (raw['providers'] is List) {
        listed = true;
        for (final key in stringList(raw['providers'])) {
          if (state.definition(key) != null && !state.providers.contains(key)) state.providers.add(key);
        }
      }
      final assignments = raw['assignments'];
      if (assignments is Map) {
        for (final e in assignments.entries) {
          final key = e.key;
          final entry = e.value;
          if (key is! String || entry is! Map || state.definition(key) == null) continue;
          state.assignments[key] = _Assignment(sets: stringList(entry['sets']), skills: stringList(entry['skills']));
        }
      }
    }
    if (!listed) {
      for (final agent in agentCatalog) {
        final keep = exists ? state.assignments.containsKey(agent.key) : _isInstalled(agent);
        if (keep) state.providers.add(agent.key);
      }
    }
    // Version-one state had a single global active list. Preserve it as a
    // standalone assignment for every added agent when first encountered.
    for (final key in state.providers) {
      state.assignments.putIfAbsent(key, () => _Assignment(skills: [...state.active]));
    }
    return state;
  }

  DeploymentSnapshot _commit(_State state) {
    try {
      writeJsonAtomic(paths.deploymentFile, state.toJson());
      return _snapshot(state, '');
    } catch (e) {
      return _snapshot(_read(), 'Error: $e');
    }
  }

  // ---- reconcile ------------------------------------------------------------

  String _dir(AgentDefinition agent) => paths.resolveUser(agent.dir);

  bool _isInstalled(AgentDefinition agent) =>
      FileSystemEntity.typeSync(paths.resolveUser(agent.detect)) != FileSystemEntityType.notFound;

  // The added agents, in the order they were added.
  List<AgentDefinition> _configured(_State state) => [for (final key in state.providers) ?state.definition(key)];

  // A symlink the cabinet made: it points straight into the store. A
  // dangling one still counts — the store side can vanish under us, and
  // the link is ours either way.
  bool _isManagedLink(String path) {
    final target = linkTarget(path);
    return target != null && p.dirname(target) == p.normalize(paths.storeDir);
  }

  // What holds a name the cabinet was asked to link, for the report. A
  // link is described by where it points, so the user can tell a dead
  // link (safe to remove) from one aimed at real content.
  String _occupant(String path) => switch (entryKind(path)) {
    EntryKind.dir => 'a folder',
    EntryKind.file => 'a file',
    EntryKind.absent => 'something',
    EntryKind.link => switch (linkTarget(path)) {
      null => 'a link',
      final target => '${isBrokenLink(path) ? 'a broken link' : 'a link'} to ${paths.tilde(target)}',
    },
  };

  List<String> _setMembers(String setName) {
    final raw = readJson(paths.collectionsFile);
    if (raw is! Map || raw['groups'] is! List) return [];
    for (final g in raw['groups'] as List) {
      if (g is Map && g['name'] == setName) return stringList(g['skills']);
    }
    return [];
  }

  // Every skill an agent is meant to have: its sets' members plus its
  // standalone skills, deduplicated. Names the store cannot satisfy are
  // kept here — they are the user's stated intent, and dropping them
  // silently is what used to make a deleted skill vanish without a word.
  List<String> _requestedNames(_State state, AgentDefinition agent) {
    final assignment = state.assignmentOf(agent.key);
    return {for (final set in assignment.sets) ..._setMembers(set), ...assignment.skills}.toList();
  }

  // Of those, the ones the store can actually deploy.
  List<String> _deployable(Iterable<String> names) =>
      names.where((name) => isSkillDir(p.join(paths.storeDir, name))).toList();

  // Removes every cabinet link from an agent's folder (real folders stay).
  void _unlinkAll(AgentDefinition agent) {
    final dir = _dir(agent);
    for (final entry in listDir(dir)) {
      final path = p.join(dir, entry);
      if (_isManagedLink(path)) Link(path).deleteSync();
    }
  }

  // Brings every agent folder in line with the state, and reports what it
  // would not force. Only symlinks that point into the store are ever
  // removed — those are the cabinet's own artifacts. A real folder, a
  // file, or somebody else's symlink stays exactly where it is, and the
  // assignment it blocks is reported instead.
  //
  // Nothing is said about entries under names the cabinet was never asked
  // to link: a broken link another tool left behind (its own store on an
  // unmounted volume, say) is not ours to audit.
  List<HealthIssue> _reconcile(_State state) {
    final issues = <HealthIssue>[];
    for (final agent in _configured(state)) {
      final requested = _requestedNames(state, agent);
      final active = _deployable(requested);
      final dir = _dir(agent);
      final enabled = !state.disabledProviders.contains(agent.key);
      for (final entry in listDir(dir)) {
        final path = p.join(dir, entry);
        if (!_isManagedLink(path)) continue;
        final keep = enabled && active.contains(entry) && linkTarget(path) == p.join(paths.storeDir, entry);
        if (!keep) Link(path).deleteSync();
      }
      // A disabled agent is meant to have nothing linked, so an
      // assignment it cannot satisfy is not a problem yet.
      if (!enabled) continue;
      for (final name in requested) {
        if (active.contains(name)) continue;
        issues.add(
          HealthIssue(
            kind: IssueKind.assignmentUnmet,
            subject: name,
            agent: agent.label,
            path: p.join(paths.storeDir, name),
          ),
        );
      }
      if (active.isEmpty) continue;
      Directory(dir).createSync(recursive: true);
      for (final name in active) {
        final link = p.join(dir, name);
        if (lexists(link)) {
          if (!_isManagedLink(link)) {
            issues.add(
              HealthIssue(
                kind: IssueKind.slotOccupied,
                subject: name,
                agent: agent.label,
                path: link,
                detail: _occupant(link),
              ),
            );
          }
          continue;
        }
        Link(link).createSync(p.join(paths.storeDir, name));
      }
    }
    issues.sort((a, b) => a.compareTo(b));
    return issues;
  }

  // ---- snapshot -------------------------------------------------------------

  DeploymentSnapshot _snapshot(_State state, String notice) {
    final issues = _reconcile(state);

    final agents = <Agent>[];
    final foreign = <ForeignSkill>[];
    for (final agent in _configured(state)) {
      final assignment = state.assignmentOf(agent.key);
      final dir = _dir(agent);
      var linked = 0;
      for (final entry in listDir(dir)) {
        final path = p.join(dir, entry);
        if (_isManagedLink(path)) {
          linked++;
        } else if (!isSymlink(path) && isSkillDir(path)) {
          foreign.add(ForeignSkill(name: entry, agent: agent.label, path: path));
        }
      }
      agents.add(
        Agent(
          key: agent.key,
          label: agent.label,
          path: paths.tilde(dir),
          dir: agent.dir,
          custom: catalogEntry(agent.key) == null,
          enabled: !state.disabledProviders.contains(agent.key),
          linked: linked,
          icon: agent.icon,
          sets: List.unmodifiable(assignment.sets),
          skills: List.unmodifiable(assignment.skills),
        ),
      );
    }

    // Agents not added yet; installed ones first.
    final available = agentCatalog.where((a) => !state.providers.contains(a.key)).toList();
    final installed = {for (final a in available) a.key: _isInstalled(a)};
    final ordered = [...available.where((a) => installed[a.key]!), ...available.where((a) => !installed[a.key]!)];
    final catalog = [
      for (final a in ordered)
        CatalogAgent(
          key: a.key,
          label: a.label,
          path: paths.tilde(_dir(a)),
          icon: a.icon,
          installed: installed[a.key]!,
        ),
    ];

    return DeploymentSnapshot(agents: agents, catalog: catalog, foreign: foreign, issues: issues, notice: notice);
  }
}
