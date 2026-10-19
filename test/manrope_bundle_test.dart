import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hashes and lengths copied from google_fonts 8.2.1 `PartM.manrope`.
/// The files are the bytes at fonts.gstatic.com/s/a/<hash>.ttf.
const Map<String, (String, int)> _manropeFiles = <String, (String, int)>{
  'assets/google_fonts/Manrope-ExtraLight.ttf': (
    'cf40c4c0abb2d5f04e0128d022f23216f2fc4d8094f928214fddb01f9810585f',
    94848,
  ),
  'assets/google_fonts/Manrope-Light.ttf': (
    '7f3d91d5b90f10d26b82559d7bdd4f5acab7be00fc87f5279106687e45a08cfa',
    94856,
  ),
  'assets/google_fonts/Manrope-Regular.ttf': (
    'be2c40a58fbf6c664a5103f086beaad13008d72dc642b82cc214feaaac3b4512',
    94948,
  ),
  'assets/google_fonts/Manrope-Medium.ttf': (
    'f85a9b09c9449d2093b67354ac5894890891fa31daf02c470f0d4206b1e03f2d',
    95036,
  ),
  'assets/google_fonts/Manrope-SemiBold.ttf': (
    '126493d07336a0628d130d7a865098475284fa94364fc4ae76fb689278bbbd93',
    95072,
  ),
  'assets/google_fonts/Manrope-Bold.ttf': (
    'f5e0482988eb686e8fa2f6bcf586f627ff39c1e9305adc90ae07edc4130ab378',
    94904,
  ),
  'assets/google_fonts/Manrope-ExtraBold.ttf': (
    '574157e96dcb3b1dd593f4fd26d62a752b395f6ab94984d1a23ed7570e5391ee',
    95664,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Manrope ships in the app and loads with runtime fetching off', () async {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('google_fonts: ^8.0.2'));

    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);

    for (final MapEntry<String, (String, int)> entry in _manropeFiles.entries) {
      final ByteData data = await rootBundle.load(entry.key);
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(bytes.length, entry.value.$2, reason: entry.key);
      expect(sha256.convert(bytes).toString(), entry.value.$1, reason: entry.key);
    }

    final String license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    expect(license, contains('SIL Open Font License'));
    expect(license, contains('Manrope'));

    expect(GoogleFonts.getFont('Manrope').fontFamily, 'Manrope_regular');
    expect(
      GoogleFonts.getFont('Manrope', fontWeight: FontWeight.w200).fontFamily,
      'Manrope_200',
    );
    expect(
      GoogleFonts.getFont('Manrope', fontWeight: FontWeight.w700).fontFamily,
      'Manrope_700',
    );
    await GoogleFonts.pendingFonts();
  });
}
