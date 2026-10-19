import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/download_notice.dart';
import 'package:lolisnatcher/core/platform/notify_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';

void main() {
  test('a switched-off or empty queue posts nothing', () {
    expect(
      noticeForQueued(enabled: false, count: 3, oneTitle: 'one', manyTitle: 'many'),
      isNull,
    );
    expect(
      noticeForQueued(enabled: true, count: 0, oneTitle: 'one', manyTitle: 'many'),
      isNull,
    );
    expect(
      noticeForFinished(enabled: false, isLastMessage: true, title: 'done', lines: const ['a']),
      isNull,
    );
    expect(
      noticeForFinished(enabled: true, isLastMessage: false, title: 'done', lines: const ['a']),
      isNull,
    );
  });

  test('queue and finish notices keep a stable id and the caller text', () {
    final DownloadNotice? one = noticeForQueued(
      enabled: true,
      count: 1,
      oneTitle: 'Added item to snatch queue',
      manyTitle: 'Added 1 items to snatch queue',
    );
    expect(one?.id, DownloadNotice.queuedId);
    expect(one?.title, 'Added item to snatch queue');
    expect(one?.body, isEmpty);

    final DownloadNotice? many = noticeForQueued(
      enabled: true,
      count: 4,
      oneTitle: 'one',
      manyTitle: 'Added 4 items to snatch queue',
    );
    expect(many?.id, DownloadNotice.queuedId);
    expect(many?.title, 'Added 4 items to snatch queue');

    final DownloadNotice? done = noticeForFinished(
      enabled: true,
      isLastMessage: true,
      title: 'Items snatched',
      lines: const ['Snatched: 2 items', 'Failed to snatch 1 file'],
    );
    expect(done?.id, DownloadNotice.finishedId);
    expect(done?.title, 'Items snatched');
    expect(done?.body, 'Snatched: 2 items\nFailed to snatch 1 file');

    final DownloadNotice? bare = noticeForFinished(
      enabled: true,
      isLastMessage: true,
      title: 'Items snatched',
      lines: const ['', '  '],
    );
    expect(bare?.body, isEmpty);
  });

  test('test mode records the notice and does not touch the plugin', () async {
    NotifyHandler.register();
    addTearDown(NotifyHandler.unregister);
    const DownloadNotice notice = DownloadNotice(id: DownloadNotice.queuedId, title: 'queued', body: '');
    await NotifyHandler.instance.show(notice);
    await NotifyHandler.instance.show(notice);
    expect(NotifyHandler.instance.posted, [notice, notice]);
  });

  test('the snatch queue posts those notices when the setting is on', () {
    final String snatch = File('lib/features/downloads/logic/snatch_handler.dart').readAsStringSync();
    expect(snatch.contains('noticeForQueued'), isTrue);
    expect(snatch.contains('noticeForFinished'), isTrue);
    expect(snatch.contains('NotifyHandler.instance.show'), isTrue);
    expect(SnatchHandler.register, isA<Function>());

    final String handler = File('lib/core/platform/notify_handler.dart').readAsStringSync();
    expect(handler.contains('flutter_local_notifications'), isTrue);
    expect(handler.contains('requestNotificationsPermission'), isTrue);
    expect(handler.contains('Tools.isTestMode'), isTrue);
    expect(handler.contains('ic_stat_download'), isTrue);
  });
}
