import 'package:flutter/material.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/core/ui/text/marquee_text.dart';
import 'package:lolisnatcher/core/ui/image/booru_favicon.dart';

/// One booru as a row: favicon, name and type (the booru pickers in tabs
/// and settings).
class TabBooruSelectorItem extends StatelessWidget {
  const TabBooruSelectorItem({
    required this.booru,
    this.withFavicon = true,
    this.compact = false,
    this.extraText,
    super.key,
  });

  final Booru booru;
  final bool withFavicon;
  final bool compact;
  final String? extraText;

  @override
  Widget build(BuildContext context) {
    final String name = ' ${booru.name}${extraText?.isNotEmpty == true ? extraText : ''}';
    final String type = ' ${booru.type?.name ?? ''}';

    final column = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        MarqueeText(
          key: ValueKey('name-$name'),
          text: name,
          isExpanded: false,
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          MarqueeText(
            key: ValueKey('type-$type'),
            text: type,
            style: DefaultTextStyle.of(context).style.copyWith(
              fontSize: 12,
              height: 1,
              color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.66),
            ),
            isExpanded: false,
          ),
        ],
      ],
    );

    return Row(
      mainAxisSize: compact ? .min : .max,
      children: [
        //Booru Icon
        if (withFavicon) ...[
          BooruFavicon(booru),
          const SizedBox(width: 4),
        ],
        //Booru name
        if (compact) column else Expanded(child: column),
      ],
    );
  }
}
