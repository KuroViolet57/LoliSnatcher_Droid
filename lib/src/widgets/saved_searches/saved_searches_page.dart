import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/saved_searches/saved_search_tile.dart';

// Full-screen list of every SavedSearch. Reused for the drawer's "View all"
// button. Uses Obx so adds/deletes from elsewhere update the page live.
class SavedSearchesPage extends StatefulWidget {
  const SavedSearchesPage({super.key});

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  @override
  void initState() {
    super.initState();
    // Defer the reload until after the first frame so the page paints
    // immediately and the list fills in from the DB asynchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SearchHandler.instance.reloadSavedSearches();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved searches'),
      ),
      body: Obx(() {
        final list = SearchHandler.instance.savedSearches;
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No saved searches yet.\nTap the bookmark icon on the search bar to add one.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => SavedSearchTile(entry: list[index]),
        );
      }),
    );
  }
}
