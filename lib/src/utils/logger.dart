import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/widgets/common/compact_error_widget.dart';
import 'package:lolisnatcher/src/utils/log_redaction.dart';
import 'package:talker/talker.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
// ignore: implementation_imports
import 'package:talker_flutter/src/controller/talker_view_controller.dart';

class Logger {
  static Logger? _loggerInstance;

  // ignore: non_constant_identifier_names
  static Logger Inst() {
    final bool isInit = _loggerInstance == null;

    _loggerInstance ??= Logger();
    _talkerInstance ??= Talker(
      settings: TalkerSettings(
        enabled: true,
        maxHistoryItems: 10000,
        useConsoleLogs: kDebugMode,
        useHistory: true,
      ),
      logger: TalkerLogger(
        output: (String message) {
          final StringBuffer buffer = StringBuffer();
          final lines = message.split('\n');
          lines.forEach(buffer.writeln);
          Platform.isIOS ? lines.forEach(print) : dev.log(buffer.toString());
        },
      ),
    );

    viewController ??= TalkerViewController(talker: talker)..toggleExpandedLogs();

    if (isInit) {
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exception is DioException && CancelToken.isCancel(details.exception as DioException)) {
          // ignore exceptions caused by cancelling dio requests (mostly for image loading)
          return;
        }
        FlutterError.presentError(details);

        Logger.Inst().log(
          '$details',
          'FlutterError',
          'onError',
          LogTypes.exception,
          s: details.stack,
        );
      };

      // Set custom compact ErrorWidget builder to prevent layout breakage
      ErrorWidget.builder = CompactErrorWidget.builder;

      PlatformDispatcher.instance.onError = (error, stack) {
        Logger.Inst().log(
          error,
          'PlatformDispatcherError',
          'onError',
          LogTypes.exception,
          s: stack,
        );
        return true;
      };
    }

    return _loggerInstance!;
  }

  static Talker? _talkerInstance;

  static Talker get talker => _talkerInstance!;

  static TalkerViewController? viewController;

  void log(
    dynamic object,
    String callerClass,
    String callerFunction,
    LogTypes? logType, {
    StackTrace? s,
  }) {
    String logStr = '';
    try {
      logStr = object is String ? object : '$object';
    } catch (_) {
      logStr = object.runtimeType.toString();
    }

    // Credentials never belong in a log. A shared export carried this
    // install's API keys, its login and complete session cookies in plain
    // text, dozens of times over, because every request line is logged whole.
    try {
      logStr = redactSecrets(logStr);
    } catch (_) {
      // Redaction must never be the reason a log line is lost.
    }

    if (logStr.length > 10000) {
      logStr = '${logStr.substring(0, 10000)}...';
    }

    final logLevel = logType?.logLevel ?? LogLevel.wtf;
    if (logLevel == LogLevel.info) {
      _talkerInstance?.info(logStr, null, s);
    } else if (logLevel == LogLevel.error) {
      _talkerInstance?.error(logStr, null, s);
    } else if (logLevel == LogLevel.warning) {
      _talkerInstance?.warning(logStr, null, s);
    } else if (logLevel == LogLevel.debug) {
      _talkerInstance?.debug(logStr, null, s);
    } else if (logLevel == LogLevel.verbose) {
      _talkerInstance?.verbose(logStr, null, s);
    } else if (logLevel == LogLevel.wtf) {
      _talkerInstance?.verbose(logStr, null, s);
    } else {
      _talkerInstance?.verbose(logStr, null, s);
    }
  }

  /// r80: a long text (a trace report) into the log whole. [log] cuts an
  /// entry at 10,000 characters, so it goes in numbered parts, cut at a line
  /// end where one falls in a part's second half. Redacted once, whole,
  /// before it is cut: a secret split between two parts would slip past.
  void logParts(
    String text,
    String callerClass,
    String callerFunction,
    LogTypes? logType, {
    required String title,
    int partChars = 9000,
  }) {
    String body = text;
    try {
      body = redactSecrets(text);
    } catch (_) {}
    final List<String> parts = splitParts(body, partChars);
    for (int i = 0; i < parts.length; i++) {
      log('$title (part ${i + 1}/${parts.length})\n${parts[i]}', callerClass, callerFunction, logType);
    }
  }

  /// [text] in pieces of at most [max] characters; joined, they are [text].
  static List<String> splitParts(String text, int max) {
    if (text.isEmpty) return const [''];
    final List<String> out = [];
    int start = 0;
    while (start < text.length) {
      int end = math.min(start + max, text.length);
      if (end < text.length) {
        final int lineEnd = text.lastIndexOf('\n', end - 1);
        if (lineEnd >= start + max ~/ 2) end = lineEnd + 1;
      }
      out.add(text.substring(start, end));
      start = end;
    }
    return out;
  }

  /// r69: the one line the app writes about a request body, built redacted.
  /// The Dio logger's own "Data:" dump printed an eahentai login's username
  /// and password in clear, so it is off and this stands in for it.
  static String requestDataLine({required String method, required String url, required dynamic data}) {
    String body;
    try {
      body = data is String ? data : jsonEncode(data);
    } catch (_) {
      body = data.toString();
    }
    // Redacted first: a cut through a secret would leave half of it in a
    // shape the rules cannot recognise.
    String line = redactSecrets('$method $url data: $body');
    if (line.length > 2200) line = '${line.substring(0, 2200)}...';
    return line;
  }

  /// Logs request bodies through [requestDataLine]; GETs carry none.
  static Interceptor get requestDataInterceptor => InterceptorsWrapper(
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
      if (options.data != null) {
        Logger.Inst().log(
          requestDataLine(method: options.method, url: options.uri.toString(), data: options.data),
          'DioNetwork',
          'request',
          LogTypes.booruHandlerInfo,
        );
      }
      handler.next(options);
    },
  );

  static TalkerDioLogger? get dioInterceptor => _talkerInstance != null
      ? TalkerDioLogger(
          talker: _talkerInstance,
          settings: const TalkerDioLoggerSettings(
            // The header dumps are where whole session cookies and bearer
            // tokens ended up; the body dump carried a login's password
            // (r69), so it is written by requestDataInterceptor instead.
            hiddenHeaders: {'cookie', 'set-cookie', 'authorization', 'x-api-key'},
            printResponseData: false,
            printRequestData: false,
            printErrorData: true,
            printResponseHeaders: true,
            printRequestHeaders: true,
            printErrorHeaders: true,
            printResponseMessage: true,
            printErrorMessage: true,
          ),
        )
      : null;
}

// TODO more types
enum LogTypes {
  booruHandlerFetchFailed,
  booruHandlerInfo,
  booruHandlerParseFailed,
  booruHandlerRawFetched,
  booruHandlerSearchURL,
  booruHandlerTagInfo,
  booruItemLoad,
  exception,
  imageInfo,
  imageLoadingError,
  loliSyncInfo,
  networkError,
  settingsError,
  settingsLoad,
  tagHandlerInfo,
  ;

  @override
  String toString() {
    return name;
  }

  static LogTypes fromString(String str) {
    return LogTypes.values.firstWhere((element) => element.name == str, orElse: () => LogTypes.exception);
  }

  LogLevel get logLevel {
    switch (this) {
      case LogTypes.booruHandlerFetchFailed:
      case LogTypes.booruHandlerParseFailed:
      case LogTypes.exception:
      case LogTypes.imageLoadingError:
      case LogTypes.networkError:
      case LogTypes.settingsError:
        return LogLevel.error;
      //
      case LogTypes.booruHandlerInfo:
      case LogTypes.booruHandlerRawFetched:
      case LogTypes.booruHandlerSearchURL:
      case LogTypes.booruHandlerTagInfo:
      case LogTypes.booruItemLoad:
      case LogTypes.imageInfo:
      case LogTypes.loliSyncInfo:
      case LogTypes.settingsLoad:
      case LogTypes.tagHandlerInfo:
        return LogLevel.info;
      // ignore: unreachable_switch_default
      default:
        return LogLevel.wtf;
    }
  }
}

enum LogLevel {
  info,
  warning,
  error,
  debug,
  verbose,
  wtf,
}
