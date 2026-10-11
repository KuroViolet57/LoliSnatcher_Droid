import 'package:lolisnatcher/core/utils/text_parser/rules/rules.dart';
import 'package:lolisnatcher/core/utils/text_parser/text_parser.dart';

export 'package:lolisnatcher/core/utils/text_parser/rules/rules.dart';
export 'package:lolisnatcher/core/utils/text_parser/text_parser.dart';

/// Pre-configured parser for booru-style comments
/// Includes common rules for URLs, tags, quotes, mentions, etc.
class CommentParser {
  CommentParser._();

  static TextParser? _instance;

  /// Get the default comment parser instance
  static TextParser get instance {
    _instance ??= createDefault();
    return _instance!;
  }

  /// Create a new parser with default rules for booru comments
  static TextParser createDefault() {
    return TextParser(
      rules: [
        // High priority - structural elements
        const UrlParseRule(),
        const CodeParseRule(),
        const QuoteParseRule(),
        const SpoilerParseRule(),
        const DiscordSpoilerParseRule(),

        // Medium priority - references and mentions
        const PostReferenceParseRule(),
        const MentionParseRule(),
        const SaidParseRule(),

        // Lower priority - formatting
        const BoldParseRule(),
        const ItalicParseRule(),
        const UnderlineParseRule(),
        const StrikethroughParseRule(),
        const RubyParseRule(),

        // Tags and hashtags
        const HashtagParseRule(),
        const TagParseRule(),

        // Line-based
        const LineQuoteParseRule(),
      ],
    );
  }
}
