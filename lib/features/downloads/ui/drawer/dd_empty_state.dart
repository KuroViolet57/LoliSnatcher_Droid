import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/core/ui/kaomoji/kaomoji.dart';

class DDEmptyState extends StatelessWidget {
  const DDEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          const Kaomoji(
            category: KaomojiCategory.indifference,
            style: TextStyle(fontSize: 36),
          ),
          Text(
            context.loc.settings.downloads.noItemsQueued,
            style: const TextStyle(fontSize: 20),
          ),
        ],
      ),
    );
  }
}
