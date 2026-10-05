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
    this.tracked = false,
    this.clashes = false,
    this.alternative = false,
    this.blockedReason,
  });

  final String name;
  final String repositoryPath;
  final String localPath;
  final String description;
  // A skill of that name is already in the store. It can still be chosen:
  // the repository's copy then replaces it and is tracked from here on.
  final bool duplicate;
  // The store's copy already comes from this very folder of this repository,
  // so there is nothing to adopt; updates arrive through the update check.
  final bool tracked;
  // Another folder of the repository has the same name, so only one of them
  // can be imported.
  final bool clashes;
  // A clashing copy that is not the default choice: a shallower folder of
  // that name exists, typically the main copy next to an add-on's.
  final bool alternative;
  final String? blockedReason;

  bool get selectable => !tracked && blockedReason == null;
  bool get replaces => duplicate && selectable;
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
    this.hasContentChanges,
  });

  final String skillName;
  final String sourceUrl;
  final String ref;
  final String repositoryPath;
  final String revision;
  final DateTime? lastCheckedAt;
  final String? remoteRevision;
  final String? lastCheckError;
  // Null for older repository-only checks; those must be checked against files.
  final bool? hasContentChanges;

  // Browser address for HTTPS, SSH, and SCP-style Git remotes.
  String? get repositoryWebUrl {
    final scp = RegExp(r'^git@([^:/\s]+):([^\s]+)$').firstMatch(sourceUrl);
    final uri = scp == null
        ? Uri.tryParse(sourceUrl)
        : Uri(scheme: 'ssh', host: scp.group(1), path: '/${scp.group(2)}');
    if (uri == null || !const {'https', 'ssh'}.contains(uri.scheme) || uri.host.isEmpty) return null;
    return Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.scheme == 'https' && uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'\.git/?$'), ''),
    ).toString();
  }

  GitTrackingState get state {
    if (lastCheckError != null) return GitTrackingState.error;
    if (hasContentChanges == null) return GitTrackingState.tracked;
    return hasContentChanges! ? GitTrackingState.updateAvailable : GitTrackingState.upToDate;
  }

  String get statusLabel => switch (state) {
    GitTrackingState.tracked => 'Tracked · not checked yet',
    GitTrackingState.upToDate => 'Up to date',
    GitTrackingState.updateAvailable => 'Update available',
    GitTrackingState.error => 'Update check failed',
  };

  GitSourceRecord withCheck({DateTime? checkedAt, String? remote, String? error, bool? contentChanges}) =>
      GitSourceRecord(
        skillName: skillName,
        sourceUrl: sourceUrl,
        ref: ref,
        repositoryPath: repositoryPath,
        revision: revision,
        lastCheckedAt: checkedAt,
        remoteRevision: remote ?? remoteRevision,
        lastCheckError: error,
        hasContentChanges: contentChanges ?? hasContentChanges,
      );

  GitSourceRecord withRevision(String value, {required DateTime updatedAt}) => GitSourceRecord(
    skillName: skillName,
    sourceUrl: sourceUrl,
    ref: ref,
    repositoryPath: repositoryPath,
    revision: value,
    lastCheckedAt: updatedAt,
    remoteRevision: value,
    hasContentChanges: false,
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
    final changes = hasContentChanges;
    if (changes != null) json['hasContentChanges'] = changes;
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
      hasContentChanges: value['hasContentChanges'] is bool ? value['hasContentChanges'] as bool : null,
    );
  }
}

enum GitTrackingState { tracked, upToDate, updateAvailable, error }

class GitUpdatePreview {
  const GitUpdatePreview({required this.revision, required this.files});

  final String revision;
  final List<GitFileChange> files;
}

enum GitFileChangeKind { added, modified, deleted }

class GitFileChange {
  const GitFileChange({required this.path, required this.kind, required this.diff, this.message});

  final String path;
  final GitFileChangeKind kind;
  final String diff;
  // Binary or large files can be compared without rendering their contents.
  final String? message;
}

class GitUpdateCheckResult {
  const GitUpdateCheckResult({required this.records, required this.checked, required this.updates, this.failures = 0});

  final Map<String, GitSourceRecord> records;
  final int checked;
  final int updates;
  final int failures;
}

class GitUpdateApplyResult {
  const GitUpdateApplyResult({required this.records, this.updated = const [], this.failures = const {}});

  final Map<String, GitSourceRecord> records;
  final List<String> updated;
  final Map<String, String> failures;
}

class GitImportResult {
  const GitImportResult(this.library, {this.sourcesSaved = 0});

  final LibraryImportResult library;
  final int sourcesSaved;
}
