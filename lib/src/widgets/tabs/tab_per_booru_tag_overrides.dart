import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';

// Per-booru tag override editor shown when a tab is in merge mode.
// One small field per participating booru (primary + secondaries). Empty
// fields inherit the main search bar's tags; non-empty fields are sent only
// to that one child handler.
class TabPerBooruTagOverrides extends StatelessWidget {
  const TabPerBooruTagOverrides({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;

    return Obx(() {
      if (searchHandler.tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      final secondaries = searchHandler.currentSecondaryBoorus.value ?? const <Booru>[];
      if (secondaries.isEmpty) {
        return const SizedBox.shrink();
      }

      final List<Booru> participants = [searchHandler.currentBooru, ...secondaries];
      final SearchTab tab = searchHandler.currentTab;

      return Padding(
        padding: const EdgeInsets.fromLTRB(5, 0, 5, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Per-booru tag overrides',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'Leave a field empty to use the main search tags.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final booru in participants)
              _OverrideRow(booru: booru, tab: tab),
          ],
        ),
      );
    });
  }
}

class _OverrideRow extends StatefulWidget {
  const _OverrideRow({required this.booru, required this.tab});

  final Booru booru;
  final SearchTab tab;

  @override
  State<_OverrideRow> createState() => _OverrideRowState();
}

class _OverrideRowState extends State<_OverrideRow> {
  late final TextEditingController controller;

  String get _booruKey => widget.booru.name ?? '';

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.tab.tagOverrides[_booruKey] ?? '');
  }

  @override
  void didUpdateWidget(covariant _OverrideRow old) {
    super.didUpdateWidget(old);
    // If the underlying tab was swapped (new SearchTab instance), reseed the
    // controller from the new map so the field reflects the restored value.
    if (!identical(old.tab, widget.tab)) {
      final restored = widget.tab.tagOverrides[_booruKey] ?? '';
      if (controller.text != restored) {
        controller.text = restored;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final key = _booruKey;
    if (key.isEmpty) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      widget.tab.tagOverrides.remove(key);
    } else {
      widget.tab.tagOverrides[key] = value;
    }
  }

  void _onSubmitted(String _) {
    // Pressing enter inside an override field runs the same search the main
    // search button does — picks up the main bar text + the just-edited
    // overrides via SearchHandler.searchAction.
    final searchHandler = SearchHandler.instance;
    searchHandler.searchAction(searchHandler.searchTextController.text, null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(100),
            ),
            child: TabBooruSelectorItem(booru: widget.booru, compact: true),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: SearchHandler.instance.currentTab.tags.isEmpty
                    ? 'Tags for this booru'
                    : SearchHandler.instance.currentTab.tags,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
