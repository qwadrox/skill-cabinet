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
  late CabinetPaths paths;
  late GitImportService service;

  void skill(String name, {String description = 'A useful skill.'}) {
    final file = File(p.join(remote, 'skills', name, 'SKILL.md'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('---\nname: $name\ndescription: $description\n---\n# $name\n');
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

  Future<void> importReviewer() async {
    Directory(p.join(paths.storeDir, 'reviewer')).deleteSync(recursive: true);
    final preview = await service.previewRepository(remote, 'main');
    expect(service.importSelected(preview, ['skills/reviewer']).sourcesSaved, 1);
  }

  List<String> pending() => [
    for (final repository in GitImportService(paths).repositories())
      for (final skill in repository.pending) skill.repositoryPath,
  ];

  setUp(() {
    root = Directory.systemTemp.createTempSync('git-discovery-');
    remote = p.join(root.path, 'remote');
    paths = CabinetPaths(p.join(root.path, 'home'));
    skill('reviewer');
    skill('skipped');
    git(['init', '-qb', 'main']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'Test']);
    commit();
    Directory(paths.storeDir).createSync(recursive: true);
    copyTree(p.join(remote, 'skills', 'reviewer'), p.join(paths.storeDir, 'reviewer'));
    // Seed a trusted local remote, as the other Git integration tests do.
    final source = GitSourceRecord(
      skillName: 'reviewer',
      sourceUrl: remote,
      ref: 'main',
      repositoryPath: 'skills/reviewer',
      revision: git(['rev-parse', 'HEAD']),
    );
    writeJsonAtomic(paths.gitSourcesFile, {'reviewer': source.toJson()});
    service = GitImportService(paths);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('import records skipped skills; checks persist genuinely new skills without importing them', () async {
    await importReviewer();
    expect(service.repositories().single.seenPaths, {'skills/reviewer', 'skills/skipped'});
    expect((await service.checkForUpdates(force: true)).repositories.single.pending, isEmpty);
    skill('new-skill', description: 'New description.');
    commit();
    final result = await service.checkForUpdates(force: true);
    expect(result.checked, 1);
    expect(result.updates, 0);
    expect(result.repositories.single.pending.single.name, 'new-skill');
    expect(result.repositories.single.pending.single.description, 'New description.');
    expect(Directory(p.join(paths.storeDir, 'new-skill')).existsSync(), isFalse);
    expect(pending(), ['skills/new-skill']);
    final cached = await GitImportService(paths).checkForUpdates();
    expect(cached.checked, 0);
    expect(cached.repositories.single.pending.single.repositoryPath, 'skills/new-skill');
    await service.checkForUpdates(force: true);
    expect(pending(), ['skills/new-skill']);
  });

  test('dismissed and initially skipped skills stay quiet across checks and reappearance', () async {
    await importReviewer();
    skill('new-skill');
    commit();
    await service.checkForUpdates(force: true);
    service.dismissDiscovery(remote, 'main', 'skills/new-skill');
    expect(pending(), isEmpty);
    skill('skipped', description: 'Changed, but already known.');
    Directory(p.join(remote, 'skills', 'new-skill')).deleteSync(recursive: true);
    commit();
    await service.checkForUpdates(force: true);
    skill('new-skill');
    commit();
    await GitImportService(paths).checkForUpdates(force: true);
    expect(pending(), isEmpty);
  });

  test('import clears only successful discoveries and preserves other pending skills', () async {
    await importReviewer();
    skill('first-new');
    skill('second-new');
    commit();
    await service.checkForUpdates(force: true);
    final preview = await service.previewRepository(remote, 'main');
    final imported = service.importSelected(preview, ['skills/first-new']);
    expect(imported.library.imported, ['first-new']);
    expect(service.sources()['first-new']!.repositoryPath, 'skills/first-new');
    expect(service.sources()['first-new']!.ref, 'main');
    expect(pending(), ['skills/second-new']);
    await service.checkForUpdates(force: true);
    expect(pending(), ['skills/second-new']);
  });

  test('an older import preview preserves discoveries from a more recent check', () async {
    await importReviewer();
    skill('first-new');
    commit();
    await service.checkForUpdates(force: true);
    final preview = await service.previewRepository(remote, 'main');
    skill('later-new');
    commit();
    await service.checkForUpdates(force: true);
    expect(pending(), ['skills/first-new', 'skills/later-new']);
    service.importSelected(preview, ['skills/first-new']);
    expect(pending(), ['skills/later-new']);
    await service.checkForUpdates(force: true);
    expect(pending(), ['skills/later-new']);
  });

  test('legacy repositories establish a quiet baseline even with a recent cached check', () async {
    final records = service.sources();
    final checked = records['reviewer']!.withCheck(checkedAt: DateTime.now().toUtc(), contentChanges: false);
    writeJsonAtomic(paths.gitSourcesFile, {'reviewer': checked.toJson()});
    skill('existing-before-migration');
    commit();
    final migrated = await service.checkForUpdates();
    expect(migrated.checked, 1);
    expect(migrated.repositories.single.pending, isEmpty);
    skill('after-migration');
    commit();
    await service.checkForUpdates(force: true);
    expect(pending(), ['skills/after-migration']);
  });

  test('ref discovery and import stay on the tracked branch, regardless of remote default', () async {
    await importReviewer();
    git(['branch', 'other']);
    skill('main-only');
    commit();
    git(['checkout', '-q', 'other']);
    skill('other-only');
    commit();
    copyTree(p.join(remote, 'skills', 'skipped'), p.join(paths.storeDir, 'skipped'));
    final sources = service.sources();
    sources['skipped'] = GitSourceRecord(
      skillName: 'skipped',
      sourceUrl: remote,
      ref: 'other',
      repositoryPath: 'skills/skipped',
      revision: git(['rev-parse', 'HEAD']),
    );
    writeJsonAtomic(paths.gitSourcesFile, {for (final entry in sources.entries) entry.key: entry.value.toJson()});
    final result = await service.checkForUpdates(force: true);
    expect(result.checked, 2);
    expect(result.repositories.where((r) => r.ref == 'main').single.pending.single.name, 'main-only');
    expect(result.repositories.where((r) => r.ref == 'other').single.pending, isEmpty);
    final preview = await service.previewRepository(remote, 'main');
    expect(preview.candidates.any((c) => c.name == 'main-only'), isTrue);
    expect(preview.candidates.any((c) => c.name == 'other-only'), isFalse);
    service.discard(preview);
  });

  test(
    'failed remote checks preserve pending discoveries; removed skills disappear after a successful check',
    () async {
      await importReviewer();
      skill('new-skill');
      commit();
      await service.checkForUpdates(force: true);
      Directory(remote).renameSync('$remote-offline');
      final failed = await service.checkForUpdates(force: true);
      expect(failed.failures, 1);
      expect(pending(), ['skills/new-skill']);
      Directory('$remote-offline').renameSync(remote);
      Directory(p.join(remote, 'skills', 'new-skill')).deleteSync(recursive: true);
      commit();
      await service.checkForUpdates(force: true);
      expect(pending(), isEmpty);
    },
  );

  test('applying an update also discovers new skills and keeps them through its cache window', () async {
    await importReviewer();
    skill('reviewer', description: 'Updated reviewer.');
    skill('new-skill');
    commit();
    final applied = await service.applyUpdates(['reviewer']);
    expect(applied.updated, ['reviewer']);
    expect(pending(), ['skills/new-skill']);
    expect((await service.checkForUpdates()).repositories.single.pending.single.name, 'new-skill');
  });

  test('new discoveries notify without content updates and dismiss through the controller', () async {
    await importReviewer();
    skill('new-skill');
    commit();
    final controller = CabinetController(paths, autoBackupDelay: null);
    addTearDown(controller.dispose);
    controller.gitSources = service.sources();
    await controller.checkGitUpdates();
    expect(controller.newGitSkills, 1);
    expect(controller.notice, const Notice.info('1 new skill available'));
    expect(controller.gitSources['reviewer']!.state, GitTrackingState.upToDate);
    final repository = controller.gitRepositories.single;
    await controller.dismissGitDiscovery(repository, repository.pending.single);
    expect(controller.newGitSkills, 0);
    expect(controller.notice, const Notice.info('All Git-tracked skills are up to date'));
  });

  test('forgetting the last tracked skill removes its discovery state', () async {
    await importReviewer();
    skill('new-skill');
    commit();
    await service.checkForUpdates(force: true);
    service.removeSource('reviewer');
    expect(service.repositories(), isEmpty);
    expect((await service.checkForUpdates(force: true)).repositories, isEmpty);
  });
}
