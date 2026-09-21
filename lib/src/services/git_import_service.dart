import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/frontmatter.dart';
import '../domain/git_import.dart';
import '../domain/library.dart';
import 'cabinet_paths.dart';
import 'fs_util.dart';
import 'library_service.dart';

class GitImportException implements Exception {
  const GitImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

// A shallow checkout is the remote adapter: discovery and import work for any
// ordinary Git server and need no host-specific API or token.
class GitImportService {
  const GitImportService(this.paths);

  static const _git = '/usr/bin/git';
  static const _tempPrefix = 'skill-cabinet-git-';
  static const maxCandidates = 200;
  static const maxFilesPerSkill = 500;
  static const maxBytesPerSkill = 50 * 1024 * 1024;

  final CabinetPaths paths;

  Future<GitImportPreview> preview(String rawUrl) async {
    final sourceUrl = validateRemoteUrl(rawUrl);
    final session = Directory.systemTemp.createTempSync(_tempPrefix);
    final checkout = p.join(session.path, 'repository');
    try {
      final clone = await Process.run(
        _git,
        [
          '-c',
          'http.lowSpeedLimit=1000',
          '-c',
          'http.lowSpeedTime=30',
          'clone',
          '--depth',
          '1',
          '--no-tags',
          '--',
          sourceUrl,
          checkout,
        ],
        environment: _gitEnvironment,
      );
      if (clone.exitCode != 0) throw GitImportException(_cloneError(clone.stderr));

      final revision = _gitValue(checkout, ['rev-parse', 'HEAD']);
      final branch = _gitValue(checkout, ['branch', '--show-current']);
      final repository = _repositoryName(sourceUrl);
      final found = findSkillDirs(checkout, limit: maxCandidates);
      final sources = _readSources();
      final candidates = <GitSkillCandidate>[];
      for (final path in found) {
        final relative = p.equals(path, checkout) ? '' : p.relative(path, from: checkout).replaceAll('\\', '/');
        final name = relative.isEmpty ? repository : p.basename(path);
        final source = sources[name];
        final duplicate = lexists(p.join(paths.storeDir, name));
        candidates.add(
          GitSkillCandidate(
            name: name,
            repositoryPath: relative,
            localPath: path,
            description: _descriptionAt(path),
            duplicate: duplicate,
            tracked: duplicate && source != null && source.sourceUrl == sourceUrl && source.repositoryPath == relative,
            blockedReason: _blockedReason(path),
          ),
        );
      }
      candidates.sort((a, b) => a.repositoryPath.compareTo(b.repositoryPath));

      final normalized = markClashes(candidates);

      return GitImportPreview(
        sourceUrl: sourceUrl,
        repository: repository,
        ref: branch.isEmpty ? 'HEAD' : branch,
        revision: revision,
        checkoutPath: checkout,
        candidates: normalized,
      );
    } catch (_) {
      if (session.existsSync()) session.deleteSync(recursive: true);
      rethrow;
    }
  }

  // Folders sharing a name would land on the same store folder. The
  // shallowest is offered by default: a repository's main copy usually
  // sits above the ones bundled with optional add-ons.
  static List<GitSkillCandidate> markClashes(List<GitSkillCandidate> candidates) {
    final byName = <String, List<GitSkillCandidate>>{};
    for (final candidate in candidates) {
      byName.putIfAbsent(candidate.name, () => []).add(candidate);
    }
    int depth(GitSkillCandidate candidate) =>
        candidate.repositoryPath.isEmpty ? 0 : candidate.repositoryPath.split('/').length;
    final preferred = {
      for (final entry in byName.entries)
        if (entry.value.length > 1)
          entry.key: (entry.value.toList()..sort((a, b) => depth(a).compareTo(depth(b)))).first.repositoryPath,
    };
    return [
      for (final candidate in candidates)
        preferred.containsKey(candidate.name)
            ? GitSkillCandidate(
                name: candidate.name,
                repositoryPath: candidate.repositoryPath,
                localPath: candidate.localPath,
                description: candidate.description,
                duplicate: candidate.duplicate,
                tracked: candidate.tracked,
                clashes: true,
                alternative: preferred[candidate.name] != candidate.repositoryPath,
                blockedReason: candidate.blockedReason,
              )
            : candidate,
    ];
  }

  GitImportResult importSelected(GitImportPreview preview, Iterable<String> pathsToImport) {
    final session = _validatedSession(preview.checkoutPath);
    final selectedPaths = pathsToImport.toSet();
    final selected = preview.candidates.where(
      (candidate) => selectedPaths.contains(candidate.repositoryPath) && candidate.selectable,
    );
    final names = <String>{};
    for (final candidate in selected) {
      if (!names.add(candidate.name)) {
        throw GitImportException('Choose one folder for ${candidate.name}; two would replace each other');
      }
    }
    if (selected.isEmpty) {
      discard(preview);
      return GitImportResult(LibraryImportResult(LibraryService(paths).scan()));
    }

    final staging = Directory(p.join(session.path, 'selected'))..createSync();
    try {
      final fresh = <String>[];
      final replacing = <String, String>{};
      for (final candidate in selected) {
        final source = _validatedCandidate(preview.checkoutPath, candidate.localPath);
        final destination = p.join(staging.path, candidate.name);
        _copyTreeSafe(source, destination);
        if (candidate.duplicate) {
          replacing[candidate.name] = destination;
        } else {
          fresh.add(destination);
        }
      }

      final replaced = <String>[];
      final problems = <String>[];
      for (final entry in replacing.entries) {
        try {
          _replaceInStore(entry.key, entry.value);
          replaced.add(entry.key);
        } catch (error) {
          problems.add('${entry.key} could not be replaced: $error');
        }
      }
      var result = LibraryService(paths).importSkills(fresh, move: true);
      if (replacing.isNotEmpty) {
        final notice = [
          if (result.snapshot.notice.isNotEmpty) result.snapshot.notice,
          if (replaced.length == 1) 'Replaced ${replaced.first} with the Git version',
          if (replaced.length > 1) 'Replaced ${replaced.length} skills with their Git versions',
          if (problems.length == 1) problems.first,
          if (problems.length > 1) '${problems.length} skills could not be replaced',
        ].join(' · ');
        result = LibraryImportResult(_withNotice(result.snapshot, notice), imported: [...result.imported, ...replaced]);
      }
      var saved = 0;
      if (result.imported.isNotEmpty) {
        final records = <String, GitSourceRecord>{
          ..._readSources(),
          for (final candidate in selected)
            if (result.imported.contains(candidate.name))
              candidate.name: GitSourceRecord(
                skillName: candidate.name,
                sourceUrl: preview.sourceUrl,
                ref: preview.ref,
                repositoryPath: candidate.repositoryPath,
                revision: preview.revision,
              ),
        };
        try {
          _writeSources(records);
          saved = result.imported.length;
        } catch (error) {
          final notice = result.snapshot.notice.isEmpty
              ? 'Imported, but Git tracking could not be saved: $error'
              : '${result.snapshot.notice} · Git tracking could not be saved: $error';
          return GitImportResult(LibraryImportResult(_withNotice(result.snapshot, notice), imported: result.imported));
        }
      }
      return GitImportResult(result, sourcesSaved: saved);
    } finally {
      if (session.existsSync()) session.deleteSync(recursive: true);
    }
  }

  // Swaps the store's copy of a skill for the staged one under the same
  // name, so agent links and skill-set memberships keep pointing at it.
  // The old copy is set aside first and put back if the swap fails.
  void _replaceInStore(String name, String staged) {
    if (!isPlainName(name)) throw GitImportException('Invalid skill name "$name"');
    final dest = p.join(paths.storeDir, name);
    // Hidden, so a scan meanwhile does not list it as a skill.
    final backup = p.join(paths.storeDir, '.$name.replaced');
    if (lexists(backup)) _removeEntry(backup);
    _renameEntry(dest, backup);
    try {
      try {
        Directory(staged).renameSync(dest);
      } on FileSystemException {
        // Another volume: copy, then remove the staged copy.
        copyTree(staged, dest);
        Directory(staged).deleteSync(recursive: true);
      }
    } catch (_) {
      if (lexists(dest)) _removeEntry(dest);
      _renameEntry(backup, dest);
      rethrow;
    }
    _removeEntry(backup);
  }

  void _renameEntry(String from, String to) => switch (FileSystemEntity.typeSync(from, followLinks: false)) {
    FileSystemEntityType.link => Link(from).renameSync(to),
    FileSystemEntityType.directory => Directory(from).renameSync(to),
    _ => File(from).renameSync(to),
  };

  // A linked-in skill loses only the link; its folder is left alone.
  void _removeEntry(String path) => switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    FileSystemEntityType.link => Link(path).deleteSync(),
    FileSystemEntityType.directory => Directory(path).deleteSync(recursive: true),
    _ => File(path).deleteSync(),
  };

  void discard(GitImportPreview preview) {
    final session = _validatedSession(preview.checkoutPath);
    if (session.existsSync()) session.deleteSync(recursive: true);
  }

  void removeSource(String skillName) {
    final records = _readSources();
    if (records.remove(skillName) != null) _writeSources(records);
  }

  Map<String, GitSourceRecord> sources() => _readSources();

  // Checks each unique repository/ref once. Git handles authentication through
  // the user's existing SSH agent or credential helper; no provider API or
  // token is involved.
  Future<GitUpdateCheckResult> checkForUpdates({bool force = false}) async {
    final records = _readSources();
    if (records.isEmpty) return const GitUpdateCheckResult(records: {}, checked: 0, updates: 0);

    final now = DateTime.now().toUtc();
    final groups = <String, List<String>>{};
    for (final entry in records.entries) {
      final source = entry.value;
      if (!force && source.lastCheckedAt != null && now.difference(source.lastCheckedAt!.toUtc()) < const Duration(hours: 24)) {
        continue;
      }
      groups.putIfAbsent('${source.sourceUrl}\u0000${source.ref}', () => []).add(entry.key);
    }
    if (groups.isEmpty) {
      return GitUpdateCheckResult(
        records: records,
        checked: 0,
        updates: records.values.where((record) => record.state == GitTrackingState.updateAvailable).length,
      );
    }

    var failures = 0;
    final remoteByGroup = <String, String>{};
    final errorsByGroup = <String, String>{};
    for (final entry in groups.entries) {
      final skill = records[entry.value.first]!;
      try {
        remoteByGroup[entry.key] = await _remoteRevision(skill.sourceUrl, skill.ref);
      } catch (error) {
        failures++;
        errorsByGroup[entry.key] = error.toString();
      }
    }

    final updated = <String, GitSourceRecord>{...records};
    for (final entry in groups.entries) {
      final remote = remoteByGroup[entry.key];
      final error = errorsByGroup[entry.key];
      for (final name in entry.value) {
        final record = records[name]!;
        updated[name] = record.withCheck(checkedAt: now, remote: remote, error: error);
      }
    }
    _writeSources(updated);
    return GitUpdateCheckResult(
      records: updated,
      checked: groups.length,
      updates: updated.values.where((record) => record.state == GitTrackingState.updateAvailable).length,
      failures: failures,
    );
  }

  Future<String> _remoteRevision(String sourceUrl, String ref) async {
    final remoteRef = ref == 'HEAD' ? 'HEAD' : 'refs/heads/$ref';
    final result = await Process.run(
      _git,
      ['-c', 'http.lowSpeedLimit=1000', '-c', 'http.lowSpeedTime=30', 'ls-remote', sourceUrl, remoteRef],
      environment: _gitEnvironment,
    ).timeout(const Duration(seconds: 45));
    if (result.exitCode != 0) throw GitImportException(_cloneError(result.stderr));
    final line = result.stdout.toString().trim().split('\n').first.trim();
    final revision = line.split(RegExp(r'\s+')).first;
    if (!RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(revision)) {
      throw const GitImportException('The remote branch could not be resolved');
    }
    return revision;
  }

  Map<String, String> get _gitEnvironment => {...Platform.environment, 'GIT_TERMINAL_PROMPT': '0'};

  String validateRemoteUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('-') || value.contains(RegExp(r'[\r\n\x00]'))) {
      throw const GitImportException('Paste a Git repository URL');
    }
    if (RegExp(r'^git@[^:/\s]+:[^\s]+$').hasMatch(value)) return value;

    final uri = Uri.tryParse(value);
    if (uri == null || !const {'https', 'ssh'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const GitImportException('Use an HTTPS or SSH Git repository URL');
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const GitImportException('The repository URL must not contain a query or fragment');
    }
    if (uri.userInfo.contains(':')) {
      throw const GitImportException('Do not put a password or token in the repository URL');
    }
    if (uri.pathSegments.isEmpty || uri.pathSegments.every((segment) => segment.isEmpty)) {
      throw const GitImportException('The repository URL has no repository path');
    }
    if (uri.host.toLowerCase() == 'github.com' && uri.pathSegments.contains('tree')) {
      throw const GitImportException('Paste the repository URL, not a GitHub folder page');
    }
    return value;
  }

  Directory _validatedSession(String checkoutPath) {
    final checkout = Directory(checkoutPath);
    if (!checkout.existsSync()) throw const GitImportException('The Git preview expired. Try again.');
    final canonicalCheckout = checkout.resolveSymbolicLinksSync();
    final session = Directory(p.dirname(canonicalCheckout));
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    if (!p.isWithin(temp, canonicalCheckout) || !p.basename(session.path).startsWith(_tempPrefix)) {
      throw const GitImportException('Invalid Git preview directory');
    }
    return session;
  }

  String _validatedCandidate(String checkoutPath, String candidatePath) {
    final checkout = Directory(checkoutPath).resolveSymbolicLinksSync();
    final candidate = Directory(candidatePath).resolveSymbolicLinksSync();
    if (candidate != checkout && !p.isWithin(checkout, candidate)) {
      throw const GitImportException('A selected skill escaped the repository checkout');
    }
    if (!isSkillDir(candidate)) throw const GitImportException('A selected folder is no longer a skill');
    return candidate;
  }

  void _copyTreeSafe(String source, String destination) {
    var files = 0;
    var bytes = 0;

    void copy(String from, String to) {
      Directory(to).createSync(recursive: true);
      for (final entity in Directory(from).listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name == '.git') continue;
        final target = p.join(to, name);
        switch (FileSystemEntity.typeSync(entity.path, followLinks: false)) {
          case FileSystemEntityType.directory:
            copy(entity.path, target);
          case FileSystemEntityType.file:
            files++;
            bytes += File(entity.path).lengthSync();
            if (files > maxFilesPerSkill) throw const GitImportException('A selected skill contains too many files');
            if (bytes > maxBytesPerSkill) throw const GitImportException('A selected skill is too large to import');
            File(entity.path).copySync(target);
          case FileSystemEntityType.link:
            throw const GitImportException('Symlinks inside skills are not supported');
          case FileSystemEntityType.notFound:
          case FileSystemEntityType.pipe:
          case FileSystemEntityType.unixDomainSock:
          default:
            throw const GitImportException('A selected skill contains an unsupported file');
        }
      }
    }

    copy(source, destination);
  }

  String? _blockedReason(String directory) {
    var files = 0;
    var bytes = 0;
    try {
      for (final entity in Directory(directory).listSync(recursive: true, followLinks: false)) {
        if (p.basename(entity.path) == '.git' || entity.path.contains('${p.separator}.git${p.separator}')) continue;
        final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
        if (type == FileSystemEntityType.link) return 'Symlinks are not supported';
        if (type == FileSystemEntityType.file) {
          files++;
          bytes += File(entity.path).lengthSync();
          if (files > maxFilesPerSkill) return 'Too many files';
          if (bytes > maxBytesPerSkill) return 'Skill is larger than 50 MB';
        }
      }
      return null;
    } catch (_) {
      return 'Could not inspect this folder';
    }
  }

  String _gitValue(String checkout, List<String> arguments) {
    final result = Process.runSync(_git, ['-C', checkout, ...arguments]);
    if (result.exitCode != 0) throw GitImportException('Could not inspect the cloned repository: ${result.stderr}');
    return result.stdout.toString().trim();
  }

  String _descriptionAt(String directory) {
    try {
      return splitFrontmatter(File(p.join(directory, 'SKILL.md')).readAsStringSync()).field('description');
    } catch (_) {
      return '';
    }
  }

  String _repositoryName(String sourceUrl) {
    final path = sourceUrl.startsWith('git@')
        ? sourceUrl.substring(sourceUrl.indexOf(':') + 1)
        : Uri.parse(sourceUrl).path;
    final name = p.posix.basename(path.replaceFirst(RegExp(r'/$'), ''));
    return name.endsWith('.git') ? name.substring(0, name.length - 4) : name;
  }

  String _cloneError(Object stderr) {
    final message = stderr
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        // git narrates the checkout it was making; that is our temp
        // directory, which says nothing to whoever pasted the URL.
        .replaceAll(RegExp(r"Cloning into '[^']*'\.\.\. ?"), '')
        .replaceAll(RegExp(r'^fatal: '), '')
        .trim();
    if (message.contains('Could not resolve host')) {
      return 'That host could not be reached. Check the URL and your connection.';
    }
    if (message.contains('Authentication failed') ||
        message.contains('Permission denied') ||
        message.contains('could not read Username')) {
      return 'Git authentication failed. Check your existing Git credentials or SSH key.';
    }
    if (message.contains('not found') || message.contains('does not exist')) {
      return 'The Git repository was not found, or you do not have access.';
    }
    return message.isEmpty ? 'Git could not clone the repository' : 'Git clone failed: $message';
  }

  Map<String, GitSourceRecord> _readSources() {
    Object? value = readJson(paths.gitSourcesFile);
    value ??= readJson(paths.githubSourcesFile);
    if (value is! Map) return {};
    final records = <String, GitSourceRecord>{};
    for (final entry in value.entries) {
      final record = GitSourceRecord.fromJson(entry.value);
      if (record != null) records[entry.key.toString()] = record;
    }
    return records;
  }

  void _writeSources(Map<String, GitSourceRecord> records) {
    writeJsonAtomic(paths.gitSourcesFile, {for (final entry in records.entries) entry.key: entry.value.toJson()});
  }

  LibrarySnapshot _withNotice(LibrarySnapshot snapshot, String notice) => LibrarySnapshot(
    root: snapshot.root,
    rootPath: snapshot.rootPath,
    skills: snapshot.skills,
    issues: snapshot.issues,
    notice: notice,
  );
}
