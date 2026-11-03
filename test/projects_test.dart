import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/domain/health.dart';
import 'package:skill_cabinet/src/domain/projects.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/collections_service.dart';
import 'package:skill_cabinet/src/services/deployment_service.dart';
import 'package:skill_cabinet/src/services/project_service.dart';

late Directory home;
late CabinetPaths paths;
late String project;

void writeSkill(String dir, String name) {
  final folder = Directory(p.join(dir, name))..createSync(recursive: true);
  File(p.join(folder.path, 'SKILL.md')).writeAsStringSync('# $name\n');
}

bool exists(String path) => FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

String exclude() {
  final file = File(p.join(project, '.git/info/exclude'));
  return file.existsSync() ? file.readAsStringSync() : '';
}

void main() {
  setUp(() {
    home = Directory.systemTemp.createTempSync('cabinet-projects-');
    paths = CabinetPaths(home.path);
    // Claude Code and Codex are installed; Codex reads project skills
    // from .agents/skills.
    Directory(p.join(home.path, '.claude')).createSync();
    Directory(p.join(home.path, '.codex')).createSync();
    writeSkill(paths.storeDir, 'blog-writer');
    writeSkill(paths.storeDir, 'seo-audit');
    writeSkill(paths.storeDir, 'review');
    CollectionsService(paths)
      ..createSet('Blog')
      ..setMembership('Blog', 'blog-writer', member: true)
      ..setMembership('Blog', 'seo-audit', member: true)
      ..createSet('Engineering')
      ..setMembership('Engineering', 'review', member: true);
    project = p.join(home.path, 'Documents/genontech');
    Directory(p.join(project, '.git/info')).createSync(recursive: true);
    File(
      p.join(project, '.git/info/exclude'),
    ).writeAsStringSync('# git ls-files --others --exclude-from=.git/info/exclude\n*.log\n');
  });
  tearDown(() => home.deleteSync(recursive: true));

  test('links a project set into every agent’s project folder and keeps it out of Git', () {
    final d = DeploymentService(paths)..sync();
    expect(d.sync().agents.map((a) => a.key), ['claude', 'codex']);
    final snap = d.setProjectSet(project, 'Blog', enabled: true);

    for (final folder in ['.claude/skills', '.agents/skills']) {
      for (final name in ['blog-writer', 'seo-audit']) {
        expect(Link(p.join(project, folder, name)).targetSync(), p.join(paths.storeDir, name));
      }
    }
    // Not globally.
    expect(exists(p.join(home.path, '.claude/skills/blog-writer')), isFalse);
    expect(snap.projects.single.sets, ['Blog']);
    expect(snap.projects.single.linked, 4);
    expect(snap.projects.single.display, '~/Documents/genontech');
    expect(snap.projectTargets.map((t) => '${t.folder}:${t.agents.join('+')}'), [
      '.agents/skills:Codex',
      '.claude/skills:Claude Code',
    ]);
    expect(exclude(), contains('*.log\n'));
    expect(exclude(), contains('/.claude/skills/blog-writer\n'));
    expect(exclude(), contains('/.agents/skills/seo-audit\n'));

    // Stored home-relative, so a restored backup finds it.
    final raw = jsonDecode(File(paths.deploymentFile).readAsStringSync());
    expect(raw['projects'], {
      '~/Documents/genontech': {
        'sets': ['Blog'],
      },
    });
  });

  test('turning the last set off leaves the project as it was', () {
    final d = DeploymentService(paths)..sync();
    final before = exclude();
    d.setProjectSet(project, 'Blog', enabled: true);
    d.setProjectSet(project, 'Blog', enabled: false);
    expect(exists(p.join(project, '.claude')), isFalse);
    expect(exists(p.join(project, '.agents')), isFalse);
    expect(exclude(), before);
  });

  test('keeps the project’s own skills and folders', () {
    writeSkill(p.join(project, '.claude/skills'), 'own');
    writeSkill(p.join(project, '.claude/skills'), 'blog-writer');
    final snap = (DeploymentService(paths)..sync()).setProjectSet(project, 'Blog', enabled: true);
    expect(File(p.join(project, '.claude/skills/own/SKILL.md')).existsSync(), isTrue);
    expect(FileSystemEntity.isLinkSync(p.join(project, '.claude/skills/blog-writer')), isFalse);
    final occupied = snap.issues.where((i) => i.kind == IssueKind.slotOccupied).single;
    expect(occupied.subject, 'blog-writer');
    expect(occupied.agent, 'genontech · .claude/skills');

    DeploymentService(paths).removeProject(project);
    expect(File(p.join(project, '.claude/skills/own/SKILL.md')).existsSync(), isTrue);
    expect(exists(p.join(project, '.agents')), isFalse);
  });

  test('does not link again what every agent of a folder has globally', () {
    final d = DeploymentService(paths)..sync();
    d.setAgentSet('claude', 'Blog', enabled: true);
    d.setProjectSet(project, 'Blog', enabled: true);
    expect(exists(p.join(project, '.claude/skills/blog-writer')), isFalse);
    expect(exists(p.join(project, '.agents/skills/blog-writer')), isTrue);
    // Turned off globally, the project gets it again.
    d.setAgentSet('claude', 'Blog', enabled: false);
    expect(exists(p.join(project, '.claude/skills/blog-writer')), isTrue);
  });

  test('follows agents being turned off, removed and renamed sets', () {
    final d = DeploymentService(paths)..sync();
    d.setProjectSet(project, 'Blog', enabled: true);
    d.setAgentEnabled('codex', enabled: false);
    expect(exists(p.join(project, '.agents')), isFalse);
    expect(exists(p.join(project, '.claude/skills/seo-audit')), isTrue);
    d.removeAgent('claude');
    expect(exists(p.join(project, '.claude')), isFalse);

    d.setAgentEnabled('codex', enabled: true);
    final snap = d.renameSet('Blog', 'Writing');
    expect(snap.projects.single.sets, ['Writing']);
  });

  test('refuses home and the cabinet as projects', () {
    final d = DeploymentService(paths)..sync();
    expect(d.addProject(home.path).notice.text, contains('global skills'));
    expect(d.setProjectSet(paths.cabinetDir, 'Blog', enabled: true).notice.text, contains('inside the cabinet'));
    expect(d.addProject(p.join(home.path, 'nope')).notice.text, contains('not a folder'));
    expect(d.sync().projects, isEmpty);
  });

  test('keeps what a newer version of the app wrote', () {
    final d = DeploymentService(paths)..sync();
    d.setProjectSet(project, 'Blog', enabled: true);
    for (final file in [paths.deploymentFile, paths.collectionsFile]) {
      final raw = jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
      raw['future'] = {'kept': true};
      File(file).writeAsStringSync(jsonEncode(raw));
    }
    d.setProjectSet(project, 'Engineering', enabled: true);
    CollectionsService(paths).createSet('Later');
    d.removeProject(project);
    for (final file in [paths.deploymentFile, paths.collectionsFile]) {
      final raw = jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
      expect(raw['future'], {'kept': true}, reason: file);
    }
    // What this version owns it still writes, even empty.
    expect(jsonDecode(File(paths.deploymentFile).readAsStringSync())['projects'], isEmpty);
  });

  test('a worktree shares its repository’s exclude file', () {
    final worktree = p.join(home.path, 'Documents/genontech-wt');
    final gitDir = p.join(project, '.git/worktrees/wt');
    Directory(gitDir).createSync(recursive: true);
    File(p.join(gitDir, 'commondir')).writeAsStringSync('../..\n');
    Directory(worktree).createSync(recursive: true);
    File(p.join(worktree, '.git')).writeAsStringSync('gitdir: $gitDir\n');
    (DeploymentService(paths)..sync()).setProjectSet(worktree, 'Engineering', enabled: true);
    expect(exclude(), contains('/.claude/skills/review\n'));
  });

  group('ProjectService', () {
    test('finds Git repositories Claude Code and Codex remember, newest first', () {
      final older = p.join(home.path, 'Code/older');
      Directory(p.join(older, '.git')).createSync(recursive: true);
      File(p.join(older, '.git/HEAD')).writeAsStringSync('ref: x');
      File(p.join(older, '.git/HEAD')).setLastModifiedSync(DateTime(2020));
      File(p.join(project, '.git/HEAD')).writeAsStringSync('ref: x');
      writeSkill(p.join(project, 'public'), 'unused');
      File(p.join(project, 'public/apple-touch-icon.png')).writeAsBytesSync([0]);
      final scratch = p.join(home.path, 'scratch');
      Directory(scratch).createSync();
      File(p.join(home.path, '.claude.json')).writeAsStringSync(
        jsonEncode({
          'projects': {home.path: {}, project: {}, scratch: {}, p.join(home.path, '.codex'): {}},
        }),
      );
      Directory(p.join(home.path, '.codex')).createSync(recursive: true);
      File(
        p.join(home.path, '.codex/config.toml'),
      ).writeAsStringSync('[projects."$older"]\ntrust_level = "trusted"\n[projects."$project"]\n');
      final found = ProjectService(paths).discover([scratch]);
      final names = found.map((f) => f.name).toList();
      expect(names, unorderedEquals(['genontech', 'older', 'scratch']));
      expect(names.indexOf('genontech'), lessThan(names.indexOf('older')));
      final genontech = found.firstWhere((f) => f.name == 'genontech');
      expect(genontech.sources, ['Claude Code', 'Codex']);
      expect(genontech.icon, p.join(project, 'public/apple-touch-icon.png'));
      expect(found.firstWhere((f) => f.name == 'scratch').sources, isEmpty);
    });

    test('reads the Codex app’s named projects and thread folders', () {
      final named = p.join(home.path, 'Documents/Codex/notes');
      Directory(named).createSync(recursive: true);
      final scratch = p.join(home.path, 'Documents/scratch');
      Directory(scratch).createSync(recursive: true);
      final db = p.join(home.path, '.codex/state_5.sqlite');
      Directory(p.dirname(db)).createSync(recursive: true);
      final result = Process.runSync('/usr/bin/sqlite3', [
        db,
        'CREATE TABLE projects (id TEXT, name TEXT); CREATE TABLE project_roots (project_id TEXT, path TEXT);'
            'CREATE TABLE threads (cwd TEXT, updated_at INTEGER);'
            "INSERT INTO projects VALUES ('1', 'My Notes'); INSERT INTO project_roots VALUES ('1', '$named');"
            "INSERT INTO threads VALUES ('$project', 4102444800), ('$project', 100), ('$scratch', 200),"
            " ('${home.path}/.codex', 300);",
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');

      final found = {for (final f in ProjectService(paths).discover(const [])) f.name: f};
      // A named project counts without Git; a thread folder only with it.
      expect(found.keys, unorderedEquals(['genontech', 'My Notes']));
      expect(found['genontech']!.sources, ['Codex']);
      expect(found['genontech']!.activity, DateTime.fromMillisecondsSinceEpoch(4102444800 * 1000));
    });

    test('picks the project’s logo the way bb does', () {
      List<String> ranked(List<String> files) =>
          (files.where((f) => ProjectService.iconScore(f) != null).toList()
            ..sort((a, b) => ProjectService.iconScore(a)!.compareTo(ProjectService.iconScore(b)!)));

      expect(
        ranked([
          'apps/frontend/portal-app/public/images/lock_icon.svg',
          'apps/frontend/portal-app/public/images/market_logo_no_text.svg',
          'apps/frontend/portal-app/public/favicon.png',
        ]).first,
        'apps/frontend/portal-app/public/favicon.png',
      );
      expect(ranked(['client/src/favicon.ico', 'client/src/apple-touch-icon.png', 'client/src/assets/logout.png']), [
        'client/src/apple-touch-icon.png',
        'client/src/favicon.ico',
      ]);
      expect(ranked(['public/favicon-16x16.png', 'public/favicon-96x96.png']).first, 'public/favicon-96x96.png');
      expect(ranked(['node_modules/x/favicon.png', 'test/fixtures/logo.png']), isEmpty);
    });

    test('remembers the icon the user chose, relative to the project', () {
      File(p.join(project, '.claude.json')).writeAsStringSync('');
      File(p.join(home.path, '.claude.json')).writeAsStringSync(
        jsonEncode({
          'projects': {project: {}},
        }),
      );
      for (final name in ['public/favicon.png', 'brand/mark.svg', 'brand/old.ico']) {
        File(p.join(project, name))
          ..createSync(recursive: true)
          ..writeAsBytesSync([0]);
      }
      final service = ProjectService(paths);
      ProjectInfo only() => service.discover(const []).single;
      expect(only().icon, p.join(project, 'public/favicon.png'));
      expect(only().iconChosen, isFalse);

      service.setIcon(project, p.join(project, 'brand/mark.svg'));
      expect(only().icon, p.join(project, 'brand/mark.svg'));
      expect(only().iconChosen, isTrue);
      expect(jsonDecode(File(paths.projectsFile).readAsStringSync()), {
        'icons': {'~/Documents/genontech': 'brand/mark.svg'},
      });
      // The chosen picture is offered first, then the logo-like ones.
      expect(service.iconChoices(project).map((i) => i.label), ['brand/mark.svg', 'public/favicon.png']);

      expect(() => service.setIcon(project, p.join(project, 'nope.png')), throwsArgumentError);
      expect(() => service.setIcon(project, p.join(project, '.claude.json')), throwsArgumentError);

      // Gone from the project: the found icon again.
      File(p.join(project, 'brand/mark.svg')).deleteSync();
      expect(only().icon, p.join(project, 'public/favicon.png'));
      expect(only().iconChosen, isFalse);

      service.setIcon(project, null);
      expect(jsonDecode(File(paths.projectsFile).readAsStringSync()), isEmpty);
    });
  });
}
