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
    this.activity,
  });

  // Absolute path of the project folder.
  final String path;
  final String name;
  // Display form (~/...).
  final String display;
  // Where it was found: 'bb', 'Claude Code', 'Codex'.
  final List<String> sources;
  // Absolute path of a PNG logo found in the project; null shows a tile.
  final String? icon;
  // Last Git activity, for ordering; null when unknown.
  final DateTime? activity;
}
