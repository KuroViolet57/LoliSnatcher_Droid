import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/board_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Boards (r73): saved "find me posts like this" searches. Each opens as a
/// tab of the virtual Boards source (`board:<id>`).
class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});

  /// How a board opens; the default makes a tab. Replaced in tests.
  static void Function(Board board)? opener;

  static void resetForTests() {
    opener = null;
  }

  static void open(BuildContext context, Board board) {
    final void Function(Board)? custom = opener;
    if (custom != null) {
      custom(board);
      return;
    }
    SearchHandler.instance.addTabByString(
      'board:${board.id}',
      customBooru: SettingsHandler.instance.ensureBoardsBooru(),
      switchToNew: true,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> {
  final BoardsHandler store = BoardsHandler.instance;

  @override
  void initState() {
    super.initState();
    store.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _edit({Board? board, Board? template}) async {
    await Navigator.of(context).push<Board>(MaterialPageRoute(builder: (_) => BoardEditPage(board: board, template: template)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boards')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('boards-new'),
        onPressed: () => _edit(),
        icon: const Icon(Symbols.add_rounded),
        label: const Text('New board'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: store.revision,
        builder: (context, _, __) {
          final List<Board> boards = store.boards;
          if (boards.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No boards yet.\n\nA board is a saved search across your sources: describe what you want in plain words, add a reference image, and pin the tags that must be there (a character, "animated"). Open it like a tab; it fills as the sources answer.',
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: boards.length,
            itemBuilder: (context, i) {
              final Board b = boards[i];
              final List<String> bits = [
                if (b.description.trim().isNotEmpty) b.description.trim(),
                if (b.mustTags.isNotEmpty) 'must: ${b.mustTags.join(' ')}',
                if (b.excludeTags.isNotEmpty) 'not: ${b.excludeTags.join(' ')}',
                if (b.sourceNames.isNotEmpty) b.sourceNames.join(', ') else 'every source',
              ];
              return ListTile(
                key: ValueKey('board-tile-${b.id}'),
                leading: _BoardThumb(board: b),
                title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(bits.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => BoardsPage.open(context, b),
                trailing: PopupMenuButton<String>(
                  key: ValueKey('board-menu-${b.id}'),
                  onSelected: (String action) async {
                    switch (action) {
                      case 'open':
                        BoardsPage.open(context, b);
                      case 'edit':
                        await _edit(board: b);
                      case 'duplicate':
                        final String newId = store.newId();
                        String copiedPath = '';
                        if (b.imagePath.isNotEmpty && File(b.imagePath).existsSync()) {
                          try {
                            copiedPath = await store.importImageFile(b.imagePath, newId);
                          } catch (_) {}
                        }
                        await store.save(b.copyWith(id: newId, name: '${b.name} (copy)', imagePath: copiedPath, clearMatches: true));
                      case 'refresh':
                        await store.save(b.copyWith(clearMatches: true));
                      case 'delete':
                        await store.delete(b.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    if (b.hasImage) const PopupMenuItem(value: 'refresh', child: Text('Refresh image matches')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BoardThumb extends StatelessWidget {
  const _BoardThumb({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    final bool hasFile = board.imagePath.isNotEmpty && File(board.imagePath).existsSync();
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: hasFile
            ? Image.file(File(board.imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Symbols.broken_image_rounded))
            : Icon(board.imageUrl.isNotEmpty ? Symbols.image_search_rounded : Symbols.dashboard_rounded, size: 32),
      ),
    );
  }
}

/// The board editor: a name (optional), the description, must-have and
/// excluded tags, the sources, a reference image (picked, pasted, or from
/// a post).
class BoardEditPage extends StatefulWidget {
  const BoardEditPage({this.board, this.template, super.key});

  /// An existing board to edit.
  final Board? board;

  /// Prefilled values for a new board (Find posts like this).
  final Board? template;

  /// Fetches a post's image with its booru's headers, for the copy made at
  /// creation. Replaced in tests.
  static Future<List<int>?> Function(String url, String? booruName)? imageFetcher = _defaultImageFetcher;

  /// r74: the downloaded image tagger — whether one is ready, and what it
  /// reads in a picture. Replaced in tests.
  static bool Function() taggerReady = _defaultTaggerReady;
  static Future<TaggerResult?> Function(Uint8List bytes)? pixelTagger = _defaultPixelTagger;

  static void resetForTests() {
    imageFetcher = _defaultImageFetcher;
    taggerReady = _defaultTaggerReady;
    pixelTagger = _defaultPixelTagger;
  }

  static bool _defaultTaggerReady() => ImageTaggerHandler.maybe?.enabled ?? false;

  static Future<TaggerResult?> _defaultPixelTagger(Uint8List bytes) async {
    final ImageTaggerHandler? t = ImageTaggerHandler.maybe;
    if (t == null || !t.enabled) return null;
    return t.tag(bytes);
  }

  static Future<List<int>?> _defaultImageFetcher(String url, String? booruName) async {
    Map<String, String> headers = {'User-Agent': Tools.browserUserAgent};
    final Booru? source = booruName == null ? null : SettingsHandler.instance.booruList.where((s) => s.name == booruName).firstOrNull;
    if (source != null) headers = await Tools.getFileCustomHeaders(source, checkForReferer: true);
    final Response<dynamic> res = await DioNetwork.get(url, headers: headers, options: Options(responseType: ResponseType.bytes)).timeout(const Duration(seconds: 20));
    return res.data is List<int> ? res.data as List<int> : null;
  }

  /// The file extension of an image address, `jpg` when it has none.
  static String extensionOf(String url) {
    final String last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final String ext = last.contains('.') ? last.split('.').last.toLowerCase() : '';
    return ext.length >= 2 && ext.length <= 4 && RegExp(r'^[a-z0-9]+$').hasMatch(ext) ? ext : 'jpg';
  }

  /// A template from a post: its tags as words (characters, series and
  /// artists first), its image as the reference.
  static Board templateFromItem(BooruItem item, Booru? source) {
    final List<String> first = [];
    final List<String> rest = [];
    for (final t in item.tagsList) {
      final String name = t.fullString.toLowerCase();
      if (name.isEmpty || name.contains(':')) continue;
      final bool lead = t.tagType == TagType.character || t.tagType == TagType.copyright || t.tagType == TagType.artist;
      (lead ? first : rest).add(name);
    }
    final List<String> words = [...first, ...rest].take(14).map((t) => t.replaceAll('_', ' ')).toList();
    final String description = words.join(' ');
    final String image = item.mediaType.value.isVideo ? item.thumbnailURL : (item.sampleURL.isNotEmpty ? item.sampleURL : item.thumbnailURL);
    // Only a real booru has headers worth sending; a feed or a local view
    // (a board tab, the favourites) does not.
    final BooruType? type = source?.type;
    final bool realSource = source != null && type != null && !type.isRecommendationFeed && !type.isLocalDb && !type.isMerge && !type.isWebView;
    return Board(
      id: '',
      name: Board.nameFromDescription(first.isNotEmpty ? first.take(3).join(' ').replaceAll('_', ' ') : description, words: 4),
      description: description,
      imageUrl: image,
      imageBooru: realSource ? (source.name ?? '') : '',
      sourceNames: const [],
    );
  }

  static Future<void> openFromItem(BuildContext context, BooruItem item, Booru? source) async {
    final Board? saved = await Navigator.of(context).push<Board>(
      MaterialPageRoute(builder: (_) => BoardEditPage(template: templateFromItem(item, source))),
    );
    if (saved != null && context.mounted) {
      BoardsPage.open(context, saved);
    }
  }

  @override
  State<BoardEditPage> createState() => _BoardEditPageState();
}

class _BoardEditPageState extends State<BoardEditPage> {
  final BoardsHandler store = BoardsHandler.instance;
  late final TextEditingController name;
  late final TextEditingController description;
  late final TextEditingController must;
  late final TextEditingController exclude;
  late final TextEditingController imageUrl;
  late final Set<String> sources;
  late String imagePath;

  /// A picked file, copied under boards/ only when the board is saved.
  String? pendingPick;

  /// r74: what the tagger read in the reference image, as chips.
  List<PixelTag> pixelTags = [];
  bool tagging = false;
  String tagError = '';
  late final String id;
  bool saving = false;

  Board? get _seed => widget.board ?? widget.template;

  @override
  void initState() {
    super.initState();
    final Board? s = _seed;
    id = widget.board?.id ?? store.newId();
    name = TextEditingController(text: s?.name ?? '');
    description = TextEditingController(text: s?.description ?? '');
    must = TextEditingController(text: s?.mustTags.join(' ') ?? '');
    exclude = TextEditingController(text: s?.excludeTags.join(' ') ?? '');
    imageUrl = TextEditingController(text: s?.imageUrl ?? '');
    sources = {...?s?.sourceNames};
    imagePath = s?.imagePath ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    must.dispose();
    exclude.dispose();
    imageUrl.dispose();
    super.dispose();
  }

  List<Booru> get _eligible => SettingsHandler.instance.booruList.where(BoardHandler.eligible).toList();

  Future<void> _pick() async {
    try {
      final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 92);
      if (file == null) return;
      if (mounted) setState(() => pendingPick = file.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick an image: $e')));
    }
  }

  /// r74: the reference image (the picked file, the copy, or the address)
  /// through the downloaded tagger; the tags become chips.
  Future<void> _tagImage() async {
    if (tagging) return;
    setState(() {
      tagging = true;
      tagError = '';
    });
    try {
      final String shown = pendingPick ?? imagePath;
      final String url = imageUrl.text.trim();
      List<int>? bytes;
      if (shown.isNotEmpty && File(shown).existsSync()) {
        bytes = File(shown).readAsBytesSync();
      } else if (url.isNotEmpty) {
        final String booru = _seed?.imageBooru ?? '';
        bytes = await BoardEditPage.imageFetcher?.call(url, booru.isNotEmpty ? booru : null);
      }
      if (bytes == null || bytes.isEmpty) throw StateError('the image could not be read');
      final TaggerResult? r = await BoardEditPage.pixelTagger?.call(Uint8List.fromList(bytes));
      if (r == null) throw StateError('no image tagger is downloaded');
      if (mounted) setState(() => pixelTags = r.all);
    } catch (e) {
      if (mounted) setState(() => tagError = 'Could not read tags from the picture: $e');
    } finally {
      if (mounted) setState(() => tagging = false);
    }
  }

  /// A tapped chip joins the must-have tags, once.
  void _addMust(String tag) {
    if (Board.parseTags(must.text).contains(tag)) return;
    setState(() => must.text = '${must.text.trim()} $tag'.trim());
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    final String desc = description.text.trim();
    final String typed = name.text.trim();
    final String url = imageUrl.text.trim();
    final String imageBooru = _seed?.imageBooru ?? '';
    if (pendingPick != null) {
      try {
        final String previous = imagePath;
        imagePath = await store.importImageFile(pendingPick!, id);
        if (previous.isNotEmpty && previous != imagePath && previous.startsWith(store.imagesDir.path)) {
          try {
            File(previous).deleteSync();
          } catch (_) {}
        }
      } catch (e) {
        Logger.Inst().log('board image copy failed: $e', 'BoardEditPage', '_save', LogTypes.booruHandlerInfo);
      }
    }
    // A post's image is copied now, through its booru's headers, so the
    // search never depends on the address staying reachable.
    if (imagePath.isEmpty && url.isNotEmpty && imageBooru.isNotEmpty) {
      try {
        final List<int>? bytes = await BoardEditPage.imageFetcher?.call(url, imageBooru);
        if (bytes != null && bytes.isNotEmpty) {
          imagePath = await store.importImageBytes(bytes, id, ext: BoardEditPage.extensionOf(url));
        }
      } catch (e) {
        Logger.Inst().log('board image copy failed, keeping the address: $e', 'BoardEditPage', '_save', LogTypes.booruHandlerInfo);
      }
    }
    final Board? existing = widget.board;
    final Board board = Board(
      id: id,
      name: typed.isNotEmpty ? typed : Board.nameFromDescription(desc),
      description: desc,
      mustTags: Board.parseTags(must.text),
      excludeTags: Board.parseTags(exclude.text),
      sourceNames: sources.toList(),
      imagePath: imagePath,
      imageUrl: url,
      imageBooru: imageBooru,
      // The cached matches stay; a changed image makes them stale by itself.
      matches: existing?.matches,
      matchedAt: existing?.matchedAt,
      matchedImage: existing?.matchedImage ?? '',
      createdAt: existing?.createdAt,
    );
    final Board saved = await store.save(board);
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final String shown = pendingPick ?? imagePath;
    final bool hasFile = shown.isNotEmpty && File(shown).existsSync();
    final bool hasAddress = imageUrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board == null ? 'New board' : 'Edit board'),
        actions: [
          TextButton(key: const ValueKey('board-save'), onPressed: saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            key: const ValueKey('board-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'Named after the description if empty'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('board-description'),
            controller: description,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'What to look for',
              hintText: 'In plain words: "a blonde girl on a beach at sunset". The words become tags the sources know.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('board-must'),
            controller: must,
            decoration: const InputDecoration(labelText: 'Must have these tags', hintText: 'animated sakamata_chloe — every result carries them'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('board-exclude'),
            controller: exclude,
            decoration: const InputDecoration(labelText: 'Never these tags', hintText: 'male furry'),
          ),
          const SizedBox(height: 20),
          Text('Reference image', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Found on SauceNAO (your API key, Settings → Recommendations → Boards) and e621\'s own search, and read by the downloaded tagger; exact matches come first, and what the match names (character, series, artist) and what the picture shows lead the search.',
            style: muted,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (hasFile)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(shown), width: 72, height: 72, fit: BoxFit.cover),
                ),
              if (hasFile) const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const ValueKey('board-pick'),
                onPressed: _pick,
                icon: const Icon(Symbols.add_photo_alternate_rounded),
                label: Text(hasFile ? 'Change image' : 'Pick image'),
              ),
              if (hasFile || hasAddress)
                IconButton(
                  key: const ValueKey('board-image-remove'),
                  tooltip: 'Remove image',
                  onPressed: () => setState(() {
                    imagePath = '';
                    pendingPick = null;
                    imageUrl.clear();
                  }),
                  icon: const Icon(Symbols.delete_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('board-image-url'),
            controller: imageUrl,
            decoration: const InputDecoration(labelText: 'Or an image address', hintText: 'https://…  (a post\'s image, a picked file wins over it)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // r74: the downloaded tagger reads the picture into chips.
          if (!BoardEditPage.taggerReady())
            Text(
              'Download the image tagger (Settings → Recommendations → Image tagger) to read tags straight from the picture.',
              key: const ValueKey('board-tag-hint'),
              style: muted,
            )
          else ...[
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('board-tag-image'),
                  onPressed: (hasFile || hasAddress) && !tagging ? _tagImage : null,
                  icon: const Icon(Symbols.image_search_rounded),
                  label: Text(tagging ? 'Reading the picture…' : 'Tags from the picture'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Tap a tag to make it a must-have.', style: muted)),
              ],
            ),
            if (tagError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tagError, style: TextStyle(color: theme.colorScheme.error))),
            if (pixelTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final PixelTag p in pixelTags)
                    ActionChip(
                      key: ValueKey('board-pixel-${p.tag}'),
                      avatar: p.character ? const Icon(Symbols.person_rounded, size: 16) : null,
                      label: Text('${p.tag} ${(p.confidence * 100).round()}%'),
                      onPressed: () => _addMust(p.tag),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 20),
          Text('Sources', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(sources.isEmpty ? 'None chosen: every booru is asked.' : 'Only the chosen boorus are asked.', style: muted),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final Booru b in _eligible)
                FilterChip(
                  key: ValueKey('board-source-${b.name}'),
                  label: Text(b.name ?? ''),
                  selected: sources.contains(b.name),
                  onSelected: (bool v) => setState(() => v ? sources.add(b.name ?? '') : sources.remove(b.name)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
