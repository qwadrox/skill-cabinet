import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType, SelectionArea, Theme, ThemeData;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:macos_ui/macos_ui.dart';

import 'scope.dart';
import 'style.dart';
import 'widgets.dart';

// The previewed skill's SKILL.md, beside the list: its frontmatter as a
// header, the body rendered as markdown.
class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key});

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  // Owned here, not handed down by the pane: the pane's own scrollbar is
  // turned off so the list gets the single, list-aligned one that
  // MacosScrollBehavior adds.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = CabinetScope.of(context);
    final name = controller.previewName;
    final preview = controller.preview;
    if (name == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.separator)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview?.heading ?? name,
                      style: context.macos.typography.title3.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (preview?.named ?? false) ...[const SizedBox(height: 2), Text(name, style: context.mono)],
                  ],
                ),
              ),
              IconAction(
                icon: CupertinoIcons.pencil,
                tooltip: 'Open SKILL.md in the default editor',
                onPressed: () => controller.openSkillFile(name),
              ),
              IconAction(
                icon: CupertinoIcons.folder,
                tooltip: 'Show in Finder',
                onPressed: () => controller.revealSkill(name),
              ),
              IconAction(icon: CupertinoIcons.xmark, tooltip: 'Close preview', onPressed: controller.closePreview),
            ],
          ),
        ),
        Expanded(
          child: preview == null
              ? const Center(child: ProgressCircle())
              : _Selectable(
                  ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    children: [
                      if (preview.problem.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: context.resolve(MacosColors.systemOrangeColor).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MacosIcon(
                                CupertinoIcons.exclamationmark_triangle,
                                size: 14,
                                color: context.resolve(MacosColors.systemOrangeColor),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(preview.problem, style: context.callout)),
                            ],
                          ),
                        ),
                      if (preview.description.isNotEmpty) ...[
                        Text('DESCRIPTION', style: context.sectionLabel),
                        const SizedBox(height: 6),
                        Text(preview.description, style: context.body.copyWith(color: context.label, height: 1.45)),
                        const SizedBox(height: 18),
                        Container(height: 1, color: context.separator),
                        const SizedBox(height: 14),
                      ],
                      if (preview.body.trim().isNotEmpty) _Markdown(preview.body),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Markdown extends StatelessWidget {
  const _Markdown(this.data);

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.body.copyWith(color: context.label, height: 1.5, fontSize: 13);
    final codeFill = context.isDark ? const Color(0x14FFFFFF) : const Color(0x0B000000);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      listBullet: base,
      tableBody: base,
      tableHead: base.copyWith(fontWeight: FontWeight.w600),
      h1: base.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
      h2: base.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3),
      h3: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
      h4: base.copyWith(fontWeight: FontWeight.w600),
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 12),
      h3Padding: const EdgeInsets.only(top: 8),
      a: base.copyWith(color: context.accent),
      code: base.copyWith(fontFamily: 'Menlo', fontSize: 12),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: codeFill,
        border: Border.all(color: context.separator),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: base.copyWith(color: context.secondaryLabel),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.separator, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.separator)),
      ),
      tableBorder: TableBorder.all(color: context.separator),
      blockSpacing: 10,
    );
    return MarkdownBody(
      data: data,
      styleSheet: sheet,
      onTapLink: (text, href, title) {
        if (href != null && Uri.tryParse(href)?.hasScheme == true) CabinetScope.read(context).openUrl(href);
      },
    );
  }
}

// Text selection (and ⌘C) across the whole preview. The markdown widgets
// come from Material, so they get a Material theme matching the window.
class _Selectable extends StatelessWidget {
  const _Selectable(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(brightness: context.macos.brightness, useMaterial3: true),
    child: Material(
      type: MaterialType.transparency,
      child: SelectionArea(child: child),
    ),
  );
}
