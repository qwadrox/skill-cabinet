// Exercises update selection and review against a temporary Git repository,
// and saves light/dark previews to build/screenshots/.
// Run: fvm flutter test tool/git_updates_screenshot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/app/cabinet_controller.dart';
import 'package:skill_cabinet/src/domain/git_import.dart';
import 'package:skill_cabinet/src/domain/notice.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/fs_util.dart';
import 'package:skill_cabinet/src/services/library_service.dart';
import 'package:skill_cabinet/src/ui/app.dart';
import 'package:skill_cabinet/src/ui/git_updates_sheet.dart';
import 'package:skill_cabinet/src/ui/modal.dart';
import 'package:skill_cabinet/src/ui/skill_pane.dart';

void main() {
  testWidgets('selection stays independent of review; update and diff previews', (tester) async {
    final root = Directory.systemTemp.createTempSync('update-ui-');
    final paths = CabinetPaths(p.join(root.path, 'home'));
    final remote = p.join(root.path, 'acme', 'seo');
    final controller = CabinetController(paths);
    addTearDown(() {
      controller.dispose();
      root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    void write(String folder, String content) {
      Directory(folder).createSync(recursive: true);
      File(p.join(folder, 'SKILL.md')).writeAsStringSync(content);
    }

    const localContent = '''---
name: seo-audit
description: Audit a website for technical SEO issues.
---

# SEO Audit

## Workflow
1. Crawl the website.
2. Check titles and meta descriptions.
3. Report issues in priority order.

## Output
Return a short list of recommended fixes.
''';
    const incomingContent = '''---
name: seo-audit
description: Audit technical SEO and search visibility.
---

# SEO Audit

## Workflow
1. Crawl the website and inspect robots.txt.
2. Check titles, canonical URLs, and structured data.
3. Identify indexing and mobile usability issues.
4. Report issues in priority order.

## Output
Group findings by severity, with evidence and suggested fixes.
''';
    final names = ['seo', 'seo-audit', 'seo-backlinks', 'seo-content', 'seo-local', 'seo-technical'];
    for (final name in names) {
      write(p.join(remote, 'skills', name), name == 'seo-audit' ? incomingContent : '# $name\n');
      write(p.join(paths.storeDir, name), name == 'seo-audit' ? localContent : '# $name\n');
    }
    File(p.join(remote, 'skills/seo-audit/checklist.md')).writeAsStringSync('# Checklist\n- Inspect indexing\n');
    File(p.join(paths.storeDir, 'seo-audit/notes.md')).writeAsStringSync('# Local notes\n');
    for (final args in [
      ['init', '-q'],
      ['config', 'user.name', 'Test'],
      ['config', 'user.email', 'test@example.com'],
      ['add', '.'],
      ['commit', '-qm', 'incoming'],
    ]) {
      expect(Process.runSync('/usr/bin/git', ['-C', remote, ...args]).exitCode, 0);
    }
    final revision = Process.runSync('/usr/bin/git', ['-C', remote, 'rev-parse', 'HEAD']).stdout.toString().trim();
    final records = {
      for (final name in names)
        name: GitSourceRecord(
          skillName: name,
          sourceUrl: remote,
          ref: 'HEAD',
          repositoryPath: 'skills/$name',
          revision: 'old',
          remoteRevision: revision,
          hasContentChanges: true,
        ),
      'already-current': GitSourceRecord(
        skillName: 'already-current',
        sourceUrl: remote,
        ref: 'HEAD',
        repositoryPath: 'unchanged',
        revision: revision,
        remoteRevision: revision,
        hasContentChanges: false,
      ),
      for (final path in ['skills/engineering/code-review', 'skills/engineering/testing', 'skills/writing/docs'])
        p.basename(path): GitSourceRecord(
          skillName: p.basename(path),
          sourceUrl: 'https://github.com/acme/agent-skills',
          ref: 'main',
          repositoryPath: path,
          revision: 'old',
          remoteRevision: revision,
          hasContentChanges: true,
        ),
    };
    writeJsonAtomic(paths.gitSourcesFile, {for (final entry in records.entries) entry.key: entry.value.toJson()});
    controller.gitSources = records;
    controller.library = LibraryService(paths).scan();
    controller.loaded = true;

    await tester.runAsync(() async {
      for (final family in ['.AppleSystemUIFont', 'SF Pro Text', 'SF Pro Display', 'SF Pro', 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync())));
        await loader.load();
      }
      final mono = FontLoader('Menlo')
        ..addFont(Future.value(ByteData.sublistView(File('/System/Library/Fonts/Menlo.ttc').readAsBytesSync())));
      await mono.load();
      final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    });
    tester.view.physicalSize = const Size(1240, 760) * 2;
    tester.view.devicePixelRatio = 2;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('macos_window_utils'), (_) async => null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (_) async => {
        'redComponent': 0.0,
        'greenComponent': 0.478,
        'blueComponent': 1.0,
        'hueComponent': 0.6085324903200698,
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);

    const key = ValueKey('update-preview');
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final captured = await boundary.toImage(pixelRatio: 2);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawColor(name.endsWith('dark') ? const Color(0xFF1E1E20) : const Color(0xFFF4F4F5), BlendMode.src);
        canvas.drawImage(captured, Offset.zero, Paint());
        final image = await recorder.endRecording().toImage(captured.width, captured.height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/screenshots').createSync(recursive: true);
        File('build/screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      tester.platformDispatcher.platformBrightnessTestValue = mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: CabinetApp(controller: controller, themeMode: mode),
        ),
      );
      await tester.pumpAndSettle();
      if (mode == ThemeMode.light) {
        controller.gitSources = {
          for (final entry in records.entries) entry.key: entry.value.withCheck(contentChanges: false),
        };
        controller.notice = const Notice.info('All Git-tracked skills are up to date');
        controller.selectAll();
        await tester.pumpAndSettle();
        expect(find.text('Review updates'), findsNothing);
        expect(
          find.byWidgetPredicate((widget) => widget is MacosIcon && widget.icon == CupertinoIcons.info_circle),
          findsOneWidget,
        );
        showGitUpdatesSheet(tester.element(find.byType(SkillPane)));
        await tester.pumpAndSettle();
        expect(find.text('No updates available'), findsOneWidget);
        final card = find.descendant(of: find.byType(AppDialogCard), matching: find.byType(ConstrainedBox)).first;
        expect(tester.getSize(card).height, lessThan(400));
        await capture('updates-empty');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        controller.gitSources = records;
        controller.notice = const Notice.warning('Unrelated notice');
        controller.selectAll();
        await tester.pumpAndSettle();
        expect(find.text('Review updates'), findsNothing);
        controller.notice = const Notice.info('9 Git updates available');
        controller.selectAll();
        await tester.pumpAndSettle();
        expect(find.text('Review updates'), findsOneWidget);
        controller.dismissNotice();
        await tester.pumpAndSettle();
      }
      showGitUpdatesSheet(tester.element(find.byType(SkillPane)));
      await tester.pumpAndSettle();
      expect(find.text('Update 9'), findsOneWidget);
      expect(find.text('already-current'), findsNothing);
      expect(find.text('Up to date'), findsNothing);
      expect(find.textContaining('Updating replaces'), findsNothing);
      expect(find.text('Deselect repo'), findsNothing);
      expect(find.text('Deselect all'), findsNothing);
      await capture('updates-${mode.name}');
      final skillCheckbox = find.byType(MacosCheckbox).at(2);
      await tester.tap(skillCheckbox);
      await tester.pumpAndSettle();
      expect(find.text('Update 8'), findsOneWidget);
      expect(find.text('Local → incoming'), findsNothing);
      await tester.tap(skillCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MacosCheckbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Update 3'), findsOneWidget);
      await tester.tap(find.byType(MacosCheckbox).first);
      await tester.pumpAndSettle();

      final checkbox = find.byType(MacosCheckbox).last;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('Update'), findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('Update 9'), findsOneWidget);

      await tester.tap(find.text('seo-audit').last);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(find.text('Local → incoming'), findsOneWidget);
      expect(find.text('SKILL.md'), findsOneWidget);
      expect(find.text('checklist.md'), findsOneWidget);
      expect(find.text('notes.md'), findsOneWidget);
      expect(find.textContaining('+4. Report issues', findRichText: true), findsOneWidget);
      await capture('changes-${mode.name}');
      await tester.tap(find.text('notes.md'));
      await tester.pumpAndSettle();
      expect(find.textContaining('-# Local notes', findRichText: true), findsOneWidget);
      await tester.tap(find.text('checklist.md'));
      await tester.pumpAndSettle();
      expect(find.textContaining('+# Checklist', findRichText: true), findsOneWidget);

      await tester.tap(
        find.byWidgetPredicate((widget) => widget is MacosIconButton && widget.semanticLabel == 'Back to updates'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update 9'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    expect(File(p.join(paths.storeDir, 'seo-audit/SKILL.md')).readAsStringSync(), localContent);
    controller.gitSources = {
      for (final entry in records.entries) entry.key: entry.value.withCheck(contentChanges: false),
    };
    await tester.pumpAndSettle();
    showGitUpdatesSheet(tester.element(find.byType(SkillPane)));
    await tester.pumpAndSettle();
    expect(find.text('No updates available'), findsOneWidget);
    expect(find.text('Update 9'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // Newly discovered skills share the update sheet and keep replacement
    // choices explicit through the existing import picker.
    const discovered = [
      GitDiscoveredSkill(
        name: 'accessibility-audit',
        repositoryPath: 'skills/accessibility-audit',
        description: 'Find accessibility issues and suggest practical improvements.',
      ),
      GitDiscoveredSkill(
        name: 'seo-schema',
        repositoryPath: 'skills/seo-schema',
        description: 'Review structured data and rich result eligibility.',
      ),
    ];
    for (final skill in discovered) {
      write(p.join(remote, skill.repositoryPath), '# ${skill.name}\n');
    }
    write(p.join(paths.storeDir, 'seo-schema'), '# My local schema skill\n');
    for (final args in [
      ['add', '.'],
      ['commit', '-qm', 'new skills'],
    ]) {
      expect(Process.runSync('/usr/bin/git', ['-C', remote, ...args]).exitCode, 0);
    }
    final discovery = GitRepositoryDiscovery(
      sourceUrl: remote,
      ref: 'HEAD',
      seenPaths: {for (final name in names) 'skills/$name', for (final skill in discovered) skill.repositoryPath},
      pending: discovered,
    );
    writeJsonAtomic(paths.gitRepositoriesFile, [discovery.toJson()]);
    writeJsonAtomic(paths.gitSourcesFile, {
      for (final entry in controller.gitSources.entries) entry.key: entry.value.toJson(),
    });
    controller.gitRepositories = [discovery];
    controller.notice = const Notice.info('2 new skills available');
    controller.selectAll();
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      tester.platformDispatcher.platformBrightnessTestValue = mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: CabinetApp(controller: controller, themeMode: mode),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review updates'), findsOneWidget);
      showGitUpdatesSheet(tester.element(find.byType(SkillPane)));
      await tester.pumpAndSettle();
      expect(find.text('NEW SKILLS'), findsOneWidget);
      expect(find.text('0 updates · 2 new'), findsOneWidget);
      expect(find.text('Import…'), findsNWidgets(2));
      expect(find.text(discovered.first.description), findsOneWidget);
      expect(find.text('No updates available'), findsNothing);
      await capture('updates-new-${mode.name}');
      const explanation =
          'New skills from this repository.\n'
          'Import any you’d like to add to your library and track for updates.';
      expect(find.text(explanation), findsNothing);
      if (mode == ThemeMode.dark) {
        final help = find.byWidgetPredicate((widget) => widget is MacosTooltip && widget.message == explanation);
        final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(help));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text(explanation), findsOneWidget);
        await capture('updates-new-tooltip-dark');
        await mouse.removePointer();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    Future<void> waitForWork(bool Function() finished) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
        if (finished()) return;
      }
      fail('Background operation did not finish');
    }

    controller.gitSources = {...controller.gitSources, 'seo-audit': records['seo-audit']!};
    controller.selectAll();
    showGitUpdatesSheet(tester.element(find.byType(SkillPane)));
    await tester.pumpAndSettle();
    expect(find.text('1 update · 2 new'), findsOneWidget);
    expect(find.text('UPDATES'), findsOneWidget);
    await capture('updates-and-new-dark');
    await tester.tap(find.text('Update 1'));
    await waitForWork(() => !controller.applyingGitUpdates);
    await tester.pumpAndSettle();
    expect(find.text('NEW SKILLS'), findsOneWidget);
    expect(find.text('0 updates · 2 new'), findsOneWidget);
    expect(find.text('Update 1'), findsNothing);

    await tester.tap(find.text('Import…').last);
    await waitForWork(() => find.text('SKILLS FOUND · 1').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('SKILLS FOUND · 1'), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);
    expect(tester.widget<PushButton>(find.widgetWithText(PushButton, 'Import & track')).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await waitForWork(() => find.text('Loading…').evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(controller.newGitSkills, 2);
    expect(File(p.join(paths.storeDir, 'seo-schema/SKILL.md')).readAsStringSync(), '# My local schema skill\n');

    await tester.tap(find.text('Import…').first);
    await waitForWork(() => find.text('SKILLS FOUND · 1').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('SKILLS FOUND · 1'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Import & track'));
    await waitForWork(() => controller.newGitSkills == 1 && find.text('Loading…').evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(controller.newGitSkills, 1);
    expect(controller.library.has('accessibility-audit'), isTrue);
    expect(controller.gitSources['accessibility-audit']!.repositoryPath, discovered.first.repositoryPath);
    expect(File(paths.deploymentFile).existsSync(), isFalse);
    expect(find.text('Import…'), findsOneWidget);
    await tester.tap(find.text('Dismiss').last);
    await waitForWork(() => controller.newGitSkills == 0);
    await tester.pumpAndSettle();
    expect(controller.newGitSkills, 0);
    expect(find.text('No updates available'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
  });
}
