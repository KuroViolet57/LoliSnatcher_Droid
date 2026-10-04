part of '../hideable_appbar.dart';

Future<List<String>> showSelectTagsDialog(
  BuildContext context,
  List<Tag> tags, {
  /// The item those tags came from, when known — decides whether the shared
  /// booru tag store may be consulted for their types.
  BooruItem? forItem,
}) async {
  final bool isDoujin = forItem != null && DoujinDataHandler.isDoujinItem(forItem);
  if (tags.isEmpty) return [];

  tags = tags.where((t) => t.fullString.trim().isNotEmpty).toList();

  final tagHandler = TagHandler.instance;

  final Map<TagType, List<Tag>> tagMap = {
    for (final type in TagType.values) type: [],
  };
  for (final t in tags) {
    // Keep the item's OWN type when it has one (doujin tags always do), and
    // never consult the shared booru tag store for a doujin item - that
    // replaced its tags with a booru's classification of the same names.
    final Tag tag = (t.tagType != TagType.none || isDoujin) ? t : tagHandler.getTag(t.fullString);
    tagMap[tag.tagType]?.add(tag);
  }
  final List<Tag> items = tagMap.values.expand((i) => i).toList();

  final List<Tag> selectedTags = [];
  final res = await LoliMultiselectDropdown(
    value: selectedTags,
    onChanged: (value) {
      selectedTags.clear();
      selectedTags.addAll(value);
    },
    expandableByScroll: false,
    items: items,
    itemBuilder: (item) => Container(
      padding: const EdgeInsets.only(
        left: 16,
        top: 8,
        bottom: 8,
      ),
      constraints: const BoxConstraints(
        minHeight: kMinInteractiveDimension,
      ),
      alignment: Alignment.centerLeft,
      child: Builder(
        builder: (context) {
          final color = item.getColour();
          return Text(
            item.fullString,
            style: TextStyle(
              color: color,
              backgroundColor: color?.withValues(alpha: 0.1),
            ),
          );
        },
      ),
    ),
    selectedItemBuilder: (items) => Text(items.join(', ')),
    labelText: context.loc.viewer.appBar.selectTags,
  ).showDialog(context);

  if (res) {
    return selectedTags.map((t) => t.fullString).toList();
  }

  return [];
}
