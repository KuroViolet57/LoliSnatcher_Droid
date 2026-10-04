import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/settings/ui/about_page.dart';
import 'package:lolisnatcher/features/sync/ui/loli_sync_page.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_settings_page.dart';
import 'package:lolisnatcher/features/recommender/ui/models_page.dart';
import 'package:lolisnatcher/features/settings/ui/modular_ui_page.dart';
import 'package:lolisnatcher/features/recommender/ui/recommendations_page.dart';
import 'package:lolisnatcher/features/accounts/ui/accounts_page.dart';
import 'package:lolisnatcher/features/backup/ui/backup_restore_page.dart';
import 'package:lolisnatcher/features/settings/ui/sources/booru_page.dart';
import 'package:lolisnatcher/features/settings/ui/database_page.dart';
import 'package:lolisnatcher/features/debug/ui/debug_page.dart';
import 'package:lolisnatcher/features/settings/ui/gallery_page.dart';
import 'package:lolisnatcher/features/settings/ui/language_page.dart';
import 'package:lolisnatcher/features/links/ui/links_page.dart';
import 'package:lolisnatcher/features/debug/ui/logger_page.dart';
import 'package:lolisnatcher/features/settings/ui/network_page.dart';
import 'package:lolisnatcher/features/settings/ui/performance_page.dart';
import 'package:lolisnatcher/features/settings/ui/privacy_page.dart';
import 'package:lolisnatcher/features/settings/ui/save_cache_page.dart';
import 'package:lolisnatcher/features/tags/ui/tags_filters_page.dart';
import 'package:lolisnatcher/features/settings/ui/theme_page.dart';
import 'package:lolisnatcher/features/settings/ui/user_interface_page.dart';
import 'package:lolisnatcher/features/settings/ui/video_page.dart';
import 'package:lolisnatcher/core/logging/log_redaction.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/ui/buttons/cancel_button.dart';
import 'package:lolisnatcher/features/settings/ui/discord_button.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/mascot_image.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _onPopInvoked(BuildContext context, bool didPop, _) async {
    await SettingsHandler.instance.saveSettings(restate: true);
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async => _onPopInvoked(context, didPop, result),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(
          title: context.loc.settings.title,
        ),
        body: Center(
          child: ListView(
            children: [
              _sectionLabel(context, 'SOURCES'),
              SettingsButton(
                name: context.loc.settings.booru.title,
                icon: const Icon(Symbols.image_search_rounded),
                page: () => const BooruPage(),
              ),
              // r88: the sign-ins (e-hentai, FurAffinity, RedGifs) in one place;
              // each source's own settings still open them too.
              SettingsButton(
                name: 'Accounts',
                subtitle: const Text('Sign-ins for e-hentai, FurAffinity and RedGifs'),
                icon: const Icon(Symbols.account_circle_rounded),
                page: () => const AccountsPage(),
              ),
              SettingsButton(
                name: context.loc.settings.itemFilters.title,
                icon: const Icon(CupertinoIcons.tag),
                page: () => const TagsFiltersPage(),
              ),
              // r85: open links to your sources in the app (Link Sheet).
              SettingsButton(
                name: 'Links',
                subtitle: const Text('Open links to your sources in the app'),
                icon: const Icon(Symbols.link_rounded),
                page: () => const LinksPage(),
              ),
              SettingsButton(
                name: 'Doujin',
                icon: const Icon(Symbols.menu_book_rounded),
                page: () => const DoujinSettingsPage(),
              ),
              _sectionLabel(context, 'RECOMMENDATIONS & AI'),
              SettingsButton(
                name: 'Recommendations',
                icon: const Icon(Symbols.auto_awesome_rounded),
                page: () => const RecommendationsPage(),
              ),
              // r88: the downloadable models, each with a page of its own.
              SettingsButton(
                name: 'Models',
                subtitle: const Text('The text model, the looks model and the image tagger: what they do, what they run on'),
                icon: const Icon(Symbols.memory_rounded),
                page: () => const ModelsPage(),
              ),
              _sectionLabel(context, 'LOOK & FEEL'),
              SettingsButton(
                name: context.loc.settings.interface.title,
                icon: const Icon(Symbols.grid_on_rounded),
                page: () => const UserInterfacePage(),
              ),
              SettingsButton(
                name: 'Modular UI',
                subtitle: const Text('Show or hide parts of the interface'),
                icon: const Icon(Symbols.toggle_on_rounded),
                page: () => const ModularUiPage(),
              ),
              SettingsButton(
                name: context.loc.settings.theme.title,
                icon: const Icon(Symbols.palette_rounded),
                page: () => const ThemePage(),
              ),
              SettingsButton(
                name: context.loc.settings.language.title,
                icon: const Icon(Symbols.translate_rounded),
                page: () => const LanguageSettingsPage(),
              ),
              _sectionLabel(context, 'VIEWING'),
              SettingsButton(
                name: context.loc.settings.viewer.title,
                icon: const Icon(Symbols.view_carousel_rounded),
                page: () => const GalleryPage(),
              ),
              SettingsButton(
                name: context.loc.settings.video.title,
                icon: const Icon(Symbols.video_settings_rounded),
                page: () => const VideoSettingsPage(),
              ),
              SettingsButton(
                name: context.loc.settings.performance.title,
                icon: const Icon(
                  Symbols.speed_rounded,
                  size: 20,
                ),
                page: () => const PerformancePage(),
              ),
              _sectionLabel(context, 'DOWNLOADS & STORAGE'),
              SettingsButton(
                name: context.loc.settings.cache.title,
                icon: const Icon(Symbols.sd_storage_rounded),
                page: () => const SaveCachePage(),
              ),
              SettingsButton(
                name: context.loc.settings.database.title,
                icon: const Icon(Symbols.list_alt_rounded),
                page: () => const DatabasePage(),
              ),
              SettingsButton(
                name: context.loc.settings.backupAndRestore.title,
                icon: const Icon(Symbols.restore_page_rounded),
                page: () => const BackupRestorePage(),
              ),
              _sectionLabel(context, 'SYSTEM'),
              SettingsButton(
                name: context.loc.settings.network.title,
                icon: const Icon(Symbols.wifi_rounded),
                page: () => const NetworkPage(),
              ),
              SettingsButton(
                name: context.loc.settings.privacy.title,
                icon: const FaIcon(
                  FontAwesomeIcons.userShield,
                  size: 20,
                ),
                page: () => const PrivacyPage(),
              ),
              SettingsButton(
                name: context.loc.settings.sync.title,
                icon: const Icon(Symbols.sync_rounded),
                action: settingsHandler.dbEnabled
                    ? null
                    : () {
                        FlashElements.showSnackbar(
                          context: context,
                          title: Text(
                            context.loc.errorExclamation,
                            style: const TextStyle(fontSize: 20),
                          ),
                          content: Text(
                            context.loc.settings.sync.dbError,
                          ),
                          leadingIcon: Symbols.error_rounded,
                          leadingIconColor: Colors.red,
                          sideColor: Colors.red,
                        );
                      },
                page: settingsHandler.dbEnabled ? () => const LoliSyncPage() : null,
              ),
              if (Logger.viewController != null)
                SettingsButton(
                  name: context.loc.settings.logs.title,
                  icon: const Icon(Symbols.print_rounded),
                  trailingIcon: const Icon(Symbols.exit_to_app_rounded),
                  action: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => SettingsDialog(
                        title: Text(
                          context.loc.settings.logs.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.loc.settings.logs.shareLogsWarningTitle,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              context.loc.settings.logs.shareLogsWarningMsg,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        actionButtons: [
                          const CancelButton(withIcon: true),
                          ElevatedButton.icon(
                            icon: const Icon(Symbols.check_rounded),
                            label: Text(context.loc.ok),
                            onPressed: () async {
                              // Build the export newest-first with a hard size
                              // cap — .text() over the whole history built one
                              // giant string (HTTP logs carry multi-KB cookie
                              // blobs) and could OOM-crash the app mid-export.
                              const int maxChars = 10 * 1024 * 1024;
                              final history = Logger.talker.history;
                              final List<String> parts = [];
                              int size = 0;
                              for (int i = history.length - 1; i >= 0; i--) {
                                String msg;
                                try {
                                  // r69: every line, the Dio logger's own
                                  // included, goes out redacted.
                                  msg = redactSecrets(
                                    history[i].generateTextMessage(
                                      timeFormat: Logger.talker.settings.timeFormat,
                                    ),
                                  );
                                } catch (_) {
                                  continue;
                                }
                                if (size + msg.length > maxChars) break;
                                size += msg.length;
                                parts.add(msg);
                              }
                              await Logger.viewController?.downloadLogsFile(
                                parts.reversed.join('\n'),
                              );
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  onLongPress: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LoggerViewPage(talker: Logger.talker),
                      ),
                    );
                  },
                ),
              Obx(() {
                if (settingsHandler.isDebug.value) {
                  return SettingsButton(
                    name: context.loc.settings.debug.title,
                    icon: const Icon(Symbols.developer_mode_rounded),
                    page: () => const DebugPage(),
                  );
                }

                return const SizedBox.shrink();
              }),
              _sectionLabel(context, 'ABOUT'),
              SettingsButton(
                name: context.loc.settings.about.title,
                icon: const Icon(Symbols.info_rounded),
                page: () => const AboutPage(),
              ),
              SettingsButton(
                name: context.loc.settings.checkForUpdates.title,
                icon: const Icon(Symbols.update_rounded),
                action: () {
                  settingsHandler.checkUpdate(withMessage: true);
                },
              ),
              SettingsButton(
                name: context.loc.settings.help.title,
                icon: const Icon(Symbols.help_center_rounded),
                action: () {
                  launchUrlString(
                    Constants.wikiURL,
                    mode: LaunchMode.externalApplication,
                  );
                },
                trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              ),
              const DiscordButton(),
              const VersionButton(),
              const MascotImage(),
            ],
          ),
        ),
      ),
    );
  }
}

class VersionButton extends StatefulWidget {
  const VersionButton({super.key});

  @override
  State<VersionButton> createState() => _VersionButtonState();
}

class _VersionButtonState extends State<VersionButton> {
  int debugTaps = 0;

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // '{codename}-{version}' — mirrors the uploaded APK's filename scheme so
    // a screenshot of this row identifies the exact test build.
    final String verText =
        '${context.loc.settings.version}: ${Constants.buildCodename}-${Constants.updateInfo.versionName}';

    const String buildTypeText = EnvironmentConfig.isFromStore
        ? '/ Play'
        : (EnvironmentConfig.isTesting ? '/ Test' : (kDebugMode ? '/ Debug' : ''));

    return SettingsButton(
      name: '$verText $buildTypeText'.trim(),
      icon: const Icon(null), // to align with other items
      action: () {
        if (settingsHandler.isDebug.value) {
          FlashElements.showSnackbar(
            context: context,
            title: Text(
              context.loc.settings.debug.alreadyEnabledSnackbarMsg,
              style: const TextStyle(fontSize: 18),
            ),
            leadingIcon: Symbols.warning_amber_rounded,
            leadingIconColor: Colors.yellow,
            sideColor: Colors.yellow,
          );
        } else {
          debugTaps++;
          if (debugTaps > 5) {
            settingsHandler.isDebug.value = true;
            // r80: kept across restarts until turned off.
            unawaited(settingsHandler.saveSettings(restate: false));
            FlashElements.showSnackbar(
              context: context,
              title: Text(
                context.loc.settings.debug.enabledSnackbarMsg,
                style: const TextStyle(fontSize: 18),
              ),
              leadingIcon: Symbols.warning_amber_rounded,
              leadingIconColor: Colors.green,
              sideColor: Colors.green,
            );
          }
        }

        setState(() {});
      },
      onLongPress: () {
        if (!settingsHandler.isDebug.value) {
          return;
        }
        //
        debugTaps = 0;
        settingsHandler.isDebug.value = false;
        unawaited(settingsHandler.saveSettings(restate: false));
        FlashElements.showSnackbar(
          context: context,
          title: Text(
            context.loc.settings.debug.disabledSnackbarMsg,
            style: const TextStyle(fontSize: 18),
          ),
          leadingIcon: Symbols.warning_amber_rounded,
          leadingIconColor: Colors.yellow,
          sideColor: Colors.yellow,
        );
      },
      drawBottomBorder: false,
    );
  }
}
