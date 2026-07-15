import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/widgets/root/predictive_back_transition.dart';

class ThemeHandler {
  ThemeHandler({
    required this.theme,
    required this.themeMode,
    required this.isAmoled,
    required this.fontFamily,
    required this.context,
  }) {
    final platformBrigtness = MediaQuery.platformBrightnessOf(context);
    isDark = themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && platformBrigtness.isDark);

    final Brightness primaryBrightness = ThemeData.estimateBrightnessForColor(
      (isDark ? darkDynamic : lightDynamic) != null ? colorScheme().primary : theme.primary!,
    );
    primaryIsDark = primaryBrightness == Brightness.dark;
    final Brightness accentBrightness = ThemeData.estimateBrightnessForColor(
      (isDark ? darkDynamic : lightDynamic) != null ? colorScheme().secondary : theme.accent!,
    );
    accentIsDark = accentBrightness == Brightness.dark;
  }

  final ThemeItem theme;
  final ThemeMode themeMode;
  final bool isAmoled;
  final String fontFamily;
  final BuildContext context;
  ColorScheme? lightDynamic;
  ColorScheme? darkDynamic;

  bool isDark = true;
  bool primaryIsDark = true;
  bool accentIsDark = true;

  void setDynamicColors(ColorScheme? light, ColorScheme? dark) {
    lightDynamic = light;
    darkDynamic = dark;

    final platformBrigtness = MediaQuery.platformBrightnessOf(context);
    isDark = themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && platformBrigtness.isDark);

    final Brightness primaryBrightness = ThemeData.estimateBrightnessForColor(
      (isDark ? darkDynamic : lightDynamic) != null ? colorScheme().primary : theme.primary!,
    );
    primaryIsDark = primaryBrightness == Brightness.dark;
    final Brightness accentBrightness = ThemeData.estimateBrightnessForColor(
      (isDark ? darkDynamic : lightDynamic) != null ? colorScheme().secondary : theme.accent!,
    );
    accentIsDark = accentBrightness == Brightness.dark;
  }

  ThemeData getTheme() {
    return isDark ? darkTheme() : lightTheme();
  }

  ThemeData lightTheme() {
    final ColorScheme lightColorScheme = colorScheme();

    return ThemeData.light(useMaterial3: true).copyWith(
      brightness: Brightness.light,
      appBarTheme: appBarTheme(lightColorScheme),
      colorScheme: lightColorScheme,
      textTheme: textTheme(),
      textSelectionTheme: textSelectionTheme(lightColorScheme),
      elevatedButtonTheme: elevatedButtonTheme(lightColorScheme),
      outlinedButtonTheme: outlinedButtonTheme(lightColorScheme),
      splashFactory: InkSparkle.splashFactory,
      applyElevationOverlayColor: true,
      buttonTheme: buttonTheme(lightColorScheme),
      cardColor: Color.lerp(lightColorScheme.surface, Colors.black, 0.04),
      dividerColor: lightColorScheme.onSurface.withValues(alpha: 0.12),
      dialogTheme: dialogTheme(lightColorScheme),
      floatingActionButtonTheme: floatingActionButtonTheme(lightColorScheme),
      iconTheme: iconTheme(lightColorScheme),
      inputDecorationTheme: inputDecorationTheme(lightColorScheme),
      primaryIconTheme: iconTheme(lightColorScheme),
      primaryTextTheme: textTheme(),
      bannerTheme: bannerTheme(),
      cardTheme: cardTheme(lightColorScheme),
      pageTransitionsTheme: pageTransitionsTheme(),
      scrollbarTheme: scrollbarTheme(lightColorScheme),
      progressIndicatorTheme: progressIndicatorTheme(lightColorScheme),
      checkboxTheme: checkboxTheme(lightColorScheme),
      switchTheme: switchTheme(lightColorScheme),
      sliderTheme: sliderTheme(lightColorScheme),
      drawerTheme: drawerTheme(lightColorScheme),
      tabBarTheme: tabBarTheme(lightColorScheme),
      dropdownMenuTheme: dropdownMenuTheme(lightColorScheme),
      dividerTheme: dividerTheme(lightColorScheme),
    );
  }

  ThemeData darkTheme() {
    final ColorScheme darkColorScheme = colorScheme();

    return ThemeData.dark(useMaterial3: true).copyWith(
      brightness: Brightness.dark,
      appBarTheme: appBarTheme(darkColorScheme),
      scaffoldBackgroundColor: scaffoldBackground(darkColorScheme) ?? darkColorScheme.surface,
      colorScheme: darkColorScheme,
      textTheme: textTheme(),
      textSelectionTheme: textSelectionTheme(darkColorScheme),
      elevatedButtonTheme: elevatedButtonTheme(darkColorScheme),
      outlinedButtonTheme: outlinedButtonTheme(darkColorScheme),
      splashFactory: InkSparkle.splashFactory,
      applyElevationOverlayColor: true,
      buttonTheme: buttonTheme(darkColorScheme),
      cardColor: darkColorScheme.surface,
      dividerColor: darkColorScheme.onSurface.withValues(alpha: 0.12),
      dialogTheme: dialogTheme(darkColorScheme),
      floatingActionButtonTheme: floatingActionButtonTheme(darkColorScheme),
      iconTheme: iconTheme(darkColorScheme),
      inputDecorationTheme: inputDecorationTheme(darkColorScheme),
      primaryIconTheme: iconTheme(darkColorScheme),
      primaryTextTheme: textTheme(),
      bannerTheme: bannerTheme(),
      cardTheme: cardTheme(darkColorScheme),
      pageTransitionsTheme: pageTransitionsTheme(),
      scrollbarTheme: scrollbarTheme(darkColorScheme),
      progressIndicatorTheme: progressIndicatorTheme(darkColorScheme),
      checkboxTheme: checkboxTheme(darkColorScheme),
      switchTheme: switchTheme(darkColorScheme),
      sliderTheme: sliderTheme(darkColorScheme),
      drawerTheme: drawerTheme(darkColorScheme),
      tabBarTheme: tabBarTheme(darkColorScheme),
      dropdownMenuTheme: dropdownMenuTheme(darkColorScheme),
      dividerTheme: dividerTheme(darkColorScheme),
    );
  }

  // ── "Flow" dark palette ─────────────────────────────────────────────────
  // Near-black violet surfaces used across the app in dark mode. The accent
  // stays theme-driven (theme.accent), so custom accent colours keep working;
  // only the neutral surfaces/text are pinned to the Flow tokens.
  static const Color flowBg = Color(0xFF0A090D); // app/page background (scaffold)
  static const Color flowLowest = Color(0xFF0E0C13); // info-flow sheet bg
  static const Color flowSurface = Color(0xFF14111B); // drawers, sheets, dialogs, cards
  static const Color flowRaised = Color(0xFF17131F); // raised card on surface
  static const Color flowInput = Color(0xFF1D1827); // input pills, chip wells
  static const Color flowDeep = Color(0xFF241E33); // deepest raised element
  static const Color flowBorder = Color(0xFF2E2940); // sheet/drawer borders
  static const Color flowBorderSoft = Color(0xFF262232); // card borders
  static const Color flowTextPrimary = Color(0xFFF2EDFA);
  static const Color flowTextBody = Color(0xFFDDD5EA);
  static const Color flowTextSecondary = Color(0xFF9C93AE);
  static const Color flowError = Color(0xFFE5766B);

  /// Scaffold/page background — darker than [ColorScheme.surface] (which is the
  /// card/drawer tone), matching the Flow layering. Dark mode only.
  Color? scaffoldBackground(ColorScheme scheme) {
    if (!isDark) return null;
    if (isAmoled) return Colors.black;
    return flowBg;
  }

  ColorScheme colorScheme() {
    if (isDark) {
      if (darkDynamic != null) {
        return darkDynamic!;
      }
    } else {
      if (lightDynamic != null) {
        return lightDynamic!;
      }
    }

    final brightness = isDark ? Brightness.dark : Brightness.light;
    final SchemeTonalSpot scheme = SchemeTonalSpot(
      // TODO replace value with toARGB32() in the next flutter release
      // ignore: deprecated_member_use
      sourceColorHct: Hct.fromInt(theme.accent!.value),
      isDark: brightness == Brightness.dark,
      contrastLevel: 0,
    );

    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: theme.accent!,
      primary: theme.primary,
      onPrimary: primaryIsDark ? Colors.white : Colors.black,
      secondary: theme.accent,
      onSecondary: accentIsDark ? Colors.white : Colors.black,
      surface: (isDark && isAmoled) ? Colors.black : Color(scheme.background),
      onSurface: Color(scheme.onBackground),
      error: Colors.redAccent,
      onError: Colors.white,
      brightness: brightness,
    );

    // In light mode, or AMOLED, keep the seed-generated scheme.
    if (!isDark || isAmoled) return base;

    // Dark mode: pin neutral surfaces/text to the Flow tokens (accent stays
    // theme-driven). This gives every screen the modern violet-near-black look
    // without hardcoding the accent.
    return base.copyWith(
      surface: flowSurface,
      onSurface: flowTextBody,
      surfaceContainerLowest: flowLowest,
      surfaceContainerLow: flowSurface,
      surfaceContainer: flowRaised,
      surfaceContainerHigh: flowInput,
      surfaceContainerHighest: flowDeep,
      onSurfaceVariant: flowTextSecondary,
      outline: flowBorder,
      outlineVariant: flowBorderSoft,
      surfaceTint: Colors.transparent,
      error: flowError,
      onError: Colors.white,
    );
  }

  TextTheme textTheme() {
    final baseTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    // Flow uses Manrope as the app-wide default; 'System' now maps to Manrope so
    // the typography reskin applies without the user having to pick a font. An
    // explicit font choice is still respected.
    final String font = fontFamily == 'System' ? 'Manrope' : fontFamily;

    try {
      return baseTheme.apply(
        fontFamily: GoogleFonts.getFont(font).fontFamily,
      );
    } catch (_) {
      return baseTheme;
    }
  }

  TextSelectionThemeData textSelectionTheme(ColorScheme colorScheme) => TextSelectionThemeData(
    cursorColor: colorScheme.secondary,
    selectionColor: Colors.blue.withValues(alpha: 0.66),
    selectionHandleColor: colorScheme.secondary,
  );

  ElevatedButtonThemeData elevatedButtonTheme(ColorScheme colorScheme) => ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: colorScheme.secondary,
      foregroundColor: accentIsDark ? Colors.white : Colors.black,
      iconColor: accentIsDark ? Colors.white : Colors.black,
      disabledForegroundColor: Colors.black,
      disabledBackgroundColor: Colors.grey,
      disabledIconColor: Colors.black,
      textStyle: TextStyle(
        fontFamily: textTheme().bodyMedium!.fontFamily,
        color: accentIsDark ? Colors.white : Colors.black,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      splashFactory: InkSparkle.splashFactory,
    ),
  );

  OutlinedButtonThemeData outlinedButtonTheme(ColorScheme colorScheme) => OutlinedButtonThemeData(
    style:
        OutlinedButton.styleFrom(
          side: BorderSide(color: colorScheme.secondary, width: 2.5),
          foregroundColor: colorScheme.secondary,
          textStyle: TextStyle(
            fontFamily: textTheme().bodyMedium!.fontFamily,
            color: colorScheme.secondary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith<BorderSide>(
            (states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: Colors.grey, width: 2.5);
              }

              return BorderSide(color: colorScheme.secondary, width: 2.5);
            },
          ),
        ),
  );

  AppBarTheme appBarTheme(ColorScheme colorScheme) {
    // Flow: dark, flat headers in dark mode (not the accent colour). Title/icons
    // in the primary text tone. Light mode keeps the classic primary bar.
    final Color barBg = isDark ? flowBg : colorScheme.primary;
    final Color barFg = isDark ? flowTextPrimary : (primaryIsDark ? Colors.white : Colors.black);
    return AppBarTheme(
      titleTextStyle: TextStyle(
        fontFamily: textTheme().bodyMedium!.fontFamily,
        color: barFg,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
      toolbarTextStyle: TextStyle(
        fontFamily: textTheme().bodyMedium!.fontFamily,
        color: barFg,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: barBg,
      foregroundColor: barFg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actionsIconTheme: IconThemeData(color: barFg),
      iconTheme: IconThemeData(color: barFg),
      titleSpacing: 8,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  ButtonThemeData buttonTheme(ColorScheme colorScheme) => ButtonThemeData(
    buttonColor: colorScheme.primary,
    textTheme: ButtonTextTheme.primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  FloatingActionButtonThemeData floatingActionButtonTheme(ColorScheme colorScheme) => FloatingActionButtonThemeData(
    backgroundColor: colorScheme.secondary,
    foregroundColor: accentIsDark ? Colors.white : Colors.black,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  IconThemeData iconTheme(ColorScheme colorScheme) => IconThemeData(
    color: colorScheme.onSurface,
    opacity: 1,
    size: 22,
  );

  InputDecorationTheme inputDecorationTheme(ColorScheme colorScheme) => InputDecorationTheme(
    fillColor: colorScheme.surfaceContainerHigh,
    filled: true,
    labelStyle: TextStyle(
      fontFamily: textTheme().bodyMedium!.fontFamily,
      color: isDark ? Colors.white : Colors.black,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    ),
    hintStyle: TextStyle(
      fontFamily: textTheme().bodyMedium!.fontFamily,
      color: isDark ? Colors.grey[300] : Colors.grey[900],
      fontSize: 18,
      fontWeight: FontWeight.w500,
    ),
    alignLabelWithHint: false,
    // contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Colors.transparent, width: 0),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.secondary, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.error, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.error, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    border: OutlineInputBorder(
      borderSide: const BorderSide(color: Colors.transparent, width: 0),
      borderRadius: BorderRadius.circular(8),
    ),
    disabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
  );

  MaterialBannerThemeData bannerTheme() => MaterialBannerThemeData(
    backgroundColor: Colors.red,
    contentTextStyle: TextStyle(
      fontFamily: textTheme().bodyMedium!.fontFamily,
      color: Colors.white,
    ),
  );

  CardThemeData cardTheme(ColorScheme colorScheme) => CardThemeData(
    color: colorScheme.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  PageTransitionsTheme pageTransitionsTheme() => PageTransitionsTheme(
    // ZoomPageTransitionsBuilder alternatives:
    // PredictiveBackPageTransitionsBuilder - android only, requires predictive back enabled, still wip
    // FadeForwardsPageTransitionsBuilder - latest material3 spec animation, currently conflicts with modal routes (and stuttering if there is a global restate?)
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: SettingsHandler.instance.usePredictiveBack
          ? const CustomPredictiveBackPageTransitionsBuilder()
          : const ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
      TargetPlatform.fuchsia: const ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: const ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: const ZoomPageTransitionsBuilder(),
    },
  );

  ScrollbarThemeData scrollbarTheme(ColorScheme colorScheme) => ScrollbarThemeData(
    thickness: WidgetStateProperty.resolveWith((states) {
      if (Platform.isAndroid || Platform.isIOS) {
        return 8;
      } else {
        final List<WidgetState> goodStates = [WidgetState.hovered, WidgetState.focused, WidgetState.pressed];
        for (final WidgetState state in states) {
          if (goodStates.contains(state)) {
            return 8;
          }
        }
        return 4;
      }
    }),
    interactive: true,
    thumbVisibility: WidgetStateProperty.resolveWith((states) {
      if (Platform.isAndroid || Platform.isIOS) {
        return true;
      } else {
        final List<WidgetState> goodStates = [WidgetState.hovered, WidgetState.focused, WidgetState.pressed];
        for (final WidgetState state in states) {
          if (goodStates.contains(state)) {
            return true;
          }
        }
        return false;
      }
    }),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      final List<WidgetState> goodStates = [WidgetState.hovered, WidgetState.focused, WidgetState.pressed];
      Color color = isDark ? Colors.grey[300]! : Colors.grey[900]!;
      color = colorScheme.secondary;
      for (final WidgetState state in states) {
        if (goodStates.contains(state)) {
          return color.withValues(alpha: 0.75);
        }
      }
      return color.withValues(alpha: 0.5);
    }),
    radius: const Radius.circular(10),
  );

  ProgressIndicatorThemeData progressIndicatorTheme(ColorScheme colorScheme) => ProgressIndicatorThemeData(
    color: colorScheme.secondary,
    circularTrackColor: colorScheme.secondaryContainer.withValues(alpha: 0.33),
    linearTrackColor: colorScheme.secondaryContainer.withValues(alpha: 0.33),
    trackGap: 5,
    refreshBackgroundColor: null,
    // ignore: deprecated_member_use
    year2023: true, // TODO change to false when they fix exception when value is null?
  );

  CheckboxThemeData checkboxTheme(ColorScheme colorScheme) => CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((states) {
      final bool isHovered = states.contains(WidgetState.hovered);
      if (states.contains(WidgetState.selected)) {
        final Color color = colorScheme.secondary;
        return isHovered ? Color.lerp(color, Colors.black, 0.15)! : color;
      } else {
        return isHovered ? Colors.grey[600] : Colors.grey;
      }
    }),
    checkColor: WidgetStateProperty.all(accentIsDark ? Colors.white : Colors.black),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  SwitchThemeData switchTheme(ColorScheme colorScheme) => SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      final bool isHovered = states.contains(WidgetState.hovered);
      if (states.contains(WidgetState.selected)) {
        final Color color = colorScheme.secondary;
        return isHovered ? Color.lerp(color, Colors.black, 0.2)! : color;
      } else {
        return isHovered ? Colors.grey[600] : Colors.grey[500];
      }
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      final bool isHovered = states.contains(WidgetState.hovered);
      if (states.contains(WidgetState.selected)) {
        final Color color = Color.lerp(colorScheme.secondary, Colors.white, 0.3)!;
        return isHovered ? Color.lerp(color, Colors.black, 0.2)! : color;
      } else {
        return isHovered ? Colors.grey[400] : Colors.grey[300];
      }
    }),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  SliderThemeData sliderTheme(ColorScheme colorScheme) => SliderThemeData(
    activeTrackColor: colorScheme.secondary,
    thumbColor: colorScheme.secondary,
    inactiveTrackColor: isDark ? Colors.grey[900]! : Colors.grey[300]!,
  );

  DrawerThemeData drawerTheme(ColorScheme colorScheme) => DrawerThemeData(
    elevation: 0,
    backgroundColor: colorScheme.surface,
    scrimColor: Colors.black.withValues(alpha: 0.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
    endShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
  );

  TabBarThemeData tabBarTheme(ColorScheme colorScheme) => TabBarThemeData(
    labelColor: colorScheme.secondary,
    unselectedLabelColor: isDark ? Colors.grey[300]! : Colors.grey[900]!,
    labelStyle: TextStyle(
      fontFamily: textTheme().bodyMedium!.fontFamily,
      fontWeight: FontWeight.w600,
    ),
    unselectedLabelStyle: TextStyle(
      fontFamily: textTheme().bodyMedium!.fontFamily,
      fontWeight: FontWeight.w400,
    ),
    indicatorSize: TabBarIndicatorSize.tab,
  );

  DropdownMenuThemeData dropdownMenuTheme(ColorScheme colorScheme) => DropdownMenuThemeData(
    menuStyle: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
    ),
  );

  DialogThemeData dialogTheme(ColorScheme colorScheme) => DialogThemeData(
    backgroundColor: colorScheme.surface,
  );

  DividerThemeData dividerTheme(ColorScheme colorScheme) => DividerThemeData(
    color: isDark ? flowBorder : Colors.grey[300],
    thickness: 1,
    space: 1,
    indent: 0,
    endIndent: 0,
  );
}

extension BrightnessExtension on Brightness {
  bool get isDark => this == Brightness.dark;
  bool get isLight => this == Brightness.light;
}
