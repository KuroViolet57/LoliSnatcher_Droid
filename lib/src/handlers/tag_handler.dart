import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class UntypedCollection {
  UntypedCollection(this.tags, this.cooldown, this.booru);
  final List<String> tags;
  final int cooldown;
  final Booru booru;
}

class TagHandler {
  TagHandler() {
    untypedQueue.addListener(queueListener);
  }

  static TagHandler get instance => GetIt.instance<TagHandler>();

  static TagHandler register() {
    if (!GetIt.instance.isRegistered<TagHandler>()) {
      GetIt.instance.registerSingleton(
        TagHandler(),
        dispose: (tagHandler) => tagHandler.dispose(),
      );
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<TagHandler>();

  int prevLength = 0;
  final Map<String, Tag> _tagMap = {};
  Map<String, Tag> get tagMap => _tagMap; // TODO read only (or is it?)

  ValueNotifier<List<UntypedCollection>> untypedQueue = ValueNotifier([]);
  ValueNotifier<bool> tagFetchActive = ValueNotifier(false);
  bool tagSaveActive = false;

  void queueListener() {
    tryGetTagTypes();
  }

  void dispose() {
    untypedQueue.removeListener(queueListener);
  }

  bool hasTag(String tagString) {
    return tagMap.containsKey(tagString.toLowerCase());
  }

  /// Check if tag is in the tag map and if it is - check if it is not outdated/stale
  bool hasTagAndNotStale(String tagString, {int staleTime = Constants.tagStaleTime}) {
    if (hasTag(tagString)) {
      final bool isNotStale = getTag(tagString).updatedAt >= (DateTime.now().millisecondsSinceEpoch - staleTime);
      return isNotStale;
    } else {
      return false;
    }
  }

  Tag getTag(String tagString) {
    tagString = tagString.toLowerCase();
    Tag? tag;
    if (hasTag(tagString)) {
      tag = tagMap[tagString];
    }
    return tag ?? Tag(tagString, tagType: TagType.none);
  }

  /// The tag as a SPECIFIC booru sees it.
  ///
  /// [tagMap] holds one type per tag string for the whole app, so the last
  /// site you browsed wins whenever two disagree. This applies your per-booru
  /// correction on top without touching that shared state — see
  /// [BooruTagStore] for why the two are kept apart. Falls back to the global
  /// answer when you have not corrected this pair, which is almost always.
  Tag getTagFor(String tagString, Booru? booru) {
    final Tag base = getTag(tagString);
    final TagType? mine = BooruTagStore.manualType(tagString, booru);
    if (mine == null || mine == base.tagType) return base;
    return base.copyWith(tagType: mine);
  }

  /// Domain-aware type lookup for DISPLAY (chip colours, type labels, icons).
  ///
  /// The shared tag map is a BOORU store: two sites that use the same tag
  /// name for different things overwrite each other in it, and a doujin
  /// source must not be coloured by a booru's classification of a coinciding
  /// name. Doujin tags already carry the site's own type, so on a doujin
  /// source the caller's [ownType] is the whole answer and the shared map is
  /// never consulted.
  TagType typeForDisplay(String tagString, Booru? booru, {TagType? ownType}) {
    if (ownType != null && ownType != TagType.none) return ownType;
    if (DoujinDataHandler.isDoujinBooru(booru)) return TagType.none;
    return getTagFor(tagString, booru).tagType;
  }

  /// The colour [typeForDisplay] resolves to, or null for an untyped tag.
  Color? colourForDisplay(String tagString, Booru? booru, {TagType? ownType}) {
    final Color? colour = typeForDisplay(tagString, booru, ownType: ownType).getColour();
    return colour == Colors.transparent ? null : colour;
  }

  Future<void> putTag(
    Tag tag, {
    required bool dbEnabled,
    bool useDB = true,
    bool preferTypeIfNone = false,
  }) async {
    tag.fullString = tag.fullString.trim().toLowerCase();
    if (tag.fullString.isEmpty) {
      return;
    }
    if (preferTypeIfNone && hasTag(tag.fullString)) {
      if (getTag(tag.fullString).tagType != TagType.none && tag.tagType == TagType.none) {
        Logger.Inst().log(
          'Skipped tag ${tag.fullString}',
          'TagHandler',
          'putTag',
          LogTypes.tagHandlerInfo,
        );
        return;
      }
    }
    _tagMap[tag.fullString] = tag;

    if (dbEnabled && useDB) {
      await SettingsHandler.instance.dbHandler.updateTagsFromObjects([tag]);
    }
    return;
  }

  void tryGetTagTypes() {
    if (!tagFetchActive.value) {
      if (untypedQueue.value.isNotEmpty) {
        getTagTypes(untypedQueue.value.removeLast());
      }
    }
  }

  Future getTagTypes(UntypedCollection untyped) async {
    if (SettingsHandler.instance.tagTypeFetchEnabled) {
      final bool dbEnabled = SettingsHandler.instance.dbEnabled;

      Logger.Inst().log('Snatching tags: ${untyped.tags}', 'TagHandler', 'getTagTypes', LogTypes.tagHandlerInfo);
      tagFetchActive.value = true;
      final temp = BooruHandlerFactory().getBooruHandler([untyped.booru], null);

      BooruHandler booruHandler = temp.booruHandler;
      if (booruHandler.shouldPopulateTags == false) {
        // if current booru doesn't support tag data, use other booru (if available) that supports it
        final boorusWithTagPopulation = SettingsHandler.instance.booruList.where(
          (b) => BooruHandlerFactory().getBooruHandler([b], null).booruHandler.shouldPopulateTags == true,
        );
        booruHandler = boorusWithTagPopulation.isEmpty
            ? booruHandler
            : BooruHandlerFactory().getBooruHandler([boorusWithTagPopulation.first], null).booruHandler;
      }

      int tagCounter = 0;
      while (untyped.tags.isNotEmpty) {
        final List<String> workingTags = [];
        const int tagMaxLimit = 100;
        final int tagMax = (untyped.tags.length > tagMaxLimit) ? tagMaxLimit : untyped.tags.length;

        for (int i = 0; i < tagMax; i++) {
          if (untyped.tags.isNotEmpty) {
            final String tag = untyped.tags.removeLast();
            if (!hasTagAndNotStale(tag) && !workingTags.contains(tag)) {
              workingTags.add(tag);
            }
          }
        }

        if (workingTags.isNotEmpty) {
          final List<Tag> newTags = await booruHandler.genTagObjects(workingTags);
          for (final Tag tag in newTags) {
            // Cross-booru enrichment is fill-in-only: a parsing handler that
            // ran `addTagsWithType` already wrote the authoritative type for
            // a given booru. We must NOT let a different booru's
            // genTagObjects response downgrade or change that type.
            // Only overwrite when the cached entry is still `none`.
            final bool cachedHasType =
                hasTag(tag.fullString) && getTag(tag.fullString).tagType != TagType.none;
            if (cachedHasType && tag.tagType != TagType.none) {
              continue;
            }
            await putTag(
              tag,
              dbEnabled: dbEnabled,
              preferTypeIfNone: true,
            );

            //TODO write tag to database
            tagCounter++;
          }
          await Future.delayed(Duration(milliseconds: untyped.cooldown), () async {});
        }
      }
      Logger.Inst().log(
        'Got $tagCounter tag types, untyped list length was: ${untyped.tags.length}',
        'TagHandler',
        'getTagTypes',
        LogTypes.tagHandlerInfo,
      );
      tagFetchActive.value = false;
    }
    tryGetTagTypes();
  }

  /// Stores given tags list with given type.
  ///
  /// Parsing handlers call this during item parsing with the type they
  /// know to be correct for the current booru (e.g. e621 classifies "human"
  /// as `species`). That classification is authoritative for that booru, so
  /// a non-none type ALWAYS overwrites whatever may be cached from another
  /// booru's previous visit. We just skip the write when the cached type is
  /// already identical, to avoid DB churn on repeat browsing.
  ///
  /// For `none` (general) writes we only seed unknown tags; we never
  /// downgrade a typed tag back to none.
  Future<void> addTagsWithType(List<String> tags, TagType type) async {
    final dbEnabled = SettingsHandler.instance.dbEnabled;

    for (final String tag in tags) {
      final String lower = tag.trim().toLowerCase();
      if (lower.isEmpty) continue;

      final bool exists = hasTag(lower);
      final TagType cachedType = exists ? getTag(lower).tagType : TagType.none;

      if (type != TagType.none) {
        if (!exists || cachedType != type) {
          await putTag(Tag(lower, tagType: type), dbEnabled: dbEnabled);
        }
      } else {
        if (!exists) {
          await putTag(Tag(lower, tagType: type), dbEnabled: dbEnabled);
        }
      }
    }
  }

  void queue(List<String> untypedTags, Booru booru, int cooldown) {
    Logger.Inst().log(
      // Type included: a booru's NAME says nothing about which API a tab is
      // actually talking to, which made a mis-typed config (loading a
      // completely different site's content under your name for it) hard to
      // spot in logs.
      'Added ${untypedTags.length} tags to queue from ${booru.name} [${booru.type?.name}]',
      'TagHandler',
      'queue',
      LogTypes.tagHandlerInfo,
    );
    if (untypedTags.isNotEmpty) {
      untypedQueue.value.add(UntypedCollection(untypedTags, cooldown, booru));
    }
  }

  Future<void> initialize() async {
    if (SettingsHandler.instance.path.isNotEmpty) {
      await loadTags();
    }
    // Your per-booru corrections are small and consulted on every tag chip
    // build, so they are held in memory from here on.
    await BooruTagStore.load();
  }

  Future<bool> loadTags() async {
    try {
      final bool dbEnabled = SettingsHandler.instance.dbEnabled;
      if (dbEnabled) {
        final List<Tag> tags = await SettingsHandler.instance.dbHandler.getAllTags();
        for (final Tag tag in tags) {
          await putTag(tag, useDB: false, dbEnabled: dbEnabled);
        }
      } else {
        if (await checkForTagsFile()) {
          await loadTagsFile();
        }
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Error loading tags: $e',
        'TagHandler',
        'loadTags',
        LogTypes.exception,
        s: s,
      );
    }

    return true;
  }

  Future<bool> checkForTagsFile() {
    final File tagFile = File('${SettingsHandler.instance.path}tags.json');
    return tagFile.exists();
  }

  Future<void> loadTagsFile() async {
    final File tagFile = File('${SettingsHandler.instance.path}tags.json');
    final String jsonString = await tagFile.readAsString();
    await loadFromJSON(jsonString);
    return;
  }

  Future<bool> loadFromJSON(
    String jsonString, {
    bool preferTagTypeIfNone = false,
    void Function(int progress, int total)? onProgress,
  }) async {
    try {
      final bool dbEnabled = SettingsHandler.instance.dbEnabled;

      final List jsonList = jsonDecode(jsonString);
      for (final Map<String, dynamic> rawTag in jsonList) {
        try {
          final Tag tagObject = Tag.fromJson(rawTag);
          await putTag(
            tagObject,
            preferTypeIfNone: preferTagTypeIfNone,
            dbEnabled: dbEnabled,
          );
          if (onProgress != null) {
            onProgress(jsonList.indexOf(rawTag), jsonList.length);
          }
          Logger.Inst().log(
            'Parsed tag: $rawTag',
            'TagHandler',
            'loadFromJSON',
            LogTypes.tagHandlerInfo,
          );
        } catch (e, s) {
          Logger.Inst().log(
            'Error parsing tag: $rawTag',
            'TagHandler',
            'loadFromJSON',
            LogTypes.exception,
            s: s,
          );
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'Error loading tags from JSON: $e',
        'TagHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  List<Tag> toList() {
    final List<Tag> tagList = [];
    tagMap.forEach((key, value) => tagList.add(value));
    return tagList;
  }

  void removeTag(Tag tag) {
    _tagMap.remove(tag.fullString);
  }

  Future<void> saveTags() async {
    tagSaveActive = true;
    final SettingsHandler settings = SettingsHandler.instance;
    await getStoragePermission();
    prevLength = tagMap.entries.length;
    if (settings.dbEnabled) {
      //await settings.dbHandler.updateTagsFromObjects(toList());
    } else {
      try {
        if (settings.path == '') {
          await settings.setConfigDir();
        }
        await Directory(settings.path).create(recursive: true);
        final File tagFile = File('${settings.path}tags.json');
        final writer = tagFile.openWrite();
        writer.write(jsonEncode(toList()));
        await writer.flush();
        await writer.close();
      } catch (e, s) {
        Logger.Inst().log(
          'FAILED TO WRITE TAG FILE: $e',
          'TagHandler',
          'saveTags',
          LogTypes.exception,
          s: s,
        );
      }
    }
    tagSaveActive = false;
    return;
  }
}
