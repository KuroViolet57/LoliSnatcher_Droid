part of '../settings_widgets.dart';

class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.trailingIcon,
    this.contentPadding,
    this.itemBuilder,
    this.itemFilter,
    this.selectedItemBuilder,
    this.itemTitleBuilder,
    this.itemSubtitleBuilder,
    this.clearable = false,
    this.searchable = false,
    this.searchCheck,
    this.onReset,
    this.itemExtent,
    this.expendableByScroll = false,
    this.placeholder,
    this.titleAsLabel = false,
    super.key,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String title;
  final Widget? subtitle;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final Widget? trailingIcon;
  final EdgeInsets? contentPadding;
  final Widget Function(T?)? itemBuilder;
  final bool Function(T?)? itemFilter;
  final Widget Function(T?)? selectedItemBuilder;
  final String Function(T?)? itemTitleBuilder;
  final String Function(T?)? itemSubtitleBuilder;
  final bool clearable;
  final bool searchable;
  final bool Function(String, T)? searchCheck;
  final VoidCallback? onReset;
  final double? itemExtent;
  final bool expendableByScroll;
  final String? placeholder;
  final bool titleAsLabel;

  String getTitle(T? value) {
    return itemTitleBuilder?.call(value) ?? value?.toString() ?? placeholder ?? '';
  }

  String getSubtitle(T? value) {
    return itemSubtitleBuilder?.call(value) ?? '';
  }

  Widget getItemWidget(T? value) {
    final String subtitle = getSubtitle(value);
    final bool hasSubtitle = subtitle.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Padding(
          padding: hasSubtitle ? const EdgeInsets.only(top: 8) : EdgeInsets.zero,
          child: itemBuilder?.call(value) ?? Text(getTitle(value)),
        ),
        if (hasSubtitle)
          Builder(
            builder: (context) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget getSelectedItemWidget(T? value) {
    return selectedItemBuilder?.call(value) ?? itemBuilder?.call(value) ?? Text(getTitle(value));
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = Theme.of(context);
    final BorderRadius cardRadius = BorderRadius.circular(13);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
      color: cardTheme.colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: cardRadius,
        side: BorderSide(color: cardTheme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!titleAsLabel)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            LoliDropdown(
              value: value,
              onChanged: onChanged ?? (item) {},
              items: items.where((item) => itemFilter?.call(item) ?? true).toList(),
              clearable: clearable,
              searchable: searchable,
              searchCheck: searchCheck,
              expandableByScroll: expendableByScroll,
              itemExtent: itemExtent,
              itemBuilder: (item) {
                final bool isCurrent = value == item;

                return Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                  alignment: Alignment.centerLeft,
                  decoration: isCurrent
                      ? BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                        )
                      : null,
                  child: getItemWidget(item),
                );
              },
              selectedItemBuilder: getSelectedItemWidget,
              labelBuilder: titleAsLabel ? null : () => const SizedBox.shrink(),
              labelText: title,
            ),
          ],
        ),
        subtitle: subtitle,
        trailing:
            trailingIcon ??
            (onReset != null
                ? IconButton(
                    onPressed: onReset,
                    icon: const Icon(Symbols.refresh_rounded),
                  )
                : null),
        dense: false,
        contentPadding: contentPadding,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),
      ),
    );
  }
}

class SettingsBooruDropdown extends StatelessWidget {
  const SettingsBooruDropdown({
    required this.value,
    required this.onChanged,
    required this.title,
    this.items,
    this.itemBuilder,
    this.selectedItemBuilder,
    this.itemFilter,
    this.subtitle,
    this.placeholder,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.nullable = false,
    this.searcheable,
    this.searchCheck,
    this.trailingIcon,
    this.contentPadding,
    this.titleAsLabel = false,
    super.key,
  });

  final Booru? value;
  final ValueChanged<Booru?>? onChanged;
  final String title;
  final List<Booru>? items;
  final Widget Function(Booru?, bool)? itemBuilder;
  final Widget Function(Booru?)? selectedItemBuilder;
  final bool Function(Booru?)? itemFilter;
  final Widget? subtitle;
  final String? placeholder;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final bool nullable;
  final bool? searcheable;
  final bool Function(String, Booru?)? searchCheck;
  final Widget? trailingIcon;
  final EdgeInsets? contentPadding;
  final bool titleAsLabel;

  Widget _selectedItemBuilder(BuildContext context, Booru? item) {
    if (item == null) {
      return Text(placeholder ?? context.loc.common.selectABooru);
    }

    if (selectedItemBuilder != null) {
      return selectedItemBuilder!(item);
    }

    return TabBooruSelectorItem(booru: item);
  }

  Widget _itemBuilder(BuildContext context, Booru? item) {
    final bool isCurrent = value == item;

    if (itemBuilder != null) {
      return itemBuilder!(item, isCurrent);
    }

    if (item == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16),
      height: kMinInteractiveDimension,
      decoration: isCurrent
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            )
          : null,
      child: TabBooruSelectorItem(booru: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usedItems = (items ?? SettingsHandler.instance.booruList).where((b) => itemFilter?.call(b) ?? true);

    return SettingsDropdown<Booru?>(
      value: value,
      items: [
        ...usedItems,
      ],
      onChanged: onChanged,
      title: title,
      subtitle: subtitle,
      drawTopBorder: drawTopBorder,
      drawBottomBorder: drawBottomBorder,
      trailingIcon: trailingIcon,
      itemBuilder: (item) => _itemBuilder(context, item),
      selectedItemBuilder: (item) => _selectedItemBuilder(context, item),
      clearable: nullable,
      searchable: searcheable ?? usedItems.length > 5,
      searchCheck:
          searchCheck ??
          (searchText, item) =>
              (item?.name?.toLowerCase().contains(searchText) ?? true) ||
              (item?.type?.name.toLowerCase().contains(searchText) ?? true),
      itemExtent: 54,
      expendableByScroll: true,
      contentPadding: contentPadding,
      titleAsLabel: titleAsLabel,
    );
  }
}

class SettingsOptionsList<T> extends StatelessWidget {
  const SettingsOptionsList({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.trailingIcon,
    this.itemBuilder,
    this.itemLeadingBuilder,
    this.selectedItemBuilder,
    this.itemTitleBuilder,
    this.clearable = false,
    this.onReset,
    super.key,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String title;
  final Widget? subtitle;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final Widget? trailingIcon;
  final Widget Function(T?)? itemBuilder;
  final Widget? Function(T?)? itemLeadingBuilder;
  final Widget Function(T?)? selectedItemBuilder;
  final String Function(T?)? itemTitleBuilder;
  final bool clearable;
  final VoidCallback? onReset;

  String getItemTitle(T? value) => itemTitleBuilder?.call(value) ?? value.toString();

  Widget? getItemLeading(T? value) => itemLeadingBuilder?.call(value);

  Widget getItemWidget(
    BuildContext context,
    T? value,
    bool isSelected,
    int index,
  ) {
    final Color baseColor = Theme.of(context).colorScheme.secondary;
    final Color oddItemColor = baseColor.withValues(alpha: 0.25);
    final Color evenItemColor = baseColor.withValues(alpha: 0.15);

    return InkWell(
      onTap: () => onChanged(value),
      child:
          (isSelected ? selectedItemBuilder ?? itemBuilder : itemBuilder)?.call(value) ??
          ListTile(
            key: Key('$index'),
            tileColor: index.isOdd ? oddItemColor : evenItemColor,
            leading: getItemLeading(value),
            title: Text(getItemTitle(value)),
            trailing: isSelected ? const Icon(Symbols.check_rounded, size: 24) : null,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: cardTheme.colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: cardTheme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            ListTile(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: subtitle,
              trailing:
                  trailingIcon ??
                  (onReset != null
                      ? IconButton(
                          onPressed: onReset,
                          icon: const Icon(Symbols.refresh_rounded),
                        )
                      : null),
              dense: false,
            ),
            ListTile(
              title: Column(
                children: [
                  for (final item in items)
                    getItemWidget(
                      context,
                      item,
                      value == item,
                      items.indexOf(item),
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
