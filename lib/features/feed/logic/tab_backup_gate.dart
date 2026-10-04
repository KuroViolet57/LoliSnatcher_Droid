/// The fields of one tab that the tab backup writes (TabBackup.toJson), as
/// plain values, so a cheap signature can be taken without encoding JSON.
class TabBackupFields {
  const TabBackupFields({
    required this.tags,
    required this.booru,
    this.id,
    this.group,
    this.poolId,
    this.poolName,
    this.doujinPostURL,
    this.doujinTitle,
    this.doujinThumb,
    this.secondaryBoorus = const [],
    this.tagOverrides = const {},
    this.inheritMainTags = const {},
  });

  final String tags;
  final String booru;
  final String? id;
  final String? group;
  final String? poolId;
  final String? poolName;
  final String? doujinPostURL;
  final String? doujinTitle;
  final String? doujinThumb;
  final List<String> secondaryBoorus;
  final Map<String, String> tagOverrides;
  final Map<String, bool> inheritMainTags;

  int get signature => Object.hash(
    tags,
    booru,
    id,
    group,
    poolId,
    poolName,
    doujinPostURL,
    doujinTitle,
    doujinThumb,
    Object.hashAll(secondaryBoorus),
    Object.hashAllUnordered(tagOverrides.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAllUnordered(inheritMainTags.entries.map((e) => Object.hash(e.key, e.value))),
  );

  String get debugLabel => '$tags|$booru|$id|$group|$poolId|$poolName|$doujinPostURL|$doujinTitle|$doujinThumb|$secondaryBoorus|$tagOverrides|$inheritMainTags';
}

/// Decides whether the periodic tab backup has anything new to write (1.0).
///
/// The backup runs every 30 seconds and used to encode every tab as JSON and
/// rewrite the TabRestore row each time, even when nothing had changed: with
/// thousands of tabs that is a visible hitch on the UI thread every 30 s. The
/// gate compares a signature of exactly the fields the backup writes (and the
/// selected tab) with the last one written; an unchanged list is skipped, but
/// still written at least every [forceEvery] in case a change slipped past the
/// signature.
class TabBackupGate {
  TabBackupGate({
    this.forceEvery = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration forceEvery;
  final DateTime Function() _now;
  int? _lastSignature;
  DateTime? _lastWrite;

  static int signatureOf(Iterable<TabBackupFields> tabs, int selectedIndex) {
    int count = 0;
    final int tabsHash = Object.hashAll(
      tabs.map((t) {
        count++;
        return t.signature;
      }),
    );
    return Object.hash(tabsHash, count, selectedIndex);
  }

  bool shouldWrite(int signature) {
    final DateTime? last = _lastWrite;
    if (last == null || _lastSignature != signature) {
      return true;
    }
    return !_now().isBefore(last.add(forceEvery));
  }

  void written(int signature) {
    _lastSignature = signature;
    _lastWrite = _now();
  }

  void reset() {
    _lastSignature = null;
    _lastWrite = null;
  }
}
