import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/git_import.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

Future<void> showGitUpdatesSheet(BuildContext context, {String? focusSkill}) => showAppModal<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => AppDialogCard(width: 760, maxHeight: 680, child: _GitUpdatesSheet(focusSkill: focusSkill)),
);

class _GitUpdatesSheet extends StatefulWidget {
  const _GitUpdatesSheet({this.focusSkill});

  final String? focusSkill;

  @override
  State<_GitUpdatesSheet> createState() => _GitUpdatesSheetState();
}

class _GitUpdatesSheetState extends State<_GitUpdatesSheet> {
  final Set<String> _selected = {};
  Map<String, String> _failures = const {};
  bool _initialized = false;
  bool _checking = false;
  bool _applying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final sources = CabinetScope.read(context).gitSources;
    final focused = widget.focusSkill;
    if (focused != null && sources[focused]?.state == GitTrackingState.updateAvailable) {
      _selected.add(focused);
    } else {
      _selected.addAll(
        sources.values
            .where((source) => source.state == GitTrackingState.updateAvailable)
            .map((source) => source.skillName),
      );
    }
  }

  Future<void> _check() async {
    if (_checking || _applying) return;
    setState(() {
      _checking = true;
      _failures = const {};
    });
    await CabinetScope.read(context).checkGitUpdates();
    if (!mounted) return;
    final sources = CabinetScope.read(context).gitSources;
    setState(() {
      _checking = false;
      _selected
        ..clear()
        ..addAll(
          sources.values
              .where((source) => source.state == GitTrackingState.updateAvailable)
              .map((source) => source.skillName),
        );
    });
  }

  Future<void> _apply() async {
    if (_selected.isEmpty || _applying || _checking) return;
    setState(() {
      _applying = true;
      _failures = const {};
    });
    final result = await CabinetScope.read(context).applyGitUpdates(_selected);
    if (!mounted) return;
    if (result.failures.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _applying = false;
      _failures = result.failures;
      _selected
        ..clear()
        ..addAll(result.failures.keys);
    });
  }

  void _toggle(String name) {
    if (_checking || _applying) return;
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final sources = controller.gitSources.values.toList()
      ..sort((a, b) {
        final byState = _stateOrder(a.state).compareTo(_stateOrder(b.state));
        return byState != 0 ? byState : a.skillName.compareTo(b.skillName);
      });
    final available = sources.where((source) => source.state == GitTrackingState.updateAvailable).toList();
    final others = sources.where((source) => source.state != GitTrackingState.updateAvailable).toList();
    final availableGroups = _groupByRepository(available);
    final otherGroups = _groupByRepository(others);
    final allSelected = available.isNotEmpty && available.every((source) => _selected.contains(source.skillName));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Git skill updates',
                      style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      available.isEmpty
                          ? 'All ${sources.length} tracked skill${sources.length == 1 ? '' : 's'} are up to date.'
                          : '${available.length} update${available.length == 1 ? '' : 's'} available. Updating replaces the tracked skill in place.',
                      style: context.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: _checking || _applying ? null : _check,
                child: _checking
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [ProgressCircle(radius: 7), SizedBox(width: 7), Text('Checking…')],
                      )
                    : const Text('Check now'),
              ),
            ],
          ),
        ),
        Container(height: 1, color: context.separator),
        Flexible(
          child: sources.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.cloud,
                  title: 'No Git-tracked skills',
                  message: Text('Skills imported from a Git repository will appear here.'),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    if (_failures.isNotEmpty) _FailureNote(_failures.length),
                    if (available.isNotEmpty) ...[
                      SectionLabel(
                        'UPDATES AVAILABLE · ${available.length}',
                        trailing: available.length < 2
                            ? null
                            : PushButton(
                                controlSize: ControlSize.small,
                                secondary: true,
                                onPressed: _applying || _checking
                                    ? null
                                    : () => setState(() {
                                        if (allSelected) {
                                          _selected.removeAll(available.map((source) => source.skillName));
                                        } else {
                                          _selected.addAll(available.map((source) => source.skillName));
                                        }
                                      }),
                                child: Text(allSelected ? 'Deselect all' : 'Select all'),
                              ),
                      ),
                      for (final group in availableGroups)
                        _RepositoryGroupCard(
                          sources: group,
                          selected: _selected,
                          failures: _failures,
                          enabled: !_applying && !_checking,
                          onToggle: _toggle,
                          onToggleAll: () => setState(() {
                            final names = group.map((source) => source.skillName);
                            if (group.every((source) => _selected.contains(source.skillName))) {
                              _selected.removeAll(names);
                            } else {
                              _selected.addAll(names);
                            }
                          }),
                        ),
                    ],
                    if (others.isNotEmpty) ...[
                      SectionLabel('OTHER TRACKED SKILLS · ${others.length}'),
                      for (final group in otherGroups) _RepositoryGroupCard(sources: group),
                    ],
                  ],
                ),
        ),
        AppDialogActions(
          children: [
            Expanded(
              child: Text(
                _applying
                    ? 'Updating ${_selected.length} skill${_selected.length == 1 ? '' : 's'}…'
                    : '${_selected.length} selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.caption,
              ),
            ),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: _applying ? null : () => Navigator.of(context).pop(),
              child: Text(available.isEmpty ? 'Done' : 'Cancel'),
            ),
            if (available.isNotEmpty) ...[
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: _selected.isEmpty || _checking || _applying ? null : _apply,
                child: _applying
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [ProgressCircle(radius: 7), SizedBox(width: 7), Text('Updating…')],
                      )
                    : const Text('Update selected'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  int _stateOrder(GitTrackingState state) => switch (state) {
    GitTrackingState.updateAvailable => 0,
    GitTrackingState.error => 1,
    GitTrackingState.tracked => 2,
    GitTrackingState.upToDate => 3,
  };
}

List<List<GitSourceRecord>> _groupByRepository(Iterable<GitSourceRecord> sources) {
  final groups = <String, List<GitSourceRecord>>{};
  for (final source in sources) {
    groups.putIfAbsent('${source.sourceUrl}\u0000${source.ref}', () => []).add(source);
  }
  final result = groups.values.toList()
    ..sort((a, b) {
      final byUrl = a.first.sourceUrl.compareTo(b.first.sourceUrl);
      return byUrl != 0 ? byUrl : a.first.ref.compareTo(b.first.ref);
    });
  for (final group in result) {
    group.sort((a, b) => a.skillName.compareTo(b.skillName));
  }
  return result;
}

class _RepositoryGroupCard extends StatelessWidget {
  const _RepositoryGroupCard({
    required this.sources,
    this.selected = const {},
    this.failures = const {},
    this.enabled = false,
    this.onToggle,
    this.onToggleAll,
  });

  final List<GitSourceRecord> sources;
  final Set<String> selected;
  final Map<String, String> failures;
  final bool enabled;
  final void Function(String name)? onToggle;
  final VoidCallback? onToggleAll;

  @override
  Widget build(BuildContext context) {
    final source = sources.first;
    final selectable = onToggle != null;
    final allSelected = sources.every((item) => selected.contains(item.skillName));
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      decoration: BoxDecoration(
        color: context.cardFill,
        border: Border.all(color: context.separator),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Row(
              children: [
                MacosIcon(CupertinoIcons.cloud, size: 14, color: context.secondaryLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: MacosTooltip(
                    message: source.sourceUrl,
                    child: Text(
                      source.sourceUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.mono.copyWith(color: context.secondaryLabel),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pill(source.ref),
                const SizedBox(width: 8),
                Text('${sources.length} skill${sources.length == 1 ? '' : 's'}', style: context.caption),
                if (selectable && sources.length > 1) ...[
                  const SizedBox(width: 10),
                  PushButton(
                    controlSize: ControlSize.small,
                    secondary: true,
                    onPressed: enabled ? onToggleAll : null,
                    child: Text(allSelected ? 'Deselect repo' : 'Select repo'),
                  ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: context.separator),
          for (final item in sources)
            _UpdateRow(
              source: item,
              selected: selected.contains(item.skillName),
              failure: failures[item.skillName],
              enabled: enabled,
              showStatus: !selectable,
              onPressed: selectable ? () => onToggle!(item.skillName) : null,
            ),
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.source,
    this.selected = false,
    this.failure,
    this.enabled = false,
    this.showStatus = true,
    this.onPressed,
  });

  final GitSourceRecord source;
  final bool selected;
  final String? failure;
  final bool enabled;
  final bool showStatus;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final selectable = onPressed != null;
    final location = source.repositoryPath.isEmpty || source.repositoryPath == '.'
        ? 'repository root'
        : source.repositoryPath;
    final detail =
        failure ?? '${source.sourceUrl}\nref: ${source.ref}\npath: $location\ncurrent: ${_short(source.revision)}';
    final color = switch (source.state) {
      GitTrackingState.updateAvailable => context.accent,
      GitTrackingState.error => context.resolve(CupertinoColors.systemRed),
      _ => context.secondaryLabel,
    };
    return HoverRow(
      semanticLabel: source.skillName,
      onPressed: selectable && enabled ? onPressed : null,
      builder: (context, _) => Opacity(
        opacity: selectable || source.state == GitTrackingState.error ? 1 : 0.7,
        child: Row(
          children: [
            if (selectable) ...[
              MacosCheckbox(value: selected, onChanged: enabled ? (_) => onPressed?.call() : null),
              const SizedBox(width: 12),
            ] else ...[
              SizedBox(width: 16, child: MacosIcon(CupertinoIcons.cloud, size: 14, color: color)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: MacosTooltip(
                message: detail,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.skillName, style: context.body.copyWith(fontWeight: FontWeight.w500)),
                    if (source.repositoryPath.isNotEmpty &&
                        source.repositoryPath != '.' &&
                        source.repositoryPath != source.skillName) ...[
                      const SizedBox(height: 2),
                      Text(
                        source.repositoryPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mono.copyWith(color: context.secondaryLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (failure != null)
              MacosTooltip(
                message: failure!,
                child: Pill('Update failed', color: context.resolve(CupertinoColors.systemRed)),
              )
            else if (showStatus)
              Pill(source.statusLabel, color: color),
          ],
        ),
      ),
    );
  }

  static String _short(String revision) => revision.length <= 8 ? revision : revision.substring(0, 8);
}

class _FailureNote extends StatelessWidget {
  const _FailureNote(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final tint = context.resolve(MacosColors.systemRedColor);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count skill${count == 1 ? '' : 's'} could not be updated. Point to “Update failed” for details.',
        style: context.caption,
      ),
    );
  }
}
