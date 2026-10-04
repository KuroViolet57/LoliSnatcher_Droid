part of '../tag_view.dart';

//

class SourceLinkErrorDialog extends StatelessWidget {
  const SourceLinkErrorDialog({
    required this.link,
    super.key,
  });

  final String link;
  List<String> get detectedUrls => const UrlParseRule()
      .findMatches(link)
      .map((m) => m.segment.metadata['url'] as String? ?? m.segment.text)
      .toList();

  Future<void> copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text(
        context.loc.copiedToClipboard,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(link, style: const TextStyle(fontSize: 16)),
      leadingIcon: Symbols.content_copy_rounded,
      sideColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.tagView.sourceDialogTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          if (detectedUrls.isNotEmpty) ...[
            Text(
              context.loc.tagView.detectedLinks,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            ...detectedUrls.map(
              (url) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Symbols.link_rounded, size: 20),
                title: Text(url, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                onTap: () async {
                  final ok = await launchUrlString(
                    url,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok) {
                    FlashElements.showSnackbar(
                      title: Text(context.loc.failedToOpenLink),
                      content: Text(url),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          ParsedText(
            text: link,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        ElevatedButton.icon(
          onPressed: () => copy(context),
          label: Text(context.loc.copy),
          icon: const Icon(Symbols.content_copy_rounded),
        ),
        const CloseDialogButton(withIcon: true),
      ],
    );
  }
}
