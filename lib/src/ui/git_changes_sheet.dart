import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:macos_ui/macos_ui.dart';

import '../domain/git_import.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

Future<void> showGitChangesSheet(
  BuildContext context, {
  required GitSourceRecord source,
  required ValueChanged<String> onReviewed,
}) => showAppModal<void>(
  context: context,
  builder: (_) => AppDialogCard(
    width: 920,
    maxHeight: 660,
    child: _GitChangesSheet(source: source, onReviewed: onReviewed),
  ),
);

class _GitChangesSheet extends StatefulWidget {
  const _GitChangesSheet({required this.source, required this.onReviewed});

  final GitSourceRecord source;
  final ValueChanged<String> onReviewed;

  @override
  State<_GitChangesSheet> createState() => _GitChangesSheetState();
}

class _GitChangesSheetState extends State<_GitChangesSheet> {
  GitUpdatePreview? _preview;
  String? _error;
  String? _selectedPath;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final preview = await CabinetScope.read(context).previewGitUpdate(widget.source.skillName);
      if (!mounted) return;
      widget.onReviewed(preview.revision);
      setState(() {
        _preview = preview;
        _selectedPath = preview.files.firstOrNull?.path;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(
            children: [
              IconAction(
                icon: CupertinoIcons.chevron_left,
                tooltip: 'Back to updates',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.source.skillName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.macos.typography.headline,
                ),
              ),
              Text('Local → incoming', style: context.caption),
            ],
          ),
        ),
        Container(height: 1, color: context.separator),
        Flexible(
          child: SizedBox(
            height: 510,
            child: _error != null
                ? EmptyState(
                    icon: CupertinoIcons.exclamationmark_circle,
                    title: 'Could not load changes',
                    message: Text(_error!),
                    action: PushButton(controlSize: ControlSize.regular, onPressed: _load, child: const Text('Retry')),
                  )
                : preview == null
                ? const Center(child: ProgressCircle())
                : preview.files.isEmpty
                ? const EmptyState(
                    icon: CupertinoIcons.checkmark_circle,
                    title: 'No content changes',
                    message: Text('The local skill matches the incoming version.'),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 220,
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final file in preview.files)
                              HoverRow(
                                semanticLabel: '${file.kind.name}: ${file.path}',
                                selected: _selectedPath == file.path,
                                onPressed: () => setState(() => _selectedPath = file.path),
                                builder: (context, _) => Row(
                                  children: [
                                    MacosIcon(
                                      switch (file.kind) {
                                        GitFileChangeKind.added => CupertinoIcons.plus,
                                        GitFileChangeKind.deleted => CupertinoIcons.minus,
                                        GitFileChangeKind.modified => CupertinoIcons.pencil,
                                      },
                                      size: 12,
                                      color: switch (file.kind) {
                                        GitFileChangeKind.added => context.resolve(MacosColors.systemGreenColor),
                                        GitFileChangeKind.deleted => context.resolve(MacosColors.systemRedColor),
                                        GitFileChangeKind.modified => context.secondaryLabel,
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: MacosTooltip(
                                        message: file.path,
                                        child: Text(
                                          file.path,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.mono,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: context.separator),
                      Expanded(child: _FileDiff(file: preview.files.firstWhere((file) => file.path == _selectedPath))),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _FileDiff extends StatelessWidget {
  const _FileDiff({required this.file});

  final GitFileChange file;

  @override
  Widget build(BuildContext context) {
    if (file.message != null) return Center(child: Text(file.message!, style: context.caption));
    final added = context.resolve(MacosColors.systemGreenColor);
    final removed = context.resolve(MacosColors.systemRedColor);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: ValueKey(file.path),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - 28),
            child: SelectableText.rich(
              TextSpan(
                style: context.mono.copyWith(height: 1.6),
                children: [
                  for (final line in file.diff.split('\n'))
                    TextSpan(
                      text: '$line\n',
                      style: line.startsWith('+')
                          ? TextStyle(color: added, backgroundColor: added.withValues(alpha: 0.1))
                          : line.startsWith('-')
                          ? TextStyle(color: removed, backgroundColor: removed.withValues(alpha: 0.1))
                          : line.startsWith('@@')
                          ? TextStyle(color: context.secondaryLabel)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
