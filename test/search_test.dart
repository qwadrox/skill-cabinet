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
  late CabinetController controller;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    home = Directory.systemTemp.createTempSync('cabinet-search-');
    final paths = CabinetPaths(home.path);
    // An agent folder, so the rows have switches to reason about.
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

  test('emptying the search field restores the full list', () {
    controller.searchField.text = 'alpha';
    expect(controller.skillRows.map((r) => r.name), ['alpha']);
    controller.searchField.clear();
    expect(controller.searching, isFalse);
    expect(controller.skillRows.map((r) => r.name), ['alpha', 'beta', 'delta', 'gamma']);
  });

  test('changing the view drops the search with it', () {
    controller.searchField.text = 'alpha';
    controller.selectSet('Engineering');
    expect(controller.searchField.text, isEmpty);
    expect(controller.skillRows.map((r) => r.name), ['alpha', 'beta']);

    controller.searchField.text = 'beta';
    controller.selectAll();
    expect(controller.searchField.text, isEmpty);
    expect(controller.skillRows.length, 4);
  });

  test('the pill narrows the add list to skills no set holds', () {
    controller.selectSet('Engineering');
    expect(controller.addableRows.map((r) => r.name), ['delta', 'gamma']);
    expect(controller.looseAddableCount, 1);

    controller.toggleLooseOnly();
    // delta is in Web, so only gamma is filed nowhere.
    expect(controller.addableRows.map((r) => r.name), ['gamma']);
    // The members list is untouched by the pill.
    expect(controller.skillRows.map((r) => r.name), ['alpha', 'beta']);

    controller.toggleLooseOnly();
    expect(controller.addableRows.map((r) => r.name), ['delta', 'gamma']);
  });

  test('the search keeps filtering both lists while the pill is on', () {
    controller.selectSet('Engineering');
    controller.toggleLooseOnly();
    controller.searchField.text = 'gamma';
    expect(controller.addableRows.map((r) => r.name), ['gamma']);
    expect(controller.skillRows, isEmpty);

    controller.searchField.text = 'alpha';
    expect(controller.addableRows, isEmpty);
    // The section stays on screen, so the pill can still be turned off.
    expect(controller.addableTotal, 2);
    expect(controller.skillRows.map((r) => r.name), ['alpha']);
  });

  test('changing the view drops the pill with it', () {
    controller.selectSet('Engineering');
    controller.toggleLooseOnly();
    controller.selectAll();
    expect(controller.looseOnly, isFalse);
  });

  test('a set header counts the members the search left', () {
    PaneSetHeader header() =>
        controller.paneEntries.whereType<PaneSetHeader>().firstWhere((h) => h.set.name == 'Engineering');
    expect(header().countLabel, '2 skills');
    controller.searchField.text = 'alpha';
    expect(header().countLabel, '1 of 2 skills');
    expect(header().expanded, isTrue);
  });
}
