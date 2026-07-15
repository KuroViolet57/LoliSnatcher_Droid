import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Flow "Details" sheet (from the viewer flyout): two-column key/value rows,
/// tap a row to copy its value; Source is a link.
Future<void> showPostDetailsSheet(BuildContext context, BooruItem item) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostDetailsSheet(item: item),
  );
}

class _PostDetailsSheet extends StatelessWidget {
  const _PostDetailsSheet({required this.item});

  final BooruItem item;

  String _humanSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String? resolution = (item.fileWidth != null && item.fileHeight != null)
        ? '${item.fileWidth!.toInt()} × ${item.fileHeight!.toInt()}'
        : null;
    final String? source = (item.sources != null && item.sources!.isNotEmpty)
        ? item.sources!.first
        : (item.postURL.isNotEmpty ? item.postURL : null);

    final List<(String, String?, bool)> rows = [
      ('ID', item.serverId, false),
      ('Rating', item.rating, false),
      ('Score', item.score, false),
      ('Resolution', resolution, false),
      ('Size', _humanSize(item.fileSize), false),
      ('Type', item.fileExt?.toUpperCase(), false),
      ('Posted', item.postDate, false),
      ('Uploader', item.uploaderName, false),
      ('Source', source, true),
      ('MD5', item.md5String, false),
    ];
    final visible = rows.where((r) => (r.$2 ?? '').isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 2),
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFF4A4260),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  'Details',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: visible.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, i) {
                final (label, value, isLink) = visible[i];
                final String val = value ?? '';
                return InkWell(
                  onTap: () {
                    if (isLink) {
                      launchUrlString(val, mode: LaunchMode.externalApplication);
                      Navigator.of(context).pop();
                      return;
                    }
                    Clipboard.setData(ClipboardData(text: val));
                    FlashElements.showSnackbar(
                      context: context,
                      duration: const Duration(seconds: 1),
                      title: Text('Copied $label', style: const TextStyle(fontSize: 16)),
                      content: Text(val, style: const TextStyle(fontSize: 14)),
                      leadingIcon: Icons.copy,
                      sideColor: Colors.green,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            val,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isLink ? theme.colorScheme.secondary : theme.colorScheme.onSurface,
                              decoration: isLink ? TextDecoration.underline : null,
                              decorationColor: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isLink ? Icons.open_in_new : Icons.copy,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 8),
        ],
      ),
    );
  }
}
