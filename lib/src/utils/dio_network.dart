// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class DioNetwork {
  DioNetwork._();

  // Status codes that mean "try again in a moment" rather than "this request
  // is broken". Boorus increasingly use 429 (Cloudflare per-IP throttling)
  // and 503 (origin overloaded), and the right user behaviour for both is
  // identical: wait, retry. Doing it once at the network layer means every
  // handler call (search, loadItem, comments, tags...) gets the same self-
  // healing without each one re-implementing it.
  static const List<int> _transientStatusCodes = [429, 503];
  static const int _transientMaxAttempts = 3;

  // Runs the request, retrying up to _transientMaxAttempts times on 429/503.
  // Uses Retry-After (seconds or HTTP-date) when the server provides it,
  // capped at 30s; otherwise 1s/2s/4s exponential backoff. Aborts immediately
  // on cancellation so swiping away cancels the wait too.
  static Future<Response> _withTransientRetries({
    required Future<Response> Function() request,
    required CancelToken? cancelToken,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await request();
      } on DioException catch (e) {
        final int? status = e.response?.statusCode;
        final bool retriable = status != null && _transientStatusCodes.contains(status);
        if (!retriable || CancelToken.isCancel(e) || attempt >= _transientMaxAttempts - 1) {
          rethrow;
        }
        attempt++;
        final Duration delay = _retryDelay(e, attempt);
        try {
          await Future.delayed(delay);
        } catch (_) {}
        if (cancelToken?.isCancelled == true) rethrow;
      }
    }
  }

  static Duration _retryDelay(DioException e, int attempt) {
    final String? raw = e.response?.headers.value('retry-after');
    if (raw != null) {
      final int? seconds = int.tryParse(raw.trim());
      if (seconds != null && seconds > 0 && seconds <= 30) {
        return Duration(seconds: seconds);
      }
      // Some servers send an HTTP-date instead of seconds; best-effort parse.
      try {
        final DateTime when = DateTime.parse(raw.trim());
        final int waitSec = when.difference(DateTime.now()).inSeconds;
        if (waitSec > 0 && waitSec <= 30) return Duration(seconds: waitSec);
      } catch (_) {}
    }
    // Exponential backoff: 1s, 2s, 4s.
    return Duration(seconds: 1 << (attempt - 1));
  }

  // ── shared HTTP client ────────────────────────────────────────────────
  // Previously every request built a fresh Dio + HttpClient and closed it
  // afterwards, throwing away the TCP connection AND the negotiated TLS
  // session — so each request (search, thumbnail, video probe...) paid a
  // full handshake, brutal on slow/keep-alive-friendly boorus. Now a single
  // long-lived HttpClient is shared by every Dio: dart:io pools connections
  // per host and reuses TLS sessions, so back-to-back requests to the same
  // booru skip the handshake entirely. The client is NEVER closed per
  // request (see the callers) — it lives for the app session.
  static HttpClient? _sharedHttpClient;

  static HttpClient get sharedHttpClient {
    final existing = _sharedHttpClient;
    if (existing != null) return existing;
    final client = HttpClient()
      // Keep idle connections warm long enough to be reused while scrolling a
      // grid / paging a feed, without holding sockets open forever.
      ..idleTimeout = const Duration(seconds: 20)
      // A host that never completes the handshake used to leave the viewer on
      // "loading" forever (no request on that path carried any timeout); with
      // this it ends in a named connectionTimeout error with a retry.
      ..connectionTimeout = const Duration(seconds: 30)
      // Bound per-host sockets so a burst of thumbnails can't exhaust fds;
      // dio queues beyond this and reuses as they free up.
      ..maxConnectionsPerHost = 8
      // Reads the live setting on each handshake, so toggling "allow
      // self-signed" takes effect without rebuilding the client.
      ..badCertificateCallback = (_, _, _) => SettingsHandler.instance.allowSelfSignedCerts;
    _sharedHttpClient = client;
    return client;
  }

  static Dio getClient({
    String? baseUrl,
    bool skipLogging = false,
  }) {
    final dio = Dio();

    final settingsHandler = SettingsHandler.instance;

    dio.options.baseUrl = baseUrl ?? '';

    // Reuse the shared, connection-pooling HttpClient (see above). The
    // adapter must NOT close it — closing would tear down every other Dio's
    // pooled connections — so createHttpClient just hands back the singleton.
    // NOTE: the returned Dio must never have close() called on it — its
    // adapter's close() would close the shared HttpClient. Callers below drop
    // the Dio (GC) instead of closing it.
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => sharedHttpClient,
    );

    if (!skipLogging) {
      dio.interceptors.add(Logger.dioInterceptor!);
      dio.interceptors.add(settingsHandler.alice.getDioInterceptor());
    }
    cookieInterceptor(dio);

    return dio;
  }

  static Options mergeOptions(Options? options, Map<String, dynamic>? headers) {
    final usedOptions = options ?? defaultOptions;
    return usedOptions.copyWith(
      headers: {
        ...?headers ?? usedOptions.headers ?? defaultOptions.headers,
      },
    );
  }

  /// used to force alice to intercept query params, because if they are not separate from the url - dio doesn't give them to alice
  static Map<String, dynamic> separateUrlAndQueryParams(String url, Map<String, dynamic>? givenQueryParams) {
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw Exception('Url parsing failed: $url');
    }

    String cleanUrl = temp.replace(queryParameters: {}).toString();
    // Uri.replace with an empty map leaves a dangling '?', and Dio then
    // appends its own params AFTER it — every request went out as
    // `path?&a=b`. Most servers shrug; Cloudflare's WAF documents
    // "malformed data" as a block trigger, and hanime1.me's block page was
    // reproduced with exactly such a URL.
    if (cleanUrl.endsWith('?')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final Map<String, dynamic> queryParams = {
      ...temp.queryParameters,
      ...?givenQueryParams,
    };

    // TODO create a separate class for this?
    return {
      'url': Uri.encodeFull(cleanUrl).replaceAll('%25', '%'),
      'query': queryParams.isEmpty ? null : queryParams,
    };
  }

  static Dio captchaInterceptor(Dio client, {String? customUserAgent}) {
    client.interceptors.add(
      InterceptorsWrapper(
        onResponse: (Response response, ResponseInterceptorHandler handler) async {
          // print('[response]');
          final bool captchaWasDetected = await Tools.checkForCaptcha(
            response,
            response.realUri,
            customUserAgent: customUserAgent,
          );
          if (!captchaWasDetected) {
            return handler.next(response);
          }

          // MERGE, never concatenate — and never join with a bare space.
          // This used to build `'$oldCookie $newCookie'`, where both strings
          // already held the whole jar. The result was every cookie sent two
          // to four times over (7979 bytes in one user's log, with
          // cf_clearance present twice), joined by spaces instead of `; ` so
          // the header was malformed as well. A repeated clearance cookie
          // reads as replay to a bot filter, which is a good way to be handed
          // the very captcha this retry is trying to get past.
          final String oldCookie = response.requestOptions.headers['Cookie'] as String? ?? '';
          final String newCookie = await Tools.getCookies(response.requestOptions.uri.toString());
          // Retire the stale clearance under its own name by KEY, not by
          // substring: replaceAll('cf_clearance', …) also rewrites an
          // existing cf_clearance_old into cf_clearance_old_old.
          final Map<String, String> previous = Tools.parseCookieString(oldCookie);
          final String? staleClearance = previous.remove('cf_clearance');
          if (staleClearance != null) {
            previous['cf_clearance_old'] = staleClearance;
          }
          final headers = {
            ...response.requestOptions.headers,
            'Cookie': Tools.mergeCookieStrings([Tools.buildCookieString(previous), newCookie]),
            Tools.captchaCheckHeader: 'done',
          };

          final opts = Options(
            method: response.requestOptions.method,
            headers: headers,
          );

          try {
            final cloneReq = await client.request(
              response.requestOptions.path,
              options: opts,
              data: response.requestOptions.data,
              queryParameters: response.requestOptions.queryParameters,
            );
            return handler.resolve(cloneReq);
          } catch (e) {
            return handler.next(response);
          }
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          // print('[error]: ${error.message} ${error.response?.statusCode}');
          final bool captchaWasDetected = await Tools.checkForCaptcha(error.response, error.requestOptions.uri);
          if (!captchaWasDetected) {
            return handler.next(error);
          }

          // MERGE, never concatenate — and never join with a bare space.
          // This used to build `'$oldCookie $newCookie'`, where both strings
          // already held the whole jar. The result was every cookie sent two
          // to four times over (7979 bytes in one user's log, with
          // cf_clearance present twice), joined by spaces instead of `; ` so
          // the header was malformed as well. A repeated clearance cookie
          // reads as replay to a bot filter, which is a good way to be handed
          // the very captcha this retry is trying to get past.
          final String oldCookie = error.requestOptions.headers['Cookie'] as String? ?? '';
          final String newCookie = await Tools.getCookies(error.requestOptions.uri.toString());
          // Retire the stale clearance under its own name by KEY, not by
          // substring: replaceAll('cf_clearance', …) also rewrites an
          // existing cf_clearance_old into cf_clearance_old_old.
          final Map<String, String> previous = Tools.parseCookieString(oldCookie);
          final String? staleClearance = previous.remove('cf_clearance');
          if (staleClearance != null) {
            previous['cf_clearance_old'] = staleClearance;
          }
          final headers = {
            ...error.requestOptions.headers,
            'Cookie': Tools.mergeCookieStrings([Tools.buildCookieString(previous), newCookie]),
            Tools.captchaCheckHeader: 'done',
          };

          final opts = Options(
            method: error.requestOptions.method,
            headers: headers,
          );

          try {
            final cloneReq = await client.request(
              error.requestOptions.path,
              options: opts,
              data: error.requestOptions.data,
              queryParameters: error.requestOptions.queryParameters,
            );
            return handler.resolve(cloneReq);
          } catch (e) {
            return handler.next(error);
          }
        },
      ),
    );
    return client;
  }

  static Dio cookieInterceptor(Dio client) {
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
          // Runs on EVERY request, and both sides carry the full jar, so
          // concatenating here doubled the header before anything else even
          // touched it. Merge by name instead (last value wins).
          final String oldCookie = options.headers['Cookie'] as String? ?? '';
          final String newCookie = await Tools.getCookies(options.uri.toString());
          final headers = {
            ...options.headers,
            'Cookie': Tools.mergeCookieStrings([oldCookie, newCookie]),
          };
          options.headers = headers;
          return handler.next(options);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) async {
          final setCookies = response.headers['set-cookie'] ?? [];
          await Tools.saveCookies(
            response.requestOptions.uri.toString(),
            setCookies,
          );
          return handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          final setCookies = error.response?.headers['set-cookie'] ?? [];
          await Tools.saveCookies(
            error.requestOptions.uri.toString(),
            setCookies,
          );
          return handler.next(error);
        },
      ),
    );

    return client;
  }

  static Options get defaultOptions {
    final options = Options(
      responseType: ResponseType.json,
      contentType: 'application/json',
      followRedirects: true,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': Tools.browserUserAgent,
      },
    );
    return options;
  }

  static Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await _withTransientRetries(
      cancelToken: cancelToken,
      request: () => client.get(
        urlAndQuery['url'],
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      ),
    );
    // Shared HttpClient — do NOT close (see getClient).
    return res;
  }

  static Future<Response> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await _withTransientRetries(
      cancelToken: cancelToken,
      request: () => client.post(
        urlAndQuery['url'],
        data: data,
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        onSendProgress: onSendProgress,
      ),
    );
    // Shared HttpClient — do NOT close (see getClient).
    return res;
  }

  static Future<Response> delete(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await _withTransientRetries(
      cancelToken: cancelToken,
      request: () => client.delete(
        urlAndQuery['url'],
        data: data,
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
      ),
    );
    // Shared HttpClient — do NOT close (see getClient).
    return res;
  }

  static Future<Response> head(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await _withTransientRetries(
      cancelToken: cancelToken,
      request: () => client.head(
        urlAndQuery['url'],
        data: data,
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
      ),
    );
    // Shared HttpClient — do NOT close (see getClient).
    return res;
  }

  static Future<Response> download(
    String url,
    String savePath, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    bool deleteOnError = true,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await client.download(
      urlAndQuery['url'],
      savePath,
      data: data,
      queryParameters: urlAndQuery['query'],
      options: mergeOptions(options, headers),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      deleteOnError: deleteOnError,
    );
    // Shared HttpClient — do NOT close (see getClient).
    return res;
  }

  static Future<Response> downloadCustom(
    String url,
    String savePath,
    String fileNameWoutExt,
    String fileExt,
    String mediaType, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    String lengthHeader = Headers.contentLengthHeader,
    bool deleteOnError = true,
    Dio Function(Dio)? customInterceptor,
  }) async {
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    options = DioMixin.checkOptions('GET', mergeOptions(options, headers));
    options.responseType = ResponseType.stream;
    Response<ResponseBody> response;
    try {
      response = await client.request<ResponseBody>(
        urlAndQuery['url'],
        data: data,
        options: options,
        queryParameters: urlAndQuery['query'],
        cancelToken: cancelToken ?? CancelToken(),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        e.response!.data = null;
      }
      rethrow;
    } finally {
      // Shared HttpClient — do NOT close it here; the response body stream is
      // consumed after this block and closing would kill the connection.
    }

    response.headers = Headers.fromMap(response.data!.headers);

    final completer = Completer<Response>();
    Future<Response> future = completer.future;
    int received = 0;

    final stream = response.data!.stream;
    bool compressed = false;
    int total = 0;
    final contentEncoding = response.headers.value(
      Headers.contentEncodingHeader,
    );
    if (contentEncoding != null) {
      compressed = ['gzip', 'deflate', 'compress'].contains(contentEncoding);
    }
    if (lengthHeader == Headers.contentLengthHeader && compressed) {
      total = -1;
    } else {
      total = int.parse(response.headers.value(lengthHeader) ?? '-1');
    }

    final String? fileUri = await ServiceHandler.createFileStreamFromSAFDirectory(
      fileNameWoutExt,
      mediaType,
      fileExt,
      savePath,
    );

    Future<void>? asyncWrite;
    bool closed = false;
    Future<void> closeAndDelete() async {
      if (!closed) {
        closed = true;
        await asyncWrite;
        if (deleteOnError && await ServiceHandler.existsFileStreamFromSAFDirectory(fileUri!)) {
          await ServiceHandler.deleteStreamToFileFromSAFDirectory(fileUri);
        }
      }
    }

    if (fileUri == null) {
      completer.completeError(
        DioMixin.assureDioException(Exception('Error creating saf file'), response.requestOptions),
      );
    }

    late StreamSubscription subscription;
    subscription = stream.listen(
      (data) {
        subscription.pause();

        // Write file asynchronously
        asyncWrite = ServiceHandler.writeStreamToFileFromSAFDirectory(fileUri!, data)
            .then((result) {
              if (!result) {
                throw Exception('Did not write file bytes');
              }

              // Notify progress
              received += data.length;

              onReceiveProgress?.call(received, total);

              if (cancelToken == null || !cancelToken.isCancelled) {
                subscription.resume();
              }
            })
            .catchError((dynamic e, StackTrace s) async {
              try {
                await subscription.cancel();
              } finally {
                completer.completeError(
                  DioMixin.assureDioException(e, response.requestOptions),
                );
              }
            });
      },
      onDone: () async {
        try {
          await asyncWrite;
          closed = true;
          await ServiceHandler.closeStreamToFileFromSAFDirectory(fileUri!);
          completer.complete(response);
        } catch (e) {
          completer.completeError(
            DioMixin.assureDioException(e, response.requestOptions),
          );
        }
      },
      onError: (e, s) async {
        try {
          await closeAndDelete();
        } finally {
          completer.completeError(
            DioMixin.assureDioException(e, response.requestOptions),
          );
        }
      },
      cancelOnError: true,
    );
    unawaited(
      cancelToken?.whenCancel.then((_) async {
        await subscription.cancel();
        await closeAndDelete();
      }),
    );

    final timeout = response.requestOptions.receiveTimeout;
    if (timeout != null) {
      future = future.timeout(timeout).catchError((dynamic e, StackTrace s) async {
        await subscription.cancel();
        await closeAndDelete();
        if (e is TimeoutException) {
          throw DioException.receiveTimeout(
            timeout: timeout,
            requestOptions: response.requestOptions,
          );
        } else {
          throw e;
        }
      });
    }

    return DioMixin.listenCancelForAsyncTask(cancelToken, future);
  }

  static String badResponseExceptionMessage(int? statusCode) {
    if (statusCode == null) {
      return '';
    }

    String message = '';

    switch (statusCode) {
      case 100:
        message = 'Continue';
        break;
      case 101:
        message = 'Switching Protocols';
        break;
      case 102:
        message = 'Processing';
        break;
      case 103:
        message = 'Early Hints';
        break;
      case 200:
        message = 'OK';
        break;
      case 201:
        message = 'Created';
        break;
      case 202:
        message = 'Accepted';
        break;
      case 203:
        message = 'Non-Authoritative Information';
        break;
      case 204:
        message = 'No Content';
        break;
      case 205:
        message = 'Reset Content';
        break;
      case 206:
        message = 'Partial Content';
        break;
      case 207:
        message = 'Multi-Status';
        break;
      case 208:
        message = 'Already Reported';
        break;
      case 226:
        message = 'IM Used';
        break;
      case 300:
        message = 'Multiple Choices';
        break;
      case 301:
        message = 'Moved Permanently';
        break;
      case 302:
        message = 'Found';
        break;
      case 303:
        message = 'See Other';
        break;
      case 304:
        message = 'Not Modified';
        break;
      case 305:
        message = 'Use Proxy';
        break;
      case 307:
        message = 'Temporary Redirect';
        break;
      case 308:
        message = 'Permanent Redirect';
        break;
      case 400:
        message = 'Bad Request';
        break;
      case 401:
        message = 'Unauthorized';
        break;
      case 402:
        message = 'Payment Required';
        break;
      case 403:
        message = 'Forbidden';
        break;
      case 404:
        message = 'Not Found';
        break;
      case 405:
        message = 'Method Not Allowed';
        break;
      case 406:
        message = 'Not Acceptable';
        break;
      case 407:
        message = 'Proxy Authentication Required';
        break;
      case 408:
        message = 'Request Timeout';
        break;
      case 409:
        message = 'Conflict';
        break;
      case 410:
        message = 'Gone';
        break;
      case 411:
        message = 'Length Required';
        break;
      case 412:
        message = 'Precondition Failed';
        break;
      case 413:
        message = 'Payload Too Large';
        break;
      case 414:
        message = 'URI Too Long';
        break;
      case 415:
        message = 'Unsupported Media Type';
        break;
      case 416:
        message = 'Range Not Satisfiable';
        break;
      case 417:
        message = 'Expectation Failed';
        break;
      case 418:
        message = "I'm a teapot";
        break;
      case 421:
        message = 'Misdirected Request';
        break;
      case 422:
        message = 'Unprocessable Entity';
        break;
      case 423:
        message = 'Locked';
        break;
      case 424:
        message = 'Failed Dependency';
        break;
      case 425:
        message = 'Too Early';
        break;
      case 426:
        message = 'Upgrade Required';
        break;
      case 428:
        message = 'Precondition Required';
        break;
      case 429:
        message = 'Too Many Requests';
        break;
      case 431:
        message = 'Request Header Fields Too Large';
        break;
      case 444:
        message = 'No Response';
        break;
      case 451:
        message = 'Unavailable For Legal Reasons';
        break;
      case 499:
        message = 'Client Closed Request';
        break;
      case 500:
        message = 'Internal Server Error';
        break;
      case 501:
        message = 'Not Implemented';
        break;
      case 502:
        message = 'Bad Gateway';
        break;
      case 503:
        message = 'Service Unavailable';
        break;
      case 504:
        message = 'Gateway Timeout';
        break;
      case 505:
        message = 'HTTP Version Not Supported';
        break;
      case 506:
        message = 'Variant Also Negotiates';
        break;
      case 507:
        message = 'Insufficient Storage';
        break;
      case 508:
        message = 'Loop Detected';
        break;
      case 510:
        message = 'Not Extended';
        break;
      case 511:
        message = 'Network Authentication Required';
        break;
      case 599:
        message = 'Network Connect Timeout';
        break;
      default:
        message = '';
        break;
    }

    message += '\n';

    if (statusCode >= 100 && statusCode < 200) {
      message += 'This is an informational response - the request was received, continuing processing';
    } else if (statusCode >= 200 && statusCode < 300) {
      message += 'The request was successful';
    } else if (statusCode >= 300 && statusCode < 400) {
      message += 'Redirection: further action needs to be taken in order to complete the request';
    } else if (statusCode >= 400 && statusCode < 500) {
      message += 'Error - the request contains bad syntax or cannot be fulfilled';
    } else if (statusCode >= 500 && statusCode < 600) {
      message += 'Server error - the server failed to fulfill a request';
    } else {
      message += 'Unknown error';
    }

    return message;
  }
}
