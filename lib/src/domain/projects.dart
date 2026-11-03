// Projects: folders on this Mac the user works in, found in the places
// coding agents remember them (bb, Claude Code, Codex) or added by hand.
// Read-only facts for display; which sets a project receives is the
// Deployment's business.

class ProjectInfo {
  const ProjectInfo({
    required this.path,
    required this.name,
    required this.display,
    required this.sources,
    this.icon,
    this.iconChosen = false,
    this.activity,
  });

  // Absolute path of the project folder.
  final String path;
  final String name;
  // Display form (~/...).
  final String display;
  // Where it was found: 'bb', 'Claude Code', 'Codex'.
  final List<String> sources;
  // Absolute path of a displayable logo (PNG, SVG, ...), the one the user
  // chose or else the best found in the project; null shows a tile.
  final String? icon;
  // The user picked the icon; false when it was found.
  final bool iconChosen;
  // Last Git activity, for ordering; null when unknown.
  final DateTime? activity;
}

// A picture that could be a project's icon, offered for choosing.
class ProjectIcon {
  const ProjectIcon({required this.file, required this.label, required this.preview});

  // What is stored when chosen: absolute path of the file.
  final String file;
  // Relative to the project when inside it, else ~/...
  final String label;
  // A displayable copy (ICO converted to PNG); null when it cannot be shown.
  final String? preview;
}
