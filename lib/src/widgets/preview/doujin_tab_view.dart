import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';

/// The whole content of a doujin-detail TAB: the detail page itself, with no
/// feed chrome around it — no main app bar, no tab carousel, no pagination or
/// end-of-results banner, no bottom search bar, no booru drawers. The page's
/// own app bar has no back button (a tab has nowhere to go back to) and the
/// right third of the screen drags open the mini tab manager.
class DoujinTabView extends StatefulWidget {
  const DoujinTabView({required this.tab, super.key});

  final SearchTab tab;

  @override
  State<DoujinTabView> createState() => _DoujinTabViewState();
}

class _DoujinTabViewState extends State<DoujinTabView> {
  final SearchHandler searchHandler = SearchHandler.instance;

  @override
  void initState() {
    super.initState();
    // A freshly created or just-restored tab hasn't fetched its item yet, and
    // there is no scrollable feed here to trigger the first page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.tab.booruHandler.filteredFetched.isEmpty && !searchHandler.isLoading.value) {
        searchHandler.runSearch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = widget.tab.booruHandler.filteredFetched;
      final bool isLoading = searchHandler.isLoading.value;

      if (items.isEmpty) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Text(
              widget.tab.doujinTitle?.isNotEmpty == true ? widget.tab.doujinTitle! : 'Doujin',
              style: const TextStyle(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load this doujin'),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => searchHandler.searchAction(widget.tab.tags, null),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
          ),
        );
      }

      return DoujinDetailPage(
        key: ValueKey('doujin-tab-${widget.tab.id}-${items.first.serverId}'),
        tab: widget.tab,
        index: 0,
        asTab: true,
      );
    });
  }
}
