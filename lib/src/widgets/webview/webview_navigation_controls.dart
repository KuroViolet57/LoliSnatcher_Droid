import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class WebviewNavigationControls extends StatelessWidget {
  const WebviewNavigationControls({required this.controller, super.key});

  final Completer<InAppWebViewController> controller;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InAppWebViewController>(
      future: controller.future,
      builder: (context, snapshot) {
        final InAppWebViewController? controller = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || controller == null) {
          return const Row(
            children: [
              Icon(Symbols.arrow_back_ios_rounded),
              Icon(Symbols.arrow_forward_ios_rounded),
              Icon(Symbols.replay_rounded),
            ],
          );
        }

        return Row(
          children: [
            // Both gestures on one InkResponse: nesting an IconButton inside
            // a GestureDetector loses the long press to the button's own ink
            // tap recognizer, which sits deeper in the gesture arena.
            InkResponse(
              radius: 24,
              onTap: () async {
                if (await controller.canGoBack()) {
                  await controller.goBack();
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.loc.webview.navigation.noBackHistoryItem)),
                  );
                }
              },
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (context) => WebviewHistoryDialog(
                    controller: controller,
                    onSelect: (String url) {
                      controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                    },
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Symbols.arrow_back_ios_rounded),
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.arrow_forward_ios_rounded),
              onPressed: () async {
                if (await controller.canGoForward()) {
                  await controller.goForward();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.loc.webview.navigation.noForwardHistoryItem)),
                  );
                  return;
                }
              },
            ),
            IconButton(
              icon: const Icon(Symbols.replay_rounded),
              onPressed: controller.reload,
            ),
          ],
        );
      },
    );
  }
}

class WebviewHistoryDialog extends StatefulWidget {
  const WebviewHistoryDialog({
    required this.controller,
    required this.onSelect,
    super.key,
  });

  final InAppWebViewController controller;
  final Function(String) onSelect;

  @override
  State<WebviewHistoryDialog> createState() => _WebviewHistoryDialogState();
}

class _WebviewHistoryDialogState extends State<WebviewHistoryDialog> {
  WebHistory? _history;
  // int? _currentIndex;
  // WebHistoryItem? _currentItem;
  List<WebHistoryItem> _historyItems = [];

  @override
  void initState() {
    super.initState();

    widget.controller.getCopyBackForwardList().then((history) {
      setState(() {
        _history = history;
        _historyItems = _history?.list ?? [];
        // _currentIndex = _history?.currentIndex;
        // _currentItem = _history?.list?[_currentIndex ?? 0];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.webview.navigation.history),
      content: ListView.builder(
        itemCount: _historyItems.length,
        itemBuilder: (context, index) {
          final item = _historyItems[index];
          return ListTile(
            title: Text(item.url.toString()),
            subtitle: Text(item.title ?? ''),
            onTap: () {
              widget.onSelect(item.url.toString());
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
