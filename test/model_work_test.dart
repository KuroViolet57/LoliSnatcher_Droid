import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/model_work.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_embedding_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_look_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_tag_runner.dart';
import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// r77: background model work (learning steps, a frame's looks run) waits for
/// a quiet moment - no touch, scroll or page change for [ModelWork.quiet] -
/// runs one step at a time, holds the tagger while a video plays (up to a
/// limit), and runs "lite" (without the models) when the app leaves the
/// screen, so nothing is lost. The clock here is a fake one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late bool playing;
  late bool away;
  final ModelWork work = ModelWork.instance;
  final ActivityClock clock = ActivityClock.instance;

  setUp(() {
    now = DateTime(2026, 9, 19, 12);
    playing = false;
    away = false;
    ModelWork.resetForTests();
    clock.now = () => now;
    work
      ..videoPlaying = (() => playing)
      ..away = (() => away);
  });

  tearDown(ModelWork.resetForTests);

  test('the thread counts: encoder 1, looks model 1, tagger 2, for every caller', () {
    expect(OnnxEmbeddingRunner('m.onnx', dim: 384, wantsTokenTypeIds: false).threads, 1);
    expect(OnnxLookRunner('i.onnx', 't.onnx').threads, 1);
    expect(OnnxTagRunner('t.onnx').threads, 2);
    expect(OnnxEmbeddingRunner('m.onnx', dim: 384, wantsTokenTypeIds: false).options.intraOpNumThreads, 1);
    expect(OnnxLookRunner('i.onnx', 't.onnx').options.intraOpNumThreads, 1);
    expect(OnnxTagRunner('t.onnx').options.intraOpNumThreads, 2);
  });

  testWidgets('quiet: a step runs at once, and its future completes when it is done', (tester) async {
    final List<String> ran = [];
    final Future<void> f = work.run('a', (bool lite) async => ran.add('a lite=$lite'));
    await tester.pump();
    await f;
    expect(ran, ['a lite=false']);
  });

  testWidgets('after a touch a step waits until 1.5 s have passed without one', (tester) async {
    clock.mark();
    final List<String> ran = [];
    unawaited(work.run('a', (bool lite) async => ran.add('a')));
    now = now.add(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, isEmpty, reason: '1.4 s after the touch');
    now = now.add(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['a']);
  });

  testWidgets('touches, scrolls and page changes all count; a step keeps waiting while they go on', (tester) async {
    final List<String> ran = [];
    clock.onPointer(const PointerDownEvent(position: Offset(10, 10)));
    unawaited(work.run('a', (bool lite) async => ran.add('a')));
    for (int i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 1));
      clock.onPointer(const PointerMoveEvent(position: Offset(10, 40)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(ran, isEmpty, reason: 'a finger kept moving');
    final PerfTraceRouteObserver observer = PerfTraceRouteObserver();
    now = now.add(const Duration(seconds: 1));
    observer.didPop(MaterialPageRoute<void>(builder: (_) => const SizedBox()), null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, isEmpty, reason: 'a page closed 0 s ago (system Back sends no touch)');
    now = now.add(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['a']);
  });

  testWidgets('a fling scroll inside the app counts as activity', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PerfTraceGestureLayer(
          child: ListView(children: [for (int i = 0; i < 60; i++) SizedBox(height: 80, child: Text('row $i'))]),
        ),
      ),
    );
    expect(clock.last, isNull);
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    expect(clock.last, isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('steps never overlap: the second starts only after the first ends', (tester) async {
    final Completer<void> gate = Completer<void>();
    final List<String> ran = [];
    unawaited(work.run('first', (bool lite) async {
      ran.add('first start');
      await gate.future;
      ran.add('first end');
    }));
    unawaited(work.run('second', (bool lite) async => ran.add('second')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(ran, ['first start']);
    gate.complete();
    await tester.pump(const Duration(milliseconds: 600));
    expect(ran, ['first start', 'first end', 'second']);
  });

  testWidgets('twenty snatches run one at a time, in order', (tester) async {
    int running = 0;
    int most = 0;
    final List<int> order = [];
    for (int i = 0; i < 20; i++) {
      unawaited(work.run('snatch $i', (bool lite) async {
        running++;
        most = running > most ? running : most;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add(i);
        running--;
      }));
    }
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(most, 1);
    expect(order, [for (int i = 0; i < 20; i++) i]);
  });

  testWidgets('a tagger step waits while a video plays; a light step behind it goes first; the tagger runs after the limit', (tester) async {
    playing = true;
    final List<String> ran = [];
    unawaited(work.run('tagger', (bool lite) async => ran.add('tagger'), heavy: true));
    unawaited(work.run('view', (bool lite) async => ran.add('view')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['view']);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['view'], reason: '30 s of video');
    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['view', 'tagger'], reason: 'past the 60 s limit');
  });

  testWidgets('a tagger step runs as soon as the video stops', (tester) async {
    playing = true;
    final List<String> ran = [];
    unawaited(work.run('tagger', (bool lite) async => ran.add('tagger'), heavy: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, isEmpty);
    playing = false;
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['tagger']);
  });

  testWidgets('leaving the app: waiting steps run at once without the models (lite), and so do new ones', (tester) async {
    clock.mark();
    final List<String> ran = [];
    unawaited(work.run('a', (bool lite) async => ran.add('a lite=$lite')));
    unawaited(work.run('b', (bool lite) async => ran.add('b lite=$lite')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, isEmpty);
    away = true;
    work.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(ran, ['a lite=true', 'b lite=true']);
    unawaited(work.run('c', (bool lite) async => ran.add('c lite=$lite')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(ran.last, 'c lite=true');
  });

  testWidgets('a step that throws is logged and does not stop the queue', (tester) async {
    final List<String> ran = [];
    final Future<void> bad = work.run('bad', (bool lite) async => throw StateError('boom'));
    unawaited(work.run('good', (bool lite) async => ran.add('good')));
    await tester.pump(const Duration(milliseconds: 300));
    await bad;
    expect(ran, ['good']);
  });

  testWidgets('each step is on the trace timeline with its name and time', (tester) async {
    PerfTrace.instance.start();
    await work.run('learn view', (bool lite) async {});
    await tester.pump();
    final List<TraceEvent> events = PerfTrace.instance.events.where((e) => e.kind.startsWith('model.')).toList();
    PerfTrace.instance.stop();
    expect(events.map((e) => e.kind).toList(), ['model.start', 'model.end']);
    expect(events.first.detail, 'learn view');
    expect(events.last.detail, matches(RegExp(r'^learn view \d+ ms$')));
  });

  testWidgets('the notification shade (inactive) is not leaving: a step keeps waiting for quiet and runs with the models', (tester) async {
    work.away = ModelWork.defaultAway;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    clock.mark();
    final List<String> ran = [];
    unawaited(work.run('a', (bool lite) async => ran.add('a lite=$lite')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, isEmpty);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['a lite=false']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock.mark();
    unawaited(work.run('b', (bool lite) async => ran.add('b lite=$lite')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(ran.last, 'b lite=true', reason: 'paused is leaving');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a step that hangs holds the queue at most stepTimeout', (tester) async {
    work.stepTimeout = const Duration(seconds: 1);
    final List<String> ran = [];
    unawaited(work.run('hang', (bool lite) => Completer<void>().future));
    unawaited(work.run('next', (bool lite) async => ran.add('next')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(ran, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['next']);
  });

  testWidgets('after lite steps drained, the callback runs once (the recommender writes its models then)', (tester) async {
    int saves = 0;
    work.onDrainedAway = () => saves++;
    clock.mark();
    unawaited(work.run('a', (bool lite) async {}));
    unawaited(work.run('b', (bool lite) async {}));
    away = true;
    work.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(saves, 1);
    away = false;
    now = now.add(const Duration(seconds: 2));
    final List<String> ran = [];
    unawaited(work.run('c', (bool lite) async => ran.add('c')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ran, ['c']);
    expect(saves, 1, reason: 'a normal step does not save');
  });
}
