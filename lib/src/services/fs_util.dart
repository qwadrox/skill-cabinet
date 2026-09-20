import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// Small filesystem helpers shared by the services.

// Something is at `path`, a dangling symlink included.
bool lexists(String path) => FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

bool isSymlink(String path) => FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.link;

// A directory (or a link to one) holding a SKILL.md.
bool isSkillDir(String path) => FileSystemEntity.isDirectorySync(path) && File(p.join(path, 'SKILL.md')).existsSync();

// What sits at `path`, judged from the entry itself.
//
// Never `isDirectorySync`, which follows links: a symlink to a folder
// would read as a real folder, and the cabinet would treat something it
// does not own as the user's own content (or the other way round).
enum EntryKind { absent, link, dir, file }

EntryKind entryKind(String path) => switch (FileSystemEntity.typeSync(path, followLinks: false)) {
  FileSystemEntityType.notFound => EntryKind.absent,
  FileSystemEntityType.link => EntryKind.link,
  FileSystemEntityType.directory => EntryKind.dir,
  _ => EntryKind.file,
};

// Where a symlink points, resolved against its own directory; null when
// the entry is not a symlink or cannot be read.
String? linkTarget(String path) {
  try {
    if (entryKind(path) != EntryKind.link) return null;
    final target = Link(path).targetSync();
    return p.normalize(p.isAbsolute(target) ? target : p.join(p.dirname(path), target));
  } catch (_) {
    return null;
  }
}

// A symlink that resolves to nothing. A chain ending in a missing file
// counts, which is why this follows links rather than using `lexists`.
bool isBrokenLink(String path) {
  final target = linkTarget(path);
  return target != null && FileSystemEntity.typeSync(target) == FileSystemEntityType.notFound;
}

// Visible entries of a directory by name, sorted case-insensitively;
// empty when it cannot be read.
List<String> listDir(String path) {
  try {
    final names = Directory(
      path,
    ).listSync(followLinks: false).map((e) => p.basename(e.path)).where((name) => !name.startsWith('.')).toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  } catch (_) {
    return [];
  }
}

// A valid single path segment, so a name can never escape its folder.
bool isPlainName(String name) =>
    name.isNotEmpty && name == p.basename(name) && name != '.' && name != '..' && !name.contains('/');

// Writes JSON atomically (temp file + rename) with a trailing newline.
void writeJsonAtomic(String path, Object json) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  tmp.renameSync(path);
}

// The decoded JSON of a file, or null when it is missing or unreadable.
Object? readJson(String path) {
  try {
    return jsonDecode(File(path).readAsStringSync());
  } catch (_) {
    return null;
  }
}

List<String> stringList(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String) v,
      ]
    : <String>[];

// `cp -R`, keeping symlinks inside the copied folder as they are.
void copyTree(String source, String dest) {
  final result = Process.runSync('/bin/cp', ['-R', source, dest]);
  if (result.exitCode != 0) {
    throw FileSystemException('cp failed: ${result.stderr}'.trim(), source);
  }
}

// Folders a skill search never walks into: version control, build output
// and dependency trees. They hold no hand-written skills and can be huge.
const _unsearchable = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '.dart_tool',
  'build',
  'dist',
  'out',
  'target',
  'Pods',
  '.venv',
  'venv',
  '.next',
  '.cache',
  '.gradle',
  'DerivedData',
};

// Every skill folder at or under `root`, breadth-first so the shallowest
// matches come first.
//
// Hidden folders are searched (a project keeps its skills in `.agents`
// or `.claude/skills`), and a skill folder is never descended into: the
// bundled files of a skill are its own, not more skills. Symlinked
// folders are not followed, so a link back up cannot loop.
List<String> findSkillDirs(String root, {int maxDepth = 6, int limit = 200}) {
  if (isSkillDir(root)) return [root];
  final found = <String>[];
  var level = [root];
  for (var depth = 0; depth < maxDepth && level.isNotEmpty && found.length < limit; depth++) {
    final next = <String>[];
    for (final dir in level) {
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(dir).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      final names = [for (final e in entries) p.basename(e.path)]..sort();
      for (final name in names) {
        if (_unsearchable.contains(name)) continue;
        final path = p.join(dir, name);
        if (entryKind(path) != EntryKind.dir) continue;
        if (isSkillDir(path)) {
          found.add(path);
          if (found.length >= limit) return found;
        } else {
          next.add(path);
        }
      }
    }
    level = next;
  }
  return found;
}
