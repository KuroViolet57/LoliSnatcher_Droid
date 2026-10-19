import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/feed/ui/search/flow_search_bar.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';

Color _chipColor(WidgetTester tester) {
  final Container box = tester.widget<Container>(find.ancestor(of: find.text('alpha'), matching: find.byType(Container)).first);
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the grid search chips repaint when a batch of tag types arrives', (tester) async {
    SettingsHandler.register();
    SearchHandler.register();
    TagHandler.register();
    SettingsHandler.instance.dbEnabled = false;
    SearchHandler.instance.searchTextController.text = 'alpha';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FlowSearchBar()),
      ),
    );
    final Color before = _chipColor(tester);
    await TagHandler.instance.putTag(Tag('alpha', tagType: TagType.artist), dbEnabled: false);
    await tester.pump();
    expect(_chipColor(tester), isNot(before));
  });
}
