import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/startup_timeline.dart';

void main() {
  late int now;

  setUp(() {
    now = 0;
    StartupTimeline.debugUseClock(() => now);
    StartupTimeline.start();
  });

  tearDown(() => StartupTimeline.debugUseClock(null));

  test('marks keep their order and the time since start', () {
    now = 12;
    StartupTimeline.mark('binding');
    now = 140;
    StartupTimeline.mark('settings');
    expect(StartupTimeline.marks.map((m) => m.$1), ['binding', 'settings']);
    expect(StartupTimeline.marks.map((m) => m.$2), [12, 140]);
  });

  test('the summary names each step with its own time and the total', () {
    now = 12;
    StartupTimeline.mark('binding');
    now = 140;
    StartupTimeline.mark('settings');
    now = 900;
    StartupTimeline.mark('tabs');
    expect(
      StartupTimeline.summary(),
      'startup: binding 12 ms · settings 128 ms · tabs 760 ms · total 900 ms',
    );
  });

  test('finish logs once; later marks and finishes are ignored', () {
    now = 50;
    StartupTimeline.mark('settings');
    now = 300;
    final String? first = StartupTimeline.finish('home');
    expect(first, 'startup: settings 50 ms · home 250 ms · total 300 ms');
    now = 400;
    StartupTimeline.mark('late');
    expect(StartupTimeline.finish('home'), isNull);
    expect(StartupTimeline.marks.length, 2);
    expect(StartupTimeline.isFinished, isTrue);
  });

  test('an empty timeline has an honest summary', () {
    expect(StartupTimeline.summary(), 'startup: no steps recorded');
  });
}
