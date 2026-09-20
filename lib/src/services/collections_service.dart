// Collections service: owns atomic skill sets.
//
//   ~/.skill-cabinet/collections.json   { "groups": [{ "name", "skills": [names], "color" }] }
//
// Members are skill names and are not checked against the Library: a set
// may name a skill that is not in the store (yet). A set's color is a
// palette slot picked at creation (the least used one), so colors stay
// put when other sets come and go. Sets stored without one get theirs on
// read, in file order, and keep it from the next write.

import '../domain/collections.dart';
import 'cabinet_paths.dart';
import 'fs_util.dart';

class _StoredSet {
  _StoredSet(this.name, this.skills, this.color);

  final String name;
  List<String> skills;
  int color;

  Map<String, Object> toJson() => {'name': name, 'skills': skills, 'color': color};
}

class CollectionsService {
  const CollectionsService(this.paths);

  final CabinetPaths paths;

  CollectionsSnapshot list() => _snapshot(_read(), '');

  CollectionsSnapshot createSet(String rawName) {
    final state = _read();
    final name = rawName.trim();
    if (name.isEmpty) return _snapshot(state, '');
    if (_find(state, name) != null) return _snapshot(state, 'Skill set "$name" already exists');
    state.add(_StoredSet(name, [], _leastUsedColor(state)));
    return _commit(state);
  }

  CollectionsSnapshot deleteSet(String name) {
    final state = _read()..removeWhere((s) => s.name == name);
    return _commit(state);
  }

  CollectionsSnapshot setMembership(String setName, String skill, {required bool member}) {
    final state = _read();
    final set = _find(state, setName);
    if (set == null) return _snapshot(state, 'Skill set not found');
    final has = set.skills.contains(skill);
    if (member && !has) set.skills.add(skill);
    if (!member && has) set.skills = set.skills.where((s) => s != skill).toList();
    return _commit(state);
  }

  // Drops a skill from every set, e.g. after it was deleted from the Library.
  CollectionsSnapshot dropSkill(String skill) {
    final state = _read();
    for (final set in state) {
      set.skills = set.skills.where((s) => s != skill).toList();
    }
    return _commit(state);
  }

  List<_StoredSet> _read() {
    final state = <_StoredSet>[];
    final raw = readJson(paths.collectionsFile);
    if (raw is! Map || raw['groups'] is! List) return state;
    for (final g in raw['groups'] as List) {
      if (g is! Map || g['name'] is! String || g['skills'] is! List) continue;
      final color = g['color'];
      state.add(
        _StoredSet(
          g['name'] as String,
          stringList(g['skills']),
          color is int && color >= 0 && color < setColorCount ? color : -1,
        ),
      );
    }
    // Backfill after every stored color is known, so it avoids them.
    for (final set in state) {
      if (set.color < 0) set.color = _leastUsedColor(state.where((s) => s.color >= 0).toList());
    }
    return state;
  }

  CollectionsSnapshot _commit(List<_StoredSet> state) {
    try {
      writeJsonAtomic(paths.collectionsFile, {
        'groups': [for (final s in state) s.toJson()],
      });
      return _snapshot(state, '');
    } catch (e) {
      return _snapshot(_read(), 'Error: $e');
    }
  }

  static _StoredSet? _find(List<_StoredSet> state, String name) {
    for (final set in state) {
      if (set.name == name) return set;
    }
    return null;
  }

  // The palette slot fewest sets use; ties go to the lowest slot.
  static int _leastUsedColor(List<_StoredSet> sets) {
    var best = 0;
    var bestCount = sets.length + 1;
    for (var color = 0; color < setColorCount; color++) {
      final count = sets.where((s) => s.color == color).length;
      if (count < bestCount) {
        best = color;
        bestCount = count;
      }
    }
    return best;
  }

  static CollectionsSnapshot _snapshot(List<_StoredSet> state, String notice) => CollectionsSnapshot(
    sets: [for (final s in state) SkillSet(name: s.name, skills: List.unmodifiable(s.skills), color: s.color)],
    notice: notice,
  );
}
