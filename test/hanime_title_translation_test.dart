import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/sources/tube/hanime1_handler.dart';

/// Hanime1 sends every non-English title to translate.googleapis.com.
/// Settings → Network must be able to stop that, and an older settings
/// file keeps the translation on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  test('a title is sent only when the switch is on and the title is not already ASCII', () async {
    expect(hanimeTitleTranslationRequested('純愛', enabled: false), isFalse);
    expect(hanimeTitleTranslationRequested('純愛', enabled: true), isTrue);
    expect(hanimeTitleTranslationRequested('already english', enabled: true), isFalse);
    expect(hanimeTitleTranslationRequested('  ', enabled: true), isFalse);

    final SettingsHandler settings = SettingsHandler.instance;
    expect(settings.map['translateHanimeTitles']!['default'], isTrue);
    expect(settings.translateHanimeTitles, isTrue);
    settings.translateHanimeTitles = false;
    expect(settings.toJson()['translateHanimeTitles'], isFalse);

    settings.translateHanimeTitles = false;
    await settings.loadFromJSON('{}', true);
    expect(settings.translateHanimeTitles, isTrue, reason: 'an older file has no key, so translation stays on');
  });

  test('the handler asks the switch before the Google call, and Network shows the switch', () {
    final String source = File('lib/sources/tube/hanime1_handler.dart').readAsStringSync();
    final int method = source.indexOf('static Future<String?> _translateFreeText');
    final int gate = source.indexOf('hanimeTitleTranslationRequested', method);
    final int google = source.indexOf('translate.googleapis.com', method);
    expect(method, greaterThan(0));
    expect(gate, greaterThan(method));
    expect(google, greaterThan(gate));

    final String page = File('lib/features/settings/ui/network_page.dart').readAsStringSync();
    expect(page, contains('Translate Hanime1 titles'));
    expect(page, contains('translateHanimeTitles'));
  });
}
