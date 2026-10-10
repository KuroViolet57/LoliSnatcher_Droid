import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/app/routing.dart';
import 'package:lolisnatcher/core/network/webview_pages.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/html.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/downloads/ui/downloads_check.dart';
import 'package:lolisnatcher/features/feed/logic/floating_preview_handler.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_build.dart';
import 'package:lolisnatcher/features/links/logic/incoming_link.dart';
import 'package:lolisnatcher/features/links/ui/linked_media_sheet.dart';
import 'package:lolisnatcher/features/tags/ui/floating_tag_preview_window.dart';
import 'package:lolisnatcher/features/webview/ui/webview_page.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// The 1.0 layer rule (docs/ARCHITECTURE.md) keeps core, sources and the
/// logic layers from importing UI. Where they still open a page or build a
/// widget, they call a hook, and the app points each hook at the UI code
/// here, once, at the top of main() before any handler registers.
/// test/layer_bindings_test.dart checks every hook.
void bindLayers() {
  SettingsHandler.afterRestoreCheck = DownloadsCheck.offerAfterRestore;
  LoliHtml.onInternalLink = internalRouting;
  WebviewPages.page = InAppWebviewView.new;
  FloatingPreviewHandler.overlayBuilder = _floatingPreviewOverlay;
  IncomingLinks.bind(LinkedMediaOpener.open);
  SnatchHandler.thumbnailPreview = _snatchThumbnail;
}

Widget _floatingPreviewOverlay() => const FloatingPreviewOverlayStack();

Widget _snatchThumbnail(BooruItem item, BooruHandler handler) => ThumbnailBuild(
  item: item,
  handler: handler,
  selectable: false,
  simple: true,
);
