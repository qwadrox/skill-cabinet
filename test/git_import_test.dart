import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/domain/git_import.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/git_import_service.dart';
import 'package:skill_cabinet/src/services/fs_util.dart';

void main() {
  test('accepts HTTPS, SSH, and SCP-style Git URLs', () {
    const service = GitImportService(CabinetPaths('/tmp/cabinet'));
    expect(service.validateRemoteUrl('https://github.com/acme/skills.git'), contains('github.com'));
    expect(service.validateRemoteUrl('ssh://git@git.example.com/acme/skills'), startsWith('ssh://'));
    expect(service.validateRemoteUrl('git@git.example.com:acme/skills.git'), startsWith('git@'));
  });

  test('rejects embedded credentials, local paths, and GitHub folder pages', () {
    const service = GitImportService(CabinetPaths('/tmp/cabinet'));
    expect(
      () => service.validateRemoteUrl('https://user:secret@example.com/acme/skills'),
      throwsA(isA<GitImportException>()),
    );
    expect(() => service.validateRemoteUrl('/tmp/skills'), throwsA(isA<GitImportException>()));
    expect(
      () => service.validateRemoteUrl('https://github.com/acme/skills/tree/main/agents'),
      throwsA(isA<GitImportException>()),
    );
  });

  test('source records round-trip through JSON', () {
    const record = GitSourceRecord(
      skillName: 'reviewer',
      sourceUrl: 'https://git.example.com/acme/skills.git',
      ref: 'main',
      repositoryPath: 'reviewer',
      revision: 'abc123',
    );
    final restored = GitSourceRecord.fromJson(record.toJson());
    expect(restored?.skillName, 'reviewer');
    expect(restored?.revision, 'abc123');
  });

  test('source metadata path stays inside the cabinet', () {
    const paths = CabinetPaths('/tmp/example-home');
    expect(p.dirname(paths.gitSourcesFile), paths.cabinetDir);
    expect(p.isAbsolute(paths.gitSourcesFile), isTrue);
  });

  test('checks a Git remote without a provider API', () async {
    final root = Directory.systemTemp.createTempSync('git-update-check-');
    addTearDown(() => root.deleteSync(recursive: true));
    final remote = Directory(p.join(root.path, 'remote'))..createSync(recursive: true);
    File(p.join(remote.path, 'SKILL.md')).writeAsStringSync('# first\n');
    for (final args in [
      ['init', '-q'],
      ['config', 'user.email', 'test@example.com'],
      ['config', 'user.name', 'Test'],
      ['add', '.'],
      ['commit', '-qm', 'first'],
    ]) {
      final result = Process.runSync('/usr/bin/git', ['-C', remote.path, ...args]);
      expect(result.exitCode, 0, reason: '${args.join(' ')} failed: ${result.stderr}');
    }
    final revision = Process.runSync('/usr/bin/git', ['-C', remote.path, 'rev-parse', 'HEAD']).stdout.toString().trim();
    final paths = CabinetPaths(p.join(root.path, 'home'));
    final record = GitSourceRecord(
      skillName: 'example',
      sourceUrl: remote.path,
      ref: 'HEAD',
      repositoryPath: '.',
      revision: revision,
    );
    writeJsonAtomic(paths.gitSourcesFile, {'example': record.toJson()});
    final first = await GitImportService(paths).checkForUpdates(force: true);
    expect(first.checked, 1);
    expect(first.records['example']?.state, GitTrackingState.upToDate);

    File(p.join(remote.path, 'SKILL.md')).writeAsStringSync('# second\n');
    final commit = Process.runSync('/usr/bin/git', ['-C', remote.path, 'add', '.']);
    expect(commit.exitCode, 0);
    final committed = Process.runSync('/usr/bin/git', ['-C', remote.path, 'commit', '-qm', 'second']);
    expect(committed.exitCode, 0);
    final second = await GitImportService(paths).checkForUpdates(force: true);
    expect(second.records['example']?.state, GitTrackingState.updateAvailable);
    expect(second.updates, 1);
  });
}
