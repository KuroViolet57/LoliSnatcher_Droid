part of '../settings_widgets.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    this.title,
    this.content,
    this.contentItems,
    this.actionButtons,
    this.titlePadding,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 20, 16, 16),
    this.buttonPadding,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    this.borderRadius,
    this.backgroundColor,
    this.surfaceTintColor,
    this.scrollable = true,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? contentItems;
  final List<Widget>? actionButtons;
  final EdgeInsets? titlePadding;
  final EdgeInsets contentPadding;
  final EdgeInsets? buttonPadding;
  final EdgeInsets insetPadding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: title,
      content:
          content ??
          SingleChildScrollView(
            child: ListBody(
              children: contentItems ?? [],
            ),
          ),
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      surfaceTintColor: surfaceTintColor ?? Theme.of(context).colorScheme.surfaceTint,
      actions: actionButtons?.isNotEmpty == true ? actionButtons : null,
      titlePadding: titlePadding,
      contentPadding: contentPadding,
      buttonPadding: buttonPadding,
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: borderRadius ?? BorderRadius.circular(10)),
      scrollable: scrollable,
    );
  }
}

class SettingsBottomSheet extends StatelessWidget {
  const SettingsBottomSheet({
    this.title,
    this.content,
    this.contentItems,
    this.actionButtons,
    this.titlePadding,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.buttonPadding,
    this.borderRadius,
    this.backgroundColor,
    this.showCloseButton = true,
    this.scrollController,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? contentItems;
  final List<Widget>? actionButtons;
  final EdgeInsets? titlePadding;
  final EdgeInsets contentPadding;
  final EdgeInsets? buttonPadding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final bool showCloseButton;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).colorScheme.surface,
        borderRadius:
            borderRadius ?? const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (title != null)
                          Padding(
                            padding: titlePadding ?? const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: title,
                          )
                        else
                          const SizedBox(height: 12),
                        if (showCloseButton)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                            child: IconButton(
                              icon: const Icon(Symbols.close_rounded),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                      ],
                    ),
                    //
                    ?content,
                    //
                    if (contentItems != null)
                      Flexible(
                        child: Padding(
                          padding: contentPadding,
                          child: SingleChildScrollView(
                            controller: scrollController,
                            child: ListBody(
                              children: contentItems ?? [],
                            ),
                          ),
                        ),
                      ),
                    if (actionButtons != null)
                      Padding(
                        padding: buttonPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: actionButtons ?? [],
                        ),
                      ),
                  ],
                ),
              ),
              //
              Positioned(
                top: 6,
                left: constraints.maxWidth / 2 - 20,
                child: Center(
                  child: SizedBox(
                    height: 4,
                    width: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor ?? Theme.of(context).colorScheme.onSurface,
                        borderRadius:
                            borderRadius ??
                            const BorderRadius.all(
                              Radius.circular(20),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SettingsPageDialog extends StatelessWidget {
  const SettingsPageDialog({
    this.title,
    this.content,
    this.actions,
    this.fab,
    this.backgroundColor,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? fab;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBodyBehindAppBar: true,
      // extendBody: true,
      // resizeToAvoidBottomInset: true,
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: title,
        actions: [
          if ((actions?.length ?? 0) > 0)
            Row(
              // add separators between actions and after the last action
              children:
                  actions
                      ?.map(
                        (e) => [
                          e,
                          const SizedBox(width: 8),
                        ],
                      )
                      .expand((e) => e)
                      .toList() ??
                  [],
            ),
        ],
      ),
      floatingActionButton: fab,
      body: SafeArea(
        child: content ?? const SizedBox.shrink(),
      ),
    );
  }
}

class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SettingsAppBar({
    required this.title,
    this.leading,
    super.key,
  });

  final String title;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: MarqueeText(
        text: title,
        isExpanded: false,
      ),
      leading: leading,
    );
  }
}
