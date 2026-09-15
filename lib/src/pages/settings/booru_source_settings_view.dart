import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/booru_site_filters.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/furaffinity_login_page.dart';
import 'package:lolisnatcher/src/pages/settings/tags_filters_page.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// A booru source's settings (r43), the booru counterpart of the doujin
/// source settings: its account, what every search on it adds (default
/// filters from the site's own sort/order and rating options, and free
/// "always add" terms), its hidden tags, and what the app knows about the
/// site. Opened from the left sidebar or the source's edit page.
class BooruSourceSettingsView extends StatefulWidget {
  const BooruSourceSettingsView({required this.booru, required this.handler, super.key});

  final Booru booru;
  final BooruHandler handler;

  @override
  State<BooruSourceSettingsView> createState() => _BooruSourceSettingsViewState();
}

class _BooruSourceSettingsViewState extends State<BooruSourceSettingsView> {
  final SourceSettingsHandler store = SourceSettingsHandler.instance;
  late final TextEditingController alwaysAdd = TextEditingController(text: store.settingsFor(widget.booru).alwaysAdd ?? '');

  @override
  void dispose() {
    alwaysAdd.dispose();
    super.dispose();
  }

  Widget _header(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.secondary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Booru booru = widget.booru;
    final BooruHandler handler = widget.handler;
    final String name = booru.name ?? 'this source';
    final DoujinFilterSpec? filters = handler.siteFilters;
    final String defaults = store.settingsFor(booru).defaultFilters ?? '';
    final int hidden = SettingsHandler.instance.hiddenTagsForBooru(booru.name).length;
    final List<String> notes = BooruSiteNotes.notesFor(booru, handler);
    final TextStyle hint = TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));

    return Scaffold(
      appBar: AppBar(title: Text('${booru.name ?? 'Source'} settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('These apply to $name only.', style: hint),
          ),
          if (handler.usesApiKey || handler.usesUserId || handler.hasSignInSupport || booru.type == BooruType.FurAffinity) ...[
            _header(theme, 'ACCOUNT'),
            if (booru.type == BooruType.FurAffinity)
              ValueListenableBuilder<int>(
                valueListenable: FurAffinitySessionHandler.instance.revision,
                builder: (context, _, _) {
                  final FurAffinitySessionHandler session = FurAffinitySessionHandler.instance;
                  return ListTile(
                    leading: const Icon(Symbols.person_rounded),
                    title: Text(session.isLoggedIn ? 'Logged in${session.username == null ? '' : ' as ~${session.username}'}' : 'Not logged in'),
                    subtitle: const Text('Mature content, the inbox, watching and favourite sync need the login.'),
                    trailing: session.isLoggedIn ? null : const Icon(Symbols.login_rounded),
                    onTap: session.isLoggedIn ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FurAffinityLoginPage())),
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(Symbols.key_rounded),
                title: const Text('Account'),
                subtitle: Text(
                  (booru.apiKey?.isNotEmpty ?? false) || (booru.userID?.isNotEmpty ?? false)
                      ? 'Credentials set · tap to change'
                      : 'No API key or login set · tap to add them on the edit page',
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BooruEdit(booru))),
              ),
          ],
          _header(theme, 'SEARCH'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Always add to searches', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: TextField(
              key: const ValueKey('source-always-add'),
              controller: alwaysAdd,
              decoration: const InputDecoration(isDense: true, hintText: 'e.g. -ai_generated -comic', border: OutlineInputBorder()),
              onChanged: (String v) => store.update(booru, (s) => s.alwaysAdd = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Terms added to every search on $name that does not already have them.', style: hint),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Default filters', style: theme.textTheme.titleSmall),
          ),
          if (filters == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('$name has no sort or rating options in the app.', style: hint),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Used when a search does not choose one itself. The search window shows them checked.', style: hint),
            ),
            DoujinFiltersBlock(
              spec: filters,
              query: defaults,
              onQueryChanged: (String q) {
                store.update(booru, (s) => s.defaultFilters = q.trim().isEmpty ? null : q.trim());
                setState(() {});
              },
            ),
          ],
          _header(theme, 'FILTERING'),
          ListTile(
            leading: const Icon(Symbols.block_rounded),
            title: const Text('Hidden tags'),
            subtitle: Text('$hidden tags hidden on $name, on top of the global list'),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagsFiltersPage()));
              if (mounted) setState(() {});
            },
          ),
          _header(theme, 'About this site'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${booru.type?.alias ?? 'Unknown'} engine · ${Uri.tryParse(booru.baseURL ?? '')?.host ?? ''}', style: hint),
                const SizedBox(height: 6),
                if (notes.isEmpty) Text('Nothing special is known about this site.', style: hint),
                for (final String n in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Symbols.info_rounded, size: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(n)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
