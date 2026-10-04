import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/ui/text/parsed_text.dart';

/// 1.0 M2: a comment's links, tags and mentions got a new TapGestureRecognizer
/// on every build, and none was ever disposed. Every recognizer ParsedText
/// makes is disposed again: when the next build replaces it, or with the widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every tap recognizer a comment makes is disposed', (tester) async {
    final Set<Object> live = {};
    void listener(ObjectEvent event) {
      if (event is ObjectCreated && event.object.runtimeType == TapGestureRecognizer) {
        live.add(event.object);
      } else if (event is ObjectDisposed) {
        live.remove(event.object);
      }
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

    double size = 14;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return ParsedText(
                text: 'see https://example.com and https://example.org, #tag and @someone',
                style: TextStyle(fontSize: size),
                selectable: false,
                onTagTap: (_) {},
                onMentionTap: (_) {},
              );
            },
          ),
        ),
      ),
    );
    expect(live, isNotEmpty, reason: 'the links are tappable');

    // Rebuilds (theme change, a spoiler toggled, scrolled back in).
    for (int i = 0; i < 3; i++) {
      setOuter(() => size++);
      await tester.pump();
    }

    await tester.pumpWidget(const SizedBox());
    expect(live, isEmpty, reason: '${live.length} tap recognizers were never disposed');
  });

  testWidgets('a link still opens after the comment rebuilt', (tester) async {
    final List<String> opened = [];
    late StateSetter setOuter;
    double size = 14;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return ParsedText(
                text: 'https://example.com',
                style: TextStyle(fontSize: size),
                selectable: false,
                onUrlTap: opened.add,
              );
            },
          ),
        ),
      ),
    );
    setOuter(() => size++);
    await tester.pump();
    await tester.tap(find.byType(ParsedText));
    expect(opened, ['https://example.com']);
  });
}
