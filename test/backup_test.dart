import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/app/cabinet_controller.dart';
import 'package:skill_cabinet/src/domain/backup.dart';
import 'package:skill_cabinet/src/services/backup_service.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/collections_service.dart';
import 'package:skill_cabinet/src/services/deployment_service.dart';

void writeSkill(String dir, String name) {
  final folder = Directory(p.join(dir, name))..createSync(recursive: true);
  File(p.join(folder.path, 'SKILL.md')).writeAsStringSync('---\nname: $name\n---\n# $name\n');
}

String git(String dir, List<String> args) {
  final result = Process.runSync('/usr/bin/git', ['-C', dir, ...args]);
  if (result.exitCode != 0) throw StateError('git ${args.join(' ')}: ${result.stderr}');
  return result.stdout.toString().trim();
}

void main() {
  late Directory root;
  late CabinetPaths paths;
  late String remote;

  // A second Mac: its own home, same remote.
  CabinetPaths newMac() {
    final home = Directory(p.join(root.path, 'new-mac'))..createSync();
    return CabinetPaths(home.path);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('cabinet-backup-');
    final home = Directory(p.join(root.path, 'home'))..createSync();
    paths = CabinetPaths(home.path);
    remote = p.join(root.path, 'remote.git');
    Process.runSync('/usr/bin/git', ['init', '--quiet', '--bare', remote]);
    writeSkill(paths.storeDir, 'alpha');
    writeSkill(paths.storeDir, 'beta');
    CollectionsService(paths)
      ..createSet('Engineering')
      ..setMembership('Engineering', 'alpha', member: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('backs up only when something changed, and says what', () {
    final backup = BackupService(paths);
    var status = backup.backUp();
    expect(status.history.single.summary, 'First backup · 2 skills');
    expect(backup.backUp().history, hasLength(1));

    writeSkill(paths.storeDir, 'gamma');
    Directory(p.join(paths.storeDir, 'beta')).deleteSync(recursive: true);
    File(p.join(paths.storeDir, 'alpha', 'SKILL.md')).writeAsStringSync('# changed\n');
    CollectionsService(paths).createSet('Web');
    status = backup.backUp();
    expect(status.history, hasLength(2));
    expect(status.history.first.summary, 'Added gamma · Removed beta · Changed alpha · Updated skill sets');
    expect(status.hasRemote, isFalse);
  });

  test('restores a backup point as a new one on top', () {
    final backup = BackupService(paths);
    final first = backup.backUp().history.single;
    writeSkill(paths.storeDir, 'gamma');
    Directory(p.join(paths.storeDir, 'alpha')).deleteSync(recursive: true);

    final status = backup.restore(first.id);
    expect(status.history, hasLength(3));
    expect(status.history.first.summary, startsWith('Restored the backup of'));
    expect(File(p.join(paths.storeDir, 'alpha', 'SKILL.md')).existsSync(), isTrue);
    expect(Directory(p.join(paths.storeDir, 'gamma')).existsSync(), isFalse);

    // The state before the restore is itself a backup point.
    expect(status.history[1].summary, 'Added gamma · Removed alpha');
  });

  test('pushes to an empty remote and restores it on a new Mac, agents included', () async {
    // A custom agent under home, stored home-relative so the new Mac's
    // home (another user name) still resolves it.
    final agentDir = p.join(paths.home, 'Work', 'agent-skills');
    DeploymentService(paths)
      ..sync()
      ..addCustomAgent('Work', agentDir);
    final work = DeploymentService(paths).sync().agents.firstWhere((a) => a.label == 'Work');
    expect(work.dir, '~/Work/agent-skills');
    DeploymentService(paths).setAgentSet(work.key, 'Engineering', enabled: true);

    final backup = BackupService(paths);
    backup.backUp();
    expect(await backup.probe(remote), RemoteContents.empty);
    backup.setRemote(remote);
    expect(backup.status().unpushed, 1);
    await backup.push();
    expect(backup.status().unpushed, 0);

    final mac = newMac();
    final restored = BackupService(mac);
    restored.backUp();
    expect(await restored.probe(remote), RemoteContents.backup);
    final status = restored.adoptRemote(remote);
    expect(status.remote, remote);
    expect(status.history.single.summary, 'First backup · 2 skills');
    expect(File(p.join(mac.storeDir, 'beta', 'SKILL.md')).existsSync(), isTrue);

    // Reconciling creates the agent folder and links the set's members.
    DeploymentService(mac).sync();
    final link = p.join(mac.home, 'Work', 'agent-skills', 'alpha');
    expect(Link(link).targetSync(), p.join(mac.storeDir, 'alpha'));

    // What the new Mac had before is kept aside.
    expect(git(mac.cabinetDir, ['branch', '--list', 'before-restore']), contains('before-restore'));

    // And it backs up to the same remote from now on.
    writeSkill(mac.storeDir, 'gamma');
    expect(restored.backUp().unpushed, 1);
    await restored.push();
    expect(restored.status().unpushed, 0);
  });

  test('refuses to overwrite a remote that moved on', () async {
    final backup = BackupService(paths)..backUp();
    backup.setRemote(remote);
    await backup.push();

    final other = BackupService(newMac())..backUp();
    await other.probe(remote);
    other.adoptRemote(remote);
    writeSkill(newMac().storeDir, 'from-elsewhere');
    other.backUp();
    await other.push();

    writeSkill(paths.storeDir, 'gamma');
    backup.backUp();
    await expectLater(
      backup.push(),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('Nothing was overwritten'))),
    );
    expect(backup.status().unpushed, 1);
  });

  test('will not connect a repository that holds something else', () async {
    final clone = p.join(root.path, 'clone');
    Process.runSync('/usr/bin/git', ['clone', '--quiet', remote, clone]);
    File(p.join(clone, 'README.md')).writeAsStringSync('hello\n');
    git(clone, ['add', '.']);
    git(clone, ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'readme']);
    git(clone, ['push', '--quiet', 'origin', 'HEAD:main']);

    final controller = CabinetController(paths);
    final result = await controller.connectBackup(remote);
    expect(result.outcome, BackupConnectOutcome.failed);
    expect(result.message, contains('something else'));
    expect(controller.backup.hasRemote, isFalse);
    controller.dispose();
  });

  test('the controller connects, then restores the remote on a new Mac', () async {
    final controller = CabinetController(paths);
    await controller.load();
    expect((await controller.connectBackup(remote)).outcome, BackupConnectOutcome.connected);
    expect(controller.backup.remote, remote);
    expect(controller.backup.unpushed, 0);
    controller.dispose();

    final fresh = CabinetController(newMac());
    await fresh.load();
    expect((await fresh.connectBackup(remote)).outcome, BackupConnectOutcome.holdsBackup);
    await fresh.restoreFromRemote(remote);
    expect(fresh.library.skills.map((s) => s.name), ['alpha', 'beta']);
    expect(fresh.collections.named('Engineering')?.skills, ['alpha']);
    expect(fresh.backup.remote, remote);
    fresh.dispose();
  });
}
