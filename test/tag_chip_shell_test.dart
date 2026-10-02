import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/gallery/tag_chip_shell.dart';

/// r77: a tag chip's preview icon sat inside the chip's own gesture area,
/// which also listens for double taps (the tag editor shortcut), so the icon
/// only reacted about 0.3 s after the finger left - long enough, on 19 Sep,
/// for the viewer to close first. The icon is now its own button laid over
/// the chip: it reacts on the first frame, while the chip keeps tap = menu,
/// double tap = editor and hold = new tab.
void main() {
  late int menu;
  late int editor;
  late int tab;
  late int preview;
  late int previewHold;

  setUp(() {
    menu = 0;
    editor = 0;
    tab = 0;
    preview = 0;
    previewHold = 0;
  });

  Future<void> chip(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TagChipShell(
              key: const ValueKey('chip'),
              color: Colors.blue.withValues(alpha: 0.16),
              shape: const StadiumBorder(),
              previewZoneWidth: TagChipShell.previewZoneWidthFor(iconSize: 16),
              previewLabel: 'Preview red_hair',
              onTap: () => menu++,
              onDoubleTap: () => editor++,
              onLongPress: () => tab++,
              onPreview: () => preview++,
              onPreviewLongPress: () => previewHold++,
              child: const Padding(
                padding: EdgeInsets.only(left: 10, right: 2, top: 3, bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('red_hair'),
                    SizedBox(width: 4),
                    SizedBox(width: 1, height: 16),
                    Padding(
                      padding: EdgeInsets.fromLTRB(11, 9, 8, 9),
                      child: Icon(Icons.picture_in_picture_alt, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset zone(WidgetTester tester) => tester.getCenter(find.byIcon(Icons.picture_in_picture_alt));
  Offset label(WidgetTester tester) => tester.getCenter(find.text('red_hair'));

  testWidgets("the preview icon reacts on the first frame, and the chip's own tap does not fire", (tester) async {
    await chip(tester);
    await tester.tapAt(zone(tester));
    await tester.pump();
    expect(preview, 1, reason: 'no 0.3 s double-tap wait');
    await tester.pump(const Duration(milliseconds: 500));
    expect(menu, 0);
    expect(editor, 0);
  });

  testWidgets('the tag name keeps tap = menu (after the double-tap wait), double tap = editor, hold = new tab', (tester) async {
    await chip(tester);
    await tester.tapAt(label(tester));
    await tester.pump();
    expect(menu, 0, reason: 'the chip still waits for a possible second tap');
    await tester.pump(const Duration(milliseconds: 350));
    expect(menu, 1);

    await tester.tapAt(label(tester));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(label(tester));
    await tester.pump(const Duration(milliseconds: 350));
    expect(editor, 1);
    expect(menu, 1);

    await tester.longPressAt(label(tester));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tab, 1);
    expect(preview, 0);
  });

  testWidgets('holding the preview icon opens a tab too; a second quick tap on it is still one window', (tester) async {
    await chip(tester);
    await tester.longPressAt(zone(tester));
    await tester.pump(const Duration(milliseconds: 100));
    expect(previewHold, 1);
    expect(tab, 0);

    final TestGesture g = await tester.startGesture(zone(tester), kind: PointerDeviceKind.touch);
    await g.up();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(zone(tester));
    await tester.pump(const Duration(milliseconds: 80));
    expect(preview, 1, reason: 'two taps within half a second open one window');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(zone(tester));
    await tester.pump();
    expect(preview, 2);
  });

  testWidgets("the preview icon is a labelled button for accessibility, and keeps the chip's size", (tester) async {
    await chip(tester);
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Preview red_hair'), findsOneWidget);
    handle.dispose();
    final Size size = tester.getSize(find.byKey(const ValueKey('chip')));
    expect(size.height, 16 + 9 + 9 + 3 + 3, reason: 'same height as before: the icon zone decides it');
  });

  testWidgets('TalkBack can activate the preview button and hold it', (tester) async {
    await chip(tester);
    final SemanticsHandle handle = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel('Preview red_hair'));
    await tester.pump();
    expect(preview, 1);
    tester.semantics.longPress(find.semantics.byLabel('Preview red_hair'));
    await tester.pump();
    expect(previewHold, 1);
    handle.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });
}
