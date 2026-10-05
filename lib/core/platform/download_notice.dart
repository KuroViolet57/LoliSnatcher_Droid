/// One phone notice for a snatch. The same id replaces the previous notice,
/// so a long queue does not stack a shade full of banners.
class DownloadNotice {
  const DownloadNotice({required this.id, required this.title, required this.body});

  static const int queuedId = 41001;
  static const int finishedId = 41002;

  final int id;
  final String title;
  final String body;
}

/// Null when notifications are off or nothing was queued.
DownloadNotice? noticeForQueued({
  required bool enabled,
  required int count,
  required String oneTitle,
  required String manyTitle,
}) {
  if (!enabled || count <= 0) return null;
  return DownloadNotice(
    id: DownloadNotice.queuedId,
    title: count == 1 ? oneTitle : manyTitle,
    body: '',
  );
}

/// Null until the snatch stream's last message, and when notifications are off.
/// Blank lines are dropped so an all-clear finish is title only.
DownloadNotice? noticeForFinished({
  required bool enabled,
  required bool isLastMessage,
  required String title,
  required List<String> lines,
}) {
  if (!enabled || !isLastMessage) return null;
  final String body = [
    for (final String line in lines)
      if (line.trim().isNotEmpty) line.trim(),
  ].join('\n');
  return DownloadNotice(id: DownloadNotice.finishedId, title: title, body: body);
}
