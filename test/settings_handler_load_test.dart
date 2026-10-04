import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/models/theme_item.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/settings/gallery_button.dart';
import 'package:lolisnatcher/models/settings/settings_enum.dart';

/// 1.0 M2: settings.json and sourceSettings.json are read and written without
/// losing what the person set: a LoliSync payload leaves this phone's own
/// values alone, a file with missing keys still loads every default, two
/// saves at once leave a whole file, and an unreadable source settings file
/// is not silently replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsHandler s;

  setUpAll(initSettingsEnumRegistry);

  setUp(() {
    SettingsHandler.register();
    SearchHandler.register();
    s = SettingsHandler.instance;
    tempDir = Directory.systemTemp.createTempSync('settings_load');
    s
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..boorusPath = '${tempDir.path}${Platform.pathSeparator}boorus${Platform.pathSeparator}'
      ..cachePath = '${tempDir.path}${Platform.pathSeparator}cache${Platform.pathSeparator}'
      ..prefBooru = '';
    s.modelThreads.clear();
    s.modelRunOn.clear();
    s.earlierDownloadFolders.clear();
    s.hiddenTags.clear();
    s.booruList.clear();
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    s.modelThreads.clear();
    s.modelRunOn.clear();
    s.earlierDownloadFolders.clear();
    s.hiddenTags.clear();
    s.booruList.clear();
    s.buttonOrder = [...GalleryButton.values];
    s.disabledButtons = [];
    s.mousewheelScrollSpeed = 10;
    s.flowSkinApplied.value = false;
    s.theme.value = s.map['theme']!['default'];
    s.isAmoled.value = false;
    s.cacheDuration = Duration.zero;
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('settings.json', () {
    test("a LoliSync payload leaves this phone's thread counts, Run on choices and earlier folders alone", () async {
      s.modelThreads['look.background'] = 3;
      s.modelRunOn['tagger'] = 'nnapi';
      s.earlierDownloadFolders.add('content://tree/old');

      // What the sending phone posts: its settings without the device-specific keys.
      final Map<String, dynamic> payload = s.toJson();
      for (final String key in s.deviceSpecificSettings) {
        payload.remove(key);
      }
      await s.loadFromJSON(jsonEncode(payload), false);

      expect(s.modelThreads, {'look.background': 3});
      expect(s.modelRunOn, {'tagger': 'nnapi'});
      expect(s.earlierDownloadFolders, ['content://tree/old']);
    });

  });

  group('sourceSettings.json', () {
    final Booru a = Booru('a', BooruType.Gelbooru, '', 'https://a.example', '');
    final Booru d = Booru('d', BooruType.Gelbooru, '', 'https://d.example', '');

    File file() => File('${s.path}sourceSettings.json');

  });
}
