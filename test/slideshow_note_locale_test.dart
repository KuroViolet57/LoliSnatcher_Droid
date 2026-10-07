import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const Map<String, String> notes = {
    'ja-JP': '動画とGIFは専用の長めのタイマーを使います。読み込み済みの最後の項目では、検索に続きがあるとき次のページを読み込みます。',
    'ru-RU': 'Видео и GIF используют свой более длинный таймер. На последнем загруженном элементе следующая страница загружается, если в поиске есть ещё.',
    'tr-TR': "Videolar ve GIF'ler kendi daha uzun zamanlayıcılarını kullanır. Yüklenen son öğede, aramada devam varsa sonraki sayfa yüklenir.",
  };
  const Map<String, String> generated = {
    'ja-JP': 'lib/gen/strings_ja_JP.g.dart',
    'ru-RU': 'lib/gen/strings_ru_RU.g.dart',
    'tr-TR': 'lib/gen/strings_tr_TR.g.dart',
  };

  test('the slideshow note matches the viewer in Japanese, Russian, and Turkish', () {
    for (final MapEntry<String, String> entry in notes.entries) {
      final Map<String, dynamic> json =
          jsonDecode(File('assets/i18n/${entry.key}.json').readAsStringSync()) as Map<String, dynamic>;
      final String note = (json['settings'] as Map<String, dynamic>)['viewer']['slideshowWIPNote'] as String;
      expect(note, entry.value, reason: entry.key);
      final String dart = File(generated[entry.key]!).readAsStringSync();
      final String dartNeedle = entry.value.replaceAll("'", r"\'");
      expect(dart.contains(dartNeedle), isTrue, reason: '${entry.key} generated strings');
    }
  });
}
