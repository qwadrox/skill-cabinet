import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations, ThemeMode;
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../app/cabinet_controller.dart';
import '../app/rows.dart';
import 'agents_sheet.dart';
import 'dialogs.dart';
import 'import_sheet.dart';
import 'git_import_sheet.dart';
import 'preview_pane.dart';
import 'scope.dart';
import 'sidebar.dart';
import 'skill_pane.dart';
import 'style.dart';

class CabinetApp extends StatelessWidget {
  const CabinetApp({super.key, required this.controller, this.themeMode = ThemeMode.system});

  final CabinetController controller;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => CabinetScope(
    controller: controller,
    child: MacosApp(
      title: 'Skill Cabinet',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      // Text selection menus in the preview come from Material.
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const CabinetShell(),
    ),
  );
}

class CabinetShell extends StatefulWidget {
  const CabinetShell({super.key});

  @override
  State<CabinetShell> createState() => _CabinetShellState();
}

class _CabinetShellState extends State<CabinetShell> {
  final _searchFocus = FocusNode();
  bool _dragging = false;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  CabinetController get _controller => CabinetScope.read(context);

  Future<void> _pickImport() async {
    final paths = await getDirectoryPaths(confirmButtonText: 'Import');
    final picked = paths.whereType<String>().toList();
    if (picked.isNotEmpty) await _import(picked);
  }

  // A folder can be a skill, or hold any number of them (a project's
  // `.agents`, a repository of skills). The search decides which, and the
  // sheet asks whether to copy or move what it found.
  Future<void> _import(List<String> paths) async {
    final controller = _controller;
    final scan = await controller.scanForImport(paths);
    if (!mounted || scan.isEmpty) return;
    final choice = await showImportSheet(context, scan);
    if (choice == null) return;
    await controller.importSkills(choice.paths, move: choice.move);
  }

  // The URL sheet clones before it closes, so it hands back a preview
  // rather than a URL.
  Future<void> _importGit() async {
    final preview = await showGitUrlSheet(context);
    if (preview == null) return;
    if (!mounted) {
      await _controller.discardGitPreview(preview);
      return;
    }
    final choice = await showGitImportSheet(context, preview);
    if (!mounted || choice == null || choice.repositoryPaths.isEmpty) {
      await _controller.discardGitPreview(preview);
      return;
    }
    await _controller.importGit(preview, choice.repositoryPaths);
  }

  void _find() {
    final field = _controller.searchField;
    _searchFocus.requestFocus();
    field.selection = TextSelection(baseOffset: 0, extentOffset: field.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: 'Skill Cabinet',
          menus: [
            PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about)]),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
              ],
            ),
            PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit)]),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Import Skill Folder…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
                  onSelected: _pickImport,
                ),
                PlatformMenuItem(label: 'Import from Git…', onSelected: _importGit),
                PlatformMenuItem(label: 'Open Store in Finder', onSelected: controller.openStore),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Find',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
                  onSelected: _find,
                ),
                PlatformMenuItem(
                  label: 'Refresh',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
                  onSelected: controller.refresh,
                ),
                PlatformMenuItem(
                  label: 'Check Git Updates',
                  onSelected: controller.checkGitUpdates,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen)],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Agents',
          menus: [PlatformMenuItem(label: 'Manage Agents…', onSelected: () => showAgentsSheet(context))],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
      ],
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _import([for (final file in details.files) file.path]);
        },
        child: Stack(
          children: [
            MacosWindow(
              sidebar: buildSidebar(),
              child: MacosScaffold(
                toolBar: _toolBar(context, controller),
                children: [
                  ContentArea(
                    minWidth: 420,
                    builder: (context, scroll) =>
                        SkillPane(scroll: scroll, onImport: _pickImport, onImportGit: _importGit),
                  ),
                  if (controller.previewName != null)
                    // noScrollBar: the pane's own scrollbar would span the
                    // whole pane, header included, and double up with the one
                    // MacosScrollBehavior already puts on the list.
                    const ResizablePane.noScrollBar(
                      minSize: 300,
                      startSize: 420,
                      maxSize: 760,
                      resizableSide: ResizableSide.left,
                      child: PreviewPane(),
                    ),
                ],
              ),
            ),
            if (_dragging) const Positioned.fill(child: IgnorePointer(child: _DropOverlay())),
          ],
        ),
      ),
    );
  }

  ToolBar _toolBar(BuildContext context, CabinetController controller) {
    final set = controller.selectedSet;
    final agent = controller.selectedAgent;
    final rows = controller.skillRows;
    final enabled = rows.where((r) => r.active).length;
    final subtitle = agent == null
        ? '${rows.length} skill${rows.length == 1 ? '' : 's'}'
        : 'for ${agent.label} · $enabled of ${rows.length} enabled';

    return ToolBar(
      titleWidth: 320,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (set != null) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: context.setColor(set.color), shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  set?.name ?? 'All skills',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.macos.typography.headline.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.caption.copyWith(fontSize: 11)),
        ],
      ),
      actions: [
        ToolBarIconButton(
          label: 'Import',
          icon: const MacosIcon(CupertinoIcons.square_arrow_down),
          showLabel: false,
          tooltipMessage: 'Import a skill folder (⌘O)',
          onPressed: _pickImport,
        ),
        ToolBarIconButton(
          label: 'Git',
          icon: const MacosIcon(CupertinoIcons.cloud_download),
          showLabel: false,
          tooltipMessage: 'Import skills from a Git repository',
          onPressed: _importGit,
        ),
        ToolBarIconButton(
          label: 'Refresh',
          icon: const MacosIcon(CupertinoIcons.arrow_clockwise),
          showLabel: false,
          tooltipMessage: 'Rescan skills and agent folders (⌘R)',
          onPressed: controller.refresh,
        ),
        ToolBarIconButton(
          label: 'Check Git Updates',
          icon: const MacosIcon(CupertinoIcons.cloud),
          showLabel: false,
          tooltipMessage: 'Check tracked skills for Git updates',
          onPressed: controller.checkGitUpdates,
        ),
        if (set != null)
          ToolBarIconButton(
            label: 'Delete Set',
            icon: const MacosIcon(CupertinoIcons.trash),
            showLabel: false,
            tooltipMessage: 'Delete this skill set',
            onPressed: () => confirmDeleteSet(context, set.name),
          ),
        const ToolBarSpacer(spacerUnits: 0.5),
        CustomToolbarItem(
          inToolbarBuilder: (context) => SizedBox(
            width: 220,
            child: MacosSearchField<void>(
              controller: controller.searchField,
              focusNode: _searchFocus,
              placeholderStyle: context.placeholder,
              placeholder: set == null ? 'Search skills' : 'Search ${set.name}',
            ),
          ),
        ),
      ],
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Container(
      color: accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(14),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: context.resolve(MacosColors.windowBackgroundColor),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosIcon(CupertinoIcons.square_arrow_down, size: 30, color: accent),
              const SizedBox(height: 8),
              Text('Drop to import', style: context.macos.typography.headline),
              const SizedBox(height: 2),
              Text('Skill folders are copied into the cabinet', style: context.caption),
            ],
          ),
        ),
      ),
    );
  }
}
