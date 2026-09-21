// Library service: owns the central store of skill folders.
//
//   ~/.skill-cabinet/skills/<name>/SKILL.md
//
// Knows nothing about skill sets or agents. Every operation returns a
// whole snapshot of the store.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/frontmatter.dart';
import '../domain/health.dart';
import '../domain/library.dart';
import 'cabinet_paths.dart';
import 'fs_util.dart';

class LibraryService {
  const LibraryService(this.paths);

  final CabinetPaths paths;

  LibrarySnapshot scan() {
    try {
      Directory(paths.storeDir).createSync(recursive: true);
      return _snapshot('');
    } catch (e) {
      return _snapshot('Error: $e');
    }
  }

  // Searches dropped or picked folders for skills. Pointing straight at
  // a skill folder yields just that one; pointing at a project yields
  // every skill inside it, `.agents` and `.claude/skills` included.
  // Nothing is written: the user picks from the result.
  ImportScan scanForImport(Iterable<String> roots) {
    final candidates = <SkillCandidate>[];
    final seen = <String>{};
    final missing = <String>[];
    var searched = 0;
    for (final root in roots) {
      final normalized = p.normalize(root);
      if (!Directory(normalized).existsSync()) {
        missing.add(p.basename(normalized));
        continue;
      }
      searched++;
      final found = findSkillDirs(normalized);
      if (found.isEmpty) missing.add(p.basename(normalized));
      for (final path in found) {
        if (!seen.add(path)) continue;
        // A skill already kept in the store (dropped back on the window)
        // is not something to import again.
        if (p.equals(p.dirname(path), paths.storeDir)) continue;
        final name = p.basename(path);
        candidates.add(
          SkillCandidate(
            name: name,
            path: path,
            description: _descriptionAt(path),
            where: p.equals(path, normalized) ? '' : p.dirname(p.relative(path, from: normalized)),
            duplicate: lexists(p.join(paths.storeDir, name)),
            folder: paths.tilde(p.dirname(path)),
          ),
        );
      }
    }
    if (candidates.isNotEmpty) return ImportScan(candidates: candidates);
    final what = missing.length == 1 && searched <= 1 ? '“${missing.first}”' : 'the dropped folders';
    return ImportScan(candidates: const [], notice: 'No skill folder (a folder with a SKILL.md) found in $what');
  }

  // Imports skill folders. `move` takes them out of where they were
  // (agent folders, a project's own `.agents`); otherwise they are
  // copied, leaving the original in place.
  LibraryImportResult importSkills(Iterable<String> sources, {required bool move}) {
    final imported = <String>[];
    final problems = <String>[];
    for (final source in sources) {
      final name = p.basename(source);
      final dest = p.join(paths.storeDir, name);
      if (!isSkillDir(source)) {
        problems.add('$name is not a skill folder (no SKILL.md)');
        continue;
      }
      if (lexists(dest)) {
        problems.add('A skill named "$name" is already in the store');
        continue;
      }
      try {
        Directory(paths.storeDir).createSync(recursive: true);
        if (move) {
          try {
            Directory(source).renameSync(dest);
          } on FileSystemException {
            // Another volume: copy, then remove the original.
            copyTree(source, dest);
            Directory(source).deleteSync(recursive: true);
          }
        } else {
          copyTree(source, dest);
        }
        imported.add(name);
      } catch (e) {
        problems.add('Import of $name failed: $e');
      }
    }
    return LibraryImportResult(_snapshot(_importNotice(imported, problems)), imported: imported);
  }

  // Imports a single skill folder.
  LibraryImportResult importSkill(String source, {required bool move}) => importSkills([source], move: move);

  // What the window says after an import. One thing gone wrong is worth
  // spelling out; several are counted, since the notice is a single line.
  String _importNotice(List<String> imported, List<String> problems) {
    final done = switch (imported.length) {
      0 => '',
      1 => 'Imported ${imported.first}',
      _ => 'Imported ${imported.length} skills',
    };
    if (problems.isEmpty) return done;
    final failed = problems.length == 1 ? problems.first : '${problems.length} skills could not be imported';
    return done.isEmpty ? failed : '$done · $failed';
  }

  // Permanently removes a skill folder from the store. Agent links and
  // skill-set memberships are cleared by the other contexts afterwards.
  LibraryDeleteResult deleteSkill(String name) {
    final target = p.join(paths.storeDir, name);
    if (!isPlainName(name)) return LibraryDeleteResult(_snapshot('Invalid skill name "$name"'));
    if (!lexists(target)) return LibraryDeleteResult(_snapshot('$name is not in the store'));
    try {
      if (isSymlink(target)) {
        Link(target).deleteSync();
      } else {
        Directory(target).deleteSync(recursive: true);
      }
    } catch (e) {
      return LibraryDeleteResult(_snapshot('Delete failed: $e'));
    }
    return LibraryDeleteResult(_snapshot('Deleted $name'), deleted: name);
  }

  // Reads one skill's SKILL.md for the preview pane. Never writes.
  SkillPreview preview(String name) {
    if (!isPlainName(name)) {
      return SkillPreview(name: name, found: false, problem: 'Invalid skill name "$name"');
    }
    final file = p.join(paths.storeDir, name, 'SKILL.md');
    final String content;
    try {
      content = File(file).readAsStringSync();
    } catch (_) {
      return SkillPreview(name: name, found: false, problem: 'SKILL.md is missing or unreadable', path: file);
    }
    final front = splitFrontmatter(content);
    return SkillPreview(
      name: name,
      found: true,
      hasFrontmatter: front.present,
      title: front.field('name'),
      description: front.field('description'),
      body: previewBody(front.body),
      problem: front.problem,
      path: file,
    );
  }

  // Store entries that are not deployable skills, and links that leave
  // the store. The store is the cabinet's own territory, so a problem in
  // it is always worth reporting — but never repairing: a folder whose
  // SKILL.md is missing may be a half-finished import, and deleting it
  // would throw away the user's work.
  List<HealthIssue> _issues() {
    final root = paths.storeDir;
    final issues = <HealthIssue>[];
    for (final name in listDir(root)) {
      final path = p.join(root, name);
      switch (entryKind(path)) {
        case EntryKind.absent:
          break;
        case EntryKind.file:
          issues.add(HealthIssue(kind: IssueKind.storeNotASkill, subject: name, path: path, detail: 'not a folder'));
        case EntryKind.dir:
          if (!isSkillDir(path)) {
            issues.add(HealthIssue(kind: IssueKind.storeNotASkill, subject: name, path: path, detail: 'no SKILL.md'));
          }
        case EntryKind.link:
          final target = linkTarget(path);
          if (target == null || isBrokenLink(path)) {
            issues.add(
              HealthIssue(
                kind: IssueKind.storeBrokenLink,
                subject: name,
                path: path,
                detail: target == null ? '' : paths.tilde(target),
              ),
            );
          } else if (!isSkillDir(path)) {
            issues.add(HealthIssue(kind: IssueKind.storeNotASkill, subject: name, path: path, detail: 'no SKILL.md'));
          } else if (!p.equals(p.dirname(target), root)) {
            // A working link to a skill kept elsewhere (a dotfiles repo,
            // say). It deploys fine, so it stays in the library; the
            // report only says the cabinet is not its owner.
            issues.add(
              HealthIssue(kind: IssueKind.storeLinksOut, subject: name, path: path, detail: paths.tilde(target)),
            );
          }
      }
    }
    issues.sort((a, b) => a.compareTo(b));
    return issues;
  }

  List<String> _skillNames() {
    final root = paths.storeDir;
    return listDir(root).where((name) => isSkillDir(p.join(root, name))).toList();
  }

  String _description(String name) => _descriptionAt(p.join(paths.storeDir, name));

  String _descriptionAt(String dir) {
    try {
      return splitFrontmatter(File(p.join(dir, 'SKILL.md')).readAsStringSync()).field('description');
    } catch (_) {
      return '';
    }
  }

  LibrarySnapshot _snapshot(String notice) => LibrarySnapshot(
    root: paths.tilde(paths.storeDir),
    rootPath: paths.storeDir,
    skills: [for (final name in _skillNames()) LibrarySkill(name: name, description: _description(name))],
    issues: _issues(),
    notice: notice,
  );
}
