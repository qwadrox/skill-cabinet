// Backup service: keeps the cabinet folder under Git.
//
//   ~/.skill-cabinet/.git          the history: one commit per backup point
//   ~/.skill-cabinet/.gitignore    temp files and Finder litter
//   origin (optional)              a remote the history is pushed to
//
// Everything in the cabinet folder is backed up: the store, the skill
// sets, the agents and their assignments, and where Git skills came from.
// A backup point is made only when something changed, so it is safe to
// ask for one at any time.
//
// One machine writes, the remote is its copy. Nothing is ever merged or
// force-pushed: a remote that moved on is reported, and taking it over is
// a restore, which keeps what it replaced on the `before-restore` branch.
//
// The local operations are quick and run in the backend's queue with the
// other services' writes. The network ones (probe, push) run outside it,
// so a slow remote never holds up the UI; they touch only Git's own data.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/backup.dart';
import 'cabinet_paths.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

// What a remote holds before it is connected.
enum RemoteContents { empty, backup, other }

class BackupService {
  const BackupService(this.paths);

  static const _git = '/usr/bin/git';
  static const _branch = 'main';
  static const _remoteRef = 'refs/remotes/origin/$_branch';
  static const _probeRef = 'refs/cabinet/probe';
  static const _historyLength = 50;
  static const _networkTimeout = Duration(seconds: 60);

  // Backups must not depend on the user's Git setup: a missing identity or
  // a signing key that wants a passphrase would stop every commit.
  static const _config = [
    '-c',
    'user.name=Skill Cabinet',
    '-c',
    'user.email=skill-cabinet@localhost',
    '-c',
    'commit.gpgsign=false',
    '-c',
    'core.quotePath=false',
  ];

  static const _ignored = '# Written by Skill Cabinet\n*.tmp\n.DS_Store\n';

  final CabinetPaths paths;

  String get _dir => paths.cabinetDir;

  // ---- local ------------------------------------------------------------------

  BackupStatus status() {
    if (!_isRepo) return BackupStatus.empty;
    final remote = _remoteUrl();
    return BackupStatus(history: _history(), remote: remote, unpushed: remote.isEmpty ? 0 : _unpushed());
  }

  // Records the cabinet as it is now, when it differs from the last backup.
  BackupStatus backUp() {
    _ensureRepo();
    _commitAll(null);
    return status();
  }

  // Puts the cabinet back to a backup point, as a new backup point on top:
  // the history only grows, so a restore can itself be undone.
  BackupStatus restore(String id) {
    _ensureRepo();
    _commitAll(null);
    final entry = _history().where((e) => e.id == id).firstOrNull;
    final date = entry == null ? id.substring(0, 7) : backupDateLabel(entry.date);
    _out(['restore', '--source', id, '--staged', '--worktree', '--', '.']);
    _commitAll('Restored the backup of $date');
    return status();
  }

  void setRemote(String url) {
    _ensureRepo();
    final args = _remoteUrl().isEmpty ? ['remote', 'add', 'origin', url] : ['remote', 'set-url', 'origin', url];
    _out(args);
  }

  BackupStatus removeRemote() {
    if (_isRepo && _remoteUrl().isNotEmpty) _out(['remote', 'remove', 'origin']);
    return status();
  }

  // Replaces the cabinet with the probed remote backup and follows that
  // remote from now on. What was here stays on the `before-restore` branch.
  BackupStatus adoptRemote(String url) {
    _ensureRepo();
    if (_run(['rev-parse', '--verify', '--quiet', _probeRef]).exitCode != 0) {
      throw const BackupException('Connect to the repository again.');
    }
    _commitAll(null);
    if (_hasHead) _out(['branch', '-f', 'before-restore', 'HEAD']);
    setRemote(url);
    _out(['update-ref', _remoteRef, _probeRef]);
    _out(['update-ref', '-d', _probeRef]);
    _out(['reset', '--hard', '--quiet', _remoteRef]);
    _out(['branch', '--set-upstream-to', 'origin/$_branch']);
    return status();
  }

  // ---- network ----------------------------------------------------------------

  // Looks at a remote before it is connected. A backup found there is
  // fetched (not checked out), ready for adoptRemote.
  Future<RemoteContents> probe(String url) async {
    _ensureRepo();
    final heads = await _network(['ls-remote', '--heads', url]);
    if (heads.trim().isEmpty) return RemoteContents.empty;
    if (!heads.split('\n').any((line) => line.endsWith('refs/heads/$_branch'))) return RemoteContents.other;
    await _network(['fetch', '--quiet', '--no-tags', url, '+refs/heads/$_branch:$_probeRef']);
    final top = _out(['ls-tree', '--name-only', _probeRef]).split('\n');
    final isBackup = top.contains('skills') || top.contains('collections.json') || top.contains('deployment.json');
    if (!isBackup) _run(['update-ref', '-d', _probeRef]);
    return isBackup ? RemoteContents.backup : RemoteContents.other;
  }

  // Sends new backup points to the remote.
  Future<void> push() async {
    if (!_isRepo || !_hasHead || _remoteUrl().isEmpty) return;
    await _network(['push', '--quiet', '--set-upstream', 'origin', '$_branch:$_branch']);
  }

  // ---- git ----------------------------------------------------------------------

  bool get _isRepo => Directory(p.join(_dir, '.git')).existsSync();

  bool get _hasHead => _run(['rev-parse', '--verify', '--quiet', 'HEAD']).exitCode == 0;

  void _ensureRepo() {
    Directory(_dir).createSync(recursive: true);
    if (!_isRepo) _out(['init', '--quiet', '--initial-branch', _branch]);
    final ignore = File(p.join(_dir, '.gitignore'));
    if (!ignore.existsSync()) ignore.writeAsStringSync(_ignored);
  }

  // Commits everything that changed; returns false when nothing did.
  bool _commitAll(String? message) {
    _out(['add', '--all']);
    if (_run(['diff', '--cached', '--quiet']).exitCode == 0) return false;
    _out(['commit', '--quiet', '--no-verify', '-m', message ?? _summary()]);
    return true;
  }

  String _remoteUrl() {
    final result = _run(['remote', 'get-url', 'origin']);
    return result.exitCode == 0 ? result.stdout.toString().trim() : '';
  }

  int _unpushed() {
    if (!_hasHead) return 0;
    final known = _run(['rev-parse', '--verify', '--quiet', _remoteRef]).exitCode == 0;
    final range = known ? '$_remoteRef..HEAD' : 'HEAD';
    return int.tryParse(_out(['rev-list', '--count', range])) ?? 0;
  }

  List<BackupEntry> _history() {
    if (!_hasHead) return const [];
    final log = _out(['log', '-n', '$_historyLength', '--format=%H%x1f%cI%x1f%s']);
    return [
      for (final line in log.split('\n'))
        if (line.split('\x1f') case [final id, final date, final summary])
          BackupEntry(id: id, date: DateTime.parse(date), summary: summary),
    ];
  }

  // A commit message from the staged changes, in the cabinet's terms:
  // "Added pdf, seo · Removed old · Updated skill sets".
  String _summary() {
    final changes = _out(['diff', '--cached', '--name-status', '--no-renames']);
    final skills = <String, Set<String>>{};
    final files = <String>{};
    for (final line in changes.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final status = line.substring(0, 1);
      final parts = p.posix.split(line.substring(tab + 1));
      if (parts.length > 1 && parts.first == 'skills') {
        skills.putIfAbsent(parts[1], () => {}).add(status);
      } else if (parts.first != '.gitignore') {
        files.add(switch (parts.first) {
          'collections.json' => 'skill sets',
          'deployment.json' => 'agents',
          'git_sources.json' => 'Git sources',
          final other => other,
        });
      }
    }
    if (!_hasHead) {
      return 'First backup · ${skills.length} skill${skills.length == 1 ? '' : 's'}';
    }
    final added = [
      for (final e in skills.entries)
        if (e.value.every((s) => s == 'A')) e.key,
    ];
    final removed = [
      for (final e in skills.entries)
        if (e.value.every((s) => s == 'D')) e.key,
    ];
    final changed = [
      for (final e in skills.entries)
        if (!added.contains(e.key) && !removed.contains(e.key)) e.key,
    ];
    final parts = [
      if (added.isNotEmpty) 'Added ${_names(added)}',
      if (removed.isNotEmpty) 'Removed ${_names(removed)}',
      if (changed.isNotEmpty) 'Changed ${_names(changed)}',
      if (files.isNotEmpty) 'Updated ${(files.toList()..sort()).join(', ')}',
    ];
    return parts.isEmpty ? 'Backup' : parts.join(' · ');
  }

  static String _names(List<String> names) {
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3} more';
  }

  Map<String, String> get _environment {
    final env = Platform.environment;
    return {
      ...env,
      'GIT_TERMINAL_PROMPT': '0',
      // No window to type a passphrase into: fail instead of hanging.
      if (!env.containsKey('GIT_SSH_COMMAND')) 'GIT_SSH_COMMAND': 'ssh -o BatchMode=yes -o ConnectTimeout=20',
    };
  }

  ProcessResult _run(List<String> args) =>
      Process.runSync(_git, ['-C', _dir, ..._config, ...args], environment: _environment);

  String _out(List<String> args) {
    final result = _run(args);
    if (result.exitCode != 0) throw BackupException(_explain(result.stderr));
    return result.stdout.toString().trim();
  }

  Future<String> _network(List<String> args) async {
    final ProcessResult result;
    try {
      result = await Process.run(_git, [
        '-C',
        _dir,
        ..._config,
        ...args,
      ], environment: _environment).timeout(_networkTimeout);
    } on TimeoutException {
      throw const BackupException('The backup repository did not answer in time.');
    }
    if (result.exitCode != 0) throw BackupException(_explain(result.stderr));
    return result.stdout.toString();
  }

  // Git's stderr, said in the cabinet's words where it is a known case.
  static String _explain(Object stderr) {
    final text = stderr.toString().trim();
    final lower = text.toLowerCase();
    if (lower.contains('rejected') || lower.contains('fetch first') || lower.contains('non-fast-forward')) {
      return 'The backup repository has changes this Mac does not have. Nothing was overwritten.';
    }
    if (lower.contains('permission denied') ||
        lower.contains('authentication failed') ||
        lower.contains('could not read username') ||
        lower.contains('terminal prompts disabled')) {
      return 'Git could not sign in to the backup repository. Set up an SSH key or Git credentials for it first.';
    }
    if (lower.contains('repository not found') || lower.contains('does not appear to be a git repository')) {
      return 'Repository not found, or you have no access to it.';
    }
    if (lower.contains('could not resolve host')) return 'Could not reach the backup repository. Are you online?';
    final message = text.replaceAll(RegExp(r'\s+'), ' ').replaceFirst(RegExp(r'^(fatal|error): '), '');
    return message.isEmpty ? 'Git failed' : message;
  }
}
