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

Future<void> renameSetDialog(BuildContext context, String name) async {
  final controller = CabinetScope.read(context);
  final renamed = await showAppModal<String>(
    context: context,
    builder: (_) => AppDialogCard(width: 380, child: _RenameSetDialog(name: name)),
  );
  if (renamed != null) await controller.renameSet(name, renamed);
}

class _RenameSetDialog extends StatefulWidget {
  const _RenameSetDialog({required this.name});

  final String name;

  @override
  State<_RenameSetDialog> createState() => _RenameSetDialogState();
}

class _RenameSetDialogState extends State<_RenameSetDialog> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.name) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty && _name.text.trim() != widget.name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Rename skill set', style: context.macos.typography.headline),
              const SizedBox(height: 14),
              MacosTextField(
                controller: _name,
                autofocus: true,
                placeholderStyle: context.placeholder,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(
              child: PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PushButton(
                controlSize: ControlSize.large,
                onPressed: ready ? _submit : null,
                child: const Text('Rename'),
              ),
            ),
          ],
        ),
      ],
    );
  }
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

Future<bool> confirmRestoreBackup(BuildContext context, String date) => _confirm(
  context,
  title: 'Restore the backup of $date?',
  message:
      'Skills, skill sets and agents go back to how they were then. The current state stays in the '
      'history, so this can be undone.',
  action: 'Restore',
);

Future<bool> confirmAdoptRemoteBackup(BuildContext context) => _confirm(
  context,
  title: 'Restore this backup?',
  message:
      'The repository already holds a Skill Cabinet backup. Restoring replaces the skills, skill sets '
      'and agents on this Mac with it, and backs up there from now on.',
  action: 'Restore',
);
