import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/about_page.dart';
import 'package:lolisnatcher/src/pages/loli_sync_page.dart';
import 'package:lolisnatcher/src/pages/settings/backup_restore_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_page.dart';
import 'package:lolisnatcher/src/pages/settings/database_page.dart';
import 'package:lolisnatcher/src/pages/settings/debug_page.dart';
import 'package:lolisnatcher/src/pages/settings/gallery_page.dart';
import 'package:lolisnatcher/src/pages/settings/language_page.dart';
import 'package:lolisnatcher/src/pages/settings/logger_page.dart';
import 'package:lolisnatcher/src/pages/settings/network_page.dart';
import 'package:lolisnatcher/src/pages/settings/performance_page.dart';
import 'package:lolisnatcher/src/pages/settings/privacy_page.dart';
import 'package:lolisnatcher/src/pages/settings/save_cache_page.dart';
import 'package:lolisnatcher/src/pages/settings/tags_filters_page.dart';
import 'package:lolisnatcher/src/pages/settings/theme_page.dart';
import 'package:lolisnatcher/src/pages/settings/user_interface_page.dart';
import 'package:lolisnatcher/src/pages/settings/video_page.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/discord_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/mascot_image.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

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
              _sectionLabel(context, 'SEARCH'),
              SettingsButton(
                name: context.loc.settings.booru.title,
                icon: const Icon(Symbols.image_search_rounded),
                page: () => const BooruPage(),
              ),
              SettingsButton(
                name: context.loc.settings.itemFilters.title,
                icon: const Icon(CupertinoIcons.tag),
                page: () => const TagsFiltersPage(),
              ),
              _sectionLabel(context, 'LOOK & FEEL'),
              SettingsButton(
                name: context.loc.settings.interface.title,
                icon: const Icon(Symbols.grid_on_rounded),
                page: () => const UserInterfacePage(),
              ),
              SettingsButton(
                name: context.loc.settings.theme.title,
                icon: const Icon(Symbols.palette_rounded),
                page: () => const ThemePage(),
              ),
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
              _sectionLabel(context, 'SYSTEM'),
              SettingsButton(
                name: context.loc.settings.performance.title,
                icon: const Icon(
                  Symbols.speed_rounded,
                  size: 20,
                ),
                page: () => const PerformancePage(),
              ),
              SettingsButton(
                name: context.loc.settings.cache.title,
                icon: const Icon(Symbols.sd_storage_rounded),
                page: () => const SaveCachePage(),
              ),
              SettingsButton(
                name: context.loc.settings.network.title,
                icon: const Icon(Symbols.wifi_rounded),
                page: () => const NetworkPage(),
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
              SettingsButton(
                name: context.loc.settings.privacy.title,
                icon: const FaIcon(
                  FontAwesomeIcons.userShield,
                  size: 20,
                ),
                page: () => const PrivacyPage(),
              ),
              SettingsButton(
                name: context.loc.settings.language.title,
                icon: const Icon(Symbols.translate_rounded),
                page: () => const LanguageSettingsPage(),
              ),
              _sectionLabel(context, 'ABOUT'),
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
              const DiscordButton(),
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
                                  msg = history[i].generateTextMessage(
                                    timeFormat: Logger.talker.settings.timeFormat,
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
