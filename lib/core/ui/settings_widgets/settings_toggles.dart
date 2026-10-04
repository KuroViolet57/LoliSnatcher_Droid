part of '../settings_widgets.dart';

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.leadingIcon,
    this.trailingIcon,
    this.defaultValue,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final Widget? subtitle;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool? defaultValue;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(13);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTile(
          enabled: enabled,
          title: Row(
            children: [
              if (leadingIcon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: leadingIcon,
                ),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              if (defaultValue != null && value != defaultValue)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Symbols.restore_rounded),
                    onPressed: () {
                      onChanged(defaultValue!);
                    },
                  ),
                ),
            ],
          ),
          subtitle: subtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: trailingIcon,
              ),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
          onTap: () => onChanged(!value),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    );
  }
}

class SettingsToggleTristate extends StatelessWidget {
  const SettingsToggleTristate({
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.leadingIcon,
    this.trailingIcon,
    this.defaultValue,
    this.reverse = false,
    super.key,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String title;
  final Widget? subtitle;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool? defaultValue;
  final bool reverse;

  void _onChangedToggle() {
    if (reverse) {
      onChanged(value == null ? true : (value == true ? false : null));
    } else {
      onChanged(value == null ? false : (value == false ? true : null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(13);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTile(
          title: Row(
            children: [
              if (leadingIcon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: leadingIcon,
                ),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              if (defaultValue != null && value != defaultValue)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Symbols.restore_rounded),
                    onPressed: () {
                      onChanged(defaultValue);
                    },
                  ),
                ),
              trailingIcon ?? const SizedBox(width: 8),
            ],
          ),
          subtitle: subtitle,
          trailing: Checkbox(
            value: value,
            tristate: true,
            onChanged: (_) => _onChangedToggle(),
          ),
          onTap: _onChangedToggle,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    );
  }
}

class SettingsSegmentedButton<T> extends StatelessWidget {
  const SettingsSegmentedButton({
    required this.value,
    required this.values,
    required this.itemTitleBuilder,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.leadingIcon,
    this.trailingIcon,
    this.defaultValue,
    super.key,
  });

  final T value;
  final List<T> values;
  final String Function(T) itemTitleBuilder;
  final ValueChanged<T> onChanged;
  final String title;
  final Widget? subtitle;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final T? defaultValue;

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
        title: Row(
          children: [
            if (leadingIcon != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: leadingIcon,
              ),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            if (defaultValue != null && value != defaultValue)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  icon: const Icon(Symbols.restore_rounded),
                  onPressed: () {
                    onChanged(defaultValue as T);
                  },
                ),
              ),
            trailingIcon ?? const SizedBox(width: 8),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton(
                onSelectionChanged: (value) => onChanged(value.first),
                emptySelectionAllowed: false,
                multiSelectionEnabled: false,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                    const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                  ),
                ),
                direction: Axis.horizontal,
                segments: [
                  for (final T v in values)
                    ButtonSegment(
                      value: v,
                      icon: const Icon(null),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                itemTitleBuilder(v),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const Icon(null),
                          ],
                        ),
                      ),
                    ),
                ],
                selected: {value},
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: subtitle,
                ),
            ],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),
      ),
    );
  }
}
