import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_reveal.dart';

/// r56: every grid thumbnail waited 200 ms before loading and then faded in
/// over 300 ms, even when the picture was already in memory; in the profiling
/// the slow grid frames drew up to 32 fading thumbnails, each its own layer.
/// A thumbnail already shown this session, or answered from the memory cache,
/// now appears at once (Modular UI switch; off keeps the wait and the fade).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String url = 'https://thumbs.invalid/1.jpg';
  const Duration fade = Duration(milliseconds: 300);

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
    ThumbnailReveal.resetForTests();
  });

  test('a thumbnail never shown waits and fades as before', () {
    expect(ThumbnailReveal.delayFor(isStandalone: true, instant: true, url: url), const Duration(milliseconds: 200));
    expect(ThumbnailReveal.delayFor(isStandalone: false, instant: true, url: url), Duration.zero);
    expect(ThumbnailReveal.fadeFor(normal: fade, instant: true, seenBefore: false, syncCall: false), fade);
  });

  test('a thumbnail already shown this session loads without the wait and appears without the fade', () {
    ThumbnailReveal.remember(url);
    expect(ThumbnailReveal.seen(url), isTrue);
    expect(ThumbnailReveal.delayFor(isStandalone: true, instant: true, url: url), Duration.zero);
    expect(ThumbnailReveal.fadeFor(normal: fade, instant: true, seenBefore: true, syncCall: false), Duration.zero);
  });

  test('a picture answered from the memory cache appears without the fade even if not remembered', () {
    expect(ThumbnailReveal.fadeFor(normal: fade, instant: true, seenBefore: false, syncCall: true), Duration.zero);
  });

  test('with the switch off every thumbnail waits and fades as before', () {
    ThumbnailReveal.remember(url);
    expect(ThumbnailReveal.delayFor(isStandalone: true, instant: false, url: url), const Duration(milliseconds: 200));
    expect(ThumbnailReveal.fadeFor(normal: fade, instant: false, seenBefore: true, syncCall: true), fade);
  });

  test('the remembered set is capped, dropping the thumbnail seen longest ago', () {
    for (int i = 0; i < ThumbnailReveal.maxRemembered; i++) {
      ThumbnailReveal.remember('https://thumbs.invalid/$i.jpg');
    }
    ThumbnailReveal.remember('https://thumbs.invalid/0.jpg'); // seen again: now the newest
    ThumbnailReveal.remember('https://thumbs.invalid/new.jpg');
    expect(ThumbnailReveal.seen('https://thumbs.invalid/0.jpg'), isTrue);
    expect(ThumbnailReveal.seen('https://thumbs.invalid/1.jpg'), isFalse);
    expect(ThumbnailReveal.seen('https://thumbs.invalid/new.jpg'), isTrue);
    expect(ThumbnailReveal.rememberedCount, ThumbnailReveal.maxRemembered);
  });

  test('the Modular UI switch is on by default', () {
    expect(ModularUi.all, contains(ModularUi.gridSeenThumbnailsAtOnce));
    expect(ModularUi.isOn(ModularUi.gridSeenThumbnailsAtOnce), isTrue);
  });
}
