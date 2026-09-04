import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/drawer_refresh.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/inner_drawer.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/downloads_drawer.dart';
import 'package:lolisnatcher/src/widgets/drawers/kemono_sidebar.dart';
import 'package:lolisnatcher/src/widgets/drawers/main_drawer.dart';
import 'package:lolisnatcher/src/widgets/preview/media_previews.dart';

class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();

  bool isDrawerOpened = false;

  void _toggleDrawer(InnerDrawerDirection? dir) {
    final state = searchHandler.mainDrawerKey.currentState;
    if (state is! InnerDrawerState) {
      return;
    }

    // if not set, the last direction will be used
    // InnerDrawerDirection.start OR InnerDrawerDirection.end
    state.toggle(direction: dir);
  }

  Future<void> _onPopInvoked(bool didPop, _) async {
    if (didPop) {
      return;
    }

    final result = await _onBackPressed();
    if (result) {
      if (Platform.isAndroid) {
        // will close the app completely
        await SystemNavigator.pop();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _onBackPressed() async {
    if (isDrawerOpened) {
      // close the drawer if it's opened
      _toggleDrawer(null);
      return false;
    }

    // ... otherwise, ask to close the app
    final bool? shouldPop = await showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: Text(context.loc.exitTheAppQuestion),
          actionButtons: [
            ElevatedButton.icon(
              label: Text(context.loc.no),
              icon: const Icon(Symbols.cancel_rounded),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton.icon(
              label: Text(context.loc.yes),
              icon: const Icon(Symbols.exit_to_app_rounded),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (BuildContext context, Orientation orientation) {
        return Obx(() {
          // A doujin tab has no booru drawers: its right edge belongs to the
          // mini tab manager, and there are no pinned tags / booru settings to
          // slide in. Disable the InnerDrawer swipe entirely for those tabs.
          final bool isDoujinTab = searchHandler.tabs.isNotEmpty && searchHandler.currentTab.isDoujinDetail;
          // On a Kemono tab the pinned-tags side carries the site's own
          // sidebar instead, unless the person switched it off from its
          // bottom row (the normal drawer's Quick access switches it back).
          final Booru? current = searchHandler.tabs.isNotEmpty ? searchHandler.currentBooru : null;
          final bool kemonoSide = (current?.type?.isKemono ?? false) && settingsHandler.kemonoSidebar.value;
          Widget pinnedSide() => kemonoSide
              ? KemonoSidebar(booru: current!, toggleDrawer: () => _toggleDrawer(null))
              : DownloadsDrawer(toggleDrawer: () => _toggleDrawer(null));
        return InnerDrawer(
          key: searchHandler.mainDrawerKey,
          onTapClose: true,
          swipe: !isDoujinTab,
          swipeChild: !isDoujinTab,

          //When setting the vertical offset, be sure to use only top or bottom
          offset: IDOffset.only(
            bottom: 0,
            right: orientation.isLandscape ? 0 : 0.5,
            left: orientation.isLandscape ? 0 : 0.5,
          ),
          scale: const IDOffset.horizontal(1),

          proportionalChildArea: true,
          borderRadius: 10,
          leftAnimationType: InnerDrawerAnimation.quadratic,
          rightAnimationType: InnerDrawerAnimation.quadratic,
          backgroundDecoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),

          //when a pointer that is in contact with the screen and moves to the right or left
          onDragUpdate: (double val, InnerDrawerDirection? direction) {
            // return values between 1 and 0
            // print(val);
            // check if the swipe is to the right or to the left
            // print(direction==InnerDrawerDirection.start);
          },

          innerDrawerCallback: (bool isOpen, InnerDrawerDirection? direction) {
            isDrawerOpened = isOpen;
            // Opening a drawer is the moment its cached counts/pins must be
            // current — they are not observable, so they are re-read here.
            if (isOpen) DrawerRefresh.request();
          }, // return  true (open) or false (close)

          leftChild: RepaintBoundary(
            child: settingsHandler.handSide.value.isLeft ? const MainDrawer() : pinnedSide(),
          ),
          rightChild: RepaintBoundary(
            child: settingsHandler.handSide.value.isRight ? const MainDrawer() : pinnedSide(),
          ),

          // Note: use "automaticallyImplyLeading: false" if you do not personalize "leading" of Bar
          scaffold: Scaffold(
            key: mainScaffoldKey,
            resizeToAvoidBottomInset: false,
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: SafeArea(
              top: false,
              bottom: false,
              child: PopScope(
                canPop: false,
                onPopInvokedWithResult: _onPopInvoked,
                child: const RepaintBoundary(child: MediaPreviews()),
              ),
            ),
          ),
        );
        });
      },
    );
  }
}
