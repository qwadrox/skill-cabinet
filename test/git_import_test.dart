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

  test('replaces a local skill with the Git copy and tracks it', () {
    final root = Directory.systemTemp.createTempSync('git-replace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = CabinetPaths(p.join(root.path, 'home'));
    final local = Directory(p.join(paths.storeDir, 'reviewer'))..createSync(recursive: true);
    File(p.join(local.path, 'SKILL.md')).writeAsStringSync('# local\n');
    File(p.join(local.path, 'notes.md')).writeAsStringSync('local only\n');

    final session = Directory.systemTemp.createTempSync('skill-cabinet-git-');
    addTearDown(() {
      if (session.existsSync()) session.deleteSync(recursive: true);
    });
    final checkout = p.join(session.path, 'repository');
    final remote = Directory(p.join(checkout, 'reviewer'))..createSync(recursive: true);
    File(p.join(remote.path, 'SKILL.md')).writeAsStringSync('# from git\n');

    final preview = GitImportPreview(
      sourceUrl: 'https://git.example.com/acme/skills.git',
      repository: 'skills',
      ref: 'main',
      revision: 'abc123',
      checkoutPath: checkout,
      candidates: [
        GitSkillCandidate(
          name: 'reviewer',
          repositoryPath: 'reviewer',
          localPath: remote.path,
          description: '',
          duplicate: true,
        ),
      ],
    );
    expect(preview.candidates.single.replaces, isTrue);

    final result = GitImportService(paths).importSelected(preview, ['reviewer']);
    expect(result.sourcesSaved, 1);
    expect(result.library.imported, ['reviewer']);
    expect(File(p.join(local.path, 'SKILL.md')).readAsStringSync(), '# from git\n');
    expect(File(p.join(local.path, 'notes.md')).existsSync(), isFalse);
    expect(Directory(paths.storeDir).listSync().map((e) => p.basename(e.path)), ['reviewer']);
    expect(GitImportService(paths).sources()['reviewer']?.sourceUrl, preview.sourceUrl);
  });

  test('a skill already tracked from the same folder is not offered again', () {
    const candidate = GitSkillCandidate(
      name: 'reviewer',
      repositoryPath: 'reviewer',
      localPath: '/tmp/x',
      description: '',
      duplicate: true,
      tracked: true,
    );
    expect(candidate.selectable, isFalse);
    expect(candidate.replaces, isFalse);
  });

  test('a name the repository holds twice defaults to the shallower copy', () {
    GitSkillCandidate at(String path) =>
        GitSkillCandidate(name: p.basename(path), repositoryPath: path, localPath: '/tmp/$path', description: '');
    final marked = GitImportService.markClashes([
      at('extensions/banana/skills/seo-image-gen'),
      at('skills/seo-audit'),
      at('skills/seo-image-gen'),
    ]);
    final byPath = {for (final c in marked) c.repositoryPath: c};
    expect(byPath['skills/seo-image-gen']!.clashes, isTrue);
    expect(byPath['skills/seo-image-gen']!.alternative, isFalse);
    expect(byPath['extensions/banana/skills/seo-image-gen']!.alternative, isTrue);
    expect(byPath['extensions/banana/skills/seo-image-gen']!.selectable, isTrue);
    expect(byPath['skills/seo-audit']!.clashes, isFalse);
  });

  test('refuses to import two folders of the same name', () {
    final session = Directory.systemTemp.createTempSync('skill-cabinet-git-');
    addTearDown(() {
      if (session.existsSync()) session.deleteSync(recursive: true);
    });
    final checkout = p.join(session.path, 'repository');
    Directory(checkout).createSync();
    GitSkillCandidate at(String path) => GitSkillCandidate(
      name: p.basename(path),
      repositoryPath: path,
      localPath: p.join(checkout, path),
      description: '',
    );
    final preview = GitImportPreview(
      sourceUrl: 'https://git.example.com/acme/skills.git',
      repository: 'skills',
      ref: 'main',
      revision: 'abc123',
      checkoutPath: checkout,
      candidates: GitImportService.markClashes([at('a/review'), at('b/review')]),
    );
    final service = GitImportService(CabinetPaths(p.join(session.path, 'home')));
    expect(() => service.importSelected(preview, ['a/review', 'b/review']), throwsA(isA<GitImportException>()));
  });
}
