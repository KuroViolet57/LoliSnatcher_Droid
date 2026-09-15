/// Browse filters on the doujin sources (r37): sort, category, language.
///
/// A source declares what it can take ([DoujinFilterSpec], from
/// `BooruHandler.doujinFilters`); the search window shows the groups as
/// checkmarks; the choice travels in the query as the source's own terms
/// (`sort:popular`, `category:manga`, `language:english`), so tabs, backups
/// and history keep working and a typed term means the same thing.
class DoujinFilterOption {
  const DoujinFilterOption(this.value, this.label);

  /// The term's value; '' means "no term for this key" (a Latest that is
  /// the plain listing).
  final String value;
  final String label;
}

class DoujinFilterGroup {
  const DoujinFilterGroup({
    required this.key,
    required this.label,
    required this.options,
    this.multi = false,
    this.defaultValue = '',
    this.defaultValues = const [],
  });

  /// The term's namespace (`sort`, `category`, `language`, `popular`, `type`).
  final String key;
  final String label;
  final List<DoujinFilterOption> options;

  /// Several values at once (`category:a category:b`) or one.
  final bool multi;

  /// What the source does when the query names nothing: shown as checked.
  final String defaultValue;

  /// A multiple choice's defaults (r40: FurAffinity checks Art and Photo).
  final List<String> defaultValues;
}

class DoujinFilterSpec {
  const DoujinFilterSpec(this.groups);

  final List<DoujinFilterGroup> groups;

  DoujinFilterGroup? group(String key) {
    for (final DoujinFilterGroup g in groups) {
      if (g.key == key) return g;
    }
    return null;
  }
}

class DoujinFilters {
  const DoujinFilters._();

  static final RegExp _term = RegExp(r'"[^"]*"|\S+');

  /// The values the query names for [key] (`key:value` terms; an excluded
  /// `-key:value` is not a choice).
  static List<String> selected(String query, String key) {
    final String prefix = '${key.toLowerCase()}:';
    final List<String> out = [];
    for (final RegExpMatch m in _term.allMatches(query)) {
      final String token = m.group(0)!;
      final String lower = token.toLowerCase();
      if (lower.startsWith(prefix) && lower.length > prefix.length) out.add(lower.substring(prefix.length));
    }
    return out;
  }

  /// [query] with every `key:*` term replaced by [values] (appended, in
  /// order); everything else stays where it was.
  static String apply(String query, String key, List<String> values) {
    final String prefix = '${key.toLowerCase()}:';
    final List<String> kept = [
      for (final RegExpMatch m in _term.allMatches(query))
        if (!m.group(0)!.toLowerCase().startsWith(prefix)) m.group(0)!,
    ];
    return [...kept, for (final String v in values) if (v.isNotEmpty) '$key:$v'].join(' ');
  }

  /// [query] without any `key:*` term — what a source sends when a term is
  /// the app's own and not the site's.
  static String strip(String query, String key) => apply(query, key, const []);

  static const List<DoujinFilterOption> commonLanguages = [
    DoujinFilterOption('english', 'English'),
    DoujinFilterOption('japanese', 'Japanese'),
    DoujinFilterOption('chinese', 'Chinese'),
    DoujinFilterOption('korean', 'Korean'),
  ];
}
