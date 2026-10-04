import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/logging/log_redaction.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_handler.dart';
import 'package:lolisnatcher/sources/furaffinity/furaffinity_session_handler.dart';
import 'package:lolisnatcher/sources/tube/rule34video_handler.dart';

/// m2 (1.0): source-side bugs from the subsystem map, each pinned by the
/// scenario that showed it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('source_fixes_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    FurAffinitySessionHandler.instance.resetForTests();
    Rule34VideoHandler.knownTagIds.clear();
    Rule34VideoHandler.knownUploaderIds.clear();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    FurAffinitySessionHandler.instance.resetForTests();
    Tools.resetCookieJarForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('credentials stay out of the log', () {
    test("FurAffinity's session cookies (a, b) are not written by getCookies; the request still carries them", () async {
      Tools.cookieJarReaderOverride = (String uri) async => const {};
      Logger.Inst();
      FurAffinitySessionHandler.instance.store(a: 'FASESSIONA0123456789', b: 'FASESSIONB0123456789');
      final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
      final int before = Logger.talker.history.length;

      final String? cookies = await FurAffinityHandler(fa, 48).getCookies();

      expect(cookies, allOf(contains('a=FASESSIONA0123456789'), contains('b=FASESSIONB0123456789')));
      final String logged = [for (final e in Logger.talker.history.skip(before)) e.generateTextMessage()].join('\n');
      expect(logged, contains('www.furaffinity.net'), reason: 'the line is still written, for diagnosis');
      expect(logged, isNot(contains('FASESSIONA0123456789')));
      expect(logged, isNot(contains('FASESSIONB0123456789')));
    });

    test("InkBunny's session id is redacted in a URL, a decoded answer and a raw JSON body", () {
      const String sid = 'SIDVALUE0123456789abc';
      expect(redactSecrets('https://inkbunny.net/api_search.php?output_mode=json&sid=$sid&text=cat'), isNot(contains(sid)));
      expect(redactSecrets('{sid: $sid, results_count_all: 3}'), isNot(contains(sid)));
      expect(redactSecrets('{"sid":"$sid","results_count_all":"3"}'), isNot(contains(sid)));
      expect(
        redactSecrets('https://inkbunny.net/api_search.php?output_mode=json&sid=$sid&text=cat'),
        contains('text=cat'),
        reason: 'only the value goes',
      );
    });
  });
}
