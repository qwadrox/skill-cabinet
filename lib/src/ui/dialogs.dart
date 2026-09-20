import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import 'modal.dart';
import 'scope.dart';
import 'style.dart';

// Asks before a destructive action; resolves true when confirmed.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final confirmed = await showAppModal<bool>(
    context: context,
    builder: (context) => MacosAlertDialog(
      appIcon: Image.asset('assets/app-icon.png', width: 56, height: 56),
      title: Text(title, textAlign: TextAlign.center, style: context.macos.typography.headline),
      message: Text(message, textAlign: TextAlign.center, style: context.caption.copyWith(fontSize: 12)),
      horizontalActions: true,
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        color: context.resolve(MacosColors.systemRedColor),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(action),
      ),
    ),
  );
  return confirmed ?? false;
}

Future<void> confirmDeleteSet(BuildContext context, String name) async {
  final controller = CabinetScope.read(context);
  final ok = await _confirm(
    context,
    title: 'Delete skill set “$name”?',
    message: 'The skills stay in the library. Only the skill set is removed.',
    action: 'Delete',
  );
  if (ok) await controller.deleteSet(name);
}

Future<void> confirmDeleteSkill(BuildContext context, String name) async {
  final controller = CabinetScope.read(context);
  final ok = await _confirm(
    context,
    title: 'Delete skill “$name”?',
    message:
        'The skill folder is permanently deleted from ${controller.library.root}, removed from every '
        'skill set, and unlinked from every agent. This cannot be undone.',
    action: 'Delete skill',
  );
  if (ok) await controller.deleteSkill(name);
}
