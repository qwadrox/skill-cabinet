import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/git_import.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

// Asks for a repository URL and clones it while the dialog stays up: the
// wait and anything that goes wrong belong here, next to the field that
// caused them, not in the pane's notice banner after the dialog closed.
Future<GitImportPreview?> showGitUrlSheet(BuildContext context) => showAppModal<GitImportPreview>(
  context: context,
  builder: (_) => const AppDialogCard(child: _GitUrlSheet()),
);

class _GitUrlSheet extends StatefulWidget {
  const _GitUrlSheet();

  @override
  State<_GitUrlSheet> createState() => _GitUrlSheetState();
}

class _GitUrlSheetState extends State<_GitUrlSheet> {
  final _url = TextEditingController();
  bool _cloning = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _url.text.trim();
    if (value.isEmpty || _cloning) return;
    // Held across the await: the dialog may be gone by the time the clone
    // lands, and the checkout still has to be cleaned up.
    final controller = CabinetScope.read(context);
    setState(() {
      _cloning = true;
      _error = null;
    });
    final outcome = await controller.previewGit(value);
    final preview = outcome.preview;
    if (!mounted) {
      if (preview != null) await controller.discardGitPreview(preview);
      return;
    }
    if (preview == null) {
      setState(() {
        _cloning = false;
        _error = outcome.error;
      });
      return;
    }
    Navigator.of(context).pop(preview);
  }

  @override
  Widget build(BuildContext context) {
    final empty = _url.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Import from Git', style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Paste an HTTPS or SSH repository URL. GitHub, GitLab, Bitbucket, and self-hosted Git work.',
                style: context.caption,
              ),
              const SizedBox(height: 14),
              MacosTextField(
                controller: _url,
                autofocus: true,
                // Not `enabled: false` while cloning: macos_ui paints a
                // disabled field with its light-mode background, which flashes
                // white in dark mode. Read-only keeps the field's own colors.
                readOnly: _cloning,
                placeholder: 'https://git.example.com/team/skills.git',
                placeholderStyle: context.placeholder,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[const SizedBox(height: 12), _ErrorNote(_error!)],
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(
              child: !_cloning
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        const ProgressCircle(radius: 8),
                        const SizedBox(width: 8),
                        Flexible(child: Text('Cloning repository…', style: context.caption)),
                      ],
                    ),
            ),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: empty || _cloning ? null : _submit,
              child: const Text('Find skills'),
            ),
          ],
        ),
      ],
    );
  }
}

// Why the clone failed, kept in the dialog so the URL can be fixed and
// tried again. Same tint and shape as the pane's notice banner.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final tint = context.resolve(MacosColors.systemRedColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MacosIcon(CupertinoIcons.xmark_octagon, size: 14, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis, style: context.caption),
          ),
        ],
      ),
    );
  }
}

class GitImportChoice {
  const GitImportChoice(this.repositoryPaths);

  final List<String> repositoryPaths;
}

Future<GitImportChoice?> showGitImportSheet(BuildContext context, GitImportPreview preview) =>
    showAppModal<GitImportChoice>(
      context: context,
      builder: (_) => AppDialogCard(width: 620, child: _GitImportSheet(preview: preview)),
    );

class _GitImportSheet extends StatefulWidget {
  const _GitImportSheet({required this.preview});

  final GitImportPreview preview;

  @override
  State<_GitImportSheet> createState() => _GitImportSheetState();
}

class _GitImportSheetState extends State<_GitImportSheet> {
  late final Set<String> _selected = {
    for (final candidate in widget.preview.candidates)
      if (candidate.selectable) candidate.repositoryPath,
  };

  Iterable<GitSkillCandidate> get _candidates => widget.preview.candidates;
  Iterable<GitSkillCandidate> get _selectable => _candidates.where((candidate) => candidate.selectable);

  void _toggle(GitSkillCandidate candidate) {
    if (!candidate.selectable) return;
    setState(() {
      if (!_selected.remove(candidate.repositoryPath)) _selected.add(candidate.repositoryPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _selected.length == _selectable.length && _selectable.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Found ${_candidates.length} skills',
                style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.preview.repository} · ${widget.preview.ref} · select skills to import and track',
                style: context.mono,
              ),
            ],
          ),
        ),
        Container(height: 1, color: context.separator),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              SectionLabel(
                'SKILLS FOUND · ${_candidates.length}',
                trailing: _selectable.length < 2
                    ? null
                    : PushButton(
                        controlSize: ControlSize.small,
                        secondary: true,
                        onPressed: () => setState(() {
                          _selected
                            ..clear()
                            ..addAll(all ? const <String>[] : _selectable.map((candidate) => candidate.repositoryPath));
                        }),
                        child: Text(all ? 'Deselect all' : 'Select all'),
                      ),
              ),
              for (final candidate in _candidates)
                HoverRow(
                  semanticLabel: candidate.name,
                  onPressed: candidate.selectable ? () => _toggle(candidate) : null,
                  builder: (context, _) => Opacity(
                    opacity: candidate.selectable ? 1 : 0.5,
                    child: Row(
                      children: [
                        MacosCheckbox(
                          value: _selected.contains(candidate.repositoryPath),
                          onChanged: candidate.selectable ? (_) => _toggle(candidate) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(candidate.name, style: context.body.copyWith(fontWeight: FontWeight.w500)),
                              const SizedBox(height: 1),
                              Text(
                                candidate.description.isEmpty ? candidate.repositoryPath : candidate.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.caption,
                              ),
                            ],
                          ),
                        ),
                        if (candidate.duplicate) const Pill('Already in library'),
                        if (candidate.blockedReason != null) Pill(candidate.blockedReason!),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(child: Text('${_selected.length} selected', style: context.caption)),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(GitImportChoice(_selected.toList())),
              child: const Text('Import & track'),
            ),
          ],
        ),
      ],
    );
  }
}
