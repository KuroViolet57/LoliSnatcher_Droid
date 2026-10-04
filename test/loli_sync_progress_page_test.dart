import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/sync/ui/loli_sync_progress_page.dart';

/// Settings → LoliSync → receive: the page that runs the receiving server and
/// shows what arrives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  Future<int> freePort(WidgetTester tester) async {
    final int? port = await tester.runAsync(() async {
      final ServerSocket s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int p = s.port;
      await s.close();
      return p;
    });
    return port!;
  }

  Future<void> open(WidgetTester tester, int port) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20))),
          home: LoliSyncProgressPage(type: 'receiver', ip: '127.0.0.1', port: '$port'),
        ),
      ),
    );
  }

  /// The server uses real sockets: the event loop runs, then a frame.
  Future<void> waitFor(WidgetTester tester, bool Function() done, {int rounds = 150}) async {
    for (int i = 0; i < rounds && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<bool> listening(WidgetTester tester, int port) async {
    final bool? answer = await tester.runAsync(() async {
      try {
        final Socket s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 3));
        s.destroy();
        return true;
      } on SocketException {
        return false;
      }
    });
    return answer!;
  }

  /// A sender's request on a raw socket (the test binding stubs HttpClient).
  Future<Socket> send(WidgetTester tester, int port, String path) async {
    final Socket? socket = await tester.runAsync(() async {
      final Socket s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 3));
      s.write('POST $path HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
      await s.flush();
      return s;
    });
    return socket!;
  }

  testWidgets('1.0: the receiver stops listening when its page goes away without the stop dialog', (tester) async {
    final int port = await freePort(tester);
    await open(tester, port);
    await waitFor(tester, () => find.textContaining('Server active at').evaluate().isNotEmpty);
    expect(find.textContaining('Server active at'), findsOneWidget);
    expect(await listening(tester, port), isTrue);

    // Something else removes the route (a popUntil, a reset of the app).
    await tester.pumpWidget(const SizedBox.shrink());
    await waitFor(tester, () => false, rounds: 10);

    expect(await listening(tester, port), isFalse, reason: 'it would keep taking settings, sources and tabs from the network');
    await waitFor(tester, () => false, rounds: 10);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
