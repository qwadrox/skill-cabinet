// Library: the skills in the central store. Knows nothing about skill
// sets or agents.
//
// The store layout is a published convention that Deployment relies on
// (it links into it, read-only):
//   ~/.skill-cabinet/skills/<name>/SKILL.md

import 'health.dart';

const cabinetDirName = '.skill-cabinet';

class LibrarySkill {
  const LibrarySkill({required this.name, required this.description});

  final String name;
  final String description;
}

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.root,
    required this.rootPath,
    required this.skills,
    this.issues = const [],
    this.notice = '',
  });

  static const empty = LibrarySnapshot(root: '', rootPath: '', skills: []);

  // Display form (~/...) and the absolute path of the store.
  final String root;
  final String rootPath;
  final List<LibrarySkill> skills;
  // Store entries the cabinet cannot deploy, reported but never touched.
  final List<HealthIssue> issues;
  final String notice;

  bool has(String name) => skills.any((s) => s.name == name);
}

class LibraryImportResult {
  const LibraryImportResult(this.snapshot, {this.imported = const []});

  final LibrarySnapshot snapshot;
  // Names of the skills that made it into the store, in import order;
  // empty when nothing was imported.
  final List<String> imported;
}

// One skill folder found under a dropped or picked location, offered to
// the user before anything is copied or moved.
class SkillCandidate {
  const SkillCandidate({
    required this.name,
    required this.path,
    required this.description,
    required this.where,
    required this.duplicate,
    this.folder = '',
  });

  // Folder name, which is the name it would take in the store.
  final String name;
  final String path;
  final String description;
  // Where it sits relative to the folder the search started from; empty
  // when that folder is the skill itself.
  final String where;
  // The folder holding it, as the import sheet groups by: ~/... under home.
  final String folder;
  // The store already holds a skill of this name, so importing it would
  // be refused. Shown, but never preselected.
  final bool duplicate;
}

// The result of searching dropped or picked folders for skills.
class ImportScan {
  const ImportScan({required this.candidates, this.notice = ''});

  static const empty = ImportScan(candidates: []);

  final List<SkillCandidate> candidates;
  // Why nothing (or not everything) was found; empty when fine.
  final String notice;

  bool get isEmpty => candidates.isEmpty;
  // Exactly one skill, and the user pointed straight at it.
  bool get single => candidates.length == 1;
}

class LibraryDeleteResult {
  const LibraryDeleteResult(this.snapshot, {this.deleted});

  final LibrarySnapshot snapshot;
  // Name of the deleted skill; null when nothing was deleted.
  final String? deleted;
}

// Read-only view of one skill's SKILL.md, for the preview pane.
class SkillPreview {
  const SkillPreview({
    required this.name,
    required this.found,
    this.hasFrontmatter = false,
    this.title = '',
    this.description = '',
    this.body = '',
    this.problem = '',
    this.path = '',
  });

  // The skill (folder) name the preview was requested for; the controller
  // drops a result whose name no longer matches the selection.
  final String name;
  // SKILL.md was readable.
  final bool found;
  // A closed `---` frontmatter block opened the file.
  final bool hasFrontmatter;
  // Frontmatter `name:` and `description:`; empty when absent.
  final String title;
  final String description;
  // The markdown after the frontmatter (the whole file without one).
  final String body;
  // Why the file or its frontmatter could not be used; empty when fine.
  final String problem;
  // Absolute path of SKILL.md.
  final String path;

  // Frontmatter `name`, else the folder name.
  String get heading => title.isNotEmpty ? title : name;
  // The frontmatter `name` differs from the folder, so both are shown.
  bool get named => title.isNotEmpty && title != name;
}
