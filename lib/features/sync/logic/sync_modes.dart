import 'package:lolisnatcher/gen/strings.g.dart';

/// What a LoliSync run does with tabs and tags, and which side this device is.
enum SyncSide {
  none,
  receiver,
  sender,
}

enum TabsMode {
  merge,
  replace,
  ;

  bool get isMerge => this == TabsMode.merge;
  bool get isReplace => this == TabsMode.replace;

  String get value {
    switch (this) {
      case TabsMode.merge:
        return 'Merge';
      case TabsMode.replace:
        return 'Replace';
    }
  }

  static TabsMode get defaultValue => TabsMode.merge;

  static TabsMode fromString(String value) {
    switch (value) {
      case 'Merge':
      case 'merge':
        return TabsMode.merge;
      case 'Replace':
      case 'replace':
        return TabsMode.replace;
    }

    return TabsMode.merge;
  }

  String get locName {
    switch (this) {
      case TabsMode.merge:
        return loc.settings.sync.merge;
      case TabsMode.replace:
        return loc.settings.sync.replace;
    }
  }
}

enum TagsMode {
  overwrite,
  preferTypeIfNone,
  ;

  bool get isOverwrite => this == TagsMode.overwrite;
  bool get isPreferTypeIfNone => this == TagsMode.preferTypeIfNone;

  String get value {
    switch (this) {
      case TagsMode.overwrite:
        return 'Overwrite';
      case TagsMode.preferTypeIfNone:
        return 'PreferTypeIfNone';
    }
  }

  static TagsMode get defaultValue => TagsMode.preferTypeIfNone;

  static TagsMode fromString(String value) {
    switch (value) {
      case 'Overwrite':
      case 'overwrite':
        return TagsMode.overwrite;
      case 'PreferTypeIfNone':
      case 'preferTypeIfNone':
        return TagsMode.preferTypeIfNone;
    }

    return TagsMode.preferTypeIfNone;
  }

  String get locName {
    switch (this) {
      case TagsMode.overwrite:
        return loc.settings.sync.overwrite;
      case TagsMode.preferTypeIfNone:
        return loc.settings.sync.preferTypeIfNone;
    }
  }
}
