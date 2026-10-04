import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/loli_dropdown.dart';

/// 1.0 M2: the dropdown sheet (every SettingsDropdown and booru picker).
/// - Its search field controller, and its own scroll controller, were never
///   disposed when the sheet closed.
/// - A current value that is not in the list (filtered out, or a stale Booru
///   instance) threw RangeError(-1) in the scroll-to-selected callback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  Widget sheet({String? value, ScrollController? controller}) => TranslationProvider(
    child: MaterialApp(
      home: Scaffold(
        body: LoliDropdownBottomSheet<String>(
          value: value,
          onChanged: (_) {},
          items: const ['one', 'two', 'three'],
          itemBuilder: Text.new,
          labelText: 'Pick',
          itemExtent: 40,
          controller: controller,
        ),
      ),
    ),
  );

  testWidgets('closing the sheet disposes the controllers it made', (tester) async {
    final Set<Object> live = {};
    void listener(ObjectEvent event) {
      final Type type = event.object.runtimeType;
      if (event is ObjectCreated && (type == TextEditingController || type == ScrollController)) {
        live.add(event.object);
      } else if (event is ObjectDisposed) {
        live.remove(event.object);
      }
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

    await tester.pumpWidget(sheet(value: 'two'));
    await tester.pump();
    expect(live, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(live, isEmpty, reason: '${live.map((o) => o.runtimeType).toList()} left undisposed');
  });

  testWidgets('a scroll controller handed in by a draggable sheet is not disposed by the sheet', (tester) async {
    final ScrollController outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(sheet(value: 'two', controller: outer));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    // Still usable: a disposed ChangeNotifier asserts on addListener.
    expect(() => outer.addListener(() {}), returnsNormally);
  });

  testWidgets('a value that is not in the list opens the sheet without an error', (tester) async {
    await tester.pumpWidget(sheet(value: 'gone'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('one'), findsOneWidget);
  });
}
