import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/redgifs_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/redgifs_login_page.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_add_dialog.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/pages/settings/source_settings_page.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class BooruEdit extends StatefulWidget {
  const BooruEdit(
    this.booru, {
    super.key,
  });

  final Booru booru;

  @override
  State<BooruEdit> createState() => _BooruEditState();
}

class _BooruEditState extends State<BooruEdit> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  final booruNameController = TextEditingController();
  final booruURLController = TextEditingController();
  final booruFaviconController = TextEditingController();
  final booruAPIKeyController = TextEditingController();
  final booruUserIDController = TextEditingController();
  final booruDefTagsController = TextEditingController();

  BooruType? booruType;
  BooruType selectedBooruType = BooruType.Autodetect;
  bool ignoreGlobalBlacklist = false;

  // TODO make standalone / move to handlers themselves
  String convertSiteUrlToApiUrl() {
    final String url = booruURLController.text;

    if (IdolSankakuHandler.knownUrls.any(url.contains)) {
      return 'https://iapi.sankakucomplex.com';
    } else if (SankakuHandler.knownUrls.any(url.contains)) {
      return 'https://sankakuapi.com';
    }

    return url;
  }

  String convertSiteUrlToFaviconUrl() {
    final String url = booruURLController.text;

    String faviconUrl = '${booruURLController.text}/favicon.ico';

    if (url.contains('agn.ph')) {
      faviconUrl = 'https://agn.ph/skin/Retro/favicon.ico';
    }

    if (booruURLController.text.contains('rule34.us')) {
      faviconUrl = 'https://rule34.us/favicon.png';
    }

    if ([
      ...SankakuHandler.knownUrls,
      ...IdolSankakuHandler.knownUrls,
      'sankakuapi.com',
    ].any(url.contains)) {
      faviconUrl = 'https://sankaku.app/images/favicon-32x32.png';
    }

    // TODO add more

    return faviconUrl;
  }

  bool isTesting = false;

  @override
  void initState() {
    super.initState();
    if (widget.booru.name != 'New') {
      booruNameController.text = widget.booru.name ?? '';
      booruURLController.text = widget.booru.baseURL ?? '';
      booruFaviconController.text = widget.booru.faviconURL ?? '';
      booruAPIKeyController.text = widget.booru.apiKey ?? '';
      booruUserIDController.text = widget.booru.userID ?? '';
      booruDefTagsController.text = widget.booru.defTags ?? '';
      selectedBooruType = BooruType.values.contains(widget.booru.type) ? widget.booru.type! : selectedBooruType;
      ignoreGlobalBlacklist = widget.booru.ignoreGlobalBlacklist;
    }
  }

  @override
  void dispose() {
    booruNameController.dispose();
    booruURLController.dispose();
    booruFaviconController.dispose();
    booruAPIKeyController.dispose();
    booruUserIDController.dispose();
    booruDefTagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: SettingsAppBar(title: context.loc.settings.booruEditor.title),
      body: Center(
        child: ListView(
          children: [
            SettingsButton(
              name: context.loc.settings.booruEditor.saveBooru,
              icon: isTesting ? const CircularProgressIndicator() : const Icon(Symbols.save_rounded),
              action: onSave,
              onLongPress: settingsHandler.isDebug.value ? () => onSave(force: true) : null,
            ),
            const SettingsButton(name: '', enabled: false),
            SettingsTextInput(
              controller: booruNameController,
              title: context.loc.settings.booruEditor.booruName,
              onChanged: (_) => setState(() {}),
              clearable: true,
              pasteable: true,
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
            SettingsTextInput(
              controller: booruURLController,
              title: context.loc.settings.booruEditor.booruUrl,
              onChanged: (_) => setState(() {}),
              inputType: TextInputType.url,
              clearable: true,
              pasteable: true,
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
            //
            if (Tools.isOnPlatformWithWebviewSupport)
              SettingsButton(
                name: context.loc.settings.webview.openWebview,
                subtitle: Text(context.loc.settings.webview.openWebviewTip),
                icon: const Icon(Symbols.public_rounded),
                action: () {
                  if (booruURLController.text.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InAppWebviewView(
                          initialUrl: booruURLController.text,
                        ),
                      ),
                    );
                  }
                },
              ),
            //
            // Per-source preferences (reader behaviour, default sort, grid
            // tag strip) — the reference apps' "<source> settings" screen.
            // Keyed by host, so only offered once the booru actually exists.
            if (widget.booru.baseURL?.isNotEmpty ?? false)
            SettingsButton(
              name: 'Source settings',
              subtitle: const Text('Reader, default sort and grid options for this source only'),
              icon: const Icon(Symbols.tune_rounded),
              action: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SourceSettingsPage(booru: widget.booru),
                  ),
                );
              },
            ),
            //
            SettingsDropdown(
              value: selectedBooruType,
              items: BooruType.dropDownValues,
              onChanged: (BooruType? newValue) {
                setState(() {
                  selectedBooruType = newValue ?? BooruType.values.first;
                  // Prefill sensible defaults for the special engines.
                  if (selectedBooruType.isRedGifs && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://www.redgifs.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'RedGifs';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://www.redgifs.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isRule34Dev && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://app.rule34.dev';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Rule34.dev';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://app.rule34.dev/icon.webp';
                    }
                  }
                  if (selectedBooruType.isHanime1 && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://hanime1.me';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Hanime1';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://hanime1.me/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isKusowanka && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://kusowanka.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Kusowanka';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://kusowanka.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isNHentai && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://nhentai.net';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'nhentai';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://nhentai.net/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isNiyaNiya && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://niyaniya.moe';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'niyaniya';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://niyaniya.moe/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isHentaiPaw && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://hentaipaw.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'HentaiPaw';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://hentaipaw.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType == BooruType.Kemono && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://kemono.cr';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Kemono';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://kemono.cr/favicon.ico';
                    }
                  }
                  if (selectedBooruType == BooruType.Pawchive && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://pawchive.pw';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Pawchive';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://pawchive.pw/static/favicon.png';
                    }
                  }
                  if (selectedBooruType.isAsmHentai && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://asmhentai.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'ASMHentai';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://asmhentai.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isEaHentai && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://eahentai.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'EAHentai';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://eahentai.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isFaccina && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://hentalk.pw';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'hentalk';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://hentalk.pw/favicon.png';
                    }
                  }
                  if (selectedBooruType.isHitomi && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://hitomi.la';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'hitomi.la';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      // hitomi serves nothing from its own host but HTML; the icon lives on ltn.
                      booruFaviconController.text =
                          'https://ltn.gold-usergeneratedcontent.net/favicon-192x192.png';
                    }
                  }
                  if (selectedBooruType.isTikPorn && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://tik.porn';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Tik.Porn';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://tik.porn/apple-touch-icon.png';
                    }
                  }
                  if (selectedBooruType.isXXXTik && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://xxxtik.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'xxxtik';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://xxxtik.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isXXXFollow && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://www.xxxfollow.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'xxxfollow';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://www.xxxfollow.com/favicon.ico';
                    }
                  }
                  if (selectedBooruType.isCivitai && booruURLController.text.trim().isEmpty) {
                    booruURLController.text = 'https://civitai.com';
                    if (booruNameController.text.trim().isEmpty) {
                      booruNameController.text = 'Civitai';
                    }
                    if (booruFaviconController.text.trim().isEmpty) {
                      booruFaviconController.text = 'https://civitai.com/favicon.ico';
                    }
                  }
                });
              },
              title: context.loc.settings.booruEditor.booruType,
              itemTitleBuilder: (BooruType? type) => type?.alias ?? '',
              expendableByScroll: true,
              searchable: true,
              searchCheck: (searchText, item) =>
                  item.name.toLowerCase().contains(searchText) || item.alias.toLowerCase().contains(searchText),
            ),
            SettingsTextInput(
              controller: booruFaviconController,
              title: context.loc.settings.booruEditor.booruFavicon,
              hintText: context.loc.settings.booruEditor.booruFaviconPlaceholder,
              onChanged: (_) => setState(() {}),
              inputType: TextInputType.url,
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
              trailingIcon: SizedBox(
                height: 24,
                width: 24,
                child: BooruFavicon(
                  null,
                  customFaviconUrl: booruFaviconController.text,
                  size: 24,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                final bool useNewBooru = !selectedBooruType.isAutodetect && booruURLController.text.isNotEmpty;
                return TagSearchBox(
                  controller: booruDefTagsController,
                  title: context.loc.settings.booruEditor.booruDefTags,
                  onChanged: (_, _) => setState(() {}),
                  hintText: context.loc.settings.booruEditor.booruDefTagsPlaceholder,
                  booru: useNewBooru
                      ? Booru(
                          'Temp',
                          selectedBooruType,
                          '',
                          booruURLController.text,
                          booruFaviconController.text,
                        )
                      : null,
                  allowMultipleTags: true,
                  readOnlyPreview: useNewBooru,
                  clearable: true,
                );
              },
            ),
            // Both of these edit BOORU blacklist state, which never filters a
            // doujin source (its blacklist lives in the source settings page
            // linked above). Offering them here meant entries that did
            // nothing - and which then removed "Add to hidden" from the tag
            // menu on that source.
            if (!DoujinDataHandler.isDoujinBooru(widget.booru)) ...[
              SettingsToggle(
                value: ignoreGlobalBlacklist,
                onChanged: (newValue) {
                  setState(() {
                    ignoreGlobalBlacklist = newValue;
                  });
                },
                title: 'Ignore global blacklist for this booru',
                leadingIcon: const Icon(Symbols.visibility_off_rounded),
                subtitle: const Text(
                  "When on, the global hidden-tags list won't filter items from this booru. Per-booru hidden tags still apply.",
                ),
              ),
              _PerBooruBlacklistEditor(
                booruName: widget.booru.name,
                onChanged: () => setState(() {}),
              ),
            ],
            Container(
              margin: const EdgeInsets.fromLTRB(10, 16, 10, 16),
              width: double.infinity,
              child: LoliHtml(
                getInstructions(),
              ),
            ),
            //
            if (selectedBooruType == BooruType.Hydrus)
              _HydrusAccessKeyWidget(
                urlController: booruURLController,
                apiKeyController: booruAPIKeyController,
              ),
            //
            if (selectedBooruType == BooruType.RedGifs) _buildRedGifsLogin(),
            // RedGifs has no per-user ID field — it logs in via the browser
            // button above and stores a session token in the key field.
            // Credential fields appear only where the engine READS them
            // (BooruHandler.usesUserId / usesApiKey): a field nothing reads
            // would make an account look configurable when it is not.
            if (selectedBooruType != BooruType.RedGifs && (_credentialCapabilities?.usesUserId ?? true))
              SettingsTextInput(
                controller: booruUserIDController,
                onChanged: (_) => setState(() {}),
                title: _credentialCapabilities?.userIdLabel ?? getUserIDTitle(),
                hintText: getUserIdPlaceholder(),
                clearable: true,
                pasteable: true,
                drawTopBorder: true,
                enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
              ),
            if (selectedBooruType != BooruType.RedGifs && (_credentialCapabilities?.usesApiKey ?? true))
              SettingsTextInput(
                controller: booruAPIKeyController,
                onChanged: (_) => setState(() {}),
                title: _credentialCapabilities?.apiKeyLabel ?? getApiKeyTitle(),
                pasteable: true,
                hintText: getApiKeyPlaceholder(),
                clearable: true,
                obscureable: shouldObscureApiKey(),
                enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
              ),
            if (selectedBooruType != BooruType.RedGifs &&
                _credentialCapabilities != null &&
                !_credentialCapabilities!.usesUserId &&
                !_credentialCapabilities!.usesApiKey)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'This source has no account or API key — there is nothing to enter.',
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          ],
        ),
      ),
    );
  }

  /// The engine behind the chosen type, asked which credential fields it
  /// reads. Autodetect has no engine yet, so both fields stay visible.
  BooruHandler? get _credentialCapabilities {
    if (selectedBooruType == BooruType.Autodetect) return null;
    return BooruHandlerFactory()
        .getBooruHandler(
          [Booru(booruNameController.text, selectedBooruType, '', booruURLController.text.trim(), '')],
          null,
        )
        .booruHandler;
  }

  String getApiKeyTitle() {
    switch (selectedBooruType) {
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
      case BooruType.R34Hentai:
      case BooruType.InkBunny:
      case BooruType.XXXTik:
        return context.loc.password;
      default:
        return context.loc.apiKey;
    }
  }

  String getApiKeyPlaceholder() {
    switch (selectedBooruType) {
      default:
        return '';
    }
  }

  String getInstructions() {
    switch (selectedBooruType) {
      case BooruType.Autodetect:
      case BooruType.Gelbooru:
      case BooruType.GelbooruAlike:
        if (booruURLController.text.contains('gelbooru.com')) {
          return GelbooruHandler.credentialsWarningText;
        } else if (booruURLController.text.contains('rule34.xxx')) {
          return GelbooruAlikesHandler.r34xxxCredentialsWarningText;
        }
        break;
      case BooruType.Hydrus:
        return '';
      case BooruType.RedGifs:
        return '<b>RedGifs</b><br>No setup needed — leave the URL as '
            'https://www.redgifs.com. Browse trending content or search tags '
            '(e.g. <i>blowjob blonde</i>). Sort with the <i>sort:</i> chip '
            '(Trending / Top / Latest). Creators are searchable via the '
            '<i>creator:name</i> tag shown in a post tag list. Type '
            '<i>niche:</i> in the search bar to autocomplete from the full '
            'catalogue of curated niches; the niches a post belongs to also '
            'show up as tags in its tag list.<br><br>'
            '<b>Login (optional):</b> use the <i>Sign in with browser</i> button '
            'below to connect your RedGifs account (their login needs a captcha, '
            'so it opens the real site). Browsing works without an account.';
      case BooruType.Rule34Dev:
        return '<b>Rule34.dev (aggregator)</b><br>No setup needed — leave the '
            'URL as https://app.rule34.dev. This reads the app.rule34.dev '
            'aggregated feed (images, GIFs and video posts).<br><br>'
            'Pick which underlying booru to browse with the <i>source:</i> '
            'chip / prefix: <i>source:r34</i> (Rule34.xxx, default), '
            '<i>source:gel</i> (Gelbooru), <i>source:e621</i>, '
            '<i>source:r34paheal</i> — e.g. <i>source:gel milf score:&gt;3</i>. '
            'Tag autocomplete follows the selected source.<br><br>'
            'Note: the "real videos" (xvideos) section streams tube sites '
            'through a private proxy and cannot be scraped directly — open '
            'app.rule34.dev in a WebView booru for that part.';
      case BooruType.Kemono:
        return '<b>Kemono</b><br>Leave the URL as https://kemono.cr. A creator '
            'archive: every post belongs to a creator on Patreon, Fanbox, '
            'Gumroad, Fantia, Boosty, SubscribeStar or DLsite, and one post can '
            'hold many files (the burst badge on a card; the files action in the '
            'viewer opens them all).<br><br>'
            '<b>Search:</b> plain words (3+ characters) search titles and text; '
            '<i>tag:x</i> filters by the site\'s tags; <i>creator:name</i> or a '
            'card from the Artists page opens one creator; <i>popular:day</i> '
            '(week, month, recent), <i>random</i>. <i>service:patreon</i> filters '
            'on the phone — the site cannot.<br><br>'
            '<b>The kemono sidebar</b> (left drawer on a Kemono tab) mirrors the '
            'site: Artists, Posts, Favorites, DMs, Announcements. Its bottom '
            'button swaps to the normal pinned-tags drawer, and Quick access '
            'swaps back.<br><br>'
            '<b>Username and password (optional):</b> the app signs in to your '
            'kemono account for Favorites (posts and artists) and syncs hearts '
            'to it. Nothing is sent anywhere else.';
      case BooruType.Pawchive:
        return '<b>Pawchive</b><br>Leave the URL as https://pawchive.pw. An archive '
            'of kemono (Patreon and Fanbox creators) on the older kemono API, '
            'with its own file host that actually answers. Same tabs, sidebar, '
            'Artists page and post page as Kemono.<br><br> '
            '<b>Search:</b> plain words (2+ characters), <i>tag:x</i>, '
            '<i>creator:name</i>, <i>service:patreon</i> (filtered on the phone). '
            'No popular feed, random post, tag list or DMs — the site has none.<br><br> '
            '<b>Username and password (optional):</b> the app signs in through '
            "the site's login form for Favorites (posts and artists) and syncs "
            'hearts. The file host blocks IPs that download unreasonably, so '
            'nothing here prefetches files.';
      case BooruType.NHentai:
        return '<b>nhentai</b><br>Leave the URL as https://nhentai.net. A '
            'DOUJIN source: every post is a whole gallery, read page by page '
            'in the built-in reader (the book icon in the viewer, or the '
            '"Read" row in the post drawer). Your position in each book is '
            'remembered.<br><br>'
            '<b>Search</b> uses the site\'s own syntax: plain words search '
            'titles and tags, <i>tag:x</i>, <i>artist:x</i>, <i>parody:x</i>, '
            '<i>character:x</i>, <i>group:x</i>, <i>language:english</i>, '
            '<i>category:doujinshi</i>, <i>pages:&gt;20</i>, and <i>-tag:x</i> '
            'to exclude. <i>sort:popular</i> / <i>sort:popular-today</i> / '
            '<i>sort:popular-week</i> / <i>sort:popular-month</i> for the '
            'popular feeds; empty search shows the newest uploads.<br><br>'
            '<b>API key (optional):</b> works fine without one. To use your '
            'account later (favorites), generate a key at '
            'nhentai.net/user/settings and paste it into the API key field.';
      case BooruType.Hanime1:
        return '<b>Hanime1</b><br>Leave the URL as https://hanime1.me. A '
            'Chinese-language hentai video site — the app translates it for '
            'you.<br><br>'
            '<b>Search in English.</b> The site\'s entire tag list is built '
            'into the app with English names, so type <i>creampie</i>, '
            '<i>ntr</i>, <i>chinese_subtitles</i>… and the matching Chinese '
            'tag is sent automatically. Autocomplete understands both '
            'languages and suggests the English name. Multiple tags combine '
            'as AND; add <i>mode:any</i> to match ANY of them instead.<br><br>'
            'Extras: <i>genre:</i> (hentai / shorts / motion_anime / 3dcg / '
            '2.5d / 2d / ai / mmd / cosplay), <i>sort:</i> (newest / '
            'latest_upload / daily / weekly / monthly / views / trending), '
            '<i>artist:name</i>, and any other words search titles as free '
            'text.<br><br>'
            'Tags on posts show in English too (appearing after you open a '
            'post — the site\'s grid carries none). Titles stay original with '
            'a machine-translated English line added underneath when '
            'translation is reachable.';
      case BooruType.Kusowanka:
        return '<b>Kusowanka</b><br>Leave the URL as https://kusowanka.com. '
            'No account or API key needed.<br><br>'
            '<b>One tag at a time.</b> This site is not a booru engine and has '
            'no way to combine tags, so a two-word search is refused rather '
            'than quietly showing you the wrong thing. Leave the search empty '
            'to browse everything newest-first.<br><br>'
            'It keeps five separate kinds of tag, and you pick one with a '
            'prefix: a bare word is a normal tag, or use '
            '<i>artist:name</i>, <i>character:name</i>, <i>parody:name</i> '
            '(series/copyright) or <i>metadata:name</i>. For example '
            '<i>metadata:animated</i> for animations. Autocomplete searches '
            'all five and labels each result.<br><br>'
            '<b>Note on tags:</b> the thumbnail grid on this site only carries '
            'numeric tag IDs, not names, so tags appear once you open a post. '
            'That also means the tag blacklist cannot hide anything on this '
            'booru until a post has been opened.';
      case BooruType.TikPorn:
        return '<b>Tik.Porn</b><br>Leave the URL as https://tik.porn. A '
            'short-form vertical video site — video only, no images. No '
            'account or API key is needed.<br><br>'
            'Leave the search empty to browse the whole catalogue. Type any '
            "words to search, or use one of the site's own categories: a "
            'single tag name (e.g. <i>redhead</i>, <i>small-tits</i>) goes '
            "straight to that tag's feed, and <i>action:anal-doggystyle</i> "
            "goes to an act's feed. Tap a creator, or type "
            "<i>creator:name</i>, for that creator's videos.<br><br>"
            'The <i>sort:</i> chip (Recent / Popular) applies to tag, action '
            'and creator feeds. Free-text search has a fixed relevance order '
            'and ignores it — the site itself offers no other orderings.';
      case BooruType.XXXTik:
        return '<b>xxxtik</b><br>Leave the URL as https://xxxtik.com. A '
            'short-form video site.<br><br>'
            'Browse recent videos, or a tag (type a single tag), and sort with '
            'the <i>sort:</i> chip (Recent / Top week / month / year / all — '
            'sorting applies to the main feed). Tap a creator, or type '
            '<i>creator:name</i>, to see that creator videos.<br><br>'
            '<b>Login (optional):</b> put your account email and password in '
            'the fields below to sign in — browsing works without an account, '
            'but signing in enables your personalised feeds. Credentials are '
            'sent only to xxxtik login (Firebase) over HTTPS.<br><br>'
            'Videos stream as HLS; downloading a native xxxtik clip is not '
            'supported (there is no single-file source), though playback works.';
      case BooruType.XXXFollow:
        return '<b>xxxfollow</b><br>Leave the URL as https://www.xxxfollow.com. '
            'A short-form video site (formerly Xfollow).<br><br>'
            'Leave the search empty to browse the discovery feed, or type a tag '
            'to see that tag videos. Use the <i>sort:</i> chip to filter by '
            'creator gender (All / Female / Male). Tapping a creator or similar '
            'tag shown above a tag results opens it.<br><br>'
            'Videos are direct MP4 files, so downloads work. As a guest the site '
            'only exposes a limited set of public videos per tag.';
      case BooruType.Civitai:
        return '<b>Civitai</b><br>Leave the URL as https://civitai.com. '
            'The AI-generation gallery, via its official public API.<br><br>'
            'Put your Civitai <b>API key</b> (civitai.com → Account settings → '
            "API Keys) in the API key field — it unlocks your account's "
            "browsing level and <i>artist:me</i> (your uploads).<br><br>"
            'Search with plain tags, or use the chips: <i>sort:</i> (incl. '
            'Random), <i>period:</i>, <i>nsfw:</i> level, <i>type:</i> '
            'image/video, <i>basemodel:</i>, <i>artist:</i>name, '
            '<i>model:</i>id, <i>post:</i>id. Exclusions (-tag) are filtered '
            'on-device. Note: the public API has no "liked images" feed.';
      case BooruType.WebView:
        return '<b>WebView (browser)</b><br>Renders any site inside a tab '
            'instead of scraping it — use it for sites that are hard or '
            'impossible to parse.<br><br>Set the URL to the site you want. '
            'To make the tab search box drive the site search, put a '
            'placeholder where the query goes: {tags} — for example, '
            '<i>https://example.com/search?q={tags}</i> <br>'
            'Downloads started inside the page are sent to the snatcher.';
      default:
        break;
    }

    return context.loc.settings.booruEditor.booruDefaultInstructions;
  }

  bool shouldObscureApiKey() {
    switch (selectedBooruType) {
      default:
        return true;
    }
  }

  String getUserIDTitle() {
    switch (selectedBooruType) {
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
      case BooruType.Danbooru:
      case BooruType.R34Hentai:
        return context.loc.login;
      case BooruType.XXXTik:
        return 'Email';
      default:
        return context.loc.userId;
    }
  }

  String getUserIdPlaceholder() {
    switch (selectedBooruType) {
      default:
        return '';
    }
  }

  Widget _buildRedGifsLogin() {
    final String token = booruAPIKeyController.text.trim();
    final DateTime? expiry = token.isEmpty ? null : RedGifsHandler.decodeJwtExpiry(token);
    final bool signedIn = expiry != null && expiry.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                signedIn ? Symbols.check_circle_rounded : Symbols.account_circle_rounded,
                color: signedIn ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  signedIn ? 'Signed in to RedGifs' : 'Not signed in (browsing as guest)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            signedIn
                ? 'Your account session is active. Sign in again if it stops working.'
                : 'Sign in with your RedGifs account to use your personal feeds and '
                      'follows. Optional — browsing works without an account.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Symbols.login_rounded),
                label: Text(signedIn ? 'Sign in again' : 'Sign in with browser'),
                onPressed: _openRedGifsLogin,
              ),
              if (signedIn) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Symbols.logout_rounded),
                  label: const Text('Sign out'),
                  onPressed: () => setState(() => booruAPIKeyController.text = ''),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRedGifsLogin() async {
    if (!Tools.isOnPlatformWithWebviewSupport) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('WebView unavailable'),
        content: const Text('Signing in to RedGifs needs a WebView, which is not available on this device.'),
        leadingIcon: Symbols.error_rounded,
        leadingIconColor: Colors.red,
      );
      return;
    }
    final String? token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RedGifsLoginPage()),
    );
    if (token != null && token.isNotEmpty && mounted) {
      setState(() => booruAPIKeyController.text = token);
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Signed in'),
        content: const Text('RedGifs account connected.'),
        leadingIcon: Symbols.check_circle_rounded,
        leadingIconColor: Colors.green,
      );
    }
  }

  void sanitizeBooruName() {
    // sanitize booru name to avoid conflicts with file paths
    booruNameController.text = Tools.sanitize(booruNameController.text).trim();
    setState(() {});
  }

  Future<bool> onTest() async {
    sanitizeBooruName();

    // The special engines don't use the standard scrape-test — just normalise
    // the URL and accept. RedGifs has a fixed API; Rule34.dev reads a fixed
    // data endpoint; WebView renders whatever URL the user provides.
    if (selectedBooruType.isRedGifs ||
        selectedBooruType.isWebView ||
        selectedBooruType.isRule34Dev ||
        selectedBooruType.isHanime1 ||
        selectedBooruType.isKusowanka ||
        selectedBooruType.isNHentai ||
        selectedBooruType.isTikPorn ||
        selectedBooruType.isXXXTik ||
        selectedBooruType.isXXXFollow) {
      if (booruNameController.text.trim().isEmpty) {
        booruNameController.text = selectedBooruType.isRedGifs
            ? 'RedGifs'
            : selectedBooruType.isRule34Dev
            ? 'Rule34.dev'
            : selectedBooruType.isHanime1
            ? 'Hanime1'
            : selectedBooruType.isKusowanka
            ? 'Kusowanka'
            : selectedBooruType.isNHentai
            ? 'nhentai'
            : selectedBooruType.isTikPorn
            ? 'Tik.Porn'
            : selectedBooruType.isXXXTik
            ? 'xxxtik'
            : selectedBooruType.isXXXFollow
            ? 'xxxfollow'
            : 'WebView';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isRedGifs) {
        booruURLController.text = 'https://www.redgifs.com';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isRule34Dev) {
        booruURLController.text = 'https://app.rule34.dev';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isHanime1) {
        booruURLController.text = 'https://hanime1.me';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isKusowanka) {
        booruURLController.text = 'https://kusowanka.com';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isNHentai) {
        booruURLController.text = 'https://nhentai.net';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isTikPorn) {
        booruURLController.text = 'https://tik.porn';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isXXXTik) {
        booruURLController.text = 'https://xxxtik.com';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isXXXFollow) {
        booruURLController.text = 'https://www.xxxfollow.com';
      }
      if (booruURLController.text.trim().isEmpty) {
        FlashElements.showSnackbar(
          context: context,
          title: Text(
            context.loc.settings.booruEditor.booruUrlRequired,
            style: const TextStyle(fontSize: 20),
          ),
          leadingIcon: Symbols.warning_amber_rounded,
          leadingIconColor: Colors.red,
          sideColor: Colors.red,
        );
        return false;
      }
      if (!booruURLController.text.contains('http')) {
        booruURLController.text = 'https://${booruURLController.text}';
      }
      if (booruFaviconController.text.trim().isEmpty) {
        booruFaviconController.text = convertSiteUrlToFaviconUrl();
      }
      booruType = selectedBooruType;
      return true;
    }

    if (booruNameController.text.trim().isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.booruNameRequired,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }

    if (booruURLController.text.trim().isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.booruUrlRequired,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }

    // add https if not specified
    if (!booruURLController.text.contains('http://') && !booruURLController.text.contains('https://')) {
      booruURLController.text = 'https://${booruURLController.text}';
    }
    if (booruURLController.text.endsWith('/')) {
      booruURLController.text = booruURLController.text.substring(0, booruURLController.text.length - 1);
    }

    booruURLController.text = convertSiteUrlToApiUrl();

    booruFaviconController.text = booruFaviconController.text.trim().isEmpty
        ? convertSiteUrlToFaviconUrl()
        : booruFaviconController.text;

    //Call the booru test
    final Booru testBooru = Booru.withKey(
      booruNameController.text,
      booruType,
      booruFaviconController.text,
      booruURLController.text,
      booruDefTagsController.text,
      booruAPIKeyController.text.isEmpty ? null : booruAPIKeyController.text,
      booruUserIDController.text.isEmpty ? null : booruUserIDController.text,
    );

    isTesting = true;
    setState(() {});

    final testResults = await booruTest(testBooru, selectedBooruType);
    final BooruType? testBooruType = testResults.booruType;
    final String errorString = testResults.errorString?.isNotEmpty == true ? testResults.errorString! : '';

    isTesting = false;
    setState(() {});

    // If a booru type is returned set the widget state
    if (testBooruType != null) {
      booruType = testBooruType;
      selectedBooruType = testBooruType;
      return true;
    } else {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 5),
        title: Text(
          context.loc.settings.booruEditor.testBooruFailedTitle,
          style: const TextStyle(fontSize: 20),
        ),
        content: Column(
          children: [
            Text(
              context.loc.settings.booruEditor.testBooruFailedMsg,
              style: const TextStyle(fontSize: 16),
            ),
            if (errorString.trim().isNotEmpty)
              Text(
                '${context.loc.error}: $errorString',
                style: const TextStyle(fontSize: 16),
              ),
          ],
        ),
        actionsBuilder: (context, controller) {
          return [
            if (errorString.trim().isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: errorString));
                  FlashElements.showSnackbar(
                    context: context,
                    title: Text(
                      context.loc.copied,
                      style: const TextStyle(fontSize: 20),
                    ),
                    sideColor: Colors.green,
                    leadingIcon: Symbols.check_rounded,
                    leadingIconColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  );
                },
                icon: const Icon(Symbols.content_copy_rounded),
                label: Text(context.loc.copyErrorText),
              ),
          ];
        },
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }
  }

  Future<void> onSave({bool force = false}) async {
    sanitizeBooruName();

    if (force) {
      booruType = selectedBooruType;
      if (booruType!.isAutodetect) {
        return;
      }
    }

    if (booruType == null && !force) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.runningTest,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Symbols.refresh_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      final res = await onTest();
      if (!res) {
        return;
      }
      await FlashElements.dismissAll();
    }

    await getStoragePermission();
    final Booru newBooru = Booru.withKey(
      booruNameController.text,
      booruType,
      booruFaviconController.text,
      booruURLController.text,
      booruDefTagsController.text,
      booruAPIKeyController.text.isEmpty ? null : booruAPIKeyController.text,
      booruUserIDController.text.isEmpty ? null : booruUserIDController.text,
    );
    newBooru.ignoreGlobalBlacklist = ignoreGlobalBlacklist;

    bool booruExists = false;
    String booruExistsReason = '';
    // Call the saveBooru on the settings handler and parse it a Booru instance with data from the input fields
    for (int i = 0; i < settingsHandler.booruList.length; i++) {
      if (settingsHandler.booruList[i].baseURL == booruURLController.text) {
        final bool alreadyExists = settingsHandler.booruList.contains(newBooru);
        final bool sameNameExists = settingsHandler.booruList.any((element) => element.name == newBooru.name);
        final bool sameURLExists = settingsHandler.booruList.any((element) => element.baseURL == newBooru.baseURL);

        if (widget.booru.name == 'New') {
          if (alreadyExists || sameNameExists || sameURLExists) {
            booruExists = true;
          }

          if (alreadyExists) {
            booruExistsReason = context.loc.settings.booruEditor.booruConfigExistsError;
          } else if (sameNameExists) {
            booruExistsReason = context.loc.settings.booruEditor.booruSameNameExistsError;
          } else if (sameURLExists) {
            booruExistsReason = context.loc.settings.booruEditor.booruSameUrlExistsError;
          }
        } else {
          if (alreadyExists) {
            booruExists = true;
            booruExistsReason = context.loc.settings.booruEditor.booruConfigExistsError;
          }
        }
      }
    }

    if (booruExists) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          booruExistsReason,
          style: const TextStyle(
            fontSize: 20,
          ),
        ),
        content: Text(
          context.loc.settings.booruEditor.thisBooruConfigWontBeAdded,
          style: const TextStyle(fontSize: 16),
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
    } else {
      final bool confirmRes =
          await showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text(context.loc.settings.booruEditor.booruConfigShouldSave),
                content: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  spacing: 8,
                  children: [
                    Row(
                      mainAxisSize: .min,
                      children: [
                        BooruFavicon(
                          null,
                          customFaviconUrl: booruFaviconController.text,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${newBooru.name} (${newBooru.baseURL})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      context.loc.settings.booruEditor.booruConfigSelectedType(booruType: newBooru.type!.name),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                actions: const [
                  CancelButton(returnData: false),
                  ConfirmButton(returnData: true),
                ],
              );
            },
          ) ??
          false;

      if (!confirmRes) {
        return;
      }

      for (int i = 0; i < settingsHandler.booruList.length; i++) {
        if (settingsHandler.booruList[i].baseURL == booruURLController.text) {
          final bool oldEditBooruExists =
              settingsHandler.booruList[i].baseURL == widget.booru.baseURL &&
              settingsHandler.booruList[i].name == widget.booru.name;
          if (!booruExists && oldEditBooruExists) {
            // remove the old config (same url and name as the start booru)
            settingsHandler.booruList.removeAt(i);
            await settingsHandler.deleteBooru(widget.booru);
          }
        }
      }

      await settingsHandler.saveBooru(newBooru);
      // Open tabs built their handler from the OLD config; re-point them at
      // the saved one so a changed type/URL takes effect immediately instead
      // of only after an app restart.
      SearchHandler.instance.applyBooruEdit(newBooru);

      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.booruConfigSaved,
          style: const TextStyle(fontSize: 20),
        ),
        content: widget.booru.name == 'New'
            ? const SizedBox(height: 20)
            : Text(
                context.loc.settings.booruEditor.existingTabsNeedReload,
                style: const TextStyle(fontSize: 16),
              ),
        leadingIcon: Symbols.done_rounded,
        leadingIconColor: Colors.green,
        sideColor: Colors.green,
      );

      if (searchHandler.tabs.isEmpty) {
        // force first tab creation after creating first booru
        searchHandler.addTabByString(
          settingsHandler.defTags,
          customBooru: newBooru,
        );
        unawaited(searchHandler.runSearch());
      }

      if (searchHandler.tabs.firstWhereOrNull(
            (tab) =>
                tab.selectedBooru.value.type == newBooru.type && tab.selectedBooru.value.baseURL == newBooru.baseURL,
          ) !=
          null) {
        // if the booru is already selected in any tab, update the booru to a new one
        // (only if their type and baseurl are the same, otherwise main booru selector will set the value to null and user has to reselect the booru)
        for (final tab in searchHandler.tabs) {
          if (tab.selectedBooru.value.type == newBooru.type && tab.selectedBooru.value.baseURL == newBooru.baseURL) {
            tab.selectedBooru.value = newBooru;
          }
        }
      }

      unawaited(
        Future.delayed(const Duration(seconds: 1)).then((_) {
          // force global restate
          searchHandler.rootRestate?.call();
        }),
      );

      Navigator.of(context).pop(true);
    }
  }

  /// This function will use the Base URL the user has entered and call a search up to three times
  /// if the searches return null each time it tries the search it uses a different
  /// type of BooruHandler
  Future<({BooruType? booruType, String? errorString})> booruTest(
    Booru booru,
    BooruType userBooruType, {
    bool withCaptchaCheck = true,
  }) async {
    BooruType? booruType;
    String? errorString;
    BooruHandler test;
    List<BooruItem> testFetched = [];
    booru.type = userBooruType;

    if (userBooruType == BooruType.Hydrus) {
      final HydrusHandler hydrusHandler = HydrusHandler(booru, 20);
      if (await hydrusHandler.verifyApiAccess()) {
        return (booruType: userBooruType, errorString: null);
      }
      return (
        booruType: null,
        errorString: context.loc.settings.booruEditor.failedVerifyApiHydrus,
      );
    }

    if (userBooruType == BooruType.Autodetect) {
      final List<BooruType> typeList = BooruType.detectable;
      for (int i = 1; i < typeList.length; i++) {
        booruType ??= (await booruTest(
          booru,
          typeList.elementAt(i),
          withCaptchaCheck: false,
        )).booruType;
      }
    } else {
      final temp = BooruHandlerFactory().getBooruHandler([booru], 5);
      test = temp.booruHandler;
      test.pageNum = temp.startingPage;
      test.pageNum++;

      testFetched =
          (await test.search(
            '',
            null,
            withCaptchaCheck: withCaptchaCheck,
          )) ??
          [];

      if (test.errorString.isNotEmpty) {
        errorString = test.errorString;
        Logger.Inst().log(
          errorString,
          'BooruEdit',
          'booruTest',
          LogTypes.exception,
        );
      }
    }

    if (booruType == null) {
      if (testFetched.isNotEmpty) {
        booruType = userBooruType;
        Logger.Inst().log(
          'Found Results as $userBooruType',
          'BooruEdit',
          'booruTest',
          LogTypes.booruHandlerInfo,
        );
        return (booruType: booruType, errorString: errorString);
      }
    }

    return (booruType: booruType, errorString: errorString);
  }
}

class _HydrusAccessKeyWidget extends StatelessWidget {
  const _HydrusAccessKeyWidget({
    required this.urlController,
    required this.apiKeyController,
  });

  final TextEditingController urlController;
  final TextEditingController apiKeyController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final HydrusHandler hydrus = HydrusHandler(
                Booru(
                  'Hydrus',
                  BooruType.Hydrus,
                  'Hydrus',
                  urlController.text,
                  '',
                ),
                5,
              );
              final String accessKey = await hydrus.getAccessKey();
              if (accessKey != '') {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Symbols.warning_amber_rounded,
                  leadingIconColor: Colors.yellow,
                  sideColor: Colors.yellow,
                );
                apiKeyController.text = accessKey;
              } else {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyFailedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyFailedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Symbols.warning_amber_rounded,
                  leadingIconColor: Colors.red,
                  sideColor: Colors.red,
                );
              }
            },
            child: Text(context.loc.settings.booruEditor.getHydrusApiKey),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          width: double.infinity,
          child: Text(
            context.loc.settings.booruEditor.hydrusInstructions,
          ),
        ),
      ],
    );
  }
}

/// Inline editor for the per-booru blacklist list. Renders below the
/// "Ignore global blacklist" toggle on the Booru edit page. Entries follow
/// the same e621-style line syntax as the global blacklist.
class _PerBooruBlacklistEditor extends StatelessWidget {
  const _PerBooruBlacklistEditor({
    required this.booruName,
    required this.onChanged,
  });

  final String? booruName;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (booruName == null || booruName!.isEmpty) {
      return const SizedBox.shrink();
    }
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<String> entries = settingsHandler.hiddenTagsForBooru(booruName).toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hidden tag lines for this booru',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.help_rounded),
                tooltip: 'Blacklist syntax',
                onPressed: () => _showHelp(context),
              ),
              IconButton(
                icon: const Icon(Symbols.add_rounded),
                tooltip: 'Add line',
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => TagsFiltersAddDialog(
                      tagFilterType: 'per-booru hidden',
                      onAdd: (String line) {
                        settingsHandler.addTagToBooruHiddenList(booruName!, line);
                      },
                    ),
                  );
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No per-booru lines yet. Tap + to add one, or use "Only on this booru" '
                'when blacklisting a tag from a post.',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...entries.map(
              (String line) => _PerBooruBlacklistRow(
                line: line,
                onRemove: () {
                  settingsHandler.removeTagFromBooruHiddenList(booruName!, line);
                  onChanged();
                },
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Blacklist syntax'),
        content: const SingleChildScrollView(
          child: Text(
            'Each entry is a line. A post on this booru is hidden if any line matches.\n\n'
            'Within a line, tokens are separated by spaces and combined with AND:\n'
            '  male solo  → hides posts with BOTH male AND solo.\n\n'
            'Prefix a token with - to require its absence:\n'
            '  fox -wolf -lion  → fox posts that have NEITHER wolf NOR lion.\n'
            '  -female  → posts WITHOUT the female tag.\n\n'
            'Prefix tokens with ~ for OR:\n'
            '  ~wolf ~lion  → posts that have EITHER wolf OR lion.\n'
            '  male ~wolf ~lion -fox  → male AND (wolf OR lion) AND NO fox.\n\n'
            'Metatags work too:\n'
            '  rating:e  rating:q  rating:s\n'
            '  score:<0   score:>=100   score:50..100\n'
            '  id:1234   width:>2000   filesize:>5mb\n'
            '  username:someone   userid:1234\n\n'
            'Lines starting with # are comments and ignored.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PerBooruBlacklistRow extends StatelessWidget {
  const _PerBooruBlacklistRow({
    required this.line,
    required this.onRemove,
  });

  final String line;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.delete_rounded, size: 20),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
