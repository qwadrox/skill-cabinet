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
    this.lastCheckedAt,
    this.remoteRevision,
    this.lastCheckError,
  });

  final String skillName;
  final String sourceUrl;
  final String ref;
  final String repositoryPath;
  final String revision;
  final DateTime? lastCheckedAt;
  final String? remoteRevision;
  final String? lastCheckError;

  GitTrackingState get state {
    if (lastCheckError != null) return GitTrackingState.error;
    if (remoteRevision == null) return GitTrackingState.tracked;
    return remoteRevision == revision ? GitTrackingState.upToDate : GitTrackingState.updateAvailable;
  }

  String get statusLabel => switch (state) {
    GitTrackingState.tracked => 'Tracked · not checked yet',
    GitTrackingState.upToDate => 'Up to date',
    GitTrackingState.updateAvailable => 'Update available',
    GitTrackingState.error => 'Update check failed',
  };

  GitSourceRecord withCheck({DateTime? checkedAt, String? remote, String? error}) => GitSourceRecord(
    skillName: skillName,
    sourceUrl: sourceUrl,
    ref: ref,
    repositoryPath: repositoryPath,
    revision: revision,
    lastCheckedAt: checkedAt,
    remoteRevision: remote ?? remoteRevision,
    lastCheckError: error,
  );

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'skillName': skillName,
      'sourceUrl': sourceUrl,
      'ref': ref,
      'repositoryPath': repositoryPath,
      'revision': revision,
    };
    final checked = lastCheckedAt;
    if (checked != null) json['lastCheckedAt'] = checked.toUtc().toIso8601String();
    final remote = remoteRevision;
    if (remote != null) json['remoteRevision'] = remote;
    final error = lastCheckError;
    if (error != null) json['lastCheckError'] = error;
    return json;
  }

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
      lastCheckedAt: DateTime.tryParse(text('lastCheckedAt') ?? ''),
      remoteRevision: text('remoteRevision'),
      lastCheckError: text('lastCheckError'),
    );
  }
}

enum GitTrackingState { tracked, upToDate, updateAvailable, error }

class GitUpdateCheckResult {
  const GitUpdateCheckResult({required this.records, required this.checked, required this.updates, this.failures = 0});

  final Map<String, GitSourceRecord> records;
  final int checked;
  final int updates;
  final int failures;
}

class GitImportResult {
  const GitImportResult(this.library, {this.sourcesSaved = 0});

  final LibraryImportResult library;
  final int sourcesSaved;
}
