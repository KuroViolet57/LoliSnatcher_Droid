part of '../settings_widgets.dart';

/// r88: a part of a settings page with a clear title (and a line on what is
/// in it), so a long page reads as a few named parts.
class SettingsPart extends StatelessWidget {
  const SettingsPart({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: theme.colorScheme.secondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.65))),
          ],
        ],
      ),
    );
  }
}

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    required this.name,
    this.icon,
    this.subtitle,
    this.page, // which page to open after button was pressed (needs to be wrapped in anonymous function, i.e.: () => Page)
    // OR
    this.action, // function to execute on button press
    this.onLongPress,
    this.trailingIcon, // icon at the end (i.e. if action is a link which will open a browser)
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.enabled = true, // disable button interaction (will also change text color to grey)
    this.iconOnly = false,
    this.dense = false,
    this.useHtml = false,
    super.key,
  });

  final String name;
  final Widget? icon;
  final Widget? subtitle;
  final Widget Function()? page;
  final VoidCallback? action;
  final VoidCallback? onLongPress;
  final Widget? trailingIcon;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final bool enabled;
  final bool iconOnly;
  final bool dense;
  final bool useHtml;

  bool get interactive => action != null || page != null;

  void onTapAction(BuildContext context) {
    PerfTrace.instance.event('ui.button', name);
    if (action != null) {
      action?.call();
    } else if (page != null) {
      SettingsPageOpen(context: context, page: (_) => page!()).open();
    }
  }

  @override
  Widget build(BuildContext context) {
    // An empty, disabled button is the pages' spacer: since the settings
    // became cards it drew a blank card (r39).
    if (name.isEmpty && !enabled && icon == null && subtitle == null && page == null && action == null) {
      return const SizedBox(height: 10);
    }
    if (iconOnly) {
      // One InkResponse for both gestures — an IconButton inside a
      // GestureDetector swallows the ancestor's long press (its own ink tap
      // recognizer is innermost in the gesture arena).
      return InkResponse(
        onTap: interactive ? () => onTapAction(context) : null,
        onLongPress: onLongPress == null ? null : () => onLongPress!(),
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: icon ?? const Icon(null),
        ),
      );
    }

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
          leading: icon,
          title: useHtml ? LoliHtml(name) : Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle,
          trailing: trailingIcon ??
              (page != null
                  ? Icon(Symbols.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant)
                  : null),
          enabled: enabled,
          dense: dense,
          onTap: interactive ? () => onTapAction(context) : null,
          onLongPress: onLongPress,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    );
  }
}

/// class used to unify the opening of settings pages logic
/// TODO get rid of this if possible after implementing proper routing
class SettingsPageOpen {
  SettingsPageOpen({
    required this.page,
    required this.context,
    this.condition = true,
    this.barrierDismissible = true,
    this.asDialog = false,
    this.asBottomSheet = false,
    this.bottomSheetExpandableByScroll = false,
    this.useFloatingDialog = false,
  }) : assert(!(asDialog && asBottomSheet), "asDialog and asBottomSheet can't be true at the same time");

  final Widget Function(ScrollController?) page;
  final BuildContext context;
  final bool condition;
  final bool barrierDismissible;
  final bool asDialog;
  final bool asBottomSheet;
  final bool bottomSheetExpandableByScroll;
  final bool useFloatingDialog;

  Future<dynamic> open() async {
    if (!condition) {
      return null;
    }

    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final bool isTooNarrow = MediaQuery.sizeOf(context).width < 550;
    final bool isDesktop = settingsHandler.appMode.value.isDesktop || SettingsHandler.isDesktopPlatform;
    final bool useDesktopMode = (!isTooNarrow && isDesktop && !asBottomSheet) || useFloatingDialog;

    dynamic result;
    if (useDesktopMode) {
      result = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            child: SizedBox(
              width: min(MediaQuery.sizeOf(context).width, 500),
              child: page(null),
            ),
          );
        },
        barrierDismissible: barrierDismissible,
      );
    } else {
      if (asDialog) {
        result = await showDialog(
          context: context,
          builder: (BuildContext context) {
            return page(null);
          },
          barrierDismissible: barrierDismissible,
        );
      } else if (asBottomSheet) {
        result = await showModalBottomSheet(
          context: context,
          builder: (BuildContext context) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: bottomSheetExpandableByScroll
                  ? GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: ColoredBox(
                        color: Colors.transparent,
                        child: DraggableScrollableSheet(
                          minChildSize: 0.3,
                          initialChildSize: 0.7,
                          maxChildSize: 1,
                          shouldCloseOnMinExtent: true,
                          builder: (_, controller) => GestureDetector(
                            // required to ignore taps on empty places inside the sheet while also allowing taps on the barrier
                            onTap: () {},
                            child: page(controller),
                          ),
                        ),
                      ),
                    )
                  : page(null),
            );
          },
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
        );
      } else {
        result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) => page(null),
          ),
        );
      }
    }
    return result;
  }
}
