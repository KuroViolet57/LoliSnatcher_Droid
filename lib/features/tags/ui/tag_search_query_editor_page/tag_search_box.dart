part of '../tag_search_query_editor_page.dart';

/// A fake input field that opens [TagSearchQueryEditorPage] when tapped
/// and displays/stores the selected tag(s)
///
/// Usage:
/// ```dart
/// TagSearchBox(
///   controller: myTagController,
///   title: 'Select tags',
///   allowMultipleTags: true,
///   showBooruSelector: true,
///   onChanged: (tags, booru) => print('Selected: $tags from $booru'),
/// )
/// ```
class TagSearchBox extends StatefulWidget {
  const TagSearchBox({
    this.title,
    this.controller,
    this.hintText,
    this.booru,
    this.allowMultipleTags = false,
    this.showBooruSelector = false,
    this.onChanged,
    this.onBooruChanged,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
    this.clearable = true,
    this.enabled = true,
    this.onlyInput = false,
    this.readOnlyPreview = false,
    this.titleAsLabel = false,
    this.showPinnedTags = true,
    super.key,
  });

  /// Controller to store/retrieve the selected tags
  final TextEditingController? controller;

  /// Label text for the input field
  final String? title;

  /// Hint text when empty
  final String? hintText;

  /// Booru for tag search
  final Booru? booru;

  /// Allow selecting multiple tags
  final bool allowMultipleTags;

  /// Show booru selector in the editor
  final bool showBooruSelector;

  /// Called when tags are selected
  final void Function(String tags, Booru? booru)? onChanged;

  /// Called when booru is changed (if showBooruSelector is true)
  final void Function(Booru? booru)? onBooruChanged;

  final bool drawTopBorder;
  final bool drawBottomBorder;
  final EdgeInsets margin;
  final bool clearable;
  final bool enabled;
  final bool onlyInput;
  final bool readOnlyPreview;
  final bool titleAsLabel;
  final bool showPinnedTags;

  @override
  State<TagSearchBox> createState() => _TagSearchBoxState();
}

class _TagSearchBoxState extends State<TagSearchBox> {
  late final TextEditingController _controller;
  Booru? get _selectedBooru => widget.booru;
  set _selectedBooru(Booru? booru) => widget.onBooruChanged?.call(booru);

  @override
  void initState() {
    super.initState();

    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _openTagSearch() async {
    if (!widget.enabled) return;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TagSearchQueryEditorPage(
          initialTags: _controller.text,
          initialBooru: _selectedBooru,
          allowMultipleTags: widget.allowMultipleTags,
          showBooruSelector: widget.showBooruSelector,
          readOnlyPreview: widget.readOnlyPreview,
          showPinnedTags: widget.showPinnedTags,
          onTagsSelected: (tags, booru) {
            setState(() {
              _controller.text = tags;
              if (booru != null) {
                _selectedBooru = booru;
                widget.onBooruChanged?.call(booru);
              }
            });
            widget.onChanged?.call(tags, booru);
          },
        ),
      ),
    );

    // Also handle result from Navigator.pop
    if (result != null && result != _controller.text) {
      setState(() {
        _controller.text = result;
      });
      widget.onChanged?.call(result, _selectedBooru);
    }
  }

  void _clear() {
    setState(() {
      _controller.clear();
    });
    widget.onChanged?.call('', _selectedBooru);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = _controller.text.isNotEmpty;
    final tagHandler = TagHandler.instance;

    final Widget field = Container(
      margin: widget.margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null && !widget.titleAsLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(widget.title!),
            ),
          //
          Material(
            color: Theme.of(context).inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.enabled ? _openTagSearch : null,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.titleAsLabel ? widget.title : null,
                  hintText: widget.hintText,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.clearable && hasText && widget.enabled)
                        IconButton(
                          icon: Icon(
                            Symbols.close_rounded,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: _clear,
                        ),
                      //
                      IconButton(
                        icon: Icon(
                          Symbols.search_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: widget.enabled ? _openTagSearch : null,
                      ),
                    ],
                  ),
                  enabled: widget.enabled,
                ),
                child: hasText
                    ? widget.allowMultipleTags
                          ? Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              alignment: WrapAlignment.start,
                              children: _controller.text
                                  .split(' ')
                                  .where((t) => t.isNotEmpty)
                                  .map(
                                    (t) => SizedBox(
                                      height: 32,
                                      child: MainSearchTagChip(tag: t),
                                    ),
                                  )
                                  .toList(),
                            )
                          : Text(
                              _controller.text.replaceAll('_', ' '),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: tagHandler.colourForDisplay(_controller.text, _selectedBooru),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                    : (widget.hintText != null
                          ? Text(
                              widget.hintText!,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                            )
                          : null),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.onlyInput) {
      return field;
    }

    return Material(
      color: Colors.transparent,
      child: ListTile(
        title: field,
        dense: false,
        shape: Border(
          top: widget.drawTopBorder ? BorderSide(color: Theme.of(context).dividerColor, width: 1) : BorderSide.none,
          bottom: widget.drawBottomBorder
              ? BorderSide(color: Theme.of(context).dividerColor, width: 1)
              : BorderSide.none,
        ),
      ),
    );
  }
}
