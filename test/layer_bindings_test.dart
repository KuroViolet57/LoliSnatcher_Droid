import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/app/layer_bindings.dart';
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
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler_factory.dart';

/// M3 (token 151): lower layers reach the UI through hooks the app binds
/// once at start. Each hook must point at the same UI code the lower layer
/// used to import, so nothing behaves differently.
void main() {
  test('bindLayers points every hook at the UI code it replaced', () {
    SettingsHandler.register();
    bindLayers();

    expect(SettingsHandler.afterRestoreCheck, DownloadsCheck.offerAfterRestore);
    expect(LoliHtml.onInternalLink, internalRouting);
    expect(WebviewPages.page, InAppWebviewView.new);
    expect(IncomingLinks.openMedia, LinkedMediaOpener.open);
    IncomingLinks.resetForTests();
    expect(IncomingLinks.openMedia, LinkedMediaOpener.open, reason: 'a test reset keeps the bound opener');

    expect(FloatingPreviewHandler.overlayBuilder(), isA<FloatingPreviewOverlayStack>());

    final BooruItem item = BooruItem(fileURL: 'f', sampleURL: 's', thumbnailURL: 't', tagsList: const [], postURL: 'p');
    final Booru booru = Booru('test', BooruType.Gelbooru, '', 'https://gelbooru.com', '');
    final Widget thumb = SnatchHandler.thumbnailPreview(item, BooruHandlerFactory().getBooruHandler([booru], null).booruHandler);
    expect(thumb, isA<ThumbnailBuild>());
    final ThumbnailBuild build = thumb as ThumbnailBuild;
    expect(build.item, same(item));
    expect(build.selectable, isFalse);
    expect(build.simple, isTrue);
  });

  test('main() binds the layers before the first handler registers', () {
    final String main = File('lib/main.dart').readAsStringSync();
    final int bind = main.indexOf('bindLayers();');
    final int firstRegister = main.indexOf('.register()');
    expect(bind, isNonNegative, reason: 'main.dart must call bindLayers()');
    expect(bind, lessThan(firstRegister));
  });
}
