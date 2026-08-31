import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/source_capture_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// A developer tool for adding support for a site the build machine cannot
/// reach.
///
/// A site behind a bot filter answers a plain HTTP request with a challenge
/// page, so its real markup is invisible from anywhere without a browser and a
/// human — and a handler written without seeing that markup is a guess. This
/// app already solves such challenges in a webview and keeps the clearance
/// cookie, so on a real device it CAN see the site. This page records what it
/// sees into a single file.
///
/// Three things get recorded:
///   * the rendered HTML of every page visited,
///   * every URL the page asked for — which is how an otherwise invisible API
///     announces itself,
///   * and, on request, the actual response bodies of those URLs, fetched
///     afterwards through the app's own HTTP stack so they carry the cookies
///     the webview earned.
class SourceCapturePage extends StatefulWidget {
  const SourceCapturePage({super.key});

  @override
  State<SourceCapturePage> createState() => _SourceCapturePageState();
}

class _SourceCapturePageState extends State<SourceCapturePage> {
  final SourceCaptureHandler capture = SourceCaptureHandler.instance;
  final TextEditingController urlController = TextEditingController();

  bool busy = false;

  bool recovered = false;

  @override
  void initState() {
    super.initState();
    // A session interrupted by the app being killed is still on disk. Pick it
    // up before anything else, so a browse that took ten minutes is not lost
    // to a restart the person never asked for.
    if (capture.entries.isEmpty && capture.hasRecoverableSession) {
      unawaited(_recover());
    }
    urlController.text = capture.target.isEmpty ? 'https://' : capture.target;
  }

  Future<void> _recover() async {
    final int skipped = await capture.restoreSession();
    if (!mounted) return;
    setState(() {
      recovered = true;
      urlController.text = capture.target.isEmpty ? 'https://' : capture.target;
    });
    if (capture.entries.isEmpty) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        'Recovered ${capture.pageCount} pages from an interrupted capture'
        '${skipped > 0 ? ' ($skipped damaged entries dropped)' : ''}',
      ),
      leadingIcon: Symbols.restore_rounded,
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  String get _url {
    final String raw = urlController.text.trim();
    if (raw.isEmpty || raw == 'https://') return '';
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  void _openBrowser() {
    final String url = _url;
    if (url.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Enter a site address first'),
        leadingIcon: Symbols.error_rounded,
      );
      return;
    }

    capture.start(url);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppWebviewView(
          initialUrl: url,
          title: 'Recording',
          subtitle: 'Solve any challenge, then browse: a listing, a gallery, a reader page',
          onResourceLoaded: capture.recordResource,
          // The page's own API calls, caught as it makes them. For a Next.js
          // app like hentaipaw.com this is the only way the API is visible at
          // all: onLoadResource never sees a client-side fetch.
          initialUserScripts: [
            UserScript(
              source: SourceCaptureHandler.networkHookScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ],
          onWebViewReady: (controller) {
            controller.addJavaScriptHandler(
              handlerName: SourceCaptureHandler.bridgeName,
              callback: (args) {
                final call = args.isNotEmpty ? args.first : null;
                if (call is! Map) return null;
                capture.recordXhr(
                  method: call['method']?.toString() ?? 'GET',
                  url: call['url']?.toString() ?? '',
                  status: (call['status'] as num?)?.toInt(),
                  contentType: call['contentType']?.toString(),
                  body: call['body']?.toString(),
                );
                return null;
              },
            );
          },
          // hentaipaw.com's own page serves api.shinybirdwhispered.com
          // interstitials that replace it; a hijacked page records nothing.
          blockPopupsAndAds: true,
          onLoadStop: (context, controller, loadedUrl) async {
            capture.attachController(controller);
            final String? html = await controller.getHtml();
            capture.recordPage(loadedUrl?.toString() ?? url, html);
            // Bodies are read HERE, while the page is alive and cleared. Doing
            // it after the webview closed is what produced a capture full of
            // URLs and no bodies on hentaipaw.com.
            await capture.fetchPendingBodies();
          },
        ),
      ),
    ).then((_) {
      capture.detachController();
      capture.stop();
      if (mounted) setState(() {});
    });
  }

  Future<void> _fetchBodies() async {
    final List<String> urls = capture.interestingResources;
    if (urls.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Nothing to fetch — browse the site first'),
        leadingIcon: Symbols.info_rounded,
      );
      return;
    }

    setState(() => busy = true);
    for (final url in urls) {
      await capture.fetchBody(url);
    }
    if (!mounted) return;
    setState(() => busy = false);
    FlashElements.showSnackbar(
      context: context,
      title: Text('Fetched ${urls.length} response bodies'),
      leadingIcon: Symbols.check_rounded,
    );
  }

  Future<void> _share() async {
    setState(() => busy = true);
    final String? path = await capture.writeBundle();
    if (!mounted) return;
    setState(() => busy = false);

    if (path == null) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Could not write the capture file'),
        leadingIcon: Symbols.error_rounded,
      );
      return;
    }
    await ServiceHandler.loadShareFileIntent(path, 'text/plain');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: capture.buildBundle()));
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: const Text('Capture copied to clipboard'),
      leadingIcon: Symbols.content_copy_rounded,
    );
  }

  String get _sizeLabel {
    final int kb = capture.totalChars ~/ 1024;
    return kb > 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Source capture')),
      body: ValueListenableBuilder<int>(
        valueListenable: capture.revision,
        builder: (context, _, _) {
          final bool hasCapture = capture.entries.isNotEmpty;

          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Records what a site actually serves, so a handler can be written for it. '
                  'Open the site below, get past any challenge, then browse a listing, a gallery '
                  'and a reader page. Everything the site sends is written to one file you can share.\n\n'
                  'Logins and session cookies are stripped from the file before it is written. '
                  'The capture is saved as it goes, so closing the app does not lose it.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Site address',
                    hintText: 'https://example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              SettingsButton(
                name: 'Open site and record',
                icon: const Icon(Symbols.travel_explore_rounded),
                action: _openBrowser,
              ),

              SettingsButton(
                name: busy ? 'Working…' : 'Fetch the response bodies',
                subtitle: const Text(
                  'Pulls the non-media URLs the site requested, using the cookies the browser earned. '
                  'This is what turns "the site calls something" into "here is what it answers".',
                ),
                icon: const Icon(Symbols.download_rounded),
                enabled: hasCapture && !busy,
                action: _fetchBodies,
              ),

              const SettingsButton(name: '', enabled: false),

              SettingsButton(
                name: 'Captured so far',
                subtitle: Text(
                  hasCapture
                      ? '${capture.pageCount} pages · ${capture.fetchCount} bodies · '
                            '${capture.resourceCount} urls · $_sizeLabel'
                      : 'Nothing yet',
                ),
                icon: const Icon(Symbols.inventory_2_rounded),
                enabled: false,
              ),

              SettingsButton(
                name: 'Share the capture file',
                icon: const Icon(Symbols.share_rounded),
                enabled: hasCapture && !busy,
                action: _share,
              ),
              SettingsButton(
                name: 'Copy the capture to clipboard',
                icon: const Icon(Symbols.content_copy_rounded),
                enabled: hasCapture && !busy,
                action: _copy,
              ),
              SettingsButton(
                name: 'Discard the capture',
                icon: const Icon(Symbols.delete_rounded),
                enabled: hasCapture && !busy,
                action: () {
                  capture.clear();
                  setState(() {});
                },
              ),

              if (hasCapture) ...[
                const SettingsButton(name: '', enabled: false),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Contents', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final entry in capture.entries)
                  if (entry.kind != CaptureKind.resource)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        entry.kind == CaptureKind.page
                            ? Symbols.description_rounded
                            : Symbols.data_object_rounded,
                        size: 20,
                      ),
                      title: Text(
                        entry.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${entry.kind.name} · ${entry.status ?? ''} '
                        '${entry.contentType ?? ''} · ${entry.size ~/ 1024} KB'
                        '${entry.truncatedFrom != null ? ' (truncated)' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
              ],

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}
