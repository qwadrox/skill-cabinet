import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/app/cabinet_controller.dart';
import 'package:skill_cabinet/src/app/rows.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';

void writeSkill(String dir, String name, {String description = ''}) {
  final folder = Directory(p.join(dir, name))..createSync(recursive: true);
  File(
    p.join(folder.path, 'SKILL.md'),
  ).writeAsStringSync('---\nname: $name\ndescription: $description\n---\n# Body\n');
}

void main() {
  late Directory home;
  late CabinetPaths paths;
  late CabinetController controller;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    home = Directory.systemTemp.createTempSync('cabinet-controller-');
    paths = CabinetPaths(home.path);
    Directory(p.join(home.path, '.claude', 'skills')).createSync(recursive: true);
    for (final name in ['alpha', 'beta', 'gamma', 'delta']) {
      writeSkill(paths.storeDir, name, description: 'Does $name things');
    }
    controller = CabinetController(paths);
    await controller.load();
    await controller.createSet('Engineering');
    for (final name in ['alpha', 'beta']) {
      await controller.setMembership('Engineering', name, member: true);
    }
    await controller.createSet('Web');
    await controller.setMembership('Web', 'delta', member: true);
    controller.selectAll();
  });

  tearDown(() {
    controller.dispose();
    home.deleteSync(recursive: true);
  });

  // Adding a skill to a set is a change to the set, not to any agent:
  // what an agent has linked must come out the other side untouched.
  test('adding to an unassigned set enables nothing', () async {
    final agent = controller.selectedAgent!;
    await controller.setSkillEnabled('gamma', true);
    final before = [...controller.deployment.agent(agent.key)!.skills];

    controller.selectSet('Engineering');
    await controller.setMembership('Engineering', 'gamma', member: true);
    await controller.setMembership('Engineering', 'delta', member: true);
    await controller.refresh();

    final after = controller.deployment.agent(agent.key)!.skills;
    expect(after, before);
    final row = controller.skillRows.firstWhere((r) => r.name == 'delta');
    expect(row.active, isFalse, reason: 'delta was off before it joined the set');
    expect(controller.skillRows.firstWhere((r) => r.name == 'gamma').active, isTrue);
  });

  test('renaming a set preserves its contents, view state, and agent assignment', () async {
    final agent = controller.selectedAgent!;
    controller.selectSet('Engineering');
    controller.toggleSection('Engineering');
    await controller.setSetEnabled('Engineering', true);

    await controller.renameSet('Engineering', 'Platform');
    await controller.refresh();

    expect(controller.selectedSet?.name, 'Platform');
    expect(controller.expandedSets, contains('Platform'));
    expect(controller.expandedSets, isNot(contains('Engineering')));
    expect(controller.collections.named('Engineering'), isNull);
    expect(controller.collections.named('Platform')!.skills, ['alpha', 'beta']);
    expect(controller.deployment.agent(agent.key)!.sets, ['Platform']);
    expect(controller.deployment.agent(agent.key)!.linked, 2);
  });

  // An import lands in the library and nowhere else. A skill that starts
  // linked for an agent is the user's decision, never the import's.
  test('a fresh import is enabled for no one', () async {
    final agent = controller.selectedAgent!;
    final before = [...controller.deployment.agent(agent.key)!.skills];
    writeSkill(p.join(home.path, 'Downloads'), 'epsilon', description: 'Fresh');

    await controller.importSkills([p.join(home.path, 'Downloads', 'epsilon')], move: false);
    await controller.refresh();

    expect(controller.library.has('epsilon'), isTrue, reason: 'the import landed in the store');
    expect(controller.deployment.agent(agent.key)!.skills, before);
    expect(controller.skillRows.firstWhere((r) => r.name == 'epsilon').active, isFalse);
    expect(Link(p.join(home.path, '.claude', 'skills', 'epsilon')).existsSync(), isFalse);
  });
}
