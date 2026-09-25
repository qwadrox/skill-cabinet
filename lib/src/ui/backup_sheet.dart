import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/backup.dart';
import 'dialogs.dart';
import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

Future<void> showBackupSheet(BuildContext context) => showAppModal<void>(
  context: context,
  builder: (_) => const AppDialogCard(width: 620, maxHeight: 640, child: _BackupSheet()),
);

class _BackupSheet extends StatelessWidget {
  const _BackupSheet();

  Future<void> _restore(BuildContext context, BackupEntry entry) async {
    final controller = CabinetScope.read(context);
    if (!await confirmRestoreBackup(context, backupDateLabel(entry.date))) return;
    await controller.restoreBackup(entry);
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final backup = controller.backup;
    final last = backup.lastBackup;

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
                    Text('Backup', style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      last == null
                          ? 'Every change is saved automatically to a Git history in the cabinet folder.'
                          : 'Last backup ${backupDateLabel(last)}. Every change is saved automatically.',
                      style: context.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: controller.backingUp ? null : controller.backUpNow,
                child: controller.backingUp
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [ProgressCircle(radius: 7), SizedBox(width: 7), Text('Backing up…')],
                      )
                    : const Text('Back up now'),
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
              const SectionLabel('REMOTE'),
              _Card(child: backup.hasRemote ? const _RemoteRow() : const _ConnectForm()),
              SectionLabel('HISTORY · ${backup.history.length}'),
              if (backup.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Text('No backups yet. The first one is made after the next change.', style: context.caption),
                )
              else
                _Card(
                  child: Column(
                    children: [
                      for (final (i, entry) in backup.history.indexed) ...[
                        if (i > 0) Container(height: 1, color: context.separator),
                        _HistoryRow(entry: entry, current: i == 0, onRestore: () => _restore(context, entry)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        AppDialogActions(
          children: [
            Expanded(
              child: Text(
                'Kept in ${controller.library.root.replaceFirst(RegExp(r'/skills$'), '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.caption,
              ),
            ),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
    decoration: BoxDecoration(
      color: context.cardFill,
      border: Border.all(color: context.separator),
      borderRadius: BorderRadius.circular(9),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

// No remote yet: a URL field. An empty repository gets this Mac's
// history; one that already holds a backup can be restored from.
class _ConnectForm extends StatefulWidget {
  const _ConnectForm();

  @override
  State<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends State<_ConnectForm> {
  final _url = TextEditingController();
  bool _connecting = false;
  String _error = '';

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
    if (url.isEmpty || _connecting) return;
    final controller = CabinetScope.read(context);
    setState(() {
      _connecting = true;
      _error = '';
    });
    final result = await controller.connectBackup(url);
    if (!mounted) return;
    if (result.outcome == BackupConnectOutcome.holdsBackup && await confirmAdoptRemoteBackup(context)) {
      await controller.restoreFromRemote(url);
    }
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: MacosTextField(
                controller: _url,
                // Not `enabled: false`: macos_ui paints a disabled field
                // white in dark mode (see the Git URL sheet).
                readOnly: _connecting,
                placeholder: 'git@github.com:you/skill-cabinet-backup.git',
                placeholderStyle: context.placeholder,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _connect(),
              ),
            ),
            const SizedBox(width: 10),
            PushButton(
              controlSize: ControlSize.regular,
              onPressed: _url.text.trim().isEmpty || _connecting ? null : _connect,
              child: _connecting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [ProgressCircle(radius: 7), SizedBox(width: 7), Text('Connecting…')],
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _error.isNotEmpty
              ? _error
              : 'Optional: an empty private repository to push every backup to. Git signs in with your '
                    'SSH key or saved credentials. On a new Mac, connect the same repository to restore it.',
          style: _error.isEmpty
              ? context.caption
              : context.caption.copyWith(color: context.resolve(CupertinoColors.systemRed)),
        ),
      ],
    ),
  );
}

class _RemoteRow extends StatelessWidget {
  const _RemoteRow();

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final backup = controller.backup;
    final red = context.resolve(CupertinoColors.systemRed);
    final error = controller.backupError;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MacosIcon(CupertinoIcons.cloud, size: 14, color: context.secondaryLabel),
              const SizedBox(width: 8),
              Expanded(
                child: MacosTooltip(
                  message: backup.remote,
                  child: Text(
                    backup.remote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mono.copyWith(color: context.label),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (error.isNotEmpty)
                Pill('Not pushed', color: red)
              else if (backup.unpushed > 0)
                Pill('${backup.unpushed} waiting', color: context.accent)
              else
                const Pill('Up to date'),
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: controller.disconnectBackup,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(error, style: context.caption.copyWith(color: red)),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.current, required this.onRestore});

  final BackupEntry entry;
  final bool current;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => HoverRow(
    radius: 0,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    semanticLabel: backupDateLabel(entry.date),
    builder: (context, hovered) => Row(
      children: [
        Text(backupDateLabel(entry.date), style: context.body.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(width: 14),
        Expanded(
          child: MacosTooltip(
            message: '${entry.summary}\n${entry.shortId}',
            child: Text(entry.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.caption),
          ),
        ),
        const SizedBox(width: 10),
        if (current)
          const Pill('Current')
        else
          Opacity(
            opacity: hovered ? 1 : 0,
            child: PushButton(
              controlSize: ControlSize.small,
              secondary: true,
              onPressed: hovered ? onRestore : null,
              child: const Text('Restore…'),
            ),
          ),
      ],
    ),
  );
}
