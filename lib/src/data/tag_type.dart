import 'package:flutter/material.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

enum TagType {
  artist,
  character,
  copyright,
  meta,
  species,
  none
  ;

  bool get isArtist => this == TagType.artist;
  bool get isCharacter => this == TagType.character;
  bool get isCopyright => this == TagType.copyright;
  bool get isMeta => this == TagType.meta;
  bool get isSpecies => this == TagType.species;
  bool get isNone => this == TagType.none;

  static TagType fromString(String string) {
    switch (string) {
      case 'artist':
        return TagType.artist;
      case 'character':
        return TagType.character;
      case 'copyright':
        return TagType.copyright;
      case 'meta':
        return TagType.meta;
      case 'species':
        return TagType.species;
      default:
        return TagType.none;
    }
  }

  @override
  String toString() {
    return name;
  }

  // "Flow" tag-type palette — softened, on-theme hues (chip text + left bar +
  // dot). Chip fill/border derive from these at low alpha in the chip widgets.
  Color? getColour() {
    switch (this) {
      case artist:
        return const Color(0xFFE890A5);
      case character:
        return const Color(0xFF8FCB94);
      case copyright:
        return const Color(0xFFCB9CD4);
      case meta:
        return const Color(0xFFE5B36B);
      case species:
        return const Color(0xFFC8A98B);
      default:
        return null;
    }
  }

  String get locName {
    final ctx = NavigationHandler.instance.navContext;
    switch (this) {
      case artist:
        return ctx.loc.tagType.artist;
      case character:
        return ctx.loc.tagType.character;
      case copyright:
        return ctx.loc.tagType.copyright;
      case meta:
        return ctx.loc.tagType.meta;
      case species:
        return ctx.loc.tagType.species;
      case none:
        return ctx.loc.tagType.none;
    }
  }
}
