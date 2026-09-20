import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/git_import.dart';
import 'modal.dart';
import 'style.dart';
import 'widgets.dart';

Future<String?> showGitUrlSheet(BuildContext context) => showAppModal<String>(
  context: context,
  builder: (_) =>
      const MacosSheet(insetPadding: EdgeInsets.symmetric(horizontal: 210, vertical: 170), child: _GitUrlSheet()),
);

class _GitUrlSheet extends StatefulWidget {
  const _GitUrlSheet();

  @override
  State<_GitUrlSheet> createState() => _GitUrlSheetState();
}

class _GitUrlSheetState extends State<_GitUrlSheet> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _url.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import from Git', style: context.macos.typography.title2.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              'Paste an HTTPS or SSH repository URL. GitHub, GitLab, Bitbucket, and self-hosted Git work.',
              style: context.caption,
            ),
          ],
        ),
      ),
      Container(height: 1, color: context.separator),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
        child: MacosTextField(
          controller: _url,
          autofocus: true,
          placeholder: 'https://git.example.com/team/skills.git',
          placeholderStyle: context.placeholder,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
      ),
      Container(height: 1, color: context.separator),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: _url.text.trim().isEmpty ? null : _submit,
              child: const Text('Find skills'),
            ),
          ],
        ),
      ),
    ],
  );
}

class GitImportChoice {
  const GitImportChoice(this.repositoryPaths);

  final List<String> repositoryPaths;
}

Future<GitImportChoice?> showGitImportSheet(BuildContext context, GitImportPreview preview) =>
    showAppModal<GitImportChoice>(
      context: context,
      builder: (_) => MacosSheet(
        insetPadding: const EdgeInsets.symmetric(horizontal: 150, vertical: 70),
        child: _GitImportSheet(preview: preview),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Found ${_candidates.length} skills',
                style: context.macos.typography.title2.copyWith(fontWeight: FontWeight.w600),
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
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
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
        Container(height: 1, color: context.separator),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
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
        ),
      ],
    );
  }
}
