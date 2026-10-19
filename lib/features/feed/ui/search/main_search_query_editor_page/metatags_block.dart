part of '../main_search_query_editor_page.dart';

//

class AddMetatagBottomSheetResult {
  AddMetatagBottomSheetResult({
    required this.tag,
    this.compareMode,
    this.value,
  });

  final MetaTag tag;
  final CompareMode? compareMode;
  final String? value;

  bool get shouldAddDirectly => switch (tag.runtimeType) {
    const (MetaTagWithCompareModes) => compareMode != null && value != null,
    const (MetaTagWithValues) => value != null,
    _ => false,
  };
}

class AddMetatagBottomSheet extends StatelessWidget {
  const AddMetatagBottomSheet(
    this.scrollController, {
    super.key,
  });

  final ScrollController? scrollController;

  void onOptionSelect(
    BuildContext context,
    MetaTag tag, {
    CompareMode? compareMode,
    String? value,
  }) {
    Navigator.of(context).pop(
      AddMetatagBottomSheetResult(
        tag: tag,
        compareMode: compareMode,
        value: value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;

    final metaTags = searchHandler.currentBooruHandler.availableMetaTags();
    if (metaTags.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
    }

    return SettingsBottomSheet(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            context.loc.searchBar.metatags,
            style: context.theme.textTheme.titleLarge,
          ),
          const SizedBox(width: 12),
          Text(
            metaTags.length.toString(),
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: EdgeInsets.zero,
      buttonPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      scrollController: scrollController,
      contentItems: [
        const SizedBox(height: 16),
        if (metaTags.any((t) => t.isFree))
          Container(
            margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: context.theme.colorScheme.surfaceContainer,
            ),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  children: [
                    const Icon(Symbols.info_rounded),
                    const SizedBox(width: 8),
                    Text(
                      context.loc.searchBar.freeMetatags,
                      style: context.theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.loc.searchBar.freeMetatagsDescription,
                ),
              ],
            ),
          ),
        //
        for (final tag in metaTags)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                switch (tag.type) {
                  case .date:
                    final metaTag = tag as DateMetaTag;
                    final res = await showSingleDatePicker(
                      context,
                      dateFormat: metaTag.dateFormat,
                    );

                    if (res is DateTime) {
                      onOptionSelect(
                        context,
                        tag,
                        compareMode: null,
                        value: DateFormat(metaTag.dateFormat).format(res),
                      );
                    }
                    break;
                  default:
                    onOptionSelect(context, tag);
                    break;
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tag.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.theme.textTheme.bodyLarge,
                                  ),
                                  Text(
                                    tag.keyName,
                                    style: context.theme.textTheme.bodySmall?.copyWith(
                                      color: context.theme.colorScheme.onSurface.withValues(alpha: 0.66),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (tag.isFree)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: context.theme.colorScheme.surfaceContainer.withValues(alpha: 0.66),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  context.loc.searchBar.free,
                                  style: context.theme.textTheme.bodySmall?.copyWith(
                                    color: context.theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            //
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      //
                      switch (tag.type) {
                        .date => Builder(
                          builder: (context) {
                            final metaTag = tag as DateMetaTag;
                            return Row(
                              spacing: 6,
                              children: [
                                IconButton.outlined(
                                  onPressed: () async {
                                    final res = await showSingleDatePicker(
                                      context,
                                      dateFormat: metaTag.dateFormat,
                                    );

                                    if (res is DateTime) {
                                      onOptionSelect(
                                        context,
                                        tag,
                                        compareMode: null,
                                        value: DateFormat(metaTag.dateFormat).format(res),
                                      );
                                    }
                                  },
                                  icon: metaTag.supportsRange
                                      ? Text(context.loc.searchBar.single)
                                      : const Icon(Symbols.calendar_month_rounded),
                                ),
                                if (metaTag.supportsRange)
                                  IconButton.outlined(
                                    onPressed: () async {
                                      final res = await showRangeDatePicker(
                                        context,
                                        dateFormat: metaTag.dateFormat,
                                      );

                                      if (res is List<DateTime> && res.length == 2) {
                                        onOptionSelect(
                                          context,
                                          tag,
                                          compareMode: null,
                                          value:
                                              DateFormat(metaTag.dateFormat).format(res[0]) +
                                              metaTag.valuesDivider +
                                              DateFormat(metaTag.dateFormat).format(res[1]),
                                        );
                                      }
                                    },
                                    icon: Text(context.loc.searchBar.range),
                                  ),
                                if (metaTag.supportsRange) const Icon(Symbols.calendar_month_rounded),
                              ],
                            );
                          },
                        ),
                        .sort => const Icon(Symbols.sort_rounded),
                        .user => const Icon(Symbols.person_outline_rounded),
                        .comparableNumber => Row(
                          spacing: 2,
                          children: [
                            for (final mode in (tag as MetaTagWithCompareModes).compareModes)
                              IconButton.outlined(
                                onPressed: () => onOptionSelect(context, tag, compareMode: mode),
                                icon: FaIcon(
                                  switch (mode) {
                                    CompareMode.exact => FontAwesomeIcons.equals,
                                    CompareMode.less => FontAwesomeIcons.lessThanEqual,
                                    CompareMode.greater => FontAwesomeIcons.greaterThanEqual,
                                  },
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                        _ => const SizedBox.shrink(),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

Future<DateTime?> showSingleDatePicker(
  BuildContext context, {
  String? dateFormat,
}) async {
  final res = await SettingsPageOpen(
    context: context,
    asBottomSheet: true,
    bottomSheetExpandableByScroll: false,
    page: (_) => SingleDatePickerBottomSheet(
      dateFormat: dateFormat,
    ),
  ).open();

  if (res is DateTime) {
    return res;
  }

  return null;
}

class SingleDatePickerBottomSheet extends StatefulWidget {
  const SingleDatePickerBottomSheet({
    this.dateFormat,
    super.key,
  });

  final String? dateFormat;

  @override
  State<SingleDatePickerBottomSheet> createState() => _SingleDatePickerBottomSheetState();
}

class _SingleDatePickerBottomSheetState extends State<SingleDatePickerBottomSheet> {
  List<DateTime> date = [DateTime.now()];

  @override
  Widget build(BuildContext context) {
    return SettingsBottomSheet(
      title: Text(
        context.loc.searchBar.selectDate,
        style: context.theme.textTheme.titleLarge,
      ),
      contentItems: [
        const SizedBox(height: 16),
        Text(
          DateFormat(widget.dateFormat ?? 'yyyy-MM-dd').format(date.first),
          style: context.theme.textTheme.bodyLarge,
        ),
        CalendarDatePicker2(
          config: CalendarDatePicker2Config(
            calendarType: CalendarDatePicker2Type.single,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            selectedDayHighlightColor: context.theme.colorScheme.secondary,
          ),
          value: date,
          onValueChanged: (value) => setState(() => date = value),
        ),
      ],
      actionButtons: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 12,
          children: [
            const CancelButton(withIcon: true),
            ConfirmButton(
              returnData: date.first,
              withIcon: true,
            ),
          ],
        ),
      ],
    );
  }
}

Future<List<DateTime>?> showRangeDatePicker(
  BuildContext context, {
  String? dateFormat,
}) async {
  final res = await SettingsPageOpen(
    context: context,
    asBottomSheet: true,
    bottomSheetExpandableByScroll: false,
    page: (_) => RangeDatePickerBottomSheet(
      dateFormat: dateFormat,
    ),
  ).open();

  if (res is List<DateTime>) {
    return res;
  }

  return null;
}

class RangeDatePickerBottomSheet extends StatefulWidget {
  const RangeDatePickerBottomSheet({
    this.dateFormat,
    super.key,
  });

  final String? dateFormat;

  @override
  State<RangeDatePickerBottomSheet> createState() => _RangeDatePickerBottomSheetState();
}

class _RangeDatePickerBottomSheetState extends State<RangeDatePickerBottomSheet> {
  List<DateTime> range = [
    DateTime.now().subtract(const Duration(days: 7)),
    DateTime.now(),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsBottomSheet(
      title: Text(
        context.loc.searchBar.selectDatesRange,
        style: context.theme.textTheme.titleLarge,
      ),
      contentItems: [
        const SizedBox(height: 16),
        Text(
          // ignore: prefer_interpolation_to_compose_strings
          DateFormat(widget.dateFormat ?? 'yyyy-MM-dd').format(range.first) +
              ' - ' +
              DateFormat(widget.dateFormat ?? 'yyyy-MM-dd').format(range.last),
          style: context.theme.textTheme.bodyLarge,
        ),
        CalendarDatePicker2(
          config: CalendarDatePicker2Config(
            calendarType: CalendarDatePicker2Type.range,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            selectedDayHighlightColor: context.theme.colorScheme.secondary,
          ),
          value: range,
          onValueChanged: (value) => setState(() => range = value),
        ),
      ],
      actionButtons: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 12,
          children: [
            const CancelButton(withIcon: true),
            ConfirmButton(
              returnData: range,
              withIcon: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// The Metatags card: the source's metatag chips. Tap one to insert `key:`
/// (or pick a date); the full list is a chevron away. The tag builder —
/// every artist, character… the source can list — is the card under this
/// one, [TagBuilderBlock].
class MetatagsBlock extends StatefulWidget {
  const MetatagsBlock({
    required this.onSelect,
    this.booru,
    super.key,
  });

  final Function(AddMetatagBottomSheetResult) onSelect;

  /// The source to build for; null follows the current tab.
  final Booru? booru;

  @override
  State<MetatagsBlock> createState() => _MetatagsBlockState();
}

class _MetatagsBlockState extends State<MetatagsBlock> with _EditorSourceMixin {
  final scrollController = ScrollController();

  @override
  Booru? get ownBooru => widget.booru;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> openMetatagsDialog() async {
    final res = await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      bottomSheetExpandableByScroll: true,
      page: AddMetatagBottomSheet.new,
    ).open();

    if (res is AddMetatagBottomSheetResult) {
      widget.onSelect(res);
    }
  }

  void onOptionSelect(
    BuildContext context,
    MetaTag tag, {
    CompareMode? compareMode,
    String? value,
  }) {
    widget.onSelect(
      AddMetatagBottomSheetResult(
        tag: tag,
        compareMode: compareMode,
        value: value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BooruHandler handler = sourceHandler;
    List<MetaTag> entries = handler.availableMetaTags();
    bool overflows = false;
    if (entries.length > 15) {
      // show only first 15 (only danbooru has this much right now) to motivate
      // user to open the bottom sheet with the full list
      entries = entries.sublist(0, 15);
      overflows = true;
    }

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return SearchSectionCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(
                    Symbols.filter_list_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.loc.searchBar.metatags,
                      style: context.theme.textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (handler.metatagsCheatSheetLink != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        onPressed: () {
                          launchUrlString(
                            handler.metatagsCheatSheetLink!,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Symbols.help_outline_rounded),
                      ),
                    ),
                  IconButton(
                    onPressed: openMetatagsDialog,
                    icon: const Icon(Symbols.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: Listener(
              onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
              child: FadingEdgeScrollView.fromScrollView(
                child: ListView.builder(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length + (overflows ? 1 : 0),
                  itemBuilder: (BuildContext context, int index) {
                    if (overflows && index == entries.length) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(context.loc.searchBar.more),
                          onPressed: openMetatagsDialog,
                        ),
                      );
                    }

                    final MetaTag tag = entries[index];

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(tag.name),
                        avatar: switch (tag.type) {
                          .date => Icon(
                            Symbols.calendar_month_rounded,
                            color: context.theme.colorScheme.onSurface,
                          ),
                          .sort => Icon(
                            Symbols.sort_rounded,
                            color: context.theme.colorScheme.onSurface,
                          ),
                          .user => Icon(
                            Symbols.person_outline_rounded,
                            color: context.theme.colorScheme.onSurface,
                          ),
                          _ => null,
                        },
                        onPressed: () async {
                          switch (tag.type) {
                            case .date:
                              final metaTag = tag as DateMetaTag;
                              final res = await showSingleDatePicker(
                                context,
                                dateFormat: metaTag.dateFormat,
                              );

                              if (res is DateTime) {
                                onOptionSelect(
                                  context,
                                  tag,
                                  compareMode: null,
                                  value: DateFormat(metaTag.dateFormat).format(res),
                                );
                              }
                              break;
                            default:
                              onOptionSelect(context, tag);
                              break;
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
