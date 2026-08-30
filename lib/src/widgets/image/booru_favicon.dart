import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/preview/shimmer_builder.dart';

/// Per-HOST favicon resolution, shared by every [BooruFavicon] in the app.
///
/// Not every site serves `/favicon.ico` — nhentai answers it with a real 404,
/// which used to leave a red error tile everywhere its icon appears. Each
/// host is therefore tried against a chain of candidates and the winner is
/// remembered, so the fallbacks are probed ONCE per host rather than on every
/// render:
///
///   1. the site's own favicon
///   2. `https://icons.duckduckgo.com/ip3/<host>.ico`
///   3. a generated letter tile (no network at all)
class FaviconResolver {
  const FaviconResolver._();

  /// host -> the candidate URL that actually loaded.
  static final Map<String, String> _working = {};

  /// Hosts where every candidate failed: render the letter tile straight away.
  static final Set<String> _letterTile = {};

  static String hostOf(String url) => Uri.tryParse(url)?.host ?? '';

  /// DuckDuckGo's icon service, which resolves icons for sites that don't
  /// serve a usable favicon.ico of their own.
  static String duckDuckGoUrlFor(String host) => 'https://icons.duckduckgo.com/ip3/$host.ico';

  /// The candidate chain for [url], best first. Empty when there's nothing to
  /// try (no URL, or the host is already known to have none).
  static List<String> candidatesFor(String url) {
    final String host = hostOf(url);
    if (url.isEmpty || host.isEmpty) return const [];
    if (_letterTile.contains(host)) return const [];

    final String? known = _working[host];
    if (known != null) return [known];

    final String ddg = duckDuckGoUrlFor(host);
    return [url, if (ddg != url) ddg];
  }

  static bool usesLetterTile(String url) {
    final String host = hostOf(url);
    return host.isNotEmpty && _letterTile.contains(host);
  }

  /// Records that [workingUrl] loaded for the source whose own icon URL is
  /// [baseUrl]. Keyed by the SOURCE's host, never the candidate's: the
  /// DuckDuckGo fallback lives on icons.duckduckgo.com, so keying by the
  /// candidate would file every site's fallback under one shared key — each
  /// would then be handed the previous site's icon.
  static void rememberWorking(String baseUrl, String workingUrl) {
    final String host = hostOf(baseUrl);
    if (host.isEmpty) return;
    _working[host] = workingUrl;
    _letterTile.remove(host);
  }

  static void rememberNone(String baseUrl) {
    final String host = hostOf(baseUrl);
    if (host.isEmpty) return;
    _working.remove(host);
    _letterTile.add(host);
  }

  /// Forgets what is known about [url]'s host, so a manual retry probes the
  /// whole chain again.
  static void forget(String url) {
    final String host = hostOf(url);
    if (host.isEmpty) return;
    _working.remove(host);
    _letterTile.remove(host);
  }

  @visibleForTesting
  static void resetForTests() {
    _working.clear();
    _letterTile.clear();
  }
}

/// The last resort: the source's initial on a colour derived from its host,
/// so a site with no usable icon still gets a stable, recognisable mark
/// instead of a broken-image glyph.
class FaviconLetterTile extends StatelessWidget {
  const FaviconLetterTile({
    required this.size,
    this.label,
    this.host,
    super.key,
  });

  final double size;
  final String? label;
  final String? host;

  static const List<Color> _palette = [
    Color(0xFF6C8EBF),
    Color(0xFFB07AA1),
    Color(0xFF77A97C),
    Color(0xFFD08A5D),
    Color(0xFF7C7BB5),
    Color(0xFF4F9C9C),
    Color(0xFFC2687B),
    Color(0xFF8A8F5C),
  ];

  static Color colourFor(String seed) {
    if (seed.isEmpty) return _palette.first;
    int hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return _palette[hash % _palette.length];
  }

  static String letterFor(String? label, String? host) {
    for (final source in [label, host]) {
      final String trimmed = (source ?? '').trim();
      if (trimmed.isEmpty) continue;
      // Skip a leading "www." so the letter is the site's own initial.
      final String cleaned = trimmed.startsWith('www.') ? trimmed.substring(4) : trimmed;
      if (cleaned.isEmpty) continue;
      return cleaned.characters.first.toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final String seed = (host?.isNotEmpty ?? false) ? host! : (label ?? '');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: colourFor(seed),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * 0.15),
          child: Text(
            letterFor(label, host),
            style: TextStyle(
              fontSize: size * 0.7,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class BooruFavicon extends StatefulWidget {
  const BooruFavicon(
    this.booru, {
    this.size = defaultSize,
    this.color,
    this.customFaviconUrl,
    super.key,
  });

  final Booru? booru;
  final double size;
  final Color? color;
  final String? customFaviconUrl;

  static const double defaultSize = 20;

  @override
  State<BooruFavicon> createState() => _BooruFaviconState();
}

class _BooruFaviconState extends State<BooruFavicon> {
  bool isIcon = false, isFailed = false, isLoaded = false, manualReloadTapped = false;
  CancelToken? cancelToken;
  ImageProvider? mainProvider;
  ImageStream? imageStream;
  late ImageStreamListener imageListener;
  String? errorCode;

  /// The fallback chain for this host (see [FaviconResolver]) and where we
  /// are in it. When it runs out, the letter tile takes over.
  List<String> _candidates = const [];
  int _candidateIndex = 0;
  bool _useLetterTile = false;

  double get size => widget.size;

  /// The source's configured icon URL — the first candidate.
  String get _baseUrl => widget.booru?.faviconURL ?? widget.customFaviconUrl ?? '';

  String get _currentUrl => _candidateIndex < _candidates.length ? _candidates[_candidateIndex] : '';

  @override
  void didUpdateWidget(BooruFavicon oldWidget) {
    // force redraw on tab change
    if (oldWidget.booru?.faviconURL != widget.booru?.faviconURL ||
        oldWidget.customFaviconUrl != widget.customFaviconUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        restartLoading();
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<ImageProvider> getImageProvider() async {
    cancelToken ??= CancelToken();
    final String url = _currentUrl;
    final bool isAvif = url.contains('.avif');
    return ResizeImage(
      isAvif
          ? CustomNetworkAvifImage(
              url,
              withCache: true,
              headers: await Tools.getFileCustomHeaders(widget.booru),
              cacheFolder: 'favicons',
              fileNameExtras: 'favicon_',
              cancelToken: cancelToken,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              onError: onError,
            )
          : CustomNetworkImage(
              url,
              withCache: true,
              headers: await Tools.getFileCustomHeaders(widget.booru),
              cacheFolder: 'favicons',
              fileNameExtras: 'favicon_',
              cancelToken: cancelToken,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              onError: onError,
            ),
      width: (size * 5).toInt(),
      height: (size * 5).toInt(),
    );
  }

  /// Moves to the next candidate in the chain, or settles on the letter tile
  /// when there is none left. Returns true when it took over the failure.
  bool _advanceCandidate() {
    if (!mounted) return false;
    if (_candidateIndex < _candidates.length - 1) {
      _candidateIndex++;
      isFailed = false;
      errorCode = null;
      // The provider is rebuilt for the next URL.
      mainProvider = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) restartLoadingCurrentChain();
      });
      return true;
    }
    if (_baseUrl.isNotEmpty) {
      // Nothing in the chain loaded: this host has no usable icon.
      FaviconResolver.rememberNone(_baseUrl);
      _useLetterTile = true;
      isLoaded = true;
      isFailed = false;
      updateState();
      return true;
    }
    return false;
  }

  /// Reloads the image for the CURRENT candidate without rebuilding the chain
  /// (which would send us back to the candidate that just failed).
  Future<void> restartLoadingCurrentChain() async {
    if (mounted) {
      await mainProvider?.evict();
    }
    disposables();
    mainProvider = await getImageProvider();
    imageStream?.removeListener(imageListener);
    imageStream = mainProvider!.resolve(ImageConfiguration.empty);
    imageListener = ImageStreamListener(
      (imageInfo, syncCall) {
        isLoaded = true;
        FaviconResolver.rememberWorking(_baseUrl, _currentUrl);
        if (!syncCall) updateState();
      },
      onError: (e, s) {
        if (_advanceCandidate()) return;
        onError(e);
      },
    );
    imageStream?.addListener(imageListener);
    updateState();
  }

  Future<void> onError(Object error) async {
    //// Error handling
    if (error is DioException && CancelToken.isCancel(error)) {
      //
    } else {
      if (error is Exception && (error as dynamic).message == 'Invalid image data') {
        final provider = (mainProvider! as ResizeImage).imageProvider;
        switch (provider) {
          case CustomNetworkImage _:
            await provider.deleteCacheFile();
            break;
          case CustomNetworkAvifImage _:
            await provider.deleteCacheFile();
            break;
        }
        disposables();
      }
      if (error is DioException &&
          error.response != null &&
          Tools.isGoodStatusCode(error.response!.statusCode) == false) {
        if (manualReloadTapped && (error.response!.statusCode == 403 || error.response!.statusCode == 503)) {
          await Tools.checkForCaptcha(error.response, error.requestOptions.uri);
          unawaited(restartLoading());
          manualReloadTapped = false;
        }
        errorCode = error.response!.statusCode.toString();
      }

      isFailed = true;
      Future.delayed(const Duration(milliseconds: 300), updateState);
    }
  }

  @override
  void initState() {
    super.initState();
    imageListener = ImageStreamListener((imageInfo, syncCall) {});
    restartLoading();
  }

  void updateState() {
    if (mounted) setState(() {});
  }

  Future<void> restartLoading() async {
    if (mounted) {
      await mainProvider?.evict();
    }
    disposables();

    isIcon =
        widget.booru?.type?.isFavouritesOrDownloads == true ||
        (widget.booru?.type == null && widget.customFaviconUrl == null);

    isFailed = false;
    errorCode = null;

    // Work out this host's candidate chain. A host already known to have no
    // usable icon goes straight to the letter tile, with no request at all.
    final String base = _baseUrl;
    _candidates = FaviconResolver.candidatesFor(base);
    _candidateIndex = 0;
    _useLetterTile = !isIcon && base.isNotEmpty && _candidates.isEmpty;

    updateState();

    if (isIcon || _useLetterTile) {
      isLoaded = true;
      updateState();
    } else {
      mainProvider ??= await getImageProvider();

      imageStream?.removeListener(imageListener);

      imageStream = mainProvider!.resolve(ImageConfiguration.empty);
      imageListener = ImageStreamListener(
        (imageInfo, syncCall) {
          isLoaded = true;
          // Remember which candidate worked, so every other icon for this
          // host starts there instead of re-probing the chain.
          FaviconResolver.rememberWorking(_baseUrl, _currentUrl);
          if (!syncCall) {
            updateState();
          }
        },
        onError: (e, s) {
          Logger.Inst().log(
            'Failed to load favicon: $_currentUrl',
            'Favicon',
            'build',
            LogTypes.imageLoadingError,
            s: s,
          );
          if (_advanceCandidate()) return;
          onError(e);
        },
      );
      imageStream?.addListener(imageListener);

      updateState();
    }
  }

  @override
  void dispose() {
    disposables();
    super.dispose();
  }

  void disposables() {
    imageStream?.removeListener(imageListener);
    imageStream = null;
    imageListener = ImageStreamListener((imageInfo, syncCall) {});

    mainProvider = null;

    if (!(cancelToken != null && cancelToken!.isCancelled)) {
      cancelToken?.cancel();
    }
    cancelToken = null;
  }

  @override
  Widget build(BuildContext context) {
    // print('Favicon build ${widget.faviconURL}');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(size / 5),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isIcon)
            switch (widget.booru?.type) {
              BooruType.Favourites => Icon(Symbols.favorite_rounded, color: Colors.red, size: size),
              BooruType.Downloads => Icon(Symbols.file_download_rounded, size: size),
              _ => Icon(CupertinoIcons.question, size: size),
            }
          // Nothing in the chain loaded for this host: a generated tile, not
          // a broken-image glyph.
          else if (_useLetterTile)
            GestureDetector(
              onTap: () {
                // A manual tap re-probes the whole chain for this host.
                manualReloadTapped = true;
                FaviconResolver.forget(_baseUrl);
                restartLoading();
              },
              child: FaviconLetterTile(
                size: size,
                // A source added without a name — which is easy to do, the
                // field is optional — used to leave both of these empty and
                // render a bare "?" on every card. The type's own name and the
                // site's address are always there to fall back on.
                label: widget.booru?.name?.isNotEmpty == true
                    ? widget.booru!.name
                    : widget.booru?.type?.alias,
                host: FaviconResolver.hostOf(_baseUrl).isNotEmpty
                    ? FaviconResolver.hostOf(_baseUrl)
                    : FaviconResolver.hostOf(widget.booru?.baseURL ?? ''),
              ),
            )
          else if (mainProvider != null)
            Image(
              image: mainProvider!,
              width: size,
              height: size,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              errorBuilder: (_, _, _) {
                return FaviconError(
                  iconSize: size,
                  color: widget.color ?? Theme.of(context).colorScheme.onSurface,
                  code: errorCode,
                  onRestart: () {
                    manualReloadTapped = true;
                    FaviconResolver.forget(_baseUrl);
                    restartLoading();
                  },
                );
              },
            )
          else if (isFailed)
            FaviconError(
              iconSize: size,
              color: Colors.grey,
              code: errorCode,
              onRestart: () {
                manualReloadTapped = true;
                FaviconResolver.forget(_baseUrl);
                restartLoading();
              },
            ),
          //
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: (isLoaded || isFailed)
                ? const SizedBox.shrink()
                : ShimmerWrap(
                    enabled: !SettingsHandler.instance.shitDevice,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(size / 5),
                      child: ShimmerCard(
                        isLoading: !isLoaded && !isFailed,
                        child: !isLoaded && !isFailed ? null : const SizedBox.shrink(),
                      ),
                    ),
                  ),
          ),

          // Image(
          //   image: NetworkImage(widget.booru.faviconURL!),
          //   width: size,
          //   height: size,
          //   errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
          //     return const Icon(Symbols.broken_image_rounded, size: size);
          //   },
          // ),
        ],
      ),
    );
  }
}

class FaviconError extends StatelessWidget {
  const FaviconError({
    this.iconSize = BooruFavicon.defaultSize,
    this.color = Colors.grey,
    this.code,
    this.onRestart,
    super.key,
  });

  final double iconSize;
  final Color color;
  final String? code;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onRestart,
        child: Stack(
          children: [
            Center(
              child: Icon(
                Symbols.broken_image_rounded,
                size: iconSize,
                color: color,
              ),
            ),
            if (code != null)
              Center(
                child: FittedBox(
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      code!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
