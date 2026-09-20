import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../domain/deployment.dart';

import 'modal.dart';
import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

Future<void> showAgentsSheet(BuildContext context) => showAppModal<void>(
  context: context,
  builder: (_) => const AppDialogCard(width: 760, maxHeight: 620, child: _AgentsSheet()),
);

// Added agents on top (on/off switch, edit its folder, remove), then the
// catalog to add from, installed agents first, and a form for an agent
// the catalog does not know. One search filters both lists.
class _AgentsSheet extends StatefulWidget {
  const _AgentsSheet();

  @override
  State<_AgentsSheet> createState() => _AgentsSheetState();
}

class _AgentsSheetState extends State<_AgentsSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String label, String path) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || label.toLowerCase().contains(q) || path.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final agents = controller.deployment.agents.where((a) => _matches(a.label, a.path)).toList();
    final catalog = controller.deployment.catalog.where((a) => _matches(a.label, a.path)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agents', style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Skills are linked into each agent’s skills folder. Turn an agent off to unlink everything '
                'without losing its assignments.',
                style: context.caption.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 14),
              MacosSearchField<void>(
                controller: _search,
                autofocus: true,
                placeholderStyle: context.placeholder,
                placeholder: 'Search agents',
                onChanged: (value) => setState(() => _query = value),
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
              SectionLabel('YOUR AGENTS · ${controller.deployment.agents.length}'),
              if (controller.deployment.agents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('No agents yet. Add one below.', style: context.caption),
                )
              else if (agents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('No match.', style: context.caption),
                ),
              for (final agent in agents) _AddedAgentRow(agent, key: ValueKey(agent.key)),
              SectionLabel('ADD AN AGENT'),
              if (catalog.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(_query.isEmpty ? 'Every agent is added.' : 'No match.', style: context.caption),
                ),
              for (final entry in catalog)
                HoverRow(
                  semanticLabel: entry.label,
                  onPressed: () => controller.addAgent(entry.key),
                  builder: (context, hovered) => Row(
                    children: [
                      AgentAvatar(icon: entry.icon, label: entry.label, size: 30),
                      const SizedBox(width: 12),
                      Expanded(child: _AgentText(entry.label, entry.path)),
                      if (entry.installed) ...[
                        Pill('Installed', color: context.resolve(MacosColors.systemGreenColor)),
                        const SizedBox(width: 10),
                      ],
                      PushButton(
                        controlSize: ControlSize.regular,
                        secondary: !hovered,
                        semanticLabel: 'Add ${entry.label}',
                        onPressed: () => controller.addAgent(entry.key),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              const _CustomAgentForm(),
            ],
          ),
        ),
        AppDialogActions(
          children: [
            if (controller.notice.isNotEmpty)
              Expanded(
                child: Text(
                  controller.notice,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.caption.copyWith(color: context.resolve(MacosColors.systemOrangeColor)),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 12),
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

class _AgentText extends StatelessWidget {
  const _AgentText(this.label, this.path);

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.body.copyWith(fontWeight: FontWeight.w500)),
      const SizedBox(height: 1),
      Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mono),
    ],
  );
}

// An added agent. Pressing the folder opens it for editing: a catalog
// agent left empty goes back to its default folder.
class _AddedAgentRow extends StatefulWidget {
  const _AddedAgentRow(this.agent, {super.key});

  final Agent agent;

  @override
  State<_AddedAgentRow> createState() => _AddedAgentRowState();
}

class _AddedAgentRowState extends State<_AddedAgentRow> {
  TextEditingController? _dir;

  @override
  void dispose() {
    _dir?.dispose();
    super.dispose();
  }

  void _edit() => setState(() => _dir = TextEditingController(text: widget.agent.dir));

  void _cancel() {
    _dir?.dispose();
    setState(() => _dir = null);
  }

  Future<void> _save() async {
    final value = _dir?.text ?? '';
    final controller = CabinetScope.read(context);
    _cancel();
    await controller.setAgentPath(widget.agent.key, value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final agent = widget.agent;
    final editing = _dir;
    return HoverRow(
      semanticLabel: agent.label,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Opacity(
                opacity: agent.enabled ? 1 : 0.45,
                child: AgentAvatar(icon: agent.icon, label: agent.label, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(child: _AgentText(agent.label, agent.path)),
              if (agent.custom) ...[const Pill('Custom'), const SizedBox(width: 10)],
              if (agent.enabled) ...[Text('${agent.linked} linked', style: context.caption), const SizedBox(width: 12)],
              MacosTooltip(
                message: agent.enabled ? 'Turn off: unlink all skills' : 'Turn on: link its skills again',
                child: MacosSwitch(
                  size: ControlSize.small,
                  value: agent.enabled,
                  onChanged: (on) => controller.setAgentEnabled(agent.key, on),
                ),
              ),
              const SizedBox(width: 10),
              MacosTooltip(
                message: 'Change the folder its skills are linked into',
                child: PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  semanticLabel: 'Change the folder of ${agent.label}',
                  onPressed: editing == null ? _edit : _cancel,
                  child: Text(editing == null ? 'Folder' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                semanticLabel: 'Remove ${agent.label}',
                onPressed: () => controller.removeAgent(agent.key),
                child: const Text('Remove'),
              ),
            ],
          ),
          if (editing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 8, 0, 2),
              child: Row(
                children: [
                  Expanded(
                    child: MacosTextField(
                      controller: editing,
                      autofocus: true,
                      placeholderStyle: context.placeholder,
                      placeholder: agent.custom ? '~/my-agent/skills' : 'Its default folder',
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PushButton(controlSize: ControlSize.regular, onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// An agent the catalog does not know: a name and the folder its skills
// are linked into.
class _CustomAgentForm extends StatefulWidget {
  const _CustomAgentForm();

  @override
  State<_CustomAgentForm> createState() => _CustomAgentFormState();
}

class _CustomAgentFormState extends State<_CustomAgentForm> {
  final _label = TextEditingController();
  final _dir = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _dir.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_label.text.trim().isEmpty || _dir.text.trim().isEmpty) return;
    final controller = CabinetScope.read(context);
    final label = _label.text;
    final dir = _dir.text;
    _label.clear();
    _dir.clear();
    setState(() {});
    await controller.addCustomAgent(label, dir);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _label.text.trim().isNotEmpty && _dir.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ANOTHER AGENT'),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Text(
            'Any tool that reads skills from a folder. Write the folder as ~/…, an absolute path, '
            'or relative to your home folder.',
            style: context.caption,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: MacosTextField(
                  controller: _label,
                  placeholderStyle: context.placeholder,
                  placeholder: 'Name',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MacosTextField(
                  controller: _dir,
                  placeholderStyle: context.placeholder,
                  placeholder: '~/my-agent/skills',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: !ready,
                semanticLabel: 'Add a custom agent',
                onPressed: ready ? _add : null,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
