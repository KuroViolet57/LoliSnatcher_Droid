import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// Strips credentials out of anything on its way into a log or a capture.
///
/// Logs get shared. A talker export sent to a developer carried this install's
/// aibooru and AllTheFallen API keys, its login, and complete Danbooru session
/// cookies, in plain text, dozens of times over. None of that is needed to
/// diagnose anything, and a log is a file that gets pasted into chats and
/// issue trackers.
String redactSecrets(String input, {List<String>? extraSecrets}) {
  if (input.isEmpty) return input;
  String out = input;

  // Query parameters that carry credentials. `login` is included because it is
  // half of a Danbooru-style api_key pair.
  for (final name in const [
    'api_key',
    'apikey',
    'apiKey',
    'password',
    'password_hash',
    'passwordSalt',
    'access_token',
    'refresh_token',
    'token',
    'login',
    'user_id',
    'userId',
  ]) {
    // replaceAllMapped, not replaceAll: Dart does not expand `\$1` in a
    // replaceAll replacement, so that form writes a literal over the text
    // being kept.
    out = out.replaceAllMapped(
      RegExp('(${RegExp.escape(name)}=)[^&\\s,}\\]"]+'),
      (m) => '${m.group(1)}<redacted>',
    );
  }

  // Named cookie values, wherever they are spelled out.
  for (final name in const [
    'cf_clearance',
    'cf_bm',
    '__cf_bm',
    'session',
    'sessionid',
    'session_id',
    '_danbooru2_session',
    'PHPSESSID',
    'csrftoken',
    'csrf_token',
    'access_token',
    'refresh_token',
    'remember_web',
    'auth_token',
  ]) {
    out = out.replaceAllMapped(
      RegExp('(${RegExp.escape(name)}\\s*[=:]\\s*"?)[^;,"\\s&]+', caseSensitive: false),
      (m) => '${m.group(1)}<redacted>',
    );
  }

  // A whole Cookie HEADER, to catch cookie names this list has never heard of.
  //
  // The lookbehind keeps it off `document.cookie="cf_clearance=..."`, which is
  // a page assigning one cookie: the named rules above have already redacted
  // its value, and matching here would swallow the cookie's NAME too and make
  // the capture harder to read.
  out = out.replaceAllMapped(
    RegExp(r'(?<![.\w])((?:Cookie|Set-Cookie)"?\s*[:=]\s*"?)([^"}\n]{8,})', caseSensitive: false),
    (m) => '${m.group(1)}<redacted>',
  );

  // Bearer / Key / Basic headers echoed into a page or a payload.
  out = out.replaceAllMapped(
    RegExp(r'((?:Bearer|Key|Basic|Token)\s+)[A-Za-z0-9._\-+/=]{8,}', caseSensitive: false),
    (m) => '${m.group(1)}<redacted>',
  );

  // Every credential this install has configured, for any booru.
  final List<String> secrets = [...?extraSecrets];
  try {
    for (final booru in SettingsHandler.instance.booruList) {
      // defTags is in here because a Booru's fifth positional field is
      // defTags, and installs put credentials there for sites that take them
      // as search parameters. Dropping it silently un-redacted them.
      for (final value in [booru.apiKey, booru.userID, booru.defTags]) {
        if (value != null && value.trim().length >= 4) secrets.add(value.trim());
      }
    }
  } catch (_) {
    // Settings unavailable (tests, early startup); the rules above still apply.
  }
  for (final secret in secrets.toSet()) {
    if (secret.length < 4) continue;
    out = out.replaceAll(secret, '<redacted>');
  }

  return out;
}
