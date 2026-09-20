import 'library.dart';

class GitImportPreview {
  const GitImportPreview({
    required this.sourceUrl,
    required this.repository,
    required this.ref,
    required this.revision,
    required this.checkoutPath,
    required this.candidates,
  });

  final String sourceUrl;
  final String repository;
  final String ref;
  final String revision;
  final String checkoutPath;
  final List<GitSkillCandidate> candidates;

  bool get isEmpty => candidates.isEmpty;
}

class GitSkillCandidate {
  const GitSkillCandidate({
    required this.name,
    required this.repositoryPath,
    required this.localPath,
    required this.description,
    this.duplicate = false,
    this.blockedReason,
  });

  final String name;
  final String repositoryPath;
  final String localPath;
  final String description;
  final bool duplicate;
  final String? blockedReason;

  bool get selectable => !duplicate && blockedReason == null;
}

class GitSourceRecord {
  const GitSourceRecord({
    required this.skillName,
    required this.sourceUrl,
    required this.ref,
    required this.repositoryPath,
    required this.revision,
  });

  final String skillName;
  final String sourceUrl;
  final String ref;
  final String repositoryPath;
  final String revision;

  Map<String, Object> toJson() => {
    'skillName': skillName,
    'sourceUrl': sourceUrl,
    'ref': ref,
    'repositoryPath': repositoryPath,
    'revision': revision,
  };

  static GitSourceRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    String? text(String key) => value[key] is String ? value[key] as String : null;
    final skillName = text('skillName');
    final sourceUrl = text('sourceUrl');
    final ref = text('ref');
    final repositoryPath = text('repositoryPath');
    // The GitHub-only prototype called this commitSha. Reading it here makes
    // the metadata migration harmless for anyone who managed an import before
    // the generic Git implementation replaced it.
    final revision = text('revision') ?? text('commitSha');
    if ([skillName, sourceUrl, ref, repositoryPath, revision].any((field) => field == null)) return null;
    return GitSourceRecord(
      skillName: skillName!,
      sourceUrl: sourceUrl!,
      ref: ref!,
      repositoryPath: repositoryPath!,
      revision: revision!,
    );
  }
}

class GitImportResult {
  const GitImportResult(this.library, {this.sourcesSaved = 0});

  final LibraryImportResult library;
  final int sourcesSaved;
}
