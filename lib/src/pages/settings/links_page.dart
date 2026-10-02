import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/source_links.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// r85: Settings → Links - lets Android and link apps such as Link Sheet
/// offer LoliSnatcher for links to your sources ([SourceLinks]).
class LinksPage extends StatefulWidget {
  const LinksPage({super.key});

  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  Future<void> _toggle(bool on) async {
    setState(() => settingsHandler.openSourceLinks = on);
    await SourceLinks.apply(on);
    unawaited(settingsHandler.saveSettings(restate: false));
  }

  String _names(List<Booru> boorus, {bool withHost = false}) => boorus
      .map((b) => withHost ? '${b.name} (${Uri.tryParse(b.baseURL ?? '')?.host ?? ''})' : '${b.name}')
      .join(', ');

  Widget _paragraph(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
    child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
  );

  @override
  Widget build(BuildContext context) {
    final r = SourceLinks.coverage(settingsHandler.booruList);
    return Scaffold(
      appBar: const SettingsAppBar(title: 'Links'),
      body: ListView(
        children: [
          SettingsToggle(
            key: const ValueKey('source-links-toggle'),
            value: settingsHandler.openSourceLinks,
            onChanged: _toggle,
            title: 'Open source links in LoliSnatcher',
            subtitle: const Text('Android and link apps such as Link Sheet offer the app for links to your sources'),
            leadingIcon: const Icon(Symbols.link_rounded),
          ),
          _paragraph(
            'A post opens in the viewer over what you are looking at. A search or tag page opens as a new tab, '
            'and the app switches to it. A doujin gallery opens as its page in a new tab. '
            "Any other page opens in the app's own page view.",
          ),
          _paragraph(
            'Android never makes the app the default for these sites by itself: pick it in Link Sheet, '
            'or turn the sites on in Android\'s "Open by default" for the app.',
          ),
          const SettingsButton(
            key: ValueKey('source-links-android'),
            name: 'Android: links this app opens',
            subtitle: Text('Open by default - only needed without a link app'),
            icon: Icon(Symbols.open_in_new_rounded),
            action: ServiceHandler.openLinkDefaultsSettings,
          ),
          if (r.covered.isNotEmpty) _paragraph('Your sources covered: ${_names(r.covered)}.'),
          if (r.uncovered.isNotEmpty)
            _paragraph(
              "Not covered - their address is not in the app's list, which only a new build can change: "
              '${_names(r.uncovered, withHost: true)}.',
            ),
        ],
      ),
    );
  }
}
