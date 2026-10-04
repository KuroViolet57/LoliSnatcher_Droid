import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lolisnatcher/core/ui/buttons/cancel_button.dart';
import 'package:lolisnatcher/core/ui/buttons/ok_button.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/models/theme_item.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/image_writer.dart';
import 'package:lolisnatcher/core/utils/debouncer.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';

part 'theme_page/clippers.dart';
part 'theme_page/font_picker.dart';

extension ThemeModeExt on ThemeMode {
  String locName(BuildContext context) => context.loc['settings.theme.$name'];
}

class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late ThemeItem theme;
  late ThemeMode themeMode;
  late bool useDynamicColor;
  late bool isAmoled;
  late String fontFamily;
  late bool enableMascot;
  late String mascotPathOverride;
  late Color? primaryPickerColor; // Color for picker shown in Card on the screen.
  late Color? accentPickerColor; // Color for picker in dialog using onChanged

  bool needToWriteMascot = false;
  int currentSdk = 0;

  @override
  void initState() {
    super.initState();
    theme = settingsHandler.theme.value;
    themeMode = settingsHandler.themeMode.value;
    useDynamicColor = settingsHandler.useDynamicColor.value;
    isAmoled = settingsHandler.isAmoled.value;
    fontFamily = settingsHandler.fontFamily.value;
    enableMascot = settingsHandler.enableDrawerMascot;
    mascotPathOverride = settingsHandler.drawerMascotPathOverride;
    primaryPickerColor = settingsHandler.customPrimaryColor.value;
    accentPickerColor = settingsHandler.customAccentColor.value;

    checkSdk();
  }

  Future<void> checkSdk() async {
    if (Platform.isAndroid) {
      currentSdk = await ServiceHandler.getAndroidSDKVersion();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    Debounce.cancel('theme_change');
    super.dispose();
  }

  //called when page is closed or to debounce theme change, sets settingshandler variables and then writes settings to disk
  Future<void> _onPopInvoked(
    _,
    _, {
    bool? withRestate,
  }) async {
    settingsHandler.theme.value = theme;
    settingsHandler.themeMode.value = themeMode;
    settingsHandler.useDynamicColor.value = useDynamicColor;
    settingsHandler.isAmoled.value = isAmoled;
    settingsHandler.fontFamily.value = fontFamily;
    settingsHandler.enableDrawerMascot = enableMascot;

    // print('onPrimary: ${ThemeData.estimateBrightnessForColor(primaryPickerColor!) == Brightness.dark}');
    // print('onAccent: ${ThemeData.estimateBrightnessForColor(accentPickerColor!) == Brightness.dark}');
    settingsHandler.customPrimaryColor.value = primaryPickerColor;
    settingsHandler.customAccentColor.value = accentPickerColor;
    //This needs to be done here because if its done in the buttons onclick
    //and you back out too fast the image path will not be returned in time to save it to settings
    if (needToWriteMascot) {
      if (mascotPathOverride.isNotEmpty) {
        mascotPathOverride = await ImageWriter().writeMascotImage(mascotPathOverride);
        settingsHandler.drawerMascotPathOverride = mascotPathOverride;
        needToWriteMascot = false;
      }
    } else {
      settingsHandler.drawerMascotPathOverride = mascotPathOverride;
    }
    await settingsHandler.saveSettings(restate: withRestate ?? false);
  }

  Future<void> updateTheme({bool withRestate = false}) async {
    // instantly do local restate
    setState(() {});

    // set global restate to happen only after X ms after last update happens
    Debounce.debounce(
      tag: 'theme_change',
      callback: () async {
        await _onPopInvoked(false, null, withRestate: withRestate);
        // The save can end after the page is closed.
        if (mounted) setState(() {});
      },
      duration: const Duration(milliseconds: 500),
    );
  }

  TextStyle? _getFontStyle(String font) {
    if (font == 'System') return null;

    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showFontPicker() async {
    final List<String> defaultFonts = [
      'System',
      'Roboto',
      'Open Sans',
      'Lato',
      'Montserrat',
      'Oswald',
      'Raleway',
      'Poppins',
      'Nunito',
      'Ubuntu',
      'Merriweather',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return _FontPickerSheet(
              currentFont: fontFamily,
              defaultFonts: defaultFonts,
              onFontSelected: (String font) {
                fontFamily = font;
                updateTheme(withRestate: true);
                Navigator.of(ctx).pop();
              },
              getFontStyle: _getFontStyle,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  Future<bool> colorPickerDialog(Color startColor, void Function(Color) onChange) async {
    return ColorPicker(
      color: startColor,
      onColorChanged: onChange,
      width: 40,
      height: 40,
      borderRadius: 4,
      spacing: 5,
      runSpacing: 5,
      wheelDiameter: 300,
      heading: Text(
        context.loc.settings.theme.selectColor,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subheading: Text(
        context.loc.settings.theme.selectedColorAndShades,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      wheelSubheading: Text(
        context.loc.settings.theme.selectedColorAndShades,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      showMaterialName: true,
      showColorName: true,
      showColorCode: true,
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        longPressMenu: true,
      ),
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorCodeTextStyle: Theme.of(context).textTheme.bodyMedium,
      colorCodePrefixStyle: Theme.of(context).textTheme.bodySmall,
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: true,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: true,
      },
      actionButtons: const ColorPickerActionButtons(
        // okButton: true,
        okIcon: Symbols.save_rounded,
        dialogOkButtonType: ColorPickerActionButtonType.elevated,
        // closeButton: true,
        closeIcon: Symbols.keyboard_return_rounded,
        dialogCancelButtonType: ColorPickerActionButtonType.elevated,
        dialogActionIcons: true,
        dialogActionButtons: true,
      ),
    ).showPickerDialog(
      context,
      constraints: BoxConstraints(
        minHeight: 480,
        minWidth: 300,
        maxWidth: min(MediaQuery.sizeOf(context).width * 0.9, 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(title: context.loc.settings.theme.title),
        body: Center(
          child: ListView(
            children: [
              SettingsOptionsList(
                value: themeMode,
                items: ThemeMode.values,
                onChanged: (ThemeMode? newValue) {
                  themeMode = newValue!;
                  updateTheme();
                },
                title: context.loc.settings.theme.themeMode,
                itemTitleBuilder: (item) => item?.locName(context) ?? '?',
                itemLeadingBuilder: (ThemeMode? item) {
                  const double size = 40;

                  return SizedBox(
                    width: size,
                    height: size,
                    child: switch (item) {
                      ThemeMode.dark => const Icon(Symbols.dark_mode_rounded),
                      ThemeMode.light => const Icon(Symbols.light_mode_rounded),
                      ThemeMode.system => Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipPath(
                            clipper: _SunClipper(),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Symbols.light_mode_rounded),
                            ),
                          ),
                          ClipPath(
                            clipper: _MoonClipper(),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 5),
                              child: Icon(Symbols.dark_mode_rounded),
                            ),
                          ),
                        ],
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  );
                },
              ),
              if (themeMode == ThemeMode.system || themeMode == ThemeMode.dark)
                SettingsToggle(
                  value: isAmoled,
                  onChanged: (bool newValue) {
                    isAmoled = newValue;
                    updateTheme();
                  },
                  title: context.loc.settings.theme.blackBg,
                ),
              if (currentSdk >= 31)
                SettingsToggle(
                  value: useDynamicColor,
                  onChanged: (bool newValue) {
                    useDynamicColor = newValue;
                    updateTheme();
                  },
                  title: context.loc.settings.theme.useDynamicColor,
                  subtitle: Platform.isAndroid ? Text(context.loc.settings.theme.android12PlusOnly) : null,
                ),
              if (!useDynamicColor)
                SettingsDropdown(
                  value: theme.name,
                  items: List<String>.from(settingsHandler.map['theme']!['options'].map((e) => e.name).toList()),
                  onChanged: (String? newValue) {
                    theme = settingsHandler.map['theme']!['options'].where((e) => e.name == newValue).toList()[0];
                    updateTheme(withRestate: true);
                  },
                  title: context.loc.settings.theme.theme,
                  itemBuilder: (String? value) {
                    final ThemeItem theme = settingsHandler.map['theme']!['options'].firstWhere((e) => e.name == value);
                    final Color? primary = theme.name == 'Custom' ? primaryPickerColor : theme.primary;
                    final Color? accent = theme.name == 'Custom' ? accentPickerColor : theme.accent;

                    const double themeSize = 40;

                    return Row(
                      children: [
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                                    .withValues(alpha: 0.6),
                                width: 1,
                              ),
                              shape: BoxShape.rectangle,
                              color: primary,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipPath(
                                    clipper: _ThemeLeftClipper(),
                                    child: Container(
                                      color: primary,
                                      height: themeSize,
                                      width: themeSize,
                                    ),
                                  ),
                                  ClipPath(
                                    clipper: _ThemeRightClipper(),
                                    child: Container(
                                      color: accent,
                                      height: themeSize,
                                      width: themeSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          context.loc['settings.theme.${value?.toLowerCase()}'] ?? '?',
                        ),
                        switch (value) {
                          'Halloween' => const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: FaIcon(FontAwesomeIcons.ghost),
                          ),
                          'Custom' => const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Symbols.build_rounded),
                          ),
                          _ => const SizedBox.shrink(),
                        },
                      ],
                    );
                  },
                ),
              if (theme.name == 'Custom' && !useDynamicColor)
                SettingsButton(
                  name: context.loc.settings.theme.primaryColor,
                  subtitle: Text(
                    '${ColorTools.materialNameAndCode(primaryPickerColor!)} '
                    'aka ${ColorTools.nameThatColor(primaryPickerColor!)}',
                  ),
                  action: () async {
                    // Store current color before we open the dialog.
                    final Color colorBeforeDialog = primaryPickerColor!;
                    // Wait for the picker to close, if dialog was dismissed,
                    // then restore the color we had before it was opened.

                    if (!await colorPickerDialog(
                      primaryPickerColor!,
                      (Color newColor) {
                        primaryPickerColor = newColor;
                        updateTheme();
                      },
                    )) {
                      primaryPickerColor = colorBeforeDialog;
                      await updateTheme();
                    }
                  },
                  trailingIcon: ColorIndicator(
                    width: 44,
                    height: 44,
                    hasBorder: true,
                    borderRadius: 4,
                    borderColor: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                        .withValues(alpha: 0.6),
                    color: primaryPickerColor!,
                  ),
                ),
              if (theme.name == 'Custom' && !useDynamicColor)
                SettingsButton(
                  name: context.loc.settings.theme.secondaryColor,
                  subtitle: Text(
                    '${ColorTools.materialNameAndCode(accentPickerColor!)} '
                    'aka ${ColorTools.nameThatColor(accentPickerColor!)}',
                  ),
                  action: () async {
                    // Store current color before we open the dialog.
                    final Color colorBeforeDialog = accentPickerColor!;
                    // Wait for the picker to close, if dialog was dismissed,
                    // then restore the color we had before it was opened.

                    if (!await colorPickerDialog(
                      accentPickerColor!,
                      (Color newColor) {
                        accentPickerColor = newColor;
                        updateTheme();
                      },
                    )) {
                      accentPickerColor = colorBeforeDialog;
                      await updateTheme();
                    }
                  },
                  trailingIcon: ColorIndicator(
                    width: 44,
                    height: 44,
                    hasBorder: true,
                    borderRadius: 4,
                    borderColor: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                        .withValues(alpha: 0.6),
                    color: accentPickerColor!,
                  ),
                ),
              if (theme.name == 'Custom' && !useDynamicColor)
                SettingsButton(
                  name: context.loc.reset,
                  icon: const Icon(Symbols.refresh_rounded),
                  action: () {
                    final ThemeItem theme = settingsHandler.map['theme']!['default'];
                    primaryPickerColor = theme.primary;
                    accentPickerColor = theme.accent;
                    updateTheme();
                  },
                ),
              const SettingsButton(name: '', enabled: false),
              SettingsButton(
                name: context.loc.settings.theme.fontFamily,
                subtitle: Text(
                  fontFamily == 'System' ? context.loc.settings.theme.systemDefault : fontFamily,
                  style: _getFontStyle(fontFamily),
                ),
                icon: const Icon(Symbols.font_download_rounded),
                trailingIcon: fontFamily == 'System'
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Symbols.refresh_rounded),
                            onPressed: () {
                              fontFamily = 'System';
                              updateTheme();
                            },
                          ),
                          const Icon(Symbols.chevron_right_rounded),
                        ],
                      ),
                action: _showFontPicker,
              ),
              const SettingsButton(name: '', enabled: false),
              SettingsToggle(
                value: enableMascot,
                onChanged: (bool newValue) {
                  enableMascot = newValue;
                  updateTheme();
                },
                title: context.loc.settings.theme.enableDrawerMascot,
              ),
              SettingsButton(
                name: context.loc.settings.theme.setCustomMascot,
                subtitle: mascotPathOverride.isEmpty
                    ? null
                    : Text('${context.loc.settings.theme.currentMascotPath}: $mascotPathOverride'),
                icon: const Icon(Symbols.image_search_rounded),
                action: () async {
                  mascotPathOverride = await ServiceHandler.getImageSAFUri();
                  needToWriteMascot = true;
                  setState(() {});
                },
              ),
              if (mascotPathOverride.isNotEmpty)
                SettingsButton(
                  name: context.loc.settings.theme.removeCustomMascot,
                  icon: const Icon(Symbols.delete_forever_rounded),
                  action: () async {
                    final File file = File(mascotPathOverride);
                    if (await file.exists()) {
                      await file.delete();
                    }
                    mascotPathOverride = '';
                    setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
