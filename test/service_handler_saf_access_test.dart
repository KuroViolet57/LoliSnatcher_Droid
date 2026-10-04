import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/platform/service_handler.dart';

/// 1.0: the download-folder warm-up asks Android whether a grant exists
/// (hasSafAccess) instead of testSAF, which opens the folder picker when no
/// grant exists and otherwise writes and deletes a test file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodCall> calls = [];

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      ServiceHandler.platform,
      (MethodCall call) async {
        calls.add(call);
        return reply(call);
      },
    );
  }

  setUp(calls.clear);
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ServiceHandler.platform, null));

  test('asks hasSafAccess with the folder, never testSAF', () async {
    answer((_) => true);
    expect(await ServiceHandler.hasSafAccess('content://tree/primary%3ADownload'), isTrue);
    expect(calls.map((c) => c.method), ['hasSafAccess']);
    expect((calls.single.arguments as Map)['uri'], 'content://tree/primary%3ADownload');
  });

  test('no grant is false', () async {
    answer((_) => false);
    expect(await ServiceHandler.hasSafAccess('content://tree/x'), isFalse);
  });

  test('a failing or missing native side is false, not an exception', () async {
    answer((_) => throw PlatformException(code: 'ERROR'));
    expect(await ServiceHandler.hasSafAccess('content://tree/x'), isFalse);
    answer((_) => null);
    expect(await ServiceHandler.hasSafAccess('content://tree/x'), isFalse);
  });
}
