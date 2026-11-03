// Project discovery: the folders the user works in, read from the places
// coding agents remember them, never written.
//
//   bb            `bb project list --json` (~/.bb/bin/bb)    names and folders
//   Claude Code   ~/.claude.json "projects"                  folders
//   Codex         ~/.codex/config.toml [projects."<folder>"] folders
//                 ~/.codex/state_<n>.sqlite                  the app's named projects, and every
//                                                            thread's folder with its last activity
//
// Only Git repositories count as found: those files also remember home,
// scratch folders and worktrees. A project named in the Codex app counts
// whatever it is; the user made it one. A folder the caller asks about
// (added by hand, or holding sets) is described whatever it is.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/projects.dart';
import 'cabinet_paths.dart';
import 'fs_util.dart';

class ProjectService {
  const ProjectService(this.paths);

  final CabinetPaths paths;

  // Found projects, plus every folder in `extra` that exists, most recently
  // active first.
  List<ProjectInfo> discover(List<String> extra) {
    final names = <String, String>{};
    final sources = <String, List<String>>{};
    // Last time an agent worked there, where it says.
    final used = <String, DateTime>{};
    void found(String raw, String source, {String? name, DateTime? at, bool named = false}) {
      final path = p.normalize(raw);
      if (!(named ? _isNamedProject(path) : _isProject(path))) return;
      final list = sources[path] ??= [];
      if (!list.contains(source)) list.add(source);
      if (name != null && name.trim().isNotEmpty) names[path] ??= name.trim();
      if (at != null && (used[path] == null || at.isAfter(used[path]!))) used[path] = at;
    }

    for (final (path, name) in _fromBb()) {
      found(path, 'bb', name: name);
    }
    for (final path in _fromClaude()) {
      found(path, 'Claude Code');
    }
    for (final path in _fromCodex()) {
      found(path, 'Codex');
    }
    final codex = _codexState();
    for (final (path, name) in codex.projects) {
      found(path, 'Codex', name: name, named: true);
    }
    for (final e in codex.threads.entries) {
      found(e.key, 'Codex', at: e.value);
    }
    for (final raw in extra) {
      final path = p.normalize(raw);
      if (Directory(path).existsSync()) sources.putIfAbsent(path, () => []);
    }

    final projects = [
      for (final e in sources.entries)
        ProjectInfo(
          path: e.key,
          name: names[e.key] ?? p.basename(e.key),
          display: paths.tilde(e.key),
          sources: e.value,
          icon: _icon(e.key),
          activity: _latest(_activity(e.key), used[e.key]),
        ),
    ];
    projects.sort((a, b) {
      final byActivity = (b.activity ?? DateTime(0)).compareTo(a.activity ?? DateTime(0));
      return byActivity != 0 ? byActivity : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return projects;
  }

  static DateTime? _latest(DateTime? a, DateTime? b) => a == null || (b != null && b.isAfter(a)) ? b : a;

  // A folder the user named as a project: anything but home and the
  // agents' own dot folders.
  bool _isNamedProject(String path) {
    if (!p.isAbsolute(path) || path == paths.home) return false;
    if (p.isWithin(paths.home, path) && p.split(p.relative(path, from: paths.home)).first.startsWith('.')) {
      return false;
    }
    return FileSystemEntity.isDirectorySync(path);
  }

  // A Git repository the user owns: not home, not inside a dot folder of
  // home (agent config, the cabinet, worktree stores), not a worktree.
  bool _isProject(String path) {
    if (!p.isAbsolute(path) || path == paths.home) return false;
    if (p.isWithin(paths.home, path) && p.split(p.relative(path, from: paths.home)).first.startsWith('.')) {
      return false;
    }
    if (p.split(path).contains('worktrees')) return false;
    return FileSystemEntity.isDirectorySync(p.join(path, '.git'));
  }

  List<(String, String?)> _fromBb() {
    final bb = paths.inHome('.bb/bin/bb');
    if (!File(bb).existsSync()) return const [];
    try {
      final result = Process.runSync(bb, ['project', 'list', '--json']);
      if (result.exitCode != 0) return const [];
      final raw = jsonDecode(result.stdout as String);
      if (raw is! List) return const [];
      return [
        for (final project in raw)
          if (project is Map && project['sources'] is List)
            for (final source in project['sources'] as List)
              if (source is Map && source['path'] is String)
                (source['path'] as String, project['name'] is String ? project['name'] as String : null),
      ];
    } catch (_) {
      return const [];
    }
  }

  List<String> _fromClaude() {
    final raw = readJson(paths.inHome('.claude.json'));
    if (raw is! Map || raw['projects'] is! Map) return const [];
    return [
      for (final key in (raw['projects'] as Map).keys)
        if (key is String) key,
    ];
  }

  static final _codexProject = RegExp(r'''^\s*\[projects\.(?:"([^"]+)"|'([^']+)')\]''', multiLine: true);

  List<String> _fromCodex() {
    final file = File(paths.inHome('.codex/config.toml'));
    if (!file.existsSync()) return const [];
    try {
      return [for (final m in _codexProject.allMatches(file.readAsStringSync())) m.group(1) ?? m.group(2)!];
    } catch (_) {
      return const [];
    }
  }

  // The Codex app's state database, newest schema first, read through the
  // system's sqlite3 in read-only mode. Missing or unreadable gives nothing.
  ({List<(String, String?)> projects, Map<String, DateTime> threads}) _codexState() {
    const none = (projects: <(String, String?)>[], threads: <String, DateTime>{});
    const sqlite = '/usr/bin/sqlite3';
    final dir = paths.inHome('.codex');
    if (!File(sqlite).existsSync() || !Directory(dir).existsSync()) return none;
    final databases = listDir(dir).where((name) => RegExp(r'^state_(\d+)\.sqlite$').hasMatch(name)).toList()
      ..sort((a, b) => _version(b).compareTo(_version(a)));
    if (databases.isEmpty) return none;
    final db = p.join(dir, databases.first);
    List<Map<String, Object?>> query(String sql) {
      try {
        final result = Process.runSync(sqlite, ['-readonly', '-json', db, sql]);
        if (result.exitCode != 0) return const [];
        final out = (result.stdout as String).trim();
        if (out.isEmpty) return const [];
        final rows = jsonDecode(out);
        return rows is List
            ? [
                for (final row in rows)
                  if (row is Map) row.cast<String, Object?>(),
              ]
            : const [];
      } catch (_) {
        return const [];
      }
    }

    final projects = [
      for (final row in query(
        'SELECT p.name AS name, r.path AS path FROM projects p JOIN project_roots r ON r.project_id = p.id',
      ))
        if (row['path'] is String) (row['path'] as String, row['name'] is String ? row['name'] as String : null),
    ];
    final threads = <String, DateTime>{
      for (final row in query('SELECT cwd, MAX(updated_at) AS at FROM threads GROUP BY cwd'))
        if (row['cwd'] is String && row['at'] is int)
          row['cwd'] as String: DateTime.fromMillisecondsSinceEpoch((row['at'] as int) * 1000),
    };
    return (projects: projects, threads: threads);
  }

  static int _version(String name) => int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '') ?? 0;

  // The project's logo, as bb finds one: among the files Git tracks (any
  // depth, so a monorepo's app counts), the best-ranked icon-like name.
  // A folder that is not a repository is searched a few levels deep.
  String? _icon(String root) {
    final files = _trackedFiles(root) ?? _shallowFiles(root);
    String? best;
    var bestScore = 1 << 30;
    for (final file in files) {
      final score = iconScore(file);
      if (score != null && score < bestScore) {
        best = file;
        bestScore = score;
      }
    }
    if (best == null) return null;
    final path = p.join(root, best);
    return p.extension(path).toLowerCase() == '.ico' ? _icoAsPng(path) : path;
  }

  // ICO is not among the formats Flutter promises to decode, so it is
  // converted once with the system's sips into the user's cache folder,
  // and again only when the icon changes.
  String? _icoAsPng(String ico) {
    try {
      final modified = File(ico).lastModifiedSync().millisecondsSinceEpoch;
      final key = '${ico.hashCode.toUnsigned(32).toRadixString(16)}-$modified';
      final png = paths.inHome('Library/Caches/skill-cabinet/project-icons/$key.png');
      if (File(png).existsSync()) return png;
      Directory(p.dirname(png)).createSync(recursive: true);
      final result = Process.runSync('/usr/bin/sips', ['-s', 'format', 'png', ico, '--out', png]);
      return result.exitCode == 0 && File(png).existsSync() ? png : null;
    } catch (_) {
      return null;
    }
  }

  List<String>? _trackedFiles(String root) {
    if (!lexists(p.join(root, '.git'))) return null;
    try {
      final result = Process.runSync('/usr/bin/git', ['-C', root, 'ls-files', '-z'], stdoutEncoding: utf8);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).split('\u0000').where((f) => f.isNotEmpty).toList();
    } catch (_) {
      return null;
    }
  }

  List<String> _shallowFiles(String root, {int depth = 4}) {
    final found = <String>[];
    void walk(String dir, int level) {
      for (final name in listDir(dir)) {
        final path = p.join(dir, name);
        if (FileSystemEntity.isDirectorySync(path)) {
          if (level < depth && !name.startsWith('.') && !_skippedDirs.contains(name.toLowerCase())) {
            walk(path, level + 1);
          }
        } else {
          found.add(p.relative(path, from: root));
        }
      }
    }

    walk(root, 0);
    return found;
  }

  static const _skippedDirs = {
    'node_modules',
    'vendor',
    'dist',
    'build',
    'out',
    'bin',
    'obj',
    'pods',
    'test',
    'tests',
    'e2e',
    'spec',
    'docs',
    'doc',
    'example',
    'examples',
    'fixtures',
    'coverage',
    'third_party',
    '.git',
  };

  static final _formats = {'.png': 0, '.svg': 0, '.jpg': 1, '.jpeg': 1, '.webp': 1, '.ico': 2};
  static final _size = RegExp(r'(\d{2,4})');
  // "logo" as a word of the name: market_logo, logo-dark, not logout.
  static final _logo = RegExp(r'(^|[-_.\s])logo([-_.\s\d]|$)');

  // Lower is better; null when the file is not a logo candidate. The name
  // decides first (an app icon beats a favicon beats a logo), then the
  // format, then how deep it sits; among sizes, the larger the better.
  static int? iconScore(String relative) {
    final parts = p.split(relative.toLowerCase());
    if (parts.any(_skippedDirs.contains)) return null;
    final file = parts.last;
    final format = _formats[p.extension(file)];
    if (format == null) return null;
    final name = p.basenameWithoutExtension(file);
    final int rank;
    if (name.startsWith('apple-touch-icon')) {
      rank = 0;
    } else if (RegExp(r'^(app[-_]?icon|ic_launcher|icon-\d+|android-chrome-\d+)').hasMatch(name) ||
        name.endsWith('-app-icon') ||
        parts.any((part) => part.endsWith('.appiconset'))) {
      rank = 1;
    } else if (name.startsWith('favicon')) {
      rank = 2;
    } else if (name == 'icon' || _logo.hasMatch(name)) {
      rank = 3;
    } else {
      return null;
    }
    final size = int.tryParse(_size.firstMatch(name)?.group(1) ?? '') ?? 0;
    // An unsized SVG scales; an unsized raster is usually small.
    final sizeBonus = p.extension(file) == '.svg' ? 9 : (size.clamp(0, 512) / 64).round();
    return rank * 10000 + format * 1000 + (parts.length - 1).clamp(0, 9) * 100 + (9 - sizeBonus.clamp(0, 9)) * 10;
  }

  // The last commit, checkout or staging, from Git's own bookkeeping.
  DateTime? _activity(String root) {
    DateTime? latest;
    for (final name in ['logs/HEAD', 'index', 'HEAD']) {
      final file = File(p.join(root, '.git', name));
      if (!file.existsSync()) continue;
      final modified = file.lastModifiedSync();
      if (latest == null || modified.isAfter(latest)) latest = modified;
    }
    return latest ?? (lexists(root) ? Directory(root).statSync().modified : null);
  }
}
