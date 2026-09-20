import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

// Asks before a destructive action; resolves true when confirmed.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final confirmed = await showAppModal<bool>(
    context: context,
    builder: (context) => AppDialogCard(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              children: [
                Image.asset('assets/app-icon.png', width: 52, height: 52),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: context.macos.typography.headline),
                const SizedBox(height: 6),
                Text(message, textAlign: TextAlign.center, style: context.caption.copyWith(fontSize: 12)),
              ],
            ),
          ),
          AppDialogActions(
            children: [
              Expanded(
                child: PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DangerButton(label: action, onPressed: () => Navigator.of(context).pop(true)),
              ),
            ],
          ),
        ],
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
