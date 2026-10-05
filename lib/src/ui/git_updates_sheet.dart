import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../domain/git_import.dart';
import 'modal.dart';
import 'git_changes_sheet.dart';
import 'git_import_sheet.dart';
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
  final Map<String, String> _reviewedRevisions = {};
  bool _initialized = false;
  bool _checking = false;
  bool _applying = false;
  bool _importing = false;
  bool _choosingDiscovery = false;
  String? _discoveryError;

  bool get _busy => _applying || _importing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final controller = CabinetScope.read(context);
    if (controller.checkingGitUpdates) return;
    _initialized = true;
    final sources = controller.gitSources;
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
    if (_checking || _busy) return;
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
    if (_selected.isEmpty || _busy || _checking) return;
    setState(() {
      _applying = true;
      _failures = const {};
    });
    final result = await CabinetScope.read(context).applyGitUpdates(_selected, reviewedRevisions: _reviewedRevisions);
    if (!mounted) return;
    if (result.failures.isEmpty && CabinetScope.read(context).newGitSkills == 0) {
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

  Future<void> _importNew(GitRepositoryDiscovery repository, GitDiscoveredSkill skill) async {
    if (_busy || _checking) return;
    final controller = CabinetScope.read(context);
    setState(() {
      _importing = true;
      _discoveryError = null;
    });
    try {
      final outcome = await controller.previewGitRepository(repository);
      final preview = outcome.preview;
      if (!mounted) {
        if (preview != null) await controller.discardGitPreview(preview);
        return;
      }
      if (preview == null) {
        setState(() => _discoveryError = outcome.error);
        return;
      }
      try {
        if (!preview.candidates.any((candidate) => candidate.repositoryPath == skill.repositoryPath)) {
          setState(() => _discoveryError = '${skill.name} is no longer in this repository. Check for updates again.');
          return;
        }
        setState(() => _choosingDiscovery = true);
        final choice = await showGitImportSheet(context, preview, onlyPaths: {skill.repositoryPath});
        if (mounted) setState(() => _choosingDiscovery = false);
        if (!mounted || choice == null || choice.repositoryPaths.isEmpty) return;
        await controller.importGit(preview, choice.repositoryPaths);
        if (mounted) {
          setState(() {
            _selected.retainWhere((name) => controller.gitSources[name]?.state == GitTrackingState.updateAvailable);
            if (controller.gitRepositories.any(
              (current) =>
                  current.key == repository.key &&
                  current.pending.any((pending) => pending.repositoryPath == skill.repositoryPath),
            )) {
              _discoveryError = controller.notice.text;
            }
          });
        }
      } finally {
        await controller.discardGitPreview(preview);
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _choosingDiscovery = false;
        });
      }
    }
  }

  Future<void> _dismissNew(GitRepositoryDiscovery repository, GitDiscoveredSkill skill) async {
    if (_busy || _checking) return;
    setState(() => _importing = true);
    await CabinetScope.read(context).dismissGitDiscovery(repository, skill);
    if (mounted) setState(() => _importing = false);
  }

  void _review(GitSourceRecord source) {
    showGitChangesSheet(
      context,
      source: source,
      onReviewed: (revision) => _reviewedRevisions[source.skillName] = revision,
    );
  }

  void _toggle(String name) {
    if (_checking || _busy) return;
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
    final others = sources.where((source) => source.state == GitTrackingState.error).toList();
    final checking = _checking || controller.checkingGitUpdates;
    final availableGroups = _groupByRepository(available);
    final otherGroups = _groupByRepository(others);
    final discoveries = controller.gitRepositories.where((repository) => repository.pending.isNotEmpty).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    GitRepositoryDiscovery? discoveryFor(GitSourceRecord source) => discoveries
        .where((repository) => repository.sourceUrl == source.sourceUrl && repository.ref == source.ref)
        .firstOrNull;
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
                child: Text(
                  'Skill updates',
                  style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              // The body shows the check's progress; this only starts one.
              IconAction(
                icon: CupertinoIcons.arrow_clockwise,
                tooltip: 'Check for updates',
                onPressed: _busy || checking ? null : _check,
              ),
            ],
          ),
        ),
        Container(height: 1, color: context.separator),
        Flexible(
          child: checking
              ? SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ProgressCircle(),
                        const SizedBox(height: 10),
                        Text('Checking for updates…', style: context.caption),
                      ],
                    ),
                  ),
                )
              : sources.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.cloud,
                  title: 'No Git-tracked skills',
                  message: Text('Skills imported from a Git repository will appear here.'),
                )
              : available.isEmpty && others.isEmpty && discoveries.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.checkmark_circle,
                  title: 'No updates available',
                  message: SizedBox.shrink(),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    if (_importing && !_choosingDiscovery)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(children: [ProgressCircle(radius: 7), SizedBox(width: 8), Text('Loading…')]),
                      ),
                    if (_discoveryError != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_discoveryError!, style: context.caption),
                      ),
                    if (_failures.isNotEmpty) _FailureNote(_failures.length),
                    if (available.isNotEmpty) ...[
                      if (others.isNotEmpty) const SectionLabel('AVAILABLE'),
                      for (final group in availableGroups)
                        _RepositoryGroupCard(
                          sources: group,
                          repository: discoveryFor(group.first),
                          onImportNew: (skill) => _importNew(discoveryFor(group.first)!, skill),
                          onDismissNew: (skill) => _dismissNew(discoveryFor(group.first)!, skill),
                          selected: _selected,
                          failures: _failures,
                          enabled: !_busy && !checking,
                          onToggle: _toggle,
                          onReview: _review,
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
                    for (final repository in discoveries)
                      if (!available.any(
                        (source) => source.sourceUrl == repository.sourceUrl && source.ref == repository.ref,
                      ))
                        _RepositoryGroupCard(
                          sources: const [],
                          repository: repository,
                          enabled: !_busy && !checking,
                          onImportNew: (skill) => _importNew(repository, skill),
                          onDismissNew: (skill) => _dismissNew(repository, skill),
                        ),
                    if (others.isNotEmpty) ...[
                      const SectionLabel('COULD NOT CHECK'),
                      for (final group in otherGroups) _RepositoryGroupCard(sources: group),
                    ],
                  ],
                ),
        ),
        AppDialogActions(
          children: [
            if (available.isNotEmpty && !checking)
              Row(
                children: [
                  MacosCheckbox(
                    semanticLabel: 'Select all updates',
                    value: allSelected
                        ? true
                        : available.any((source) => _selected.contains(source.skillName))
                        ? null
                        : false,
                    onChanged: checking || _busy
                        ? null
                        : (_) => setState(() {
                            final names = available.map((source) => source.skillName);
                            if (allSelected) {
                              _selected.removeAll(names);
                            } else {
                              _selected.addAll(names);
                            }
                          }),
                  ),
                  const SizedBox(width: 8),
                  Text('Select all', style: context.caption),
                ],
              ),
            const Spacer(),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(available.isEmpty || checking ? 'Done' : 'Cancel'),
            ),
            if (available.isNotEmpty && !checking) ...[
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: _selected.isEmpty || checking || _busy ? null : _apply,
                child: _applying
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [ProgressCircle(radius: 7), SizedBox(width: 7), Text('Updating…')],
                      )
                    : Text(_selected.isEmpty ? 'Update' : 'Update ${_selected.length}'),
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

String _repositoryLabel(String url) {
  final path = url.startsWith('git@') ? url.split(':').last : Uri.tryParse(url)?.path ?? url;
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return (parts.length > 1 ? parts.sublist(parts.length - 2).join('/') : path).replaceFirst(RegExp(r'\.git$'), '');
}

class _RepositoryGroupCard extends StatelessWidget {
  const _RepositoryGroupCard({
    required this.sources,
    this.selected = const {},
    this.failures = const {},
    this.enabled = false,
    this.onToggle,
    this.onToggleAll,
    this.onReview,
    this.repository,
    this.onImportNew,
    this.onDismissNew,
  });

  final GitRepositoryDiscovery? repository;
  final void Function(GitDiscoveredSkill skill)? onImportNew;
  final void Function(GitDiscoveredSkill skill)? onDismissNew;
  final List<GitSourceRecord> sources;
  final Set<String> selected;
  final Map<String, String> failures;
  final bool enabled;
  final void Function(String name)? onToggle;
  final VoidCallback? onToggleAll;
  final void Function(GitSourceRecord source)? onReview;

  @override
  Widget build(BuildContext context) {
    final sourceUrl = repository?.sourceUrl ?? sources.first.sourceUrl;
    final ref = repository?.ref ?? sources.first.ref;
    final pending = repository?.pending ?? const <GitDiscoveredSkill>[];
    final selectable = onToggle != null;
    final allSelected = sources.every((item) => selected.contains(item.skillName));
    final someSelected = sources.any((item) => selected.contains(item.skillName));
    // Folder headers only help when the repository's skills live in more
    // than one folder; a single shared folder would just repeat itself.
    final folders = groupByFolder(sources, (item) {
      final folder = p.posix.dirname(item.repositoryPath);
      return item.repositoryPath.isEmpty || folder == '.' ? '/' : '$folder/';
    })..sortShallowestFirst();
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
                if (selectable)
                  MacosCheckbox(
                    semanticLabel: 'Select repository updates',
                    value: allSelected
                        ? true
                        : someSelected
                        ? null
                        : false,
                    onChanged: enabled ? (_) => onToggleAll?.call() : null,
                  )
                else
                  MacosIcon(CupertinoIcons.cloud, size: 14, color: context.secondaryLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: MacosTooltip(
                    message: '$sourceUrl\n$ref',
                    child: Text(
                      _repositoryLabel(sourceUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.mono.copyWith(color: context.secondaryLabel),
                    ),
                  ),
                ),
                if (pending.isNotEmpty)
                  Text(
                    '${sources.length} update${sources.length == 1 ? '' : 's'} · ${pending.length} new',
                    style: context.caption,
                  ),
              ],
            ),
          ),
          Container(height: 1, color: context.separator),
          if (sources.isNotEmpty && pending.isNotEmpty) const SectionLabel('UPDATES'),
          for (final (folder, items) in folders) ...[
            if (folders.length > 1) FolderHeader(folder, count: items.length),
            for (final item in items)
              _UpdateRow(
                source: item,
                selected: selected.contains(item.skillName),
                failure: failures[item.skillName],
                enabled: enabled,
                showStatus: !selectable,
                onToggle: selectable ? () => onToggle!(item.skillName) : null,
                onReview: selectable && enabled ? () => onReview?.call(item) : null,
              ),
          ],
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
              child: Row(
                children: [
                  Text('NEW SKILLS', style: context.sectionLabel),
                  const SizedBox(width: 6),
                  MacosTooltip(
                    message:
                        'New skills from this repository.\n'
                        'Import any you’d like to add to your library and track for updates.',
                    child: MacosIcon(CupertinoIcons.info_circle, size: 13, color: context.tertiaryLabel),
                  ),
                ],
              ),
            ),
            for (final skill in pending)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body.copyWith(fontWeight: FontWeight.w500),
                          ),
                          Text(skill.repositoryPath, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mono),
                          if (skill.description.isNotEmpty)
                            Text(
                              skill.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.caption,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PushButton(
                      controlSize: ControlSize.small,
                      secondary: true,
                      onPressed: enabled ? () => onImportNew?.call(skill) : null,
                      child: const Text('Import…'),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.small,
                      secondary: true,
                      onPressed: enabled ? () => onDismissNew?.call(skill) : null,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
          ],
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
    this.onToggle,
    this.onReview,
  });

  final GitSourceRecord source;
  final bool selected;
  final String? failure;
  final bool enabled;
  final bool showStatus;
  final VoidCallback? onToggle;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final selectable = onToggle != null;
    final location = source.repositoryPath.isEmpty || source.repositoryPath == '.'
        ? 'repository root'
        : source.repositoryPath;
    final checkError = failure == null && source.state == GitTrackingState.error ? source.lastCheckError : null;
    final detail =
        failure ?? '${source.sourceUrl}\nref: ${source.ref}\npath: $location\ncurrent: ${_short(source.revision)}';
    final color = switch (source.state) {
      GitTrackingState.updateAvailable => context.accent,
      GitTrackingState.error => context.resolve(CupertinoColors.systemRed),
      _ => context.secondaryLabel,
    };
    return HoverRow(
      semanticLabel: selectable ? 'Review changes to ${source.skillName}' : source.skillName,
      onPressed: onReview,
      builder: (context, _) => Opacity(
        opacity: selectable || source.state == GitTrackingState.error ? 1 : 0.7,
        child: Row(
          children: [
            if (selectable) ...[
              MacosCheckbox(value: selected, onChanged: enabled ? (_) => onToggle?.call() : null),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      source.skillName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (checkError != null)
                      Text(checkError, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.caption),
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
              Pill(source.statusLabel, color: color)
            else
              MacosIcon(CupertinoIcons.chevron_right, size: 12, color: context.tertiaryLabel),
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
