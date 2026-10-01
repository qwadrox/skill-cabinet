import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/app/cabinet_controller.dart';
import 'package:skill_cabinet/src/domain/git_import.dart';
import 'package:skill_cabinet/src/domain/notice.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/fs_util.dart';
import 'package:skill_cabinet/src/services/git_import_service.dart';

void main() {
  late Directory root;
  late String remote;
  late String incoming;
  late String local;
  late CabinetPaths paths;
  late GitImportService service;

  void write(String folder, String name, String content) {
    final file = File(p.join(folder, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String git(List<String> args) {
    final result = Process.runSync('/usr/bin/git', ['-C', remote, ...args]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return result.stdout.toString().trim();
  }

  void commit() {
    git(['add', '.']);
    git(['commit', '-qm', 'change']);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('git-diff-test-');
    remote = p.join(root.path, 'remote');
    incoming = p.join(remote, 'skills', 'reviewer');
    paths = CabinetPaths(p.join(root.path, 'home'));
    local = p.join(paths.storeDir, 'reviewer');
    for (final folder in [incoming, local]) {
      write(folder, 'SKILL.md', '# Original\n');
      write(folder, 'references/guide.md', 'same\n');
    }
    git(['init', '-q']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'Test']);
    commit();
    final record = GitSourceRecord(
      skillName: 'reviewer',
      sourceUrl: remote,
      ref: 'HEAD',
      repositoryPath: 'skills/reviewer',
      revision: git(['rev-parse', 'HEAD']),
    );
    writeJsonAtomic(paths.gitSourcesFile, {'reviewer': record.toJson()});
    service = GitImportService(paths);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('compares actual local edits, added, deleted and binary files without changing the cabinet', () async {
    write(local, 'SKILL.md', '# My local edits\n');
    write(local, 'local-only.md', 'my notes\n');
    write(incoming, 'SKILL.md', '# Incoming\n');
    write(incoming, 'new file.md', 'new\n');
    File(p.join(incoming, 'image.png')).writeAsBytesSync([0, 1, 2]);
    commit();
    final metadata = File(paths.gitSourcesFile).readAsStringSync();

    final preview = await service.previewUpdate('reviewer');
    final files = {for (final file in preview.files) file.path: file};
    expect(preview.files.first.path, 'SKILL.md');
    expect(files.keys, unorderedEquals(['SKILL.md', 'local-only.md', 'new file.md', 'image.png']));
    expect(files['SKILL.md']!.diff, contains('-# My local edits'));
    expect(files['SKILL.md']!.diff, contains('+# Incoming'));
    expect(files['local-only.md']!.kind, GitFileChangeKind.deleted);
    expect(files['local-only.md']!.diff, contains('-my notes'));
    expect(files['new file.md']!.kind, GitFileChangeKind.added);
    expect(files['image.png']!.message, 'Binary file');
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), '# My local edits\n');
    expect(File(p.join(local, 'local-only.md')).existsSync(), isTrue);
    expect(File(paths.gitSourcesFile).readAsStringSync(), metadata);
  });

  test('repository changes outside the skill produce an empty content diff', () async {
    write(remote, 'README.md', 'unrelated change\n');
    commit();
    expect((await service.previewUpdate('reviewer')).files, isEmpty);
  });

  test('update notice stays accurate when another repository cannot be checked', () async {
    write(incoming, 'SKILL.md', '# Updated reviewer\n');
    commit();
    final records = {
      ...service.sources(),
      'unavailable': GitSourceRecord(
        skillName: 'unavailable',
        sourceUrl: p.join(root.path, 'missing-repository'),
        ref: 'HEAD',
        repositoryPath: '.',
        revision: 'old',
      ),
    };
    writeJsonAtomic(paths.gitSourcesFile, {for (final e in records.entries) e.key: e.value.toJson()});
    final controller = CabinetController(paths)..gitSources = records;
    addTearDown(controller.dispose);
    await controller.checkGitUpdates();
    expect(controller.gitSources['reviewer']!.state, GitTrackingState.updateAvailable);
    expect(controller.gitSources['unavailable']!.state, GitTrackingState.error);
    expect(controller.notice, const Notice.info('1 Git update available'));
  });

  test('checking for updates is informational; only an unreachable repository warns', () async {
    final controller = CabinetController(paths)..gitSources = service.sources();
    addTearDown(controller.dispose);
    final checking = controller.checkGitUpdates();
    expect(controller.notice, const Notice.info('Checking Git repositories for updates…'));
    await checking;
    expect(controller.notice, const Notice.info('All Git-tracked skills are up to date'));

    Directory(incoming).deleteSync(recursive: true);
    commit();
    await controller.checkGitUpdates();
    expect(controller.notice, const Notice.warning('Could not check 1 Git repository'));
  });

  test('update list excludes unchanged skills when a shared repository advances', () async {
    final before = git(['rev-parse', 'HEAD']);
    final otherLocal = p.join(paths.storeDir, 'other');
    final otherIncoming = p.join(remote, 'skills', 'other');
    write(otherLocal, 'SKILL.md', '# Other\n');
    write(otherIncoming, 'SKILL.md', '# Other\n');
    write(incoming, 'SKILL.md', '# Updated reviewer\n');
    commit();
    final records = {
      'reviewer': service.sources()['reviewer']!,
      'other': GitSourceRecord(
        skillName: 'other',
        sourceUrl: remote,
        ref: 'HEAD',
        repositoryPath: 'skills/other',
        revision: before,
      ),
    };
    writeJsonAtomic(paths.gitSourcesFile, {for (final e in records.entries) e.key: e.value.toJson()});
    final checked = await service.checkForUpdates(force: true);
    expect(checked.checked, 1);
    expect(checked.updates, 1);
    expect(checked.records['reviewer']!.state, GitTrackingState.updateAvailable);
    expect(checked.records['other']!.state, GitTrackingState.upToDate);
    expect(service.sources()['other']!.state, GitTrackingState.upToDate);
    expect(checked.records['other']!.revision, before);
    expect(File(p.join(otherLocal, 'SKILL.md')).readAsStringSync(), '# Other\n');
  });

  test('recent repository-only checks are recomputed on startup', () async {
    final record = service.sources()['reviewer']!;
    write(remote, 'README.md', 'unrelated change\n');
    commit();
    final legacy = record.withCheck(checkedAt: DateTime.now().toUtc(), remote: git(['rev-parse', 'HEAD']));
    writeJsonAtomic(paths.gitSourcesFile, {'reviewer': legacy.toJson()});
    expect(legacy.state, GitTrackingState.tracked);
    final checked = await service.checkForUpdates();
    expect(checked.checked, 1);
    expect(checked.updates, 0);
    expect(service.sources()['reviewer']!.state, GitTrackingState.upToDate);
    expect((await service.checkForUpdates()).checked, 0);
  });

  test('a forced check compares local edits even when the remote revision has not changed', () async {
    expect((await service.checkForUpdates(force: true)).updates, 0);
    write(local, 'SKILL.md', '# Local changes\n');
    expect((await service.checkForUpdates(force: true)).updates, 1);
    write(local, 'SKILL.md', '# Original\n');
    expect((await service.checkForUpdates(force: true)).updates, 0);
  });

  test('a missing incoming skill reports an error instead of claiming it is unchanged', () async {
    Directory(incoming).deleteSync(recursive: true);
    commit();
    final checked = await service.checkForUpdates(force: true);
    expect(checked.updates, 0);
    expect(checked.failures, 1);
    expect(checked.records['reviewer']!.state, GitTrackingState.error);
    expect(checked.records['reviewer']!.lastCheckError, contains('"skills/reviewer" no longer exists on HEAD'));
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), '# Original\n');
  });

  test('previews executable permissions and files that cannot be rendered as text', () async {
    for (final folder in [incoming, local]) {
      write(folder, 'run.sh', '#!/bin/sh\n');
    }
    expect(Process.runSync('/bin/chmod', ['+x', p.join(incoming, 'run.sh')]).exitCode, 0);
    File(p.join(incoming, 'data.bin')).writeAsBytesSync([255, 254, 253]);
    write(incoming, 'large.md', 'a' * (256 * 1024 + 1));
    commit();
    final preview = await service.previewUpdate('reviewer');
    final files = {for (final file in preview.files) file.path: file};
    expect(files['run.sh']!.message, 'Executable permission added');
    expect(files['data.bin']!.message, 'Binary file');
    expect(files['large.md']!.message, 'File too large to preview');
  });

  test('a remote changed after review is refused without replacing local files', () async {
    write(incoming, 'SKILL.md', '# Reviewed\n');
    commit();
    final reviewed = await service.previewUpdate('reviewer');
    write(incoming, 'SKILL.md', '# Later\n');
    commit();
    final refused = await service.applyUpdates(['reviewer'], reviewedRevisions: {'reviewer': reviewed.revision});
    expect(refused.updated, isEmpty);
    expect(refused.failures['reviewer'], contains('changed since review'));
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), '# Original\n');
    final refreshed = await service.previewUpdate('reviewer');
    final applied = await service.applyUpdates(['reviewer'], reviewedRevisions: {'reviewer': refreshed.revision});
    expect(applied.updated, ['reviewer']);
    expect(applied.failures, isEmpty);
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), '# Later\n');
  });

  test('review refuses unsafe names and symlinked incoming files', () async {
    await expectLater(service.previewUpdate('../reviewer'), throwsA(isA<GitImportException>()));
    Link(p.join(incoming, 'linked.md')).createSync('SKILL.md');
    commit();
    await expectLater(service.previewUpdate('reviewer'), throwsA(isA<GitImportException>()));
    expect(File(p.join(local, 'SKILL.md')).readAsStringSync(), '# Original\n');
  });
}
