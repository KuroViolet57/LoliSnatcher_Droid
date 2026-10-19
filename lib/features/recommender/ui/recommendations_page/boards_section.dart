part of '../recommendations_page.dart';

/// Boards (r73): the SauceNAO key the reference-image search runs on.
class _BoardsSection extends StatefulWidget {
  const _BoardsSection();

  @override
  State<_BoardsSection> createState() => _BoardsSectionState();
}

class _BoardsSectionState extends State<_BoardsSection> {
  final BoardsHandler store = BoardsHandler.instance;
  late final TextEditingController key;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    key = TextEditingController(text: store.sauceNaoApiKey);
    store.load().then((_) {
      if (mounted && key.text.isEmpty && store.sauceNaoApiKey.isNotEmpty) setState(() => key.text = store.sauceNaoApiKey);
    });
  }

  @override
  void dispose() {
    // A key pasted and left at once must not be lost with the timer.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(store.setSauceNaoApiKey(key.text));
    }
    key.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => store.setSauceNaoApiKey(value));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boards', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "A board's reference image is looked up on SauceNAO, which needs your own API key (free: saucenao.com → Register → API). Without a key, image boards fall back to e621's own search and to the description.",
              style: muted,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('saucenao-key'),
              controller: key,
              decoration: const InputDecoration(labelText: 'SauceNAO API key', isDense: true),
              onChanged: _changed,
            ),
          ],
        ),
      ),
    );
  }
}
