import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/secure_storage_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/settings/logger_page.dart';
import 'package:lolisnatcher/src/pages/settings/source_capture_page.dart';
import 'package:lolisnatcher/src/pages/settings/text_parser_test_page.dart';
import 'package:lolisnatcher/src/services/capture_files.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/tags_manager/tm_dialog.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  final TextEditingController sessionStrController = TextEditingController();

  @override
  void dispose() {
    sessionStrController.dispose();
    super.dispose();
  }

  Future<dynamic> showTagsManager(BuildContext context) async {
    return SettingsPageOpen(
      context: context,
      page: (_) => const TagsManagerDialog(),
    ).open();
  }

  Future<void> _onPopInvoked(_, _) async {
    await settingsHandler.saveSettings(restate: true);
  }

  /// r80: the finished trace's report goes whole into the log (in numbered
  /// parts: an entry used to be cut at 10,000 characters) and into a file in
  /// the captures folder, then shows. A long one is shown in part: the whole
  /// of it is in the file and the log.
  Future<void> _showTraceReport() async {
    final String report = PerfTrace.instance.report();
    final SavedCapture? saved = await CaptureFiles.keepTraceReport(report);
    final String? savedPath = saved?.where;

    if (!mounted) return;
    const int shownChars = 20000;
    final String shown = report.length > shownChars
        ? '${report.substring(0, shownChars)}\n\n… ${report.length - shownChars} more characters in the file and the log.'
        : report;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trace'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              shown,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          if (savedPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Saved',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Symbols.content_copy_rounded),
            label: const Text('Copy'),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: report));
              } catch (e) {
                // Android refuses a very large copy across the Binder.
                if (!context.mounted) return;
                FlashElements.showSnackbar(
                  context: context,
                  title: const Text('Too long to copy'),
                  content: Text(savedPath == null ? 'It is in the log page, in parts.' : 'It is in the log page and in $savedPath'),
                  leadingIcon: Symbols.error_rounded,
                );
                return;
              }
              if (!context.mounted) return;
              FlashElements.showSnackbar(
                context: context,
                title: const Text('Trace copied'),
                content: Text(savedPath == null ? 'In the log page too' : 'Also saved to $savedPath'),
                leadingIcon: Symbols.content_copy_rounded,
              );
            },
          ),
          const CancelButton(label: 'Close', withIcon: true),
        ],
      ),
    );
  }

  /// r80: a folder of its own for captures instead of the download folder.
  Future<void> _pickCapturesFolder() async {
    if (!Platform.isAndroid) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Android only'),
        content: const Text('Here captures go into a "captures" folder inside the download folder.'),
        leadingIcon: Symbols.info_rounded,
      );
      return;
    }
    final String path = await ServiceHandler.getSAFDirectoryAccess();
    if (path.isEmpty || !mounted) return;
    setState(() => settingsHandler.capturesPath = path);
    await settingsHandler.saveSettings(restate: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.debug.title,
        ),
        body: Center(
          child: ListView(
            children: [
              SettingsToggle(
                value: settingsHandler.showPerf.value,
                onChanged: (newValue) {
                  setState(() {
                    settingsHandler.showPerf.value = newValue;
                  });
                },
                title: context.loc.settings.debug.showPerformanceGraph,
              ),
              SettingsToggle(
                value: settingsHandler.showFps.value,
                onChanged: (newValue) {
                  setState(() {
                    settingsHandler.showFps.value = newValue;
                  });
                },
                title: context.loc.settings.debug.showFPSGraph,
              ),
              SettingsToggle(
                value: settingsHandler.showImageStats.value,
                onChanged: (newValue) {
                  setState(() {
                    settingsHandler.showImageStats.value = newValue;
                  });
                },
                title: context.loc.settings.debug.showImageStats,
              ),
              SettingsToggle(
                value: settingsHandler.showVideoStats.value,
                onChanged: (newValue) {
                  setState(() {
                    settingsHandler.showVideoStats.value = newValue;
                  });
                },
                title: context.loc.settings.debug.showVideoStats,
              ),
              if (kDebugMode)
                SettingsToggle(
                  value: settingsHandler.blurImages.value,
                  onChanged: (newValue) {
                    setState(() {
                      settingsHandler.blurImages.value = newValue;
                      ViewerHandler.instance.videoAutoMute = newValue;
                    });
                  },
                  title: context.loc.settings.debug.blurImagesAndMuteVideosDevOnly,
                ),
              if (SettingsHandler.isDesktopPlatform)
                SettingsToggle(
                  value: settingsHandler.desktopListsDrag,
                  onChanged: (newValue) {
                    setState(() {
                      settingsHandler.desktopListsDrag = newValue;
                    });
                  },
                  title: context.loc.settings.debug.enableDragScrollOnListsDesktopOnly,
                ),

              SettingsButton(
                name: context.loc.settings.debug.animationSpeed(speed: timeDilation),
                icon: const Icon(Symbols.timelapse_rounded),
                action: () {
                  const List<double> speeds = [0.25, 0.5, 0.75, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20];
                  final int currentIndex = speeds.indexOf(timeDilation);
                  int newIndex = 0;
                  if ((currentIndex + 1) <= (speeds.length - 1)) {
                    newIndex = currentIndex + 1;
                  }
                  timeDilation = speeds[newIndex];
                  setState(() {});
                },
              ),

              ValueListenableBuilder<bool>(
                valueListenable: PerfTrace.instance.isRecording,
                builder: (context, recording, _) => ValueListenableBuilder<int>(
                  valueListenable: PerfTrace.instance.revision,
                  builder: (context, _, _) => SettingsButton(
                    name: recording
                        ? 'Stop recording · ${PerfTrace.instance.frameCount} frames'
                        : 'Record a trace',
                    subtitle: Text(
                      recording
                          ? 'Use the app as usual, then come back here and stop. Frames, video players and pages opened are being written down.'
                          : 'Records how smoothly the app runs (per frame) and what it is doing — video players built, re-pointed or dropped, posts and screens opened. No cable and no special build needed.',
                    ),
                    icon: Icon(
                      recording ? Symbols.stop_circle_rounded : Symbols.fiber_manual_record_rounded,
                      color: recording ? Colors.red : null,
                    ),
                    action: () async {
                      if (recording) {
                        PerfTrace.instance.stop();
                        await _showTraceReport();
                      } else {
                        PerfTrace.instance.start();
                      }
                    },
                  ),
                ),
              ),

              // r80: where a trace report and a source capture are written.
              SettingsButton(
                key: const ValueKey('captures-folder'),
                name: 'Captures folder',
                subtitle: Text(CaptureFiles.describeTarget()),
                icon: const Icon(Symbols.folder_rounded),
                action: _pickCapturesFolder,
              ),
              if (settingsHandler.capturesPath.isNotEmpty)
                SettingsButton(
                  key: const ValueKey('captures-folder-reset'),
                  name: 'Use the download folder for captures',
                  icon: const Icon(Symbols.refresh_rounded),
                  action: () async {
                    setState(() => settingsHandler.capturesPath = '');
                    await settingsHandler.saveSettings(restate: false);
                  },
                ),

              SettingsButton(
                name: context.loc.settings.debug.tagsManager,
                icon: const Icon(CupertinoIcons.tag),
                action: () {
                  showTagsManager(context);
                },
              ),

              SettingsButton(
                name: 'Text Parser Test',
                icon: const Icon(Symbols.text_fields_rounded),
                page: () => const TextParserTestPage(),
              ),

              SettingsButton(
                name: context.loc.settings.debug.resolution(
                  width: MediaQuery.sizeOf(context).width.toPrecision(4).toString(),
                  height: MediaQuery.sizeOf(context).height.toPrecision(4).toString(),
                ),
              ),
              SettingsButton(
                name: context.loc.settings.debug.pixelRatio(
                  ratio: MediaQuery.devicePixelRatioOf(context).toPrecision(4).toString(),
                ),
              ),

              const SettingsButton(name: '', enabled: false),

              SettingsButton(
                name: context.loc.settings.debug.logger,
                action: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoggerViewPage(talker: Logger.talker),
                    ),
                  );
                },
                trailingIcon: const Icon(Symbols.print_rounded),
              ),

              SettingsButton(
                name: context.loc.settings.debug.webview,
                icon: const Icon(Symbols.public_rounded),
                page: () => const InAppWebviewView(initialUrl: 'gelbooru.com'),
              ),
              SettingsButton(
                name: 'Source capture',
                subtitle: const Text(
                  'Record what a site actually serves — including one behind a bot filter — '
                  'so support can be written for it',
                ),
                icon: const Icon(Symbols.frame_inspect_rounded),
                page: () => const SourceCapturePage(),
              ),
              SettingsButton(
                name: context.loc.settings.debug.deleteAllCookies,
                icon: const Icon(Symbols.cookie_rounded),
                action: () async {
                  await CookieManager.instance(webViewEnvironment: webViewEnvironment).deleteAllCookies();
                  globalWindowsCookies.clear();
                },
              ),

              if (kDebugMode)
                SettingsButton(
                  name: context.loc.settings.debug.clearSecureStorage,
                  action: () {
                    SecureStorageHandler.instance.deleteAll();
                  },
                ),

              const SettingsButton(name: '', enabled: false),

              SettingsButton(
                name: context.loc.settings.debug.getSessionString,
                icon: const Icon(Symbols.content_copy_rounded),
                action: () async {
                  final str = SearchHandler.instance.generateBackupJson() ?? '';
                  await Clipboard.setData(ClipboardData(text: str));
                  FlashElements.showSnackbar(
                    context: context,
                    duration: const Duration(seconds: 2),
                    title: Text(context.loc.copiedToClipboard, style: const TextStyle(fontSize: 20)),
                    content: Text(
                      str,
                      style: const TextStyle(fontSize: 16),
                    ),
                    leadingIcon: Symbols.content_copy_rounded,
                    sideColor: Colors.green,
                  );
                },
              ),
              SettingsButton(
                name: context.loc.settings.debug.setSessionString,
                icon: const Icon(Symbols.restore_rounded),
                action: () async {
                  await showDialog(
                    context: context,
                    builder: (_) {
                      return AlertDialog(
                        content: Column(
                          children: [
                            SettingsTextInput(
                              controller: sessionStrController,
                              title: context.loc.settings.debug.sessionString,
                              onlyInput: true,
                              pasteable: true,
                            ),
                          ],
                        ),
                        actions: [
                          const CancelButton(),
                          ElevatedButton(
                            onPressed: () async {
                              if (sessionStrController.text.isNotEmpty) {
                                SearchHandler.instance.replaceTabs(sessionStrController.text);

                                FlashElements.showSnackbar(
                                  context: context,
                                  duration: const Duration(seconds: 2),
                                  title: Text(
                                    context.loc.settings.debug.restoredSessionFromString,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  content: Text(
                                    sessionStrController.text,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  leadingIcon: Symbols.content_copy_rounded,
                                  sideColor: Colors.green,
                                );
                              }
                            },
                            child: Text(context.loc.ok),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              // dummy button to use at least one icon from fontawesome regular and solid packs (brands pack is used in discord button)
              // this is required because flutter doesn't tree-shake resources correctly if they are not used at all
              // more on that here: https://pub.dev/packages/font_awesome_flutter#faq
              const Opacity(
                opacity: 0,
                child: SettingsButton(
                  name: '',
                  enabled: false,
                  icon: FaIcon(FontAwesomeIcons.addressBook),
                  trailingIcon: FaIcon(FontAwesomeIcons.solidAddressBook),
                  drawTopBorder: false,
                  drawBottomBorder: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
