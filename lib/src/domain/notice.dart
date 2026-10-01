// A one-line message for the window. Its level is decided where the message
// is written, never guessed from the wording: progress and results are info,
// a refused or partly failed action is a warning, and a failure is an error.
enum NoticeLevel { info, warning, error }

class Notice {
  const Notice(this.text, this.level);
  const Notice.info(this.text) : level = NoticeLevel.info;
  const Notice.warning(this.text) : level = NoticeLevel.warning;
  const Notice.error(this.text) : level = NoticeLevel.error;

  static const none = Notice.info('');

  final String text;
  final NoticeLevel level;

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  @override
  bool operator ==(Object other) => other is Notice && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(text, level);

  @override
  String toString() => text;
}
