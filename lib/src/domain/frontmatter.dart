// SKILL.md frontmatter: a `---` fenced block of `key: value` lines at the
// top of the file. Only the few top-level fields the app shows are read;
// this is not a YAML parser.

class Frontmatter {
  const Frontmatter({required this.lines, required this.body, required this.problem});

  // Lines between the fences; null when the file has none.
  final List<String>? lines;
  final String body;
  final String problem;

  bool get present => lines != null;

  String field(String key) => lines == null ? '' : frontmatterField(lines!, key);
}

Frontmatter splitFrontmatter(String content) {
  final lines = content.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return Frontmatter(
      lines: null,
      body: lines.join('\n'),
      problem: 'No frontmatter: SKILL.md does not start with ---',
    );
  }
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      return Frontmatter(lines: lines.sublist(1, i), body: lines.sublist(i + 1).join('\n'), problem: '');
    }
  }
  return Frontmatter(lines: null, body: lines.join('\n'), problem: 'Malformed frontmatter: the closing --- is missing');
}

// Reads a top-level `key:` value (single-line or a folded/literal block).
String frontmatterField(List<String> lines, String key) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('$key:')) continue;
    var value = line.substring(key.length + 1).trim();
    if (value == '>' || value == '|' || value == '>-' || value == '|-') {
      final parts = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        if (next.isNotEmpty && next[0] != ' ' && next[0] != '\t') break;
        parts.add(next.trim());
      }
      value = parts.join(' ').trim();
    }
    if (value.length >= 2 && (value[0] == '"' || value[0] == "'") && value[value.length - 1] == value[0]) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
  return '';
}

// Markdown for the preview: tabs as spaces, no control characters, no
// leading/trailing blank lines.
String previewBody(String body) {
  return body
      .replaceAll('\t', '    ')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000b-\u001f\u007f]'), '')
      .replaceFirst(RegExp(r'^\s*\n'), '')
      .replaceFirst(RegExp(r'\s+$'), '');
}
