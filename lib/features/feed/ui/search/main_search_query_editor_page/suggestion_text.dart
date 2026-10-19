part of '../main_search_query_editor_page.dart';

class TagSuggestionText extends StatelessWidget {
  const TagSuggestionText({
    required this.tag,
    this.searchText = '',
    this.isExpanded = true,
    super.key,
  });

  final TagSuggestion tag;
  final String searchText;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final tagHandler = TagHandler.instance;

    Color? tagColor = !tag.type.isNone ? tag.type.getColour() : tagHandler.getTag(tag.tag).getColour();
    tagColor ??= context.theme.colorScheme.onSurface;

    //

    final style = context.theme.textTheme.bodyLarge?.copyWith(
      color: tagColor,
      fontWeight: FontWeight.w400,
      height: 1,
    );

    final bool isMultiword = tag.tag.split(' ').length > 1;

    final List<TextSpan> spans = [];
    if (searchText.isNotEmpty) {
      final List<String> split = tag.tag.split(searchText);
      for (int i = 0; i < split.length; i++) {
        spans.add(
          TextSpan(
            text: isMultiword ? split[i] : split[i].replaceAll('_', ' '),
            style: style,
          ),
        );
        if (i < split.length - 1) {
          spans.add(
            TextSpan(
              text: isMultiword ? searchText : searchText.replaceAll('_', ' '),
              style: style?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      }
    } else {
      spans.add(
        TextSpan(
          text: isMultiword ? tag.tag : tag.tag.replaceAll('_', ' '),
          style: style?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return MarqueeText.rich(
      textSpan: TextSpan(children: spans),
      style: style,
      isExpanded: isExpanded,
    );
  }
}
