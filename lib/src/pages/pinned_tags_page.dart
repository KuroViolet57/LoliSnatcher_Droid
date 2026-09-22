import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag_visibility.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/followed_artists_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart' show doujinPinsAsPinnedTags;

/// Tag suggestions for the pin builder.
typedef PinTagSuggester = Future<List<TagSuggestion>> Function(String input);

/// Where a source's pins are kept: the database for boorus, the doujin store
/// (which keeps no names or order) for doujin sources.
abstract class PinnedTagsStore {
  const PinnedTagsStore();

  factory PinnedTagsStore.forBooru(Booru booru) =>
      DoujinDataHandler.isDoujinBooru(booru) ? _DoujinPinnedTagsStore(booru) : _DbPinnedTagsStore(booru);

  bool get supportsTitles;

  /// The source's own pins and the global ones.
  Future<List<PinnedTag>> list();

  Future<void> add(String tags, {String? title, required bool global});

  Future<void> update(PinnedTag pin, String tags, {String? title, required bool global});

  Future<void> remove(PinnedTag pin);

  Future<void> reorder(List<PinnedTag> ordered);
}

class _DbPinnedTagsStore extends PinnedTagsStore {
  const _DbPinnedTagsStore(this.booru);

  final Booru booru;

  @override
  bool get supportsTitles => true;

  @override
  Future<List<PinnedTag>> list() async {
    // r79: hides left by pins deleted before r79 are dropped here, where every
    // database pin can be read; they would hide a new pin that reuses the id.
    if (SettingsHandler.instance.dbHandler.db != null) {
      try {
        PinnedTagVisibility.forgetMissing(await SettingsHandler.instance.dbHandler.getAllPinnedTags());
      } catch (_) {}
    }
    return SettingsHandler.instance.dbHandler.getPinnedTags(booruType: booru.type?.name, booruName: booru.name);
  }

  @override
  Future<void> add(String tags, {String? title, required bool global}) async {
    await SettingsHandler.instance.dbHandler.addPinnedTag(
      tags,
      booruType: global ? null : booru.type?.name,
      booruName: global ? null : booru.name,
      title: title,
    );
  }

  @override
  Future<void> update(PinnedTag pin, String tags, {String? title, required bool global}) =>
      SettingsHandler.instance.dbHandler.updatePinnedTag(
        pin.id,
        tagName: tags,
        title: title,
        booruType: global ? null : booru.type?.name,
        booruName: global ? null : booru.name,
      );

  @override
  Future<void> remove(PinnedTag pin) => SettingsHandler.instance.dbHandler.removePinnedTag(pin.id);

  @override
  Future<void> reorder(List<PinnedTag> ordered) => SettingsHandler.instance.dbHandler.updatePinnedTagsOrder(ordered);
}

class _DoujinPinnedTagsStore extends PinnedTagsStore {
  const _DoujinPinnedTagsStore(this.booru);

  final Booru booru;

  @override
  bool get supportsTitles => false;

  /// The doujin adapter gives every pin id -1 and marks a pin for every doujin
  /// source with a label: distinct ids (the list's keys) and a real scope.
  @override
  Future<List<PinnedTag>> list() async => [
    for (final (int i, PinnedTag p) in doujinPinsAsPinnedTags(booru).indexed)
      PinnedTag(
        id: -(i + 1),
        tagName: p.tagName,
        pinnedAt: p.pinnedAt,
        booruName: p.labels.isEmpty ? booru.name : null,
        booruType: p.labels.isEmpty ? booru.type : null,
      ),
  ];

  @override
  Future<void> add(String tags, {String? title, required bool global}) async =>
      DoujinDataHandler.instance.addPin(tags, booru, global: global);

  @override
  Future<void> update(PinnedTag pin, String tags, {String? title, required bool global}) async {
    DoujinDataHandler.instance.removePin(pin.tagName, booru);
    DoujinDataHandler.instance.addPin(tags, booru, global: global);
  }

  @override
  Future<void> remove(PinnedTag pin) async => DoujinDataHandler.instance.removePin(pin.tagName, booru);

  @override
  Future<void> reorder(List<PinnedTag> ordered) async {}
}

/// Tag suggestions for a source's pin builder (r52): the tag index pulled for
/// it first, then the tags the app has seen, then the site's own autocomplete.
class PinTagSuggestions {
  const PinTagSuggestions._();

  static PinTagSuggester forBooru(Booru booru) {
    BooruHandler? handler;
    return (String input) async {
      final String query = input.trim().replaceFirst(RegExp('^[-~]'), '');
      if (query.isEmpty) return const [];
      final List<TagSuggestion> out = [];
      final Set<String> seen = {};
      void add(String tag, TagType type) {
        if (tag.isNotEmpty && seen.add(tag.toLowerCase())) out.add(TagSuggestion(tag: tag, type: type));
      }

      for (final BooruTagEntry e in await BooruTagStore.browse(booru, query: query, limit: 10)) {
        add(e.name, e.tagType);
      }
      if (out.length < 8) {
        try {
          for (final String tag in await SettingsHandler.instance.dbHandler.getTags(query, 10)) {
            add(tag, TagHandler.instance.getTag(tag).tagType);
          }
        } catch (_) {}
      }
      if (out.length < 5) {
        try {
          handler ??= BooruHandlerFactory().getBooruHandler([booru], null).booruHandler;
          if (handler!.hasTagSuggestions) {
            final res = await handler!.getTagSuggestions(query);
            res.fold((_) {}, (data) {
              for (final TagSuggestion s in data) {
                add(s.tag, s.type);
              }
            });
          }
        } catch (_) {}
      }
      return out.take(10).toList();
    };
  }
}

/// A source's pinned tags (r50, Quick access in the left sidebar): pins of
/// one or several tags, named, reordered, edited, hidden on this source (r52)
/// and deleted. A tap searches the pin in a new tab on that source.
class PinnedTagsPage extends StatefulWidget {
  const PinnedTagsPage({required this.booru, this.store, this.onOpen, this.suggest, super.key});

  final Booru booru;

  /// Replaced in tests.
  final PinnedTagsStore? store;

  /// Replaces the default (a new tab on [booru]).
  final ValueChanged<String>? onOpen;

  /// Replaces the default [PinTagSuggestions.forBooru].
  final PinTagSuggester? suggest;

  @override
  State<PinnedTagsPage> createState() => _PinnedTagsPageState();
}

class _PinnedTagsPageState extends State<PinnedTagsPage> {
  late final PinnedTagsStore store = widget.store ?? PinnedTagsStore.forBooru(widget.booru);
  late final PinTagSuggester suggest = widget.suggest ?? PinTagSuggestions.forBooru(widget.booru);

  List<PinnedTag> pins = [];
  bool loading = true;

  String get sourceName => widget.booru.name ?? 'this source';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<PinnedTag> all = [];
    try {
      all = await store.list();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      // Follows are labelled pins with their own page.
      pins = all.where((p) => !FollowedArtistsHandler.isFollowPin(p)).toList();
      loading = false;
    });
  }

  void _open(PinnedTag pin) {
    if (widget.onOpen != null) {
      widget.onOpen!(pin.tagName);
      return;
    }
    SearchHandler.instance.addTabByString(pin.tagName, customBooru: widget.booru, switchToNew: true);
    Navigator.of(context).pop();
  }

  Future<void> _edit([PinnedTag? pin]) async {
    final PinBuilderResult? result = await showModalBottomSheet<PinBuilderResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PinBuilderSheet(
        initial: pin,
        supportsTitles: store.supportsTitles,
        sourceName: sourceName,
        suggest: suggest,
      ),
    );
    if (result == null) return;
    if (pin == null) {
      await store.add(result.tags, title: result.title, global: result.global);
    } else {
      await store.update(pin, result.tags, title: result.title, global: result.global);
    }
    await _load();
  }

  void _toggleHidden(PinnedTag pin) {
    PinnedTagVisibility.setHidden(pin, widget.booru, !PinnedTagVisibility.isHidden(pin, widget.booru));
    setState(() {});
  }

  Future<void> _delete(PinnedTag pin) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${pin.displayName}"?'),
        content: Text(pin.tagName),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    await store.remove(pin);
    await _load();
  }

  Future<void> _reorder(int from, int to) async {
    setState(() {
      final PinnedTag moved = pins.removeAt(from);
      pins.insert(to > from ? to - 1 : to, moved);
    });
    await store.reorder(pins);
  }

  Widget _tile(ThemeData theme, int index) {
    final PinnedTag pin = pins[index];
    final bool named = (pin.title ?? '').trim().isNotEmpty;
    final bool hidden = PinnedTagVisibility.isHidden(pin, widget.booru);
    final String subtitle = [
      if (named) pin.tagName,
      if (pin.isGlobal) 'All sources',
      if (hidden) 'Hidden on $sourceName',
    ].join(' · ');
    return ListTile(
      key: ValueKey('pinned-${pin.id}'),
      leading: store.supportsTitles
          ? ReorderableDragStartListener(index: index, child: const Icon(Symbols.drag_indicator_rounded))
          : const Icon(Symbols.push_pin_rounded),
      title: Text(
        pin.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: hidden ? TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)) : null,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => _open(pin),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('pinned-hide-${pin.id}'),
            tooltip: hidden ? 'Show on $sourceName' : 'Hide on $sourceName',
            icon: Icon(hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded),
            onPressed: () => _toggleHidden(pin),
          ),
          IconButton(
            key: ValueKey('pinned-edit-${pin.id}'),
            tooltip: 'Edit pin',
            icon: const Icon(Symbols.edit_rounded),
            onPressed: () => _edit(pin),
          ),
          IconButton(
            key: ValueKey('pinned-delete-${pin.id}'),
            tooltip: 'Delete pin',
            icon: Icon(Symbols.delete_rounded, color: theme.colorScheme.error),
            onPressed: () => _delete(pin),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.booru.name ?? 'Source'} pinned tags')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('pinned-add'),
        onPressed: () => _edit(),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('New pin'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pins.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pinned tags yet. A pin can search several tags at once.', textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              buildDefaultDragHandles: false,
              itemCount: pins.length,
              onReorder: _reorder,
              itemBuilder: (context, index) => _tile(theme, index),
            ),
    );
  }
}

class PinBuilderResult {
  const PinBuilderResult(this.tags, this.title, this.global);

  /// The tags, space-separated: the search the pin runs.
  final String tags;
  final String? title;
  final bool global;
}

/// Builds or edits one pin: tags as chips (several can be typed at once, with
/// suggestions as you type), an optional name, and whether it shows on every
/// source.
class PinBuilderSheet extends StatefulWidget {
  const PinBuilderSheet({
    required this.supportsTitles,
    required this.sourceName,
    this.initial,
    this.suggest,
    super.key,
  });

  final PinnedTag? initial;
  final bool supportsTitles;
  final String sourceName;
  final PinTagSuggester? suggest;

  @override
  State<PinBuilderSheet> createState() => _PinBuilderSheetState();
}

class _PinBuilderSheetState extends State<PinBuilderSheet> {
  late final List<String> tags = [...?widget.initial?.tags];
  final TextEditingController tagController = TextEditingController();
  late final TextEditingController titleController = TextEditingController(text: widget.initial?.title ?? '');
  late bool global = widget.initial?.isGlobal ?? false;

  List<TagSuggestion> suggestions = [];
  Timer? _debounce;
  int _asked = 0;
  String _lastWord = '';

  @override
  void initState() {
    super.initState();
    tagController.addListener(_onTyped);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    tagController.removeListener(_onTyped);
    tagController.dispose();
    titleController.dispose();
    super.dispose();
  }

  String get _typedWord => tagController.text.split(RegExp(r'\s+')).last;

  void _onTyped() {
    final String word = _typedWord;
    if (word == _lastWord) return;
    _lastWord = word;
    _debounce?.cancel();
    if (word.replaceFirst(RegExp('^[-~]'), '').isEmpty || widget.suggest == null) {
      if (suggestions.isNotEmpty) setState(() => suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final int ask = ++_asked;
      List<TagSuggestion> found = const [];
      try {
        found = await widget.suggest!(word);
      } catch (_) {}
      if (!mounted || ask != _asked) return;
      setState(() => suggestions = found.take(8).toList());
    });
  }

  void _addTyped() {
    for (final String t in tagController.text.split(RegExp(r'\s+'))) {
      if (t.isNotEmpty && !tags.contains(t)) tags.add(t);
    }
    tagController.clear();
    suggestions = [];
    setState(() {});
  }

  /// The suggestion replaces the word being typed; a leading `-` or `~` stays.
  void _take(TagSuggestion s) {
    final List<String> words = tagController.text.split(RegExp(r'\s+'));
    final String prefix = RegExp('^[-~]').firstMatch(words.last)?.group(0) ?? '';
    words[words.length - 1] = '$prefix${s.tag}';
    tagController.text = words.join(' ');
    _addTyped();
  }

  void _save() {
    _addTyped();
    if (tags.isEmpty) return;
    final String title = titleController.text.trim();
    Navigator.of(context).pop(PinBuilderResult(tags.join(' '), title.isEmpty ? null : title, global));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initial == null ? 'New pin' : 'Edit pin',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pin-builder-tag'),
                    controller: tagController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Add tags', hintText: 'fox solo -comic'),
                    onSubmitted: (_) => _addTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('pin-builder-add'),
                  tooltip: 'Add',
                  onPressed: _addTyped,
                  icon: const Icon(Symbols.add_rounded),
                ),
              ],
            ),
            for (final TagSuggestion s in suggestions)
              ListTile(
                key: ValueKey('pin-builder-suggestion-${s.tag}'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Symbols.sell_rounded, size: 18),
                title: Text(s.tag, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _take(s),
              ),
            const SizedBox(height: 10),
            if (tags.isEmpty)
              Text('A pin searches all of its tags together.', style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final String t in tags)
                    InputChip(
                      key: ValueKey('pin-builder-chip-$t'),
                      label: Text(t),
                      onDeleted: () => setState(() => tags.remove(t)),
                    ),
                ],
              ),
            if (widget.supportsTitles) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pin-builder-title'),
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
            ],
            SwitchListTile(
              key: const ValueKey('pin-builder-global'),
              contentPadding: EdgeInsets.zero,
              value: global,
              onChanged: (v) => setState(() => global = v),
              title: const Text('Pin on every source'),
              subtitle: Text(global ? 'Shown on every source' : 'Only on ${widget.sourceName}'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('pin-builder-save'),
                onPressed: _save,
                icon: const Icon(Symbols.push_pin_rounded),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
