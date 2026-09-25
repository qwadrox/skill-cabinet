// Backup: the cabinet folder's own Git history, optionally pushed to one
// remote the user owns. One machine writes; the remote is a copy of it,
// never merged from.

// One backup point: a commit in the cabinet's history.
class BackupEntry {
  const BackupEntry({required this.id, required this.date, required this.summary});

  final String id;
  final DateTime date;
  final String summary;

  String get shortId => id.length <= 7 ? id : id.substring(0, 7);
}

class BackupStatus {
  const BackupStatus({this.history = const [], this.remote = '', this.unpushed = 0, this.notice = ''});

  static const empty = BackupStatus();

  // Newest first.
  final List<BackupEntry> history;
  // The remote's URL; empty when backups stay on this Mac.
  final String remote;
  // Backup points the remote does not have yet.
  final int unpushed;
  final String notice;

  bool get hasRemote => remote.isNotEmpty;
  DateTime? get lastBackup => history.isEmpty ? null : history.first.date;
}

// What connecting a remote found.
enum BackupConnectOutcome {
  // The remote was empty and now holds this Mac's history.
  connected,
  // The remote already holds a backup; nothing was changed. Restoring it
  // is the user's call.
  holdsBackup,
  failed,
}

class BackupConnectResult {
  const BackupConnectResult(this.outcome, {this.message = ''});

  final BackupConnectOutcome outcome;
  final String message;
}

// "2026-09-25 14:03", local time.
String backupDateLabel(DateTime date) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
