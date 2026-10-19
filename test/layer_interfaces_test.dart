import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/ui/bottom_bar_visibility.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/ui/waterfall_bottom_bar.dart';
import 'package:lolisnatcher/features/video/logic/video_frame_players.dart';
import 'package:lolisnatcher/features/video/ui/media_kit_player_view.dart';

/// M3 (token 151): interfaces a lower layer uses in place of a UI import.
void main() {
  testWidgets('NavigationHandler.bottomBar reaches the bar State behind bottomBarKey', (WidgetTester tester) async {
    final NavigationHandler nav = NavigationHandler();
    expect(nav.bottomBar, isNull);
    await tester.pumpWidget(_FakeBar(key: nav.bottomBarKey));
    final _FakeBarState bar = tester.state(find.byType(_FakeBar));
    nav.bottomBar?.hide();
    nav.bottomBar?.show();
    expect(bar.calls, ['hide', 'show']);
  });

  test('the waterfall bottom bar State is a BottomBarVisibility', () {
    // A type check without building the bar (its fields read handlers).
    bool isA2<A, B>() => <A>[] is List<B>;
    expect(isA2<WaterfallBottomBarState, BottomBarVisibility>(), isTrue);
  });

  test('frame players: nothing showing until the media_kit pool exists, then the pool answers', () {
    expect(VideoFramePlayers.source.showing('https://x/v.mp4'), isNull);
    MediaKitPlayerView.resetPool(); // creates the pool
    expect(VideoFramePlayers.source, isA<MediaKitFrameSource>());
    expect(VideoFramePlayers.source.showing('https://x/v.mp4'), isNull, reason: 'the pool is empty');
  });
}

class _FakeBar extends StatefulWidget {
  const _FakeBar({super.key});

  @override
  State<_FakeBar> createState() => _FakeBarState();
}

class _FakeBarState extends State<_FakeBar> implements BottomBarVisibility {
  final List<String> calls = [];

  @override
  void show() => calls.add('show');

  @override
  void hide() => calls.add('hide');

  @override
  Widget build(BuildContext context) => const SizedBox();
}
