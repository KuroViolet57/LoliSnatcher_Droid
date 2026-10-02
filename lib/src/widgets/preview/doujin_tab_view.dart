import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/utils/perf_trace.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/pages/doujin_detail_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/tabs/doujin_mini_tab_manager.dart';

/// The whole content of a doujin-detail TAB: the detail page itself, with no
/// feed chrome around it — no main app bar, no tab carousel, no pagination or
/// end-of-results banner, no bottom search bar, no booru drawers. The page's
/// own app bar has no back button (a tab has nowhere to go back to) and the
/// right third of the screen drags open the mini tab manager.
///
/// When the gallery cannot be loaded (a session that expired while the tab
/// waited, a site that is down, a gallery key the source no longer
/// remembers) the error screen keeps every way out the loaded page has —
/// the tab manager, closing the tab — names the source's reason, and its
/// Retry re-runs the tab's own search rather than rebuilding the tab (r34,
/// r35).
class DoujinTabView extends StatefulWidget {
  const DoujinTabView({required this.tab, super.key});

  final SearchTab tab;

  @override
  State<DoujinTabView> createState() => _DoujinTabViewState();
}

class _DoujinTabViewState extends State<DoujinTabView> with TraceLifecycle {
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

  void _closeTab() {
    final int index = searchHandler.tabs.indexOf(widget.tab);
    if (index < 0) return;
    searchHandler.removeTabAt(tabIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = widget.tab.booruHandler.filteredFetched;
      final bool isLoading = searchHandler.isLoading.value;

      if (items.isEmpty) {
        final String title = widget.tab.doujinTitle?.isNotEmpty == true ? widget.tab.doujinTitle! : 'Doujin';
        // The tab's own handler knows why; the search handler's line is the
        // same thing when this is the current tab.
        final String own = widget.tab.booruHandler.errorString.trim();
        final String reason = own.isNotEmpty ? own : searchHandler.errorString.value.trim();
        final String? link = widget.tab.doujinPostURL?.isNotEmpty == true ? widget.tab.doujinPostURL : null;
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            leading: IconButton(
              key: const Key('doujin-tab-close'),
              tooltip: 'Close tab',
              icon: const Icon(Symbols.close_rounded),
              onPressed: _closeTab,
            ),
            title: Text(
              title,
              style: const TextStyle(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (link != null)
                IconButton(
                  key: const Key('doujin-tab-open-browser'),
                  tooltip: 'Open in browser',
                  icon: const Icon(Symbols.public_rounded),
                  onPressed: () => launchUrlString(Uri.encodeFull(link), mode: LaunchMode.externalApplication),
                ),
              Builder(
                builder: (context) => IconButton(
                  key: const Key('doujin-tab-tabs'),
                  tooltip: 'Tabs',
                  icon: const Icon(Symbols.tab_rounded),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          ),
          endDrawer: const DoujinMiniTabManager(),
          drawerEdgeDragWidth: DoujinDetailPage.edgeDragWidthFor(MediaQuery.sizeOf(context)),
          body: Stack(
            children: [
              Center(
                child: isLoading
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Could not load this doujin', style: TextStyle(fontSize: 16)),
                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                reason,
                                key: const Key('doujin-tab-reason'),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                // The tab's own search again — not a new tab
                                // without its saved gallery URL (r34).
                                FilledButton.icon(
                                  onPressed: searchHandler.retrySearch,
                                  icon: const Icon(Symbols.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                                if (link != null)
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: link));
                                      FlashElements.showSnackbar(
                                        context: context,
                                        title: const Text('Link copied', style: TextStyle(fontSize: 18)),
                                        duration: const Duration(seconds: 2),
                                        sideColor: Colors.green,
                                      );
                                    },
                                    icon: const Icon(Symbols.content_copy_rounded),
                                    label: const Text('Copy link'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _closeTab,
                                  icon: const Icon(Symbols.close_rounded),
                                  label: const Text('Close tab'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
              const Positioned(top: 0, bottom: 0, right: 0, child: DoujinMiniTabEdgeHandle()),
            ],
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
