part of '../main_search_query_editor_page.dart';

class PinTagDialogResult {
  PinTagDialogResult({
    required this.pinForCurrentBooru,
    this.labels = const [],
  });

  final bool pinForCurrentBooru;
  final List<String> labels;
}

class PinTagDialog extends StatefulWidget {
  const PinTagDialog({
    required this.tagName,
    required this.currentBooru,
    required this.existingLabels,
    super.key,
  });

  final String tagName;
  final Booru currentBooru;
  final List<String> existingLabels;

  @override
  State<PinTagDialog> createState() => _PinTagDialogState();
}

class _PinTagDialogState extends State<PinTagDialog> {
  bool pinForCurrentBooru = false;
  final labelController = TextEditingController();
  final Set<String> selectedLabels = {};

  @override
  void dispose() {
    labelController.dispose();
    super.dispose();
  }

  void _addLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty && !selectedLabels.contains(trimmed)) {
      setState(() {
        selectedLabels.add(trimmed);
        labelController.clear();
      });
    }
  }

  void _removeLabel(String label) {
    setState(() => selectedLabels.remove(label));
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      onClosing: () {},
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 32,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Text(
              context.loc.pinnedTags.pinTag,
              style: context.theme.textTheme.headlineMedium,
            ),
            Builder(
              builder: (context) {
                final bool isMultiword = widget.tagName.split(' ').length > 1;

                return Text(
                  context.loc.pinnedTags.pinQuestion(
                    tag: isMultiword ? widget.tagName : widget.tagName.replaceAll('_', ' '),
                  ),
                  style: context.theme.textTheme.bodyLarge,
                );
              },
            ),
            CheckboxListTile(
              value: pinForCurrentBooru,
              onChanged: (value) => setState(() => pinForCurrentBooru = value ?? false),
              title: Text(context.loc.pinnedTags.onlyForBooru(name: widget.currentBooru.name ?? '')),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: context.loc.pinnedTags.labelsOptional,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: labelController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Symbols.add_rounded, size: 18),
                              onPressed: () => _addLabel(labelController.text),
                            )
                          : null,
                    ),
                    onSubmitted: _addLabel,
                  ),
                ),
                //
                if (widget.existingLabels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Symbols.arrow_drop_down_rounded),
                      tooltip: context.loc.pinnedTags.selectExistingLabel,
                      onSelected: _addLabel,
                      itemBuilder: (context) => widget.existingLabels
                          .where((l) => !selectedLabels.contains(l))
                          .map(
                            (label) => PopupMenuItem(
                              value: label,
                              child: Text(label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                //
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: ValueListenableBuilder(
                      valueListenable: labelController,
                      builder: (_, value, _) {
                        if (value.text.isNotEmpty) {
                          return IconButton(
                            icon: const Icon(Symbols.add_rounded),
                            onPressed: () => _addLabel(value.text),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ],
            ),
            //
            Text(context.loc.pinnedTags.typeAndPressAdd),
            //
            if (selectedLabels.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: selectedLabels
                    .map(
                      (label) => Chip(
                        label: Text(label),
                        onDeleted: () => _removeLabel(label),
                        deleteIconColor: context.theme.colorScheme.error,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            //
            SizedBox(
              width: double.maxFinite,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  const CancelButton(),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      PinTagDialogResult(
                        pinForCurrentBooru: pinForCurrentBooru,
                        labels: selectedLabels.toList(),
                      ),
                    ),
                    icon: const Icon(Symbols.push_pin_rounded),
                    label: Text(context.loc.pinnedTags.pin),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Doujin pins rendered as PinnedTag rows for the shared pin UI.
/// id == -1 marks them: never a DB row, unpin routes to the doujin store.
List<PinnedTag> doujinPinsAsPinnedTags(Booru booru) => [
  for (final p in DoujinDataHandler.instance.pinsFor(booru))
    PinnedTag(
      id: -1,
      tagName: p.tag,
      pinnedAt: p.addedAt,
      labels: p.booruHost == null ? const ['all doujins'] : const [],
    ),
];

Future<void> showPinTagDialog(
  BuildContext context,
  String tagName,
  Booru currentBooru,
  VoidCallback onTagPinned,
) async {
  final settingsHandler = SettingsHandler.instance;
  final bool isDoujin = DoujinDataHandler.isDoujinBooru(currentBooru);

  // Load existing labels for the dropdown (doujin pins don't do labels)
  final existingLabels = isDoujin
      ? const <String>[]
      : await settingsHandler.dbHandler.getPinnedTagLabels(
          booruType: currentBooru.type?.name,
          booruName: currentBooru.name,
        );

  final result = await showModalBottomSheet<PinTagDialogResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PinTagDialog(
      tagName: tagName,
      currentBooru: currentBooru,
      existingLabels: existingLabels,
    ),
  );

  if (result != null) {
    if (isDoujin) {
      // Doujin pins live in the doujin store, never in the PinnedTag table.
      // "Global" here means all DOUJIN sources, not booru-global.
      DoujinDataHandler.instance.addPin(
        tagName,
        currentBooru,
        global: !result.pinForCurrentBooru,
      );
    } else {
      await settingsHandler.dbHandler.addPinnedTag(
        tagName,
        booruType: result.pinForCurrentBooru ? currentBooru.type?.name : null,
        booruName: result.pinForCurrentBooru ? currentBooru.name : null,
        labels: result.labels,
      );
    }

    onTagPinned();

    final labelText = result.labels.isNotEmpty ? ' [${result.labels.join(', ')}]' : '';
    FlashElements.showSnackbar(
      title: Text(context.loc.pinnedTags.tagPinned, style: const TextStyle(fontSize: 20)),
      content: Text(
        result.pinForCurrentBooru
            ? context.loc.pinnedTags.pinnedForBooru(name: currentBooru.name ?? '', labels: labelText)
            : context.loc.pinnedTags.pinnedGloballyWithLabels(labels: labelText),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.push_pin_rounded,
      leadingIconColor: Colors.green,
      duration: const Duration(seconds: 2),
    );
  }
}

Future<bool> showUnpinTagDialog(
  BuildContext context,
  String tagName,
  PinnedTag pinnedTag,
  VoidCallback onTagUnpinned,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => BottomSheet(
      onClosing: () {},
      builder: (context) {
        final bool isMultiword = tagName.split(' ').length > 1;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 32,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Text(
                ctx.loc.pinnedTags.unpinTag,
                style: context.theme.textTheme.headlineMedium,
              ),
              Text(
                ctx.loc.pinnedTags.unpinQuestion(tag: isMultiword ? tagName : tagName.replaceAll('_', ' ')),
              ),
              SizedBox(
                width: double.maxFinite,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      const CancelButton(),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Symbols.push_pin_rounded),
                        label: Text(ctx.loc.pinnedTags.unpin),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  if (result == true) {
    final settingsHandler = SettingsHandler.instance;
    if (pinnedTag.id == -1) {
      // Sentinel id: a doujin pin — remove from the doujin store.
      DoujinDataHandler.instance.removePin(tagName, SearchHandler.instance.currentBooru);
    } else {
      await settingsHandler.dbHandler.removePinnedTag(pinnedTag.id);
    }

    onTagUnpinned();

    FlashElements.showSnackbar(
      title: Text(context.loc.pinnedTags.tagUnpinned, style: const TextStyle(fontSize: 20)),
      sideColor: Colors.orange,
      leadingIcon: Symbols.push_pin_rounded,
      leadingIconColor: Colors.orange,
      duration: const Duration(seconds: 2),
    );
  }

  return result ?? false;
}

class EditLabelsDialog extends StatefulWidget {
  const EditLabelsDialog({
    required this.currentLabels,
    required this.existingLabels,
    super.key,
  });

  final List<String> currentLabels;
  final List<String> existingLabels;

  @override
  State<EditLabelsDialog> createState() => _EditLabelsDialogState();
}

class _EditLabelsDialogState extends State<EditLabelsDialog> {
  final TextEditingController labelController = TextEditingController();
  late final Set<String> selectedLabels;

  @override
  void initState() {
    super.initState();
    selectedLabels = Set.from(widget.currentLabels);
  }

  @override
  void dispose() {
    labelController.dispose();
    super.dispose();
  }

  void _addLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty && !selectedLabels.contains(trimmed)) {
      setState(() {
        selectedLabels.add(trimmed);
        labelController.clear();
      });
    }
  }

  void _removeLabel(String label) {
    setState(() => selectedLabels.remove(label));
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      onClosing: () {},
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 32,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Text(
              context.loc.pinnedTags.editLabels,
              style: context.theme.textTheme.headlineMedium,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: context.loc.pinnedTags.labels,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: labelController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Symbols.add_rounded, size: 18),
                              onPressed: () => _addLabel(labelController.text),
                            )
                          : null,
                    ),
                    onSubmitted: _addLabel,
                    autofocus: true,
                  ),
                ),
                //
                if (widget.existingLabels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Symbols.arrow_drop_down_rounded),
                      tooltip: context.loc.pinnedTags.selectExistingLabel,
                      onSelected: _addLabel,
                      itemBuilder: (context) => widget.existingLabels
                          .where((l) => !selectedLabels.contains(l))
                          .map(
                            (label) => PopupMenuItem(
                              value: label,
                              child: Text(label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                //
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: ValueListenableBuilder(
                      valueListenable: labelController,
                      builder: (_, value, _) {
                        if (value.text.isNotEmpty) {
                          return IconButton(
                            icon: const Icon(Symbols.add_rounded),
                            onPressed: () => _addLabel(value.text),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ],
            ),
            //
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.loc.pinnedTags.typeAndPressAdd),
            ),
            //
            if (selectedLabels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: selectedLabels
                      .map(
                        (label) => Chip(
                          label: Text(label),
                          onDeleted: () => _removeLabel(label),
                          deleteIconColor: context.theme.colorScheme.error,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ),
            //
            SizedBox(
              width: double.maxFinite,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    const CancelButton(),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(selectedLabels.toList()),
                      icon: const Icon(Symbols.check_rounded),
                      label: Text(context.loc.save),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManualPinTagDialogResult {
  ManualPinTagDialogResult({
    required this.tagName,
    required this.pinForCurrentBooru,
    this.labels = const [],
  });

  final String tagName;
  final bool pinForCurrentBooru;
  final List<String> labels;
}

class ManualPinTagDialog extends StatefulWidget {
  const ManualPinTagDialog({
    required this.currentBooru,
    required this.existingLabels,
    super.key,
  });

  final Booru currentBooru;
  final List<String> existingLabels;

  @override
  State<ManualPinTagDialog> createState() => _ManualPinTagDialogState();
}

class _ManualPinTagDialogState extends State<ManualPinTagDialog> {
  final tagController = TextEditingController();
  final labelController = TextEditingController();
  bool pinForCurrentBooru = false;
  final Set<String> selectedLabels = {};

  @override
  void dispose() {
    tagController.dispose();
    labelController.dispose();
    super.dispose();
  }

  void _addLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty && !selectedLabels.contains(trimmed)) {
      setState(() {
        selectedLabels.add(trimmed);
        labelController.clear();
      });
    }
  }

  void _removeLabel(String label) {
    setState(() => selectedLabels.remove(label));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = tagController.text.trim().isNotEmpty;

    return BottomSheet(
      onClosing: () {},
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 32,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Text(
              context.loc.pinnedTags.addPinnedTag,
              style: context.theme.textTheme.headlineMedium,
            ),
            TagSearchBox(
              controller: tagController,
              title: context.loc.pinnedTags.tagQuery,
              hintText: context.loc.pinnedTags.tagQueryHint,
              titleAsLabel: true,
              allowMultipleTags: false,
              showBooruSelector: true,
              onlyInput: true,
              showPinnedTags: false,
              onChanged: (_, _) => setState(() {}),
            ),
            //
            Text(
              context.loc.pinnedTags.rawQueryHelp,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
            //
            CheckboxListTile(
              value: pinForCurrentBooru,
              onChanged: (value) => setState(() => pinForCurrentBooru = value ?? false),
              title: Text(context.loc.pinnedTags.onlyForBooru(name: widget.currentBooru.name ?? '')),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            //
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: context.loc.pinnedTags.labelsOptional,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: labelController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Symbols.add_rounded, size: 18),
                              onPressed: () => _addLabel(labelController.text),
                            )
                          : null,
                    ),
                    onSubmitted: _addLabel,
                  ),
                ),
                //
                if (widget.existingLabels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Symbols.arrow_drop_down_rounded),
                      tooltip: context.loc.pinnedTags.selectExistingLabel,
                      onSelected: _addLabel,
                      itemBuilder: (context) => widget.existingLabels
                          .where((l) => !selectedLabels.contains(l))
                          .map(
                            (label) => PopupMenuItem(
                              value: label,
                              child: Text(label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                //
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: ValueListenableBuilder(
                      valueListenable: labelController,
                      builder: (_, value, _) {
                        if (value.text.isNotEmpty) {
                          return IconButton(
                            icon: const Icon(Symbols.add_rounded),
                            onPressed: () => _addLabel(value.text),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ],
            ),
            //
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.loc.pinnedTags.typeAndPressAdd),
            ),
            //
            if (selectedLabels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: selectedLabels
                      .map(
                        (label) => Chip(
                          label: Text(label),
                          onDeleted: () => _removeLabel(label),
                          deleteIconColor: context.theme.colorScheme.error,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ),
            //
            SizedBox(
              width: double.maxFinite,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: .end,
                  children: [
                    const CancelButton(),
                    ElevatedButton.icon(
                      onPressed: canSubmit
                          ? () => Navigator.of(context).pop(
                              ManualPinTagDialogResult(
                                tagName: tagController.text.trim(),
                                pinForCurrentBooru: pinForCurrentBooru,
                                labels: selectedLabels.toList(),
                              ),
                            )
                          : null,
                      icon: const Icon(Symbols.push_pin_rounded),
                      label: Text(context.loc.pinnedTags.pin),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
