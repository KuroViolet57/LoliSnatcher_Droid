import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// r65: a recorder inside the app, so a slow moment can be looked at without a
/// cable and a profile build. It counts frames the way the phone draws them
/// (build = the app's own work, raster = drawing), and notes what the app was
/// doing - players built or re-pointed, pages opened - on one timeline.
void main() {
  // The recorder listens to the engine's frame timings, so it needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PerfTrace.instance.clearForTests);

  void frames(List<(int build, int raster)> list, {int startMs = 0}) {
    int at = startMs;
    for (final (int build, int raster) in list) {
      PerfTrace.instance.addFrame(buildUs: build * 1000, rasterUs: raster * 1000, atMs: at);
      at += 8;
    }
  }

  test('a recording starts empty and collects frames only while it runs', () {
    final PerfTrace t = PerfTrace.instance;
    expect(t.isRecording.value, isFalse);

    frames([(2, 5)]);
    expect(t.frameCount, 0, reason: 'nothing is recorded before start');

    t.start();
    frames([(2, 5), (3, 6)]);
    expect(t.frameCount, 2);

    t.stop();
    frames([(4, 7)]);
    expect(t.frameCount, 2, reason: 'nothing after stop');

    t.start();
    expect(t.frameCount, 0, reason: 'a new recording starts clean');
  });

  test('frames are sorted into the buckets that matter on a 120 Hz screen', () {
    final PerfTrace t = PerfTrace.instance..start();
    frames([
      (2, 4), // fine
      (10, 4), // app over 8.3
      (2, 12), // draw over 8.3
      (20, 4), // app over 16.7
      (2, 40), // draw over 33.3
      (120, 2), // app hitch over 100
    ]);

    expect(t.frameCount, 6);
    expect(t.buildOver(8.3), 3, reason: '10, 20 and 120 ms');
    expect(t.rasterOver(8.3), 2, reason: 'only 12 and 40; the 4 ms ones are fine');
    expect(t.buildOver(33.3), 1);
    expect(t.rasterOver(33.3), 1);
    expect(t.worstBuildMs, closeTo(120, 0.1));
    expect(t.worstRasterMs, closeTo(40, 0.1));
  });

  test('the median and the 95th tell a steady recording from a spiky one', () {
    final PerfTrace t = PerfTrace.instance..start();
    frames([for (int i = 0; i < 19; i++) (2, 4)]);
    frames([(200, 300)]);

    expect(t.medianBuildMs, closeTo(2, 0.5));
    expect(t.medianRasterMs, closeTo(4, 0.5));
    expect(
      t.p95BuildMs,
      closeTo(2, 0.5),
      reason: 'one spike in twenty frames does not move the 95th - which is why the worst is reported too',
    );
    expect(t.worstBuildMs, closeTo(200, 0.1));
    expect(t.worstRasterMs, closeTo(300, 0.1));
  });

  test('what the app was doing lands on the timeline, counted by kind', () {
    final PerfTrace t = PerfTrace.instance..start();
    t.event('video.create', 'https://a.invalid/1.mp4');
    t.event('video.rebind', 'https://a.invalid/2.mp4');
    t.event('video.rebind', 'https://a.invalid/3.mp4');
    t.event('viewer.page', '4');

    expect(t.counts['video.rebind'], 2);
    expect(t.counts['video.create'], 1);
    expect(t.events.length, 4);
    expect(t.events.last.kind, 'viewer.page');
  });

  test('the timeline is capped, so a long recording cannot grow forever', () {
    final PerfTrace t = PerfTrace.instance..start();
    for (int i = 0; i < PerfTrace.maxEvents + 50; i++) {
      t.event('video.rebind', '$i');
    }

    expect(t.events.length, PerfTrace.maxEvents);
    expect(t.events.first.detail, '50', reason: 'the oldest ones drop off');
    expect(t.counts['video.rebind'], PerfTrace.maxEvents + 50, reason: 'counts still see everything');
  });

  test('the report says what happened, in numbers a person can read', () {
    final PerfTrace t = PerfTrace.instance..start();
    frames([(2, 4), (40, 9), (2, 210)]);
    t.event('video.create', 'https://a.invalid/1.mp4');
    t.stop();

    final String report = t.report();
    expect(report, contains('FRAMES'));
    expect(report, contains('WHAT HAPPENED'));
    expect(report, contains('TIMELINE'));
    expect(report, contains('video.create'));
    expect(report, contains('3 frames'));
    // the two hitches have to be visible in the text, not just in the numbers
    expect(report, contains('40'));
    expect(report, contains('210'));
  });

  test('a report with nothing in it still reads as a report', () {
    final PerfTrace t = PerfTrace.instance..start();
    t.stop();
    expect(t.report(), contains('FRAMES'));
    expect(t.report(), contains('0 frames'));
  });
}
