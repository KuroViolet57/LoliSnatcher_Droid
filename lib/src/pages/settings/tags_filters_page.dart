import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:lolisnatcher/src/data/tag.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_add_dialog.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_edit_dialog.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_list.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_settings_list.dart';

class TagsFiltersPage extends StatefulWidget {
  const TagsFiltersPage({super.key});

  @override
  State<TagsFiltersPage> createState() => _TagsFiltersPageState();
}

class _TagsFiltersPageState extends State<TagsFiltersPage> with SingleTickerProviderStateMixin {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late TabController tabController;
  final ScrollController scrollController = ScrollController();
  final TextEditingController tagSearchController = TextEditingController();

  List<String> hiddenList = [];
  List<String> markedList = [];
  bool filterHated = false, filterMarked = false, filterFavourites = false, filterSnatched = false, filterAi = false;

  @override
  void initState() {
    super.initState();

    hiddenList = settingsHandler.hiddenTags.toList();
    hiddenList.sort(sortTags);

    markedList = settingsHandler.markedTags.toList();
    markedList.sort(sortTags);

    filterHated = settingsHandler.filterHated;
    filterMarked = settingsHandler.filterMarked;
    filterFavourites = settingsHandler.filterFavourites;
    filterSnatched = settingsHandler.filterSnatched;
    filterAi = settingsHandler.filterAi;

    tabController = TabController(vsync: this, length: 3)..addListener(updateState);
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showBlacklistHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Blacklist syntax'),
        content: const SingleChildScrollView(
          child: Text(
            'Each entry is a "line" in the e621-style blacklist. A post is hidden '
            'if any line matches it.\n\n'
            'Within a line, tokens are separated by spaces and combined with AND:\n\n'
            '  male solo\n'
            '    → hides posts that have BOTH male AND solo.\n\n'
            'Prefix a token with - to require its absence:\n\n'
            '  fox -wolf -lion\n'
            '    → hides fox posts that have NEITHER wolf NOR lion.\n\n'
            '  -female\n'
            '    → hides every post WITHOUT the female tag.\n\n'
            'Prefix tokens with ~ for OR (at least one must match):\n\n'
            '  ~wolf ~lion\n'
            '    → hides posts that have EITHER wolf OR lion.\n\n'
            '  male ~wolf ~lion -fox\n'
            '    → hides posts with male AND (wolf OR lion) AND NO fox.\n\n'
            'Metatags also work:\n\n'
            '  rating:e  rating:q  rating:s\n'
            '  score:<0   score:>=100   score:50..100\n'
            '  id:1234   width:>2000   filesize:>5mb\n'
            '  username:someone   userid:1234   uploader:!1234\n\n'
            'Lines starting with # are comments and ignored.\n\n'
            'Tip: existing single-tag entries keep working — they are just lines '
            'with one token.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    tagSearchController.dispose();
    tabController.removeListener(updateState);
    tabController.dispose();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    settingsHandler.hiddenTags = settingsHandler.cleanTagsList(hiddenList.map(Tag.new).toList()).toSet();
    settingsHandler.invalidateBlacklistCache();
    settingsHandler.markedTags = settingsHandler.cleanTagsList(markedList.map(Tag.new).toList()).toSet();
    settingsHandler.filterHated = filterHated;
    settingsHandler.filterMarked = filterMarked;
    settingsHandler.filterFavourites = filterFavourites;
    settingsHandler.filterSnatched = filterSnatched;
    settingsHandler.filterAi = filterAi;
    await settingsHandler.saveSettings(restate: false);
  }

  List<String> getTagsList(String type) {
    List<String> tagsList = [];
    if (type == 'Hidden') {
      tagsList = hiddenList;
    } else if (type == 'Marked') {
      tagsList = markedList;
    }
    return tagsList;
  }

  int sortTags(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  void addTag(String newTag, String type) {
    if (newTag.isEmpty) {
      return;
    }

    final List<String> changedList = getTagsList(type);
    if (changedList.contains(newTag)) {
      duplicateMessage(newTag, type);
    } else {
      changedList.add(newTag);
      changedList.sort(sortTags);
      updateState();
    }
  }

  void editTag(String oldTag, String newTag, String type) {
    if (newTag.isEmpty) {
      return;
    }

    final List<String> changedList = getTagsList(type);
    if (changedList.contains(newTag)) {
      duplicateMessage(newTag, type);
    } else {
      final int index = changedList.indexOf(oldTag);
      changedList[index] = newTag;
      changedList.sort(sortTags);
      updateState();
    }
  }

  void deleteTag(String tag, String type) {
    final List<String> changedList = getTagsList(type);
    changedList.remove(tag);
    changedList.sort(sortTags);
    updateState();
  }

  void duplicateMessage(String tag, String type) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(context.loc.settings.itemFilters.duplicateFilter, style: const TextStyle(fontSize: 20)),
      content: Text(
        context.loc.settings.itemFilters.alreadyInList(tag: tag, type: type),
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Symbols.warning_amber_rounded,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
    );
  }

  void openAddDialog(String type) {
    SettingsPageOpen(
      context: context,
      asDialog: true,
      page: (_) => TagsFiltersAddDialog(
        tagFilterType: type,
        onAdd: (String newTag) => addTag(newTag, type),
      ),
    ).open();
  }

  void openEditDialog(String tag, String type) {
    SettingsPageOpen(
      context: context,
      asDialog: true,
      page: (_) => TagsFiltersEditDialog(
        tag: tag,
        onEdit: (String newTag) => editTag(tag, newTag, type),
        onDelete: (String tag) => deleteTag(tag, type),
      ),
    ).open();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(context.loc.settings.itemFilters.title),
          actions: [
            IconButton(
              icon: const Icon(Symbols.help_rounded),
              tooltip: 'Blacklist syntax',
              onPressed: _showBlacklistHelp,
            ),
          ],
          bottom: TabBar(
            controller: tabController,
            indicatorColor: Theme.of(context).colorScheme.secondary,
            onTap: (_) => tagSearchController.clear(),
            labelColor: Theme.of(context).colorScheme.onSecondary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.66),
            labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 16),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(
                  CupertinoIcons.eye_slash,
                  size: 24,
                  color: Colors.red,
                ),
                height: 60,
                child: Center(
                  child: MarqueeText(
                    text: context.loc.settings.itemFilters.hidden,
                    isExpanded: false,
                  ),
                ),
              ),
              Tab(
                icon: const Icon(
                  Symbols.star_rounded,
                  size: 24,
                  color: Colors.yellow,
                ),
                height: 60,
                child: MarqueeText(
                  text: context.loc.settings.itemFilters.marked,
                  isExpanded: false,
                ),
              ),
              Tab(
                icon: Icon(
                  Symbols.settings_rounded,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                height: 60,
                child: MarqueeText(
                  text: context.loc.settings.title,
                  isExpanded: false,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: tabController.index < 2
            ? FloatingActionButton(
                onPressed: () {
                  openAddDialog(tabController.index == 0 ? 'Hidden' : 'Marked');
                },
                child: const Icon(Symbols.add_rounded),
              )
            : null,
        body: TabBarView(
          controller: tabController,
          children: [
            TagsFiltersList(
              tagsList: hiddenList,
              filterTagsType: 'Hidden',
              onTagSelected: (String tag) {
                openEditDialog(tag, 'Hidden');
              },
              onSearchTextChanged: (String newText) {
                updateState();
              },
              scrollController: scrollController,
              tagSearchController: tagSearchController,
              openAddDialog: () => openAddDialog('Hidden'),
            ),
            TagsFiltersList(
              tagsList: markedList,
              filterTagsType: 'Marked',
              onTagSelected: (String tag) {
                openEditDialog(tag, 'Marked');
              },
              onSearchTextChanged: (String newText) {
                updateState();
              },
              scrollController: scrollController,
              tagSearchController: tagSearchController,
              openAddDialog: () => openAddDialog('Marked'),
            ),
            TagsFiltersSettingsList(
              scrollController: scrollController,
              filterHated: filterHated,
              onFilterHatedChanged: (bool newValue) {
                filterHated = newValue;
                updateState();
              },
              filterMarked: filterMarked,
              onFilterMarkedChanged: (bool newValue) {
                filterMarked = newValue;
                updateState();
              },
              filterFavourites: filterFavourites,
              onFilterFavouritesChanged: (bool newValue) {
                filterFavourites = newValue;
                updateState();
              },
              filterSnatched: filterSnatched,
              onFilterSnatchedChanged: (bool newValue) {
                filterSnatched = newValue;
                updateState();
              },
              filterAi: filterAi,
              onFilterAiChanged: (bool newValue) {
                filterAi = newValue;
                updateState();
              },
            ),
          ],
        ),
      ),
    );
  }
}
