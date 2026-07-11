import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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
              icon: isTesting ? const CircularProgressIndicator() : const Icon(Icons.save),
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
                icon: const Icon(Icons.public),
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
            SettingsToggle(
              value: ignoreGlobalBlacklist,
              onChanged: (newValue) {
                setState(() {
                  ignoreGlobalBlacklist = newValue;
                });
              },
              title: 'Ignore global blacklist for this booru',
              leadingIcon: const Icon(Icons.visibility_off_outlined),
              subtitle: const Text(
                "When on, the global hidden-tags list won't filter items from this booru. Per-booru hidden tags still apply.",
              ),
            ),
            _PerBooruBlacklistEditor(
              booruName: widget.booru.name,
              onChanged: () => setState(() {}),
            ),
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
            SettingsTextInput(
              controller: booruUserIDController,
              onChanged: (_) => setState(() {}),
              title: getUserIDTitle(),
              hintText: getUserIdPlaceholder(),
              clearable: true,
              pasteable: true,
              drawTopBorder: true,
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
            SettingsTextInput(
              controller: booruAPIKeyController,
              onChanged: (_) => setState(() {}),
              title: getApiKeyTitle(),
              pasteable: true,
              hintText: getApiKeyPlaceholder(),
              clearable: true,
              obscureable: shouldObscureApiKey(),
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          ],
        ),
      ),
    );
  }

  String getApiKeyTitle() {
    switch (selectedBooruType) {
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
      case BooruType.R34Hentai:
      case BooruType.InkBunny:
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
            '<i>creator:name</i> tag shown in a post tag list.';
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

  void sanitizeBooruName() {
    // sanitize booru name to avoid conflicts with file paths
    booruNameController.text = Tools.sanitize(booruNameController.text).trim();
    setState(() {});
  }

  Future<bool> onTest() async {
    sanitizeBooruName();

    // The special engines don't scrape, so there's nothing to test — just
    // normalise the URL and accept. RedGifs has a fixed API; WebView renders
    // whatever URL (optionally with a {tags} placeholder) the user provides.
    if (selectedBooruType.isRedGifs || selectedBooruType.isWebView) {
      if (booruNameController.text.trim().isEmpty) {
        booruNameController.text = selectedBooruType.isRedGifs ? 'RedGifs' : 'WebView';
      }
      if (booruURLController.text.trim().isEmpty && selectedBooruType.isRedGifs) {
        booruURLController.text = 'https://www.redgifs.com';
      }
      if (booruURLController.text.trim().isEmpty) {
        FlashElements.showSnackbar(
          context: context,
          title: Text(
            context.loc.settings.booruEditor.booruUrlRequired,
            style: const TextStyle(fontSize: 20),
          ),
          leadingIcon: Icons.warning_amber,
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
        leadingIcon: Icons.warning_amber,
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
        leadingIcon: Icons.warning_amber,
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
                    leadingIcon: Icons.check,
                    leadingIconColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(context.loc.copyErrorText),
              ),
          ];
        },
        leadingIcon: Icons.warning_amber,
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
        leadingIcon: Icons.refresh,
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
        leadingIcon: Icons.warning_amber,
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
        leadingIcon: Icons.done,
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
                  leadingIcon: Icons.warning_amber,
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
                  leadingIcon: Icons.warning_amber,
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
                icon: const Icon(Icons.help_outline),
                tooltip: 'Blacklist syntax',
                onPressed: () => _showHelp(context),
              ),
              IconButton(
                icon: const Icon(Icons.add),
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
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
