import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/library.dart';
import 'modal.dart';
import 'style.dart';
import 'widgets.dart';

// What the user chose in the import sheet: which skills, and whether the
// originals stay where they are.
class ImportChoice {
  const ImportChoice({required this.paths, required this.move});

  final List<String> paths;
  // The folder leaves its old home. For a project's own `.agents`, this
  // is how the cabinet takes ownership; copying instead leaves a second,
  // drifting copy behind.
  final bool move;
}

// Shows what a drop or an open panel turned up and asks how to take it.
// Returns null when the user cancels or picks nothing.
Future<ImportChoice?> showImportSheet(BuildContext context, ImportScan scan) => showAppModal<ImportChoice>(
  context: context,
  builder: (_) => AppDialogCard(width: 720, maxHeight: 680, child: _ImportSheet(scan: scan)),
);

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.scan});

  final ImportScan scan;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  // Selected by path, so the set survives nothing but this sheet.
  late final Set<String> _selected = {
    for (final c in widget.scan.candidates)
      if (!c.duplicate) c.path,
  };

  List<SkillCandidate> get _candidates => widget.scan.candidates;
  Iterable<SkillCandidate> get _importable => _candidates.where((c) => !c.duplicate);
  int get _duplicates => _candidates.length - _importable.length;

  void _toggle(SkillCandidate candidate) {
    if (candidate.duplicate) return;
    setState(() {
      if (!_selected.remove(candidate.path)) _selected.add(candidate.path);
    });
  }

  void _setAll(bool on) => setState(() {
    _selected
      ..clear()
      ..addAll(on ? _importable.map((c) => c.path) : const <String>[]);
  });

  void _done({required bool move}) {
    // Keep the order the search found them in, shallowest first.
    final paths = [
      for (final c in _candidates)
        if (_selected.contains(c.path)) c.path,
    ];
    Navigator.of(context).pop(paths.isEmpty ? null : ImportChoice(paths: paths, move: move));
  }

  Widget _row(SkillCandidate candidate) => HoverRow(
    semanticLabel: candidate.name,
    onPressed: candidate.duplicate ? null : () => _toggle(candidate),
    builder: (context, _) => Opacity(
      opacity: candidate.duplicate ? 0.5 : 1,
      child: Row(
        children: [
          MacosCheckbox(
            value: _selected.contains(candidate.path),
            onChanged: candidate.duplicate ? null : (_) => _toggle(candidate),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SkillCandidateText(name: candidate.name, description: candidate.description, path: candidate.path),
          ),
          if (candidate.duplicate) ...[const SizedBox(width: 10), const Pill('Already in library')],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    final all = _selected.length == _importable.length && _importable.isNotEmpty;

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
                _candidates.length == 1 ? 'Import this skill?' : 'Found ${_candidates.length} skills',
                style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Copy leaves the folders where they are; move takes them into the library, so the library '
                'is the only copy.',
                style: context.caption.copyWith(fontSize: 12),
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
                _duplicates == 0
                    ? 'SKILLS FOUND · ${_candidates.length}'
                    : 'SKILLS FOUND · ${_importable.length} of ${_candidates.length} available',
                trailing: _importable.length < 2
                    ? null
                    : PushButton(
                        controlSize: ControlSize.small,
                        secondary: true,
                        onPressed: () => _setAll(!all),
                        child: Text(all ? 'Deselect all' : 'Select all'),
                      ),
              ),
              for (final (folder, candidates) in groupByFolder(_candidates, (c) => c.folder)) ...[
                FolderHeader(folder, count: candidates.length),
                for (final candidate in candidates) _row(candidate),
              ],
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(child: Text(count == 0 ? 'Nothing selected' : '$count selected', style: context.caption)),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: count == 0 ? null : () => _done(move: true),
              child: const Text('Move'),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: count == 0 ? null : () => _done(move: false),
              child: const Text('Copy'),
            ),
          ],
        ),
      ],
    );
  }
}
