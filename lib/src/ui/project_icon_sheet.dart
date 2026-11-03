import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../app/rows.dart';
import '../domain/projects.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

// Picks a project's icon when the one found is wrong: a picture from the
// project, any picture on the Mac, or back to the one found.
Future<void> chooseProjectIcon(BuildContext context, ProjectRow project) async {
  final controller = CabinetScope.read(context);
  final choice = await showAppModal<_Choice>(
    context: context,
    builder: (_) => AppDialogCard(
      width: 560,
      maxHeight: 620,
      child: _ProjectIconSheet(project: project, choices: controller.projectIconChoices(project.path)),
    ),
  );
  if (choice != null) await controller.setProjectIcon(project.path, choice.file);
}

// The picked file; null goes back to the found icon.
class _Choice {
  const _Choice(this.file);

  final String? file;
}

class _ProjectIconSheet extends StatelessWidget {
  const _ProjectIconSheet({required this.project, required this.choices});

  final ProjectRow project;
  final Future<List<ProjectIcon>> choices;

  Future<void> _browse(BuildContext context) async {
    final navigator = Navigator.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['png', 'svg', 'jpg', 'jpeg', 'webp', 'ico']),
      ],
      initialDirectory: project.exists ? project.path : null,
      confirmButtonText: 'Use as Icon',
    );
    if (file != null) navigator.pop(_Choice(file.path));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Row(
            children: [
              ProjectAvatar(icon: project.icon, name: project.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Icon for ${project.name}', style: context.macos.typography.headline),
                    const SizedBox(height: 2),
                    Text(
                      project.iconChosen
                          ? 'You chose this icon. Pick another, or go back to the one found in the project.'
                          : 'Found in the project. Pick another picture if this is not its logo.',
                      style: context.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: FutureBuilder<List<ProjectIcon>>(
            future: choices,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _message(context, 'Could not look through the project: ${snapshot.error}');
              }
              final icons = snapshot.data;
              if (icons == null) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: ProgressCircle(radius: 10)),
                );
              }
              if (icons.isEmpty) {
                return _message(context, 'No logo-like pictures in this project. Choose one from anywhere.');
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final icon in icons)
                      _IconTile(
                        icon: icon,
                        name: project.name,
                        current: project.icon != null && (icon.preview == project.icon || icon.file == project.icon),
                        onPressed: () => Navigator.of(context).pop(_Choice(icon.file)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        AppDialogActions(
          children: [
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => _browse(context),
              child: const Text('Choose Image…'),
            ),
            const SizedBox(width: 10),
            if (project.iconChosen)
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.of(context).pop(const _Choice(null)),
                child: const Text('Use Found Icon'),
              ),
            const Spacer(),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _message(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
    child: Text(text, style: context.caption.copyWith(fontSize: 12)),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.name, required this.current, required this.onPressed});

  final ProjectIcon icon;
  final String name;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: icon.label,
      child: SizedBox(
        width: 124,
        child: HoverRow(
          radius: 8,
          selected: current,
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          semanticLabel: icon.label,
          onPressed: onPressed,
          builder: (context, _) => Column(
            children: [
              ProjectAvatar(icon: icon.preview, name: name, size: 48),
              const SizedBox(height: 6),
              Text(
                icon.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.caption.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
