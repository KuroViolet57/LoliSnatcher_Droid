import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_handler.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_parser.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_session_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/furaffinity/ui/furaffinity_sidebar.dart';

/// A first watchlist page of 30 artists that says there is more; every later
/// page fails.
class _WatchlistProbe extends FurAffinityHandler {
  _WatchlistProbe(Booru booru) : super(booru, FurAffinityHandler.pageSize);

  int calls = 0;

  @override
  Future<({List<FurAffinityWatchEntry> users, bool hasNext})> fetchWatchlist(String username, int page) async {
    calls++;
    if (page == 1) {
      return (users: [for (int i = 0; i < 30; i++) FurAffinityWatchEntry(username: 'artist$i')], hasNext: true);
    }
    throw Exception('page $page failed');
  }
}

/// 1.0 M2 (tabs): FurAffinity's sidebar and its watched-artists page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('furaffinity_sidebar_fixes');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.furAffinitySidebar.value = true;
    FurAffinitySessionHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    FurAffinitySessionHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('watched artists: after a failed page one scroll gesture asks once, not once per scroll event', (tester) async {
    final _WatchlistProbe probe = _WatchlistProbe(fa);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: FurAffinityWatchlistPage(booru: fa, username: 'kuroviolet', handler: probe),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(probe.calls, 1);
    expect(find.text('artist0'), findsOneWidget);

    // Scrolled to the end: page 2 is asked for and fails.
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pump();
    expect(find.textContaining('page 2 failed'), findsOneWidget);
    expect(probe.calls, 2, reason: 'the rest of that scroll must not ask again');

    // A new scroll gesture is a new try.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(probe.calls, 3);
  });
}
