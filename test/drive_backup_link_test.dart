import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/services/drive_backup.dart';

/// r42: linking Google Drive did nothing on the device. Google's consent
/// worked, then the token exchange failed with "Failed host lookup:
/// 'oauth2.googleapis.com'" while the browser was in front (a background app's
/// network can be cut), the browser page had already said "linked", and the
/// error was a snackbar behind the browser.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("the token exchange tries Google's other token addresses when one cannot be reached", () async {
    final List<String> tried = [];
    final Map<String, dynamic>? tokens = await DriveBackup.exchange(
      {'code': 'c'},
      retryDelay: Duration.zero,
      post: (String url, Map<String, String> body) async {
        tried.add(Uri.parse(url).host);
        if (url.contains('oauth2.googleapis.com')) throw const SocketException("Failed host lookup: 'oauth2.googleapis.com'");
        return {'refresh_token': 'r'};
      },
    );
    expect(tokens, {'refresh_token': 'r'});
    expect(tried, ['oauth2.googleapis.com', 'www.googleapis.com']);
    expect(DriveBackup.tokenEndpoints.map((u) => Uri.parse(u).host).toSet(), hasLength(3));
  });

  test('an answer from Google (even a refusal) is not asked again elsewhere', () async {
    int calls = 0;
    final Map<String, dynamic>? tokens = await DriveBackup.exchange(
      {'code': 'c'},
      retryDelay: Duration.zero,
      post: (String url, Map<String, String> body) async {
        calls++;
        return null;
      },
    );
    expect(tokens, isNull);
    expect(calls, 1);
  });

  test('when Google cannot be reached at all, the error says what on the phone blocks the app', () async {
    int calls = 0;
    await expectLater(
      DriveBackup.exchange(
        {'code': 'c'},
        retryDelay: Duration.zero,
        post: (String url, Map<String, String> body) async {
          calls++;
          throw const SocketException("Failed host lookup: 'oauth2.googleapis.com'");
        },
      ),
      throwsA(isA<SocketException>()),
    );
    expect(calls, DriveBackup.tokenEndpoints.length * 2, reason: 'every address, twice');
    final String message = DriveBackup.friendlyError(const SocketException("Failed host lookup: 'oauth2.googleapis.com'"));
    expect(message, contains('oauth2.googleapis.com'));
    expect(message, contains('data saver'));
    expect(DriveBackup.friendlyError(Exception('boom')), contains('boom'));
  });

  test('the browser page sends the person back to the app instead of claiming the link is done', () {
    final String page = DriveBackup.landingPageForTests(linked: true);
    expect(page, contains('Go back to LoliSnatcher'));
    expect(page, isNot(contains('is linked')));
  });
}
