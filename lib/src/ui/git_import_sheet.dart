import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

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
      builder: (_) => AppDialogCard(width: 720, maxHeight: 680, child: _GitImportSheet(preview: preview)),
    );

class _GitImportSheet extends StatefulWidget {
  const _GitImportSheet({required this.preview});

  final GitImportPreview preview;

  @override
  State<_GitImportSheet> createState() => _GitImportSheetState();
}

// Skills the library already has start unchecked and stay out of "Select
// all": choosing one overwrites the local copy, so it takes a deliberate
// click on that row. So do the alternative copies of a name the repository
// holds twice; choosing one drops the other.
class _GitImportSheetState extends State<_GitImportSheet> {
  late final Set<String> _selected = {for (final candidate in _new) candidate.repositoryPath};

  Iterable<GitSkillCandidate> get _candidates => widget.preview.candidates;
  Iterable<GitSkillCandidate> get _new =>
      _candidates.where((candidate) => candidate.selectable && !candidate.replaces && !candidate.alternative);
  int get _replacing =>
      _candidates.where((candidate) => candidate.replaces && _selected.contains(candidate.repositoryPath)).length;

  void _toggle(GitSkillCandidate candidate) {
    if (!candidate.selectable) return;
    setState(() {
      if (!_selected.remove(candidate.repositoryPath)) _select(candidate);
    });
  }

  void _select(GitSkillCandidate candidate) => _selected
    ..removeAll(_candidates.where((other) => other.name == candidate.name).map((other) => other.repositoryPath))
    ..add(candidate.repositoryPath);

  // Grouped by the folder holding them, relative to the repository. A
  // repository that is itself one skill gets no header.
  List<(String, List<GitSkillCandidate>)> get _groups {
    final root = '${widget.preview.repository}/';
    final groups = groupByFolder(_candidates, (candidate) {
      final folder = p.posix.dirname(candidate.repositoryPath);
      return candidate.repositoryPath.isEmpty || folder == '.' ? root : '$folder/';
    });
    if (groups.length == 1 && _candidates.length == 1 && _candidates.single.repositoryPath.isEmpty) {
      return [('', groups.single.$2)];
    }
    // Shallowest first: the main skills folder before add-ons nested
    // deeper, whose copies are the alternatives.
    int depth(String folder) => folder.split('/').length;
    return groups..sort((a, b) {
      final byDepth = depth(a.$1).compareTo(depth(b.$1));
      return byDepth != 0 ? byDepth : a.$1.compareTo(b.$1);
    });
  }

  Widget _row(GitSkillCandidate candidate, Color warning) => HoverRow(
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
            child: SkillCandidateText(
              name: candidate.name,
              description: candidate.description,
              path: candidate.repositoryPath.isEmpty ? '${widget.preview.repository}/' : candidate.repositoryPath,
            ),
          ),
          const SizedBox(width: 10),
          if (candidate.clashes) ...[
            MacosTooltip(
              message:
                  'The repository has more than one folder named ${candidate.name}. '
                  'Only one can be imported; choosing this one leaves the other out.',
              child: Pill(candidate.alternative ? 'Alternative copy' : 'Main copy'),
            ),
            const SizedBox(width: 6),
          ],
          if (candidate.tracked)
            const Pill('Already tracked')
          else if (candidate.replaces)
            MacosTooltip(
              message:
                  'Replace the library’s copy with this one, which is then kept up to date from '
                  'the repository. Agents and skill sets keep it; local edits are lost.',
              child: _selected.contains(candidate.repositoryPath)
                  ? Pill('Replaces local copy', color: warning)
                  : const Pill('In library'),
            ),
          if (candidate.blockedReason != null) Pill(candidate.blockedReason!),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = _new.isNotEmpty && _new.every((candidate) => _selected.contains(candidate.repositoryPath));
    final replacing = _replacing;
    final warning = context.resolve(MacosColors.systemOrangeColor);
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
                trailing: _new.length < 2
                    ? null
                    : PushButton(
                        controlSize: ControlSize.small,
                        secondary: true,
                        onPressed: () => setState(() {
                          if (all) {
                            _selected.clear();
                          } else {
                            _new.forEach(_select);
                          }
                        }),
                        child: Text(all ? 'Deselect all' : 'Select all'),
                      ),
              ),
              for (final (folder, candidates) in _groups) ...[
                if (folder.isNotEmpty) FolderHeader(folder, count: candidates.length),
                for (final candidate in candidates) _row(candidate, warning),
              ],
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '${_selected.length} selected',
                  children: [
                    if (replacing > 0)
                      TextSpan(
                        text: ' · replaces $replacing local skill${replacing == 1 ? '' : 's'}',
                        style: TextStyle(color: warning),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.caption,
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
