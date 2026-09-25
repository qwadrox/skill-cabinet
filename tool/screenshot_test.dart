// Renders the app offscreen against a sample home and writes PNGs, for
// checking the UI without a display:
//   SKILL_CABINET_HOME=/path/to/sample-home fvm flutter test tool/screenshot_test.dart
// Output goes to build/screenshots/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skill_cabinet/src/app/cabinet_controller.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/ui/agents_sheet.dart';
import 'package:skill_cabinet/src/ui/backup_sheet.dart';
import 'package:skill_cabinet/src/ui/app.dart';
import 'package:skill_cabinet/src/ui/skill_pane.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  testWidgets('screenshots', (tester) async {
    final home = Platform.environment['SKILL_CABINET_HOME'];
    if (home == null) return;
    await tester.runAsync(() async {
      for (final family in ['.AppleSystemUIFont', 'SF Pro Text', 'SF Pro Display', 'SF Pro', 'Roboto']) {
        await _font(family, ['/System/Library/Fonts/SFNS.ttf']);
      }
      await _font('Menlo', ['/System/Library/Fonts/Menlo.ttc']);
      final icons = File(
        '${Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache'}'
        '/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
      );
      if (icons.existsSync()) await _font('packages/cupertino_icons/CupertinoIcons', [icons.path]);
    });

    tester.view.physicalSize = const Size(1240, 760) * 2;
    tester.view.devicePixelRatio = 2;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('macos_window_utils'), (_) async => null);
    // The system accent: blue.
    const accent = {'redComponent': 0.0, 'greenComponent': 0.478, 'blueComponent': 1.0};
    messenger.setMockMethodCallHandler(const MethodChannel('appkit_ui_element_colors'), (call) async {
      final components = ((call.arguments as Map)['components'] as List).cast<String>();
      return {for (final c in components) c: accent[c] ?? 1.0};
    });
    messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);

    final controller = CabinetController(CabinetPaths(home));
    await tester.runAsync(controller.load);
    Directory('build/screenshots').createSync(recursive: true);

    const shotKey = ValueKey('shot');
    Future<void> capture(String name, ThemeMode mode) async {
      final backdrop = mode == ThemeMode.dark ? const Color(0xFF1E1E20) : const Color(0xFFF4F4F5);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
        final captured = await boundary.toImage(pixelRatio: 2);
        // macos_ui clears the window so the native vibrancy shows through;
        // put a window-colored backdrop under it.
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(backdrop, BlendMode.src);
        canvas.drawImage(captured, Offset.zero, Paint());
        final image = await recorder.endRecording().toImage(captured.width, captured.height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> shot(String name, {ThemeMode mode = ThemeMode.light}) async {
      tester.platformDispatcher.platformBrightnessTestValue = mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: CabinetApp(controller: controller, themeMode: mode),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      await capture(name, mode);
    }

    await shot('all-light');
    await shot('all-dark', mode: ThemeMode.dark);
    controller.toggleSection('Web');
    await tester.runAsync(() async {
      controller.togglePreview('frontend-design');
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await shot('preview-light');
    await shot('preview-dark', mode: ThemeMode.dark);
    controller.closePreview();
    controller.selectSet('Web');
    await shot('set-light');
    await tester.runAsync(() async {
      controller.togglePreview('broken');
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    controller.selectAll();
    await shot('broken-dark', mode: ThemeMode.dark);
    // The agents sheet over the window.
    showAgentsSheet(tester.element(find.byType(SkillPane)));
    await tester.pumpAndSettle();
    // Let the logos decode.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    await capture('agents-dark', ThemeMode.dark);
    Navigator.of(tester.element(find.byType(SkillPane)), rootNavigator: true).pop();
    await tester.pumpAndSettle();
    // The backup sheet, with whatever history the sample home has.
    await tester.runAsync(controller.backUpNow);
    showBackupSheet(tester.element(find.byType(SkillPane)));
    await tester.pumpAndSettle();
    await capture('backup-dark', ThemeMode.dark);
    debugDefaultTargetPlatformOverride = null;
  });
}
