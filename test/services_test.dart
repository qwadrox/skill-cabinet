import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/domain/health.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/collections_service.dart';
import 'package:skill_cabinet/src/services/deployment_service.dart';
import 'package:skill_cabinet/src/services/fs_util.dart';
import 'package:skill_cabinet/src/services/library_service.dart';

late Directory home;
late CabinetPaths paths;

void writeSkill(String dir, String name, {String? description, String body = '# Body'}) {
  final folder = Directory(p.join(dir, name))..createSync(recursive: true);
  final front = description == null ? '' : '---\nname: $name\ndescription: $description\n---\n';
  File(p.join(folder.path, 'SKILL.md')).writeAsStringSync('$front$body\n');
}

void main() {
  setUp(() {
    home = Directory.systemTemp.createTempSync('cabinet-test-');
    paths = CabinetPaths(home.path);
  });
  tearDown(() => home.deleteSync(recursive: true));

  group('LibraryService', () {
    test('scans the store sorted, with frontmatter descriptions', () {
      writeSkill(paths.storeDir, 'zeta', description: 'Last');
      writeSkill(paths.storeDir, 'Alpha', description: '"Quoted"');
      Directory(p.join(paths.storeDir, 'not-a-skill')).createSync();
      final snap = LibraryService(paths).scan();
      expect(snap.skills.map((s) => s.name), ['Alpha', 'zeta']);
      expect(snap.skills.first.description, 'Quoted');
      expect(snap.root, '~/.skill-cabinet/skills');
    });

    test('copies dropped folders, refuses duplicates and non-skills', () {
      final outside = p.join(home.path, 'Downloads');
      writeSkill(outside, 'pdf', description: 'PDFs');
      final lib = LibraryService(paths);
      final result = lib.importSkill(p.join(outside, 'pdf'), move: false);
      expect(result.imported, ['pdf']);
      expect(Directory(p.join(outside, 'pdf')).existsSync(), isTrue);
      expect(lib.importSkill(p.join(outside, 'pdf'), move: false).imported, isEmpty);
      Directory(p.join(outside, 'empty')).createSync();
      final bad = lib.importSkill(p.join(outside, 'empty'), move: false);
      expect(bad.imported, isEmpty);
      expect(bad.snapshot.notice, contains('not a skill folder'));
    });

    test('moves agent folders into the store', () {
      final agentDir = p.join(home.path, '.claude/skills');
      writeSkill(agentDir, 'mine');
      final result = LibraryService(paths).importSkill(p.join(agentDir, 'mine'), move: true);
      expect(result.imported, ['mine']);
      expect(Directory(p.join(agentDir, 'mine')).existsSync(), isFalse);
      expect(File(p.join(paths.storeDir, 'mine', 'SKILL.md')).existsSync(), isTrue);
    });

    test('finds skills nested in a project and imports the chosen ones', () {
      final project = p.join(home.path, 'Project');
      writeSkill(p.join(project, '.agents'), 'review', description: 'Reviews code');
      writeSkill(p.join(project, '.claude/skills'), 'deploy');
      writeSkill(p.join(project, 'node_modules/pkg'), 'ignored');
      writeSkill(paths.storeDir, 'review');
      final lib = LibraryService(paths);
      final scan = lib.scanForImport([project]);
      expect(scan.candidates.map((c) => c.name), containsAll(['review', 'deploy']));
      expect(scan.candidates.map((c) => c.name), isNot(contains('ignored')));
      expect(scan.candidates.firstWhere((c) => c.name == 'review').duplicate, isTrue);
      expect(scan.candidates.firstWhere((c) => c.name == 'deploy').where, '.claude/skills');

      final result = lib.importSkills([for (final c in scan.candidates) c.path], move: true);
      expect(result.imported, ['deploy']);
      expect(result.snapshot.notice, contains('already in the store'));
      expect(Directory(p.join(project, '.claude/skills/deploy')).existsSync(), isFalse);
      expect(Directory(p.join(project, '.agents/review')).existsSync(), isTrue);
    });

    test('pointing straight at a skill yields only that skill', () {
      final outside = p.join(home.path, 'Downloads');
      writeSkill(outside, 'pdf');
      writeSkill(p.join(outside, 'pdf'), 'nested');
      final scan = LibraryService(paths).scanForImport([p.join(outside, 'pdf')]);
      expect(scan.single, isTrue);
      expect(scan.candidates.single.name, 'pdf');
      expect(scan.candidates.single.where, '');
    });

    test('reports when a folder holds no skill', () {
      final empty = Directory(p.join(home.path, 'Empty'))..createSync();
      final scan = LibraryService(paths).scanForImport([empty.path]);
      expect(scan.isEmpty, isTrue);
      expect(scan.notice, contains('Empty'));
    });

    test('deletes only plain names', () {
      writeSkill(paths.storeDir, 'gone');
      final lib = LibraryService(paths);
      expect(lib.deleteSkill('../x').deleted, isNull);
      expect(lib.deleteSkill('gone').deleted, 'gone');
      expect(lib.scan().skills, isEmpty);
    });

    test('previews frontmatter and body, and reports problems', () {
      writeSkill(paths.storeDir, 'a', description: 'Desc', body: '\n\n# Title\n\ttext\n\n');
      File(
        p.join(paths.storeDir, 'a', 'SKILL.md'),
      ).writeAsStringSync('---\nname: Other\ndescription: >\n  folded\n  text\n---\n\n# Title\n\ttext\n\n');
      final preview = LibraryService(paths).preview('a');
      expect(preview.found, isTrue);
      expect(preview.heading, 'Other');
      expect(preview.named, isTrue);
      expect(preview.description, 'folded text');
      expect(preview.body, '# Title\n    text');
      expect(preview.problem, isEmpty);

      writeSkill(paths.storeDir, 'b');
      expect(LibraryService(paths).preview('b').problem, contains('No frontmatter'));
      expect(LibraryService(paths).preview('missing').found, isFalse);
    });
  });

  group('CollectionsService', () {
    test('creates sets with least-used colors and edits membership', () {
      final c = CollectionsService(paths);
      c.createSet(' Web ');
      c.createSet('Data');
      expect(c.createSet('Web').notice, contains('already exists'));
      var snap = c.setMembership('Web', 'pdf', member: true);
      snap = c.setMembership('Web', 'pdf', member: true);
      expect(snap.named('Web')!.skills, ['pdf']);
      expect(snap.sets.map((s) => s.color), [0, 1]);
      c.deleteSet('Web');
      expect(c.createSet('Ops').named('Ops')!.color, 0);
      c.setMembership('Data', 'x', member: true);
      expect(c.dropSkill('x').named('Data')!.skills, isEmpty);
    });

    test('renames a set without changing its contents or color', () {
      final c = CollectionsService(paths);
      c.createSet('Web');
      c.createSet('Data');
      c.setMembership('Web', 'pdf', member: true);

      final renamed = c.renameSet('Web', ' Platform ');

      expect(renamed.named('Web'), isNull);
      expect(renamed.named('Platform')!.skills, ['pdf']);
      expect(renamed.named('Platform')!.color, 0);
      expect(c.renameSet('Platform', 'Data').notice, contains('already exists'));
      expect(c.list().sets.map((set) => set.name), ['Platform', 'Data']);
    });

    test('backfills missing colors avoiding stored ones', () {
      Directory(paths.cabinetDir).createSync(recursive: true);
      File(paths.collectionsFile).writeAsStringSync(
        jsonEncode({
          'groups': [
            {'name': 'a', 'skills': []},
            {'name': 'b', 'skills': [], 'color': 0},
          ],
        }),
      );
      expect(CollectionsService(paths).list().sets.map((s) => s.color), [1, 0]);
    });
  });

  group('DeploymentService', () {
    late String claudeDir;
    setUp(() {
      Directory(p.join(home.path, '.claude')).createSync();
      claudeDir = p.join(home.path, '.claude/skills');
      writeSkill(paths.storeDir, 'pdf');
      writeSkill(paths.storeDir, 'docx');
    });

    test('starts with installed agents and links assigned skills', () {
      final d = DeploymentService(paths);
      var snap = d.sync();
      expect(snap.agents.map((a) => a.key), ['claude']);
      expect(snap.catalog.any((c) => c.key == 'claude'), isFalse);

      snap = d.setAgentSkill('claude', 'pdf', enabled: true);
      expect(Link(p.join(claudeDir, 'pdf')).targetSync(), p.join(paths.storeDir, 'pdf'));
      expect(snap.agents.single.linked, 1);

      snap = d.setAgentSkill('claude', 'pdf', enabled: false);
      expect(FileSystemEntity.typeSync(p.join(claudeDir, 'pdf'), followLinks: false), FileSystemEntityType.notFound);
    });

    test('adds a custom agent and links into its own folder', () {
      final d = DeploymentService(paths)..sync();
      var snap = d.addCustomAgent(' My Tool ', '~/tools/my/skills');
      final key = snap.agents.last.key;
      expect(key, 'custom:my-tool');
      expect(snap.agents.last.label, 'My Tool');
      expect(snap.agents.last.custom, isTrue);

      snap = d.setAgentSkill(key, 'pdf', enabled: true);
      final link = p.join(home.path, 'tools/my/skills/pdf');
      expect(Link(link).targetSync(), p.join(paths.storeDir, 'pdf'));
      expect(snap.agents.last.linked, 1);

      // It survives a reread, and its assignments go with it when removed.
      expect(DeploymentService(paths).sync().agents.map((a) => a.key), ['claude', key]);
      snap = DeploymentService(paths).removeAgent(key);
      expect(snap.agents.map((a) => a.key), ['claude']);
      expect(FileSystemEntity.typeSync(link, followLinks: false), FileSystemEntityType.notFound);
      expect(jsonDecode(File(paths.deploymentFile).readAsStringSync())['assignments'].containsKey(key), isFalse);
    });

    test('refuses a custom agent without a name, or on a taken or bad folder', () {
      final d = DeploymentService(paths)..sync();
      expect(d.addCustomAgent('  ', '~/x/skills').notice, contains('name'));
      expect(d.addCustomAgent('X', '  ').notice, contains('folder'));
      expect(d.addCustomAgent('X', '.claude/skills').notice, contains('same folder as Claude Code'));
      expect(d.addCustomAgent('X', '.skill-cabinet/skills/inner').notice, contains('inside the library'));
      expect(d.sync().agents.map((a) => a.key), ['claude']);
    });

    test('moves an agent to another folder and back to its default', () {
      final d = DeploymentService(paths)..sync();
      d.setAgentSkill('claude', 'pdf', enabled: true);
      var snap = d.setAgentPath('claude', '.claude/other-skills');
      final moved = p.join(home.path, '.claude/other-skills/pdf');
      expect(snap.agents.single.path, '~/.claude/other-skills');
      expect(Link(moved).targetSync(), p.join(paths.storeDir, 'pdf'));
      expect(FileSystemEntity.typeSync(p.join(claudeDir, 'pdf'), followLinks: false), FileSystemEntityType.notFound);

      // The override is stored home-relative, and an empty folder restores the default.
      expect(DeploymentService(paths).sync().agents.single.dir, '~/.claude/other-skills');
      snap = DeploymentService(paths).setAgentPath('claude', '');
      expect(snap.agents.single.path, '~/.claude/skills');
      expect(Link(p.join(claudeDir, 'pdf')).targetSync(), p.join(paths.storeDir, 'pdf'));
      expect(FileSystemEntity.typeSync(moved, followLinks: false), FileSystemEntityType.notFound);
    });

    test('links set members and unlinks when the agent is disabled', () {
      CollectionsService(paths)
        ..createSet('Office')
        ..setMembership('Office', 'pdf', member: true)
        ..setMembership('Office', 'docx', member: true);
      final d = DeploymentService(paths)..sync();
      expect(d.setAgentSet('claude', 'Office', enabled: true).agents.single.linked, 2);
      expect(d.setAgentEnabled('claude', enabled: false).agents.single.linked, 0);
      expect(d.setAgentEnabled('claude', enabled: true).agents.single.linked, 2);
    });

    test('renames set assignments for every agent', () {
      CollectionsService(paths)
        ..createSet('Office')
        ..setMembership('Office', 'pdf', member: true);
      final d = DeploymentService(paths)..sync();
      d.addAgent('codex');
      d.setAgentSet('claude', 'Office', enabled: true);
      d.setAgentSet('codex', 'Office', enabled: true);
      CollectionsService(paths).renameSet('Office', 'Work');

      final snap = d.renameSet('Office', 'Work');

      expect(snap.agents, hasLength(2));
      expect(snap.agents.every((agent) => agent.sets.single == 'Work'), isTrue);
      expect(snap.agents.every((agent) => agent.linked == 1), isTrue);
    });

    test('never touches real folders; reports them as foreign and occupied', () {
      writeSkill(claudeDir, 'pdf');
      writeSkill(claudeDir, 'own');
      final d = DeploymentService(paths)..sync();
      final snap = d.setAgentSkill('claude', 'pdf', enabled: true);
      expect(snap.issues.single.kind, IssueKind.slotOccupied);
      expect(snap.issues.single.subject, 'pdf');
      expect(snap.issues.single.detail, 'a folder');
      expect(snap.foreign.map((f) => f.name), ['own', 'pdf']);
      expect(File(p.join(claudeDir, 'own', 'SKILL.md')).existsSync(), isTrue);
    });

    test('leaves links pointing elsewhere alone', () {
      Directory(claudeDir).createSync(recursive: true);
      writeSkill(p.join(home.path, 'elsewhere'), 'x');
      Link(p.join(claudeDir, 'x')).createSync(p.join(home.path, 'elsewhere', 'x'));
      DeploymentService(paths).sync();
      expect(Link(p.join(claudeDir, 'x')).existsSync(), isTrue);
    });

    test('adds and removes agents, refusing shared folders', () {
      final d = DeploymentService(paths)..sync();
      expect(d.addAgent('cline').agents.map((a) => a.key), ['claude', 'cline']);
      expect(d.addAgent('warp').notice, contains('same folder as Cline'));
      d.setAgentSkill('cline', 'pdf', enabled: true);
      final clineLink = p.join(home.path, '.agents/skills/pdf');
      expect(Link(clineLink).existsSync(), isTrue);
      final snap = d.removeAgent('cline');
      expect(snap.agents.map((a) => a.key), ['claude']);
      expect(Link(clineLink).existsSync(), isFalse);
      // Assignments survive, so adding it back restores the link.
      d.addAgent('cline');
      expect(Link(clineLink).existsSync(), isTrue);
    });

    test('unassigning a deleted skill removes its links', () {
      final d = DeploymentService(paths)..sync();
      d.setAgentSkill('claude', 'pdf', enabled: true);
      LibraryService(paths).deleteSkill('pdf');
      final snap = d.unassignSkill('pdf');
      expect(snap.agents.single.skills, isEmpty);
      expect(FileSystemEntity.typeSync(p.join(claudeDir, 'pdf'), followLinks: false), FileSystemEntityType.notFound);
    });

    test('migrates version-one state and files without providers', () {
      Directory(paths.cabinetDir).createSync(recursive: true);
      File(paths.deploymentFile).writeAsStringSync(
        jsonEncode({
          'active': ['pdf'],
          'assignments': {
            'codex': {'sets': [], 'skills': []},
          },
        }),
      );
      final snap = DeploymentService(paths).sync();
      expect(snap.agents.map((a) => a.key), ['codex']);
      expect(snap.agents.single.skills, isEmpty);

      File(paths.deploymentFile).writeAsStringSync(
        jsonEncode({
          'active': ['pdf'],
          'providers': ['claude'],
        }),
      );
      expect(DeploymentService(paths).sync().agents.single.skills, ['pdf']);
    });

    test('reads files written by the Native SDK version', () {
      Directory(paths.cabinetDir).createSync(recursive: true);
      File(paths.deploymentFile).writeAsStringSync('''{
  "active": [],
  "providers": ["claude", "nope"],
  "disabledProviders": [],
  "assignments": { "claude": { "sets": ["S"], "skills": ["docx"] } }
}
''');
      final snap = DeploymentService(paths).sync();
      expect(snap.agents.single.sets, ['S']);
      expect(snap.agents.single.linked, 1);
    });
  });

  group('health', () {
    late String claudeDir;
    setUp(() {
      Directory(p.join(home.path, '.claude')).createSync();
      claudeDir = p.join(home.path, '.claude/skills');
      writeSkill(paths.storeDir, 'pdf');
    });

    List<HealthIssue> storeIssues() => LibraryService(paths).scan().issues;

    test('reports store entries that are not deployable skills', () {
      Directory(p.join(paths.storeDir, 'half-done')).createSync(recursive: true);
      File(p.join(paths.storeDir, 'notes.txt')).writeAsStringSync('hi');
      final issues = storeIssues();
      expect(issues.map((i) => i.subject), ['half-done', 'notes.txt']);
      expect(issues.map((i) => i.kind), everyElement(IssueKind.storeNotASkill));
      expect(issues.first.detail, 'no SKILL.md');
      expect(issues.last.detail, 'not a folder');
      // Reported, never repaired.
      expect(Directory(p.join(paths.storeDir, 'half-done')).existsSync(), isTrue);
      expect(File(p.join(paths.storeDir, 'notes.txt')).existsSync(), isTrue);
    });

    test('reports a broken link in the store', () {
      Link(p.join(paths.storeDir, 'gone')).createSync(p.join(home.path, 'nowhere', 'gone'));
      final issue = storeIssues().single;
      expect(issue.kind, IssueKind.storeBrokenLink);
      expect(issue.subject, 'gone');
      expect(LibraryService(paths).scan().skills.map((s) => s.name), ['pdf']);
      expect(isBrokenLink(p.join(paths.storeDir, 'gone')), isTrue);
    });

    test('a store link that leaves the store is reported but stays deployable', () {
      writeSkill(p.join(home.path, 'dotfiles'), 'mine');
      Link(p.join(paths.storeDir, 'mine')).createSync(p.join(home.path, 'dotfiles', 'mine'));
      final snap = LibraryService(paths).scan();
      expect(snap.skills.map((s) => s.name), ['mine', 'pdf']);
      final issue = snap.issues.single;
      expect(issue.kind, IssueKind.storeLinksOut);
      expect(issue.detail, '~/dotfiles/mine');

      final d = DeploymentService(paths)..sync();
      expect(d.setAgentSkill('claude', 'mine', enabled: true).agents.single.linked, 1);
    });

    test('an assignment the store cannot satisfy is reported, not dropped', () {
      final d = DeploymentService(paths)..sync();
      expect(d.setAgentSkill('claude', 'pdf', enabled: true).issues, isEmpty);

      // The skill loses its SKILL.md behind the app's back.
      File(p.join(paths.storeDir, 'pdf', 'SKILL.md')).deleteSync();
      final snap = d.sync();
      final unmet = snap.issues.singleWhere((i) => i.kind == IssueKind.assignmentUnmet);
      expect(unmet.subject, 'pdf');
      expect(unmet.agent, 'Claude Code');
      // Our own dead link goes; the assignment stays, so the skill can
      // come back without the user re-enabling it.
      expect(lexists(p.join(claudeDir, 'pdf')), isFalse);
      expect(snap.agents.single.skills, ['pdf']);
      final state = jsonDecode(File(paths.deploymentFile).readAsStringSync()) as Map;
      expect((state['assignments'] as Map)['claude']['skills'], ['pdf']);
    });

    test('a missing set member is reported for the agents assigned the set', () {
      CollectionsService(paths)
        ..createSet('Office')
        ..setMembership('Office', 'pdf', member: true)
        ..setMembership('Office', 'ghost', member: true);
      final snap = (DeploymentService(paths)..sync()).setAgentSet('claude', 'Office', enabled: true);
      expect(snap.issues.single.kind, IssueKind.assignmentUnmet);
      expect(snap.issues.single.subject, 'ghost');
      expect(snap.agents.single.linked, 1);
    });

    test('a disabled agent reports nothing it was not going to link', () {
      final d = DeploymentService(paths)..sync();
      d.setAgentSkill('claude', 'ghost', enabled: true);
      expect(d.setAgentEnabled('claude', enabled: false).issues, isEmpty);
      expect(d.setAgentEnabled('claude', enabled: true).issues.single.subject, 'ghost');
    });

    test('a foreign link on an assigned name is reported and left alone', () {
      Directory(claudeDir).createSync(recursive: true);
      writeSkill(p.join(home.path, 'elsewhere'), 'pdf');
      final link = p.join(claudeDir, 'pdf');
      Link(link).createSync(p.join(home.path, 'elsewhere', 'pdf'));

      final snap = (DeploymentService(paths)..sync()).setAgentSkill('claude', 'pdf', enabled: true);
      final issue = snap.issues.single;
      expect(issue.kind, IssueKind.slotOccupied);
      expect(issue.detail, 'a link to ~/elsewhere/pdf');
      expect(issue.message, contains('already uses this name'));
      expect(Link(link).targetSync(), p.join(home.path, 'elsewhere', 'pdf'));
    });

    test('a broken link on an assigned name is reported as what it is', () {
      Directory(claudeDir).createSync(recursive: true);
      final link = p.join(claudeDir, 'pdf');
      Link(link).createSync(p.join(home.path, 'elsewhere', 'pdf'));

      final snap = (DeploymentService(paths)..sync()).setAgentSkill('claude', 'pdf', enabled: true);
      expect(snap.issues.single.detail, 'a broken link to ~/elsewhere/pdf');
      expect(lexists(link), isTrue);
    });

    test('says nothing about links under names it was never asked to make', () {
      Directory(claudeDir).createSync(recursive: true);
      // Another tool's store on a volume that is not mounted: every link
      // it made dangles at once, and none of it is ours to report.
      for (final name in ['their-a', 'their-b', 'their-c']) {
        Link(p.join(claudeDir, name)).createSync('/Volumes/Backup/skills/$name');
      }
      final snap = (DeploymentService(paths)..sync()).setAgentSkill('claude', 'pdf', enabled: true);
      expect(snap.issues, isEmpty);
      expect(listDir(claudeDir), ['pdf', 'their-a', 'their-b', 'their-c']);
    });
  });
}
