import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/source_settings_page.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// The top-level DOUJIN settings hub: the global layer that every doujin
/// source inherits, then one entry per configured doujin source for its
/// overrides — mirroring the reference app's Settings → Sources structure.
class DoujinSettingsPage extends StatelessWidget {
  const DoujinSettingsPage({super.key});

  List<Booru> get _doujinSources => [
    for (final booru in SettingsHandler.instance.booruList)
      if (BooruHandlerFactory().getBooruHandler([booru], null).booruHandler.hasReader) booru,
  ];

  @override
  Widget build(BuildContext context) {
    final List<Booru> sources = _doujinSources;

    return Scaffold(
      appBar: AppBar(title: const Text('Doujin')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Doujin sources read like books: galleries with a reader, chapters, and '
              'their own settings. Global settings apply everywhere; each source below '
              'can override any of them.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          SettingsButton(
            name: 'Global doujin settings',
            subtitle: const Text('Reader, search, recommendations and grid defaults for every doujin source'),
            icon: const Icon(Symbols.settings_rounded),
            page: () => const SourceSettingsPage(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text(
              'SOURCES',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          if (sources.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No doujin sources configured yet — add nhentai in Boorus & Search.'),
            ),
          for (final booru in sources)
            SettingsButton(
              name: booru.name ?? 'unnamed',
              subtitle: Text(booru.baseURL ?? ''),
              icon: BooruFavicon(booru, size: 22),
              page: () => SourceSettingsPage(booru: booru),
            ),
        ],
      ),
    );
  }
}
