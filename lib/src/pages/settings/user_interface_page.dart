import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/data/settings/app_mode.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/data/settings/button_position.dart';
import 'package:lolisnatcher/src/data/settings/hand_side.dart';
import 'package:lolisnatcher/src/data/settings/preview_display_mode.dart';
import 'package:lolisnatcher/src/data/settings/preview_quality.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class UserInterfacePage extends StatefulWidget {
  const UserInterfacePage({super.key});

  @override
  State<UserInterfacePage> createState() => _UserInterfacePageState();
}

class _UserInterfacePageState extends State<UserInterfacePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  final TextEditingController columnsLandscapeController = TextEditingController();
  final TextEditingController columnsPortraitController = TextEditingController();
  final TextEditingController mouseSpeedController = TextEditingController();
  final TextEditingController bottomSheetSizeController = TextEditingController();

  late PreviewQuality previewMode;
  late PreviewDisplayMode previewDisplay, previewDisplayFallback;
  late ButtonPosition scrollGridButtonsPosition;
  late bool showBottomSearchbar,
      useTopSearchbarInput,
      showSearchbarQuickActions,
      autofocusSearchbar,
      disableVibration,
      usePredictiveBack,
      inlineRelatedGrids,
      useBottomInfoSheet,
      hideStatusBar,
      enableInterestTracking;
  late String defaultTabAddMode;
  late AppMode appMode;
  late HandSide handSide;

  @override
  void initState() {
    super.initState();
    columnsPortraitController.text = settingsHandler.portraitColumns.toString();
    columnsLandscapeController.text = settingsHandler.landscapeColumns.toString();
    bottomSheetSizeController.text = settingsHandler.bottomSheetSizeMultiplier.toString();
    appMode = settingsHandler.appMode.value;
    handSide = settingsHandler.handSide.value;
    showBottomSearchbar = settingsHandler.showBottomSearchbar;
    useTopSearchbarInput = settingsHandler.useTopSearchbarInput;
    showSearchbarQuickActions = settingsHandler.showSearchbarQuickActions;
    autofocusSearchbar = settingsHandler.autofocusSearchbar;
    disableVibration = settingsHandler.disableVibration;
    usePredictiveBack = settingsHandler.usePredictiveBack;
    inlineRelatedGrids = settingsHandler.inlineRelatedGrids;
    enableInterestTracking = settingsHandler.enableInterestTracking;
    useBottomInfoSheet = settingsHandler.useBottomInfoSheet;
    hideStatusBar = settingsHandler.hideStatusBar;
    defaultTabAddMode = settingsHandler.defaultTabAddMode;
    previewDisplay = settingsHandler.previewDisplay;
    previewDisplayFallback = settingsHandler.previewDisplayFallback;
    previewMode = settingsHandler.previewMode;
    scrollGridButtonsPosition = settingsHandler.scrollGridButtonsPosition;
    mouseSpeedController.text = settingsHandler.mousewheelScrollSpeed.toString();
  }

  @override
  void dispose() {
    columnsLandscapeController.dispose();
    columnsPortraitController.dispose();
    mouseSpeedController.dispose();
    bottomSheetSizeController.dispose();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    settingsHandler.appMode.value = appMode;
    settingsHandler.handSide.value = handSide;
    settingsHandler.showBottomSearchbar = showBottomSearchbar;
    settingsHandler.useTopSearchbarInput = useTopSearchbarInput;
    settingsHandler.showSearchbarQuickActions = showSearchbarQuickActions;
    settingsHandler.autofocusSearchbar = autofocusSearchbar;
    settingsHandler.disableVibration = disableVibration;
    final bool needThemeChange = usePredictiveBack != settingsHandler.usePredictiveBack;
    settingsHandler.usePredictiveBack = usePredictiveBack;
    settingsHandler.inlineRelatedGrids = inlineRelatedGrids;
    settingsHandler.enableInterestTracking = enableInterestTracking;
    settingsHandler.useBottomInfoSheet = useBottomInfoSheet;
    settingsHandler.hideStatusBar = hideStatusBar;
    // Apply the status-bar preference immediately on the way out.
    unawaited(ServiceHandler.setSystemUiVisibility(true));
    settingsHandler.bottomSheetSizeMultiplier =
        (double.tryParse(bottomSheetSizeController.text) ?? 2.0).clamp(0.5, 3.0);
    settingsHandler.defaultTabAddMode = defaultTabAddMode;
    settingsHandler.previewMode = previewMode;
    settingsHandler.previewDisplay = previewDisplay;
    settingsHandler.previewDisplayFallback = previewDisplayFallback;
    settingsHandler.scrollGridButtonsPosition = scrollGridButtonsPosition;
    settingsHandler.landscapeColumns = max(1, int.tryParse(columnsLandscapeController.text) ?? 6);
    settingsHandler.portraitColumns = max(1, int.tryParse(columnsPortraitController.text) ?? 3);
    settingsHandler.mousewheelScrollSpeed = double.parse(mouseSpeedController.text);
    await settingsHandler.saveSettings(restate: needThemeChange);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.interface.title,
        ),
        body: Center(
          child: ListView(
            children: [
              // TODO disabled for now, until we rework desktop ui
              // mobile mode only for now (force enabled on settings init)
              if (false)
                // ignore: dead_code
                SettingsOptionsList(
                  value: appMode,
                  items: AppMode.values,
                  onChanged: (AppMode? newValue) async {
                    bool confirmation = false;
                    if ((Platform.isAndroid || Platform.isIOS) && newValue?.isDesktop == true) {
                      confirmation =
                          await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return SettingsDialog(
                                title: Text(context.loc.settings.interface.appUIModeWarningTitle),
                                contentItems: [
                                  Text(
                                    context.loc.settings.interface.appUIModeWarning,
                                  ),
                                ],
                                actionButtons: const [
                                  CancelButton(),
                                  ConfirmButton(),
                                ],
                              );
                            },
                          ) ??
                          false;
                    } else {
                      confirmation = true;
                    }

                    if (!confirmation) {
                      return;
                    }

                    setState(() {
                      appMode = newValue!;
                    });
                  },
                  title: context.loc.settings.interface.appUIMode,
                  itemLeadingBuilder: (item) {
                    return switch (item) {
                      AppMode.Mobile => const Icon(Symbols.phone_android_rounded),
                      AppMode.Desktop => const Icon(Symbols.desktop_windows_rounded),
                      _ => const Icon(null),
                    };
                  },
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.interface.appUIModeWarningTitle),
                            contentItems: [
                              Text(context.loc.settings.interface.appUIModeHelpMobile),
                              Text(context.loc.settings.interface.appUIModeHelpDesktop),
                              const SizedBox(height: 10),
                              Text(
                                context.loc.settings.interface.appUIModeHelpWarning,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              SettingsOptionsList(
                value: handSide,
                items: HandSide.values,
                onChanged: (HandSide? newValue) {
                  setState(() {
                    handSide = newValue!;
                  });
                },
                title: context.loc.settings.interface.handSide,
                itemTitleBuilder: (item) => item?.locName ?? '?',
                trailingIcon: IconButton(
                  icon: const Icon(Symbols.back_hand_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.interface.handSide),
                          contentItems: [
                            Text(context.loc.settings.interface.handSideHelp),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SettingsToggle(
                value: showBottomSearchbar,
                onChanged: (newValue) {
                  setState(() {
                    showBottomSearchbar = newValue;
                  });
                },
                title: context.loc.settings.interface.showSearchBarInPreviewGrid,
              ),
              SettingsToggle(
                value: useTopSearchbarInput,
                onChanged: (newValue) {
                  setState(() {
                    useTopSearchbarInput = newValue;
                  });
                },
                title: context.loc.settings.interface.moveInputToTopInSearchView,
              ),
              SettingsToggle(
                value: showSearchbarQuickActions,
                onChanged: (newValue) {
                  setState(() {
                    showSearchbarQuickActions = newValue;
                  });
                },
                title: context.loc.settings.interface.searchViewQuickActionsPanel,
              ),
              SettingsToggle(
                value: autofocusSearchbar,
                onChanged: (newValue) {
                  setState(() {
                    autofocusSearchbar = newValue;
                  });
                },
                title: context.loc.settings.interface.searchViewInputAutofocus,
              ),
              SettingsToggle(
                value: usePredictiveBack,
                onChanged: (newValue) {
                  setState(() {
                    usePredictiveBack = newValue;
                  });
                },
                title: context.loc.settings.interface.usePredictiveBack,
              ),
              SettingsToggle(
                value: disableVibration,
                onChanged: (newValue) {
                  setState(() {
                    disableVibration = newValue;
                  });
                },
                title: context.loc.settings.interface.disableVibration,
                subtitle: Text(context.loc.settings.interface.disableVibrationSubtitle),
              ),
              SettingsToggle(
                value: hideStatusBar,
                onChanged: (newValue) {
                  setState(() {
                    hideStatusBar = newValue;
                  });
                  settingsHandler.hideStatusBar = newValue;
                  ServiceHandler.setSystemUiVisibility(true);
                },
                title: 'Hide status bar',
                leadingIcon: const Icon(Symbols.fullscreen_rounded),
                subtitle: const Text(
                  'Hides the Android status bar (clock, battery, notifications) app-wide so it stops intruding while you scroll. The bottom navigation bar stays.',
                ),
              ),
              SettingsToggle(
                value: enableInterestTracking,
                onChanged: (newValue) {
                  setState(() {
                    enableInterestTracking = newValue;
                  });
                },
                title: 'Personalized recommendations',
                leadingIcon: const Icon(Symbols.auto_awesome_rounded),
                subtitle: const Text(
                  "Learns which tags you tend to view, favourite, collect and search — on your device only — to power the 'For You' tab. Turn off to stop building the taste profile (you can wipe it from the For You page).",
                ),
              ),
              SettingsToggle(
                value: inlineRelatedGrids,
                onChanged: (newValue) {
                  setState(() {
                    inlineRelatedGrids = newValue;
                  });
                },
                title: 'Inline related-posts grids',
                leadingIcon: const Icon(Symbols.grid_view_rounded),
                subtitle: const Text(
                  "Shows 'More from this artist' and 'More from this uploader' thumbnail rows at the top of the post-details drawer (where supported by the booru). Turn off if you want a leaner drawer or to save bandwidth.",
                ),
              ),
              SettingsToggle(
                value: useBottomInfoSheet,
                onChanged: (newValue) {
                  setState(() {
                    useBottomInfoSheet = newValue;
                  });
                },
                title: 'Bottom info sheet',
                leadingIcon: const Icon(Symbols.vertical_align_bottom_rounded),
                subtitle: const Text(
                  'Show the post info panel (tags, metadata) as a Boorusama-style sheet dragged up from the bottom of the viewer, instead of the classic right-side drawer. Open it with the info button or by swiping up from the bottom edge. Turn off to restore the side drawer.',
                ),
              ),
              if (useBottomInfoSheet)
                SettingsTextInput(
                  controller: bottomSheetSizeController,
                  title: 'Bottom sheet size',
                  hintText: '2',
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                  numberStep: 0.5,
                  numberMin: 0.5,
                  numberMax: 3,
                  numberButtons: true,
                  resetText: () => '2',
                  subtitle: const Text(
                    'How much of the screen the sheet fills when open, in thirds: 1 ≈ a third, 1.5 ≈ half, 2 ≈ two thirds, 3 ≈ full. The player shrinks to fill the space above it, and the sheet locks at this height so its content scrolls in place.',
                  ),
                ),
              SettingsDropdown<String>(
                value: defaultTabAddMode,
                items: const ['end', 'next'],
                itemTitleBuilder: (v) => v == 'next'
                    ? 'Next to current tab'
                    : 'End of tab list',
                onChanged: (v) {
                  setState(() {
                    defaultTabAddMode = v ?? 'end';
                  });
                },
                title: 'New tab placement (single tap)',
                trailingIcon: const Icon(Symbols.tab_rounded),
              ),
              SettingsTextInput(
                controller: columnsPortraitController,
                title: context.loc.settings.interface.previewColumnsPortrait,
                inputType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                onChanged: (String? text) {
                  setState(() {});
                },
                resetText: () => settingsHandler.map['portraitColumns']!['default']!.toString(),
                numberButtons: true,
                numberStep: 1,
                numberMin: 1,
                numberMax: double.infinity,
                validator: (String? value) {
                  final int? parse = int.tryParse(value ?? '');
                  if (value == null || value.isEmpty) {
                    return context.loc.validationErrors.required;
                  } else if (parse == null) {
                    return context.loc.validationErrors.invalidNumericValue;
                  } else if (parse > 4 && (Platform.isAndroid || Platform.isIOS || kDebugMode)) {
                    return context.loc.validationErrors.moreThan4ColumnsWarning;
                  } else {
                    return null;
                  }
                },
              ),
              SettingsTextInput(
                controller: columnsLandscapeController,
                title: context.loc.settings.interface.previewColumnsLandscape,
                inputType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                resetText: () => settingsHandler.map['landscapeColumns']!['default']!.toString(),
                numberButtons: true,
                numberStep: 1,
                numberMin: 1,
                numberMax: double.infinity,
                validator: (String? value) {
                  final int? parse = int.tryParse(value ?? '');
                  if (value == null || value.isEmpty) {
                    return context.loc.validationErrors.required;
                  } else if (parse == null) {
                    return context.loc.validationErrors.invalidNumericValue;
                  } else if (parse > 8 && (Platform.isAndroid || Platform.isIOS || kDebugMode)) {
                    return context.loc.validationErrors.moreThan8ColumnsWarning;
                  } else {
                    return null;
                  }
                },
              ),
              SettingsOptionsList<PreviewQuality>(
                value: previewMode,
                items: PreviewQuality.values,
                onChanged: (PreviewQuality? newValue) {
                  setState(() {
                    previewMode = newValue ?? PreviewQuality.defaultValue;
                  });
                },
                title: context.loc.settings.interface.previewQuality,
                itemTitleBuilder: (e) => e?.locName ?? '',
                trailingIcon: IconButton(
                  icon: const Icon(Symbols.help_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.interface.previewQuality),
                          contentItems: [
                            Text(context.loc.settings.interface.previewQualityHelp),
                            Text(
                              context.loc.settings.interface.previewQualityHelpSample,
                            ),
                            Text(context.loc.settings.interface.previewQualityHelpThumbnail),
                            const Text(' '),
                            Text(
                              context.loc.settings.interface.previewQualityHelpNote,
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SettingsOptionsList<PreviewDisplayMode>(
                value: previewDisplay,
                items: PreviewDisplayMode.values,
                itemTitleBuilder: (item) => switch (item) {
                  .square => '${item!.locName} (1:1)',
                  .rectangle => '${item!.locName} (9:16)',
                  .staggered => item!.locName,
                  _ => '?',
                },
                itemLeadingBuilder: (item) {
                  return switch (item) {
                    .square => const Icon(Symbols.crop_square_rounded),
                    .rectangle => Transform.rotate(
                      angle: pi / 2,
                      child: const Icon(Symbols.crop_16_9_rounded),
                    ),
                    .staggered => const Icon(Symbols.dashboard_rounded),
                    _ => const Icon(null),
                  };
                },
                onChanged: (PreviewDisplayMode? newValue) {
                  setState(() {
                    previewDisplay = newValue ?? PreviewDisplayMode.defaultValue;
                  });
                },
                title: context.loc.settings.interface.previewDisplay,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                child: previewDisplay.isStaggered
                    ? SettingsOptionsList<PreviewDisplayMode>(
                        value: previewDisplayFallback,
                        items: PreviewDisplayMode.values.where((e) => !e.isStaggered).toList(),
                        itemTitleBuilder: (item) => switch (item) {
                          .square => '${item!.locName} (1:1)',
                          .rectangle => '${item!.locName} (9:16)',
                          _ => '?',
                        },
                        itemLeadingBuilder: (item) {
                          return switch (item) {
                            .square => const Icon(Symbols.crop_square_rounded),
                            .rectangle => Transform.rotate(
                              angle: pi / 2,
                              child: const Icon(Symbols.crop_16_9_rounded),
                            ),
                            _ => const Icon(null),
                          };
                        },
                        onChanged: (PreviewDisplayMode? newValue) {
                          setState(() {
                            previewDisplayFallback = newValue ?? PreviewDisplayMode.defaultValue;
                          });
                        },
                        title: context.loc.settings.interface.previewDisplayFallback,
                        subtitle: Text(context.loc.settings.interface.previewDisplayFallbackHelp),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              SettingsToggle(
                value: settingsHandler.disableImageScaling,
                onChanged: (newValue) async {
                  if (newValue) {
                    final res = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.interface.dontScaleImagesWarningTitle),
                          contentItems: [
                            Text(
                              context.loc.settings.interface.dontScaleImagesWarning,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              context.loc.settings.interface.dontScaleImagesWarningMsg,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                          actionButtons: const [
                            CancelButton(withIcon: true),
                            ConfirmButton(withIcon: true),
                          ],
                        );
                      },
                    );

                    if (res != true) {
                      return;
                    }
                  }

                  setState(() {
                    settingsHandler.disableImageScaling = newValue;
                  });
                },
                title: context.loc.settings.interface.dontScaleImages,
                leadingIcon: const Icon(Symbols.close_fullscreen_rounded),
                subtitle: Text(context.loc.settings.interface.dontScaleImagesSubtitle),
              ),
              Stack(
                children: [
                  SettingsToggle(
                    value: !settingsHandler.disableImageScaling ? false : settingsHandler.gifsAsThumbnails,
                    onChanged: (newValue) {
                      setState(() {
                        settingsHandler.gifsAsThumbnails = newValue;
                      });
                    },
                    title: context.loc.settings.interface.gifThumbnails,
                    leadingIcon: const Icon(Symbols.gif_rounded),
                    subtitle: Text(context.loc.settings.interface.gifThumbnailsRequires),
                  ),
                  if (!settingsHandler.disableImageScaling)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
              SettingsOptionsList<ButtonPosition>(
                value: scrollGridButtonsPosition,
                items: ButtonPosition.values,
                onChanged: (ButtonPosition? newValue) {
                  setState(() {
                    scrollGridButtonsPosition = newValue ?? ButtonPosition.defaultValue;
                  });
                },
                title: context.loc.settings.interface.scrollPreviewsButtonsPosition,
                itemTitleBuilder: (e) => e?.locName ?? '',
              ),
              if (SettingsHandler.isDesktopPlatform)
                SettingsTextInput(
                  controller: mouseSpeedController,
                  title: context.loc.settings.interface.mouseWheelScrollModifier,
                  hintText: context.loc.settings.interface.scrollModifier,
                  inputType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  resetText: () => settingsHandler.map['mousewheelScrollSpeed']!['default']!.toString(),
                  numberButtons: true,
                  numberStep: settingsHandler.map['mousewheelScrollSpeed']!['step']!.toDouble(),
                  numberMin: settingsHandler.map['mousewheelScrollSpeed']!['lowerLimit']!.toDouble(),
                  numberMax: settingsHandler.map['mousewheelScrollSpeed']!['upperLimit']!.toDouble(),
                  validator: (String? value) {
                    final double? parse = double.tryParse(value ?? '');
                    if (value == null || value.isEmpty) {
                      return context.loc.validationErrors.required;
                    } else if (parse == null) {
                      return context.loc.validationErrors.invalidNumericValue;
                    } else if (parse > settingsHandler.map['mousewheelScrollSpeed']!['upperLimit']! ||
                        parse < settingsHandler.map['mousewheelScrollSpeed']!['lowerLimit']!) {
                      return context.loc.validationErrors.rangeError(
                        min: settingsHandler.map['mousewheelScrollSpeed']!['lowerLimit']!,
                        max: settingsHandler.map['mousewheelScrollSpeed']!['upperLimit']!,
                      );
                    } else {
                      return null;
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
