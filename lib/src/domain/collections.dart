// Collections: named skill sets. Members are skill names; a name the
// Library no longer has is simply not shown. Knows nothing about agents.

// Sets get one of setColorCount palette slots when created.
const setColorCount = 6;

class SkillSet {
  const SkillSet({required this.name, required this.skills, required this.color});

  final String name;
  final List<String> skills;
  // Palette slot, 0 .. setColorCount - 1; the view maps it to a color.
  final int color;

  bool has(String skill) => skills.contains(skill);
}

class CollectionsSnapshot {
  const CollectionsSnapshot({required this.sets, this.notice = ''});

  static const empty = CollectionsSnapshot(sets: []);

  final List<SkillSet> sets;
  final String notice;

  SkillSet? named(String name) {
    for (final set in sets) {
      if (set.name == name) return set;
    }
    return null;
  }
}
