// Health: what reconciliation found and will not repair.
//
// Each context reports only what it owns — the Library its store, the
// Deployment the agent folders it links into — and the view layer joins
// the two lists. Two rules decide what belongs here:
//
//   * The cabinet repairs only its own artifacts. Anything else (a real
//     folder, someone else's symlink, a half-written skill) is reported
//     and left exactly as it is.
//   * A problem is worth reporting once it affects what the cabinet was
//     asked to do. A broken link in an agent's folder under a name we
//     were never asked to link belongs to whoever made it; another tool
//     whose store sits on an unmounted volume must not fill this list.

enum IssueKind {
  // A store entry that is not a deployable skill: no SKILL.md, or not a
  // folder at all.
  storeNotASkill,
  // A store entry that is a symlink leaving the store. It still works,
  // but the cabinet does not own what it points at.
  storeLinksOut,
  // A store entry that is a symlink to nothing.
  storeBrokenLink,
  // Something that is not ours holds a name we were asked to link.
  slotOccupied,
  // An assignment the store cannot satisfy.
  assignmentUnmet,
}

class HealthIssue {
  const HealthIssue({required this.kind, required this.subject, required this.path, this.agent = '', this.detail = ''});

  final IssueKind kind;
  // The skill or store entry the issue is about.
  final String subject;
  // Label of the agent whose folder it concerns; empty for store issues.
  final String agent;
  // Absolute path of the offending entry, for Finder.
  final String path;
  // What occupies a slot, or where a link points. Display form (~/...).
  final String detail;

  // One line naming the problem, addressed to the user.
  String get message => switch (kind) {
    IssueKind.storeNotASkill => 'Not a skill folder${detail.isEmpty ? '' : ' ($detail)'} — nothing to deploy.',
    IssueKind.storeLinksOut => 'Links out of the store, to $detail. The cabinet does not own what it points at.',
    IssueKind.storeBrokenLink => 'A broken link${detail.isEmpty ? '' : ' to $detail'}. Nothing to deploy.',
    IssueKind.slotOccupied => 'Not linked into $agent: $detail already uses this name.',
    IssueKind.assignmentUnmet => 'Assigned to $agent, but the store has no skill by this name.',
  };

  // Sorting key: store issues first, then by name, then by agent, so the
  // same state always reads the same way.
  int compareTo(HealthIssue other) {
    final byKind = kind.index.compareTo(other.kind.index);
    if (byKind != 0) return byKind;
    final bySubject = subject.toLowerCase().compareTo(other.subject.toLowerCase());
    return bySubject != 0 ? bySubject : agent.compareTo(other.agent);
  }
}
