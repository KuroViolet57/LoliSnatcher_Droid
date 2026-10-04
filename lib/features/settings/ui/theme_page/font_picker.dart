part of '../theme_page.dart';

class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.currentFont,
    required this.defaultFonts,
    required this.onFontSelected,
    required this.getFontStyle,
    required this.scrollController,
  });

  final String currentFont;
  final List<String> defaultFonts;
  final ValueChanged<String> onFontSelected;
  final TextStyle? Function(String) getFontStyle;
  final ScrollController scrollController;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  String selectedFont = 'System';
  late bool showAllFonts;

  // Extended list of popular Google Fonts
  static const List<String> extendedFonts = [
    'Playfair Display',
    'Source Sans 3',
    'Noto Sans',
    'Inter',
    'Quicksand',
    'Work Sans',
    'Fira Sans',
    'Josefin Sans',
    'Cabin',
    'Karla',
    'Libre Baskerville',
    'Inconsolata',
    'Source Code Pro',
    'Space Mono',
    'JetBrains Mono',
    'Crimson Text',
    'Bitter',
    'Archivo',
    'Rubik',
    'Comfortaa',
  ];

  @override
  void initState() {
    super.initState();

    selectedFont = widget.currentFont;
    // Auto-expand if current font is from extended list or is a custom font
    final isCustomFont =
        !widget.defaultFonts.contains(selectedFont) &&
        !extendedFonts.contains(selectedFont) &&
        selectedFont != 'System';
    showAllFonts = extendedFonts.contains(selectedFont) || isCustomFont;
  }

  Future<void> _showCustomFontDialog(BuildContext context) async {
    final initialText =
        !widget.defaultFonts.contains(selectedFont) && !extendedFonts.contains(selectedFont) && selectedFont != 'System'
        ? selectedFont
        : '';
    final controller = TextEditingController(text: initialText);

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _CustomFontDialog(controller: controller),
    );

    if (result != null && result.isNotEmpty) {
      widget.onFontSelected(result);
    }
  }

  TextStyle? _getExtendedFontStyle(String font) {
    if (font == 'System') {
      return context.isDark ? ThemeData.dark().textTheme.bodyMedium : ThemeData.light().textTheme.bodyMedium;
    }

    // First check if it's in the default fonts
    final defaultStyle = widget.getFontStyle(font);
    if (defaultStyle != null) return defaultStyle;

    // Extended fonts
    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return defaultStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> fontsToShow = showAllFonts ? [...widget.defaultFonts, ...extendedFonts] : widget.defaultFonts;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                context.loc.settings.theme.fontFamily,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Symbols.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            controller: widget.scrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              // +1 for "View more fonts" (when collapsed) or "Custom font" (when expanded)
              itemCount: fontsToShow.length + 1,
              itemBuilder: (context, index) {
                // "View more fonts" button (when collapsed)
                if (!showAllFonts && index == fontsToShow.length) {
                  return ListTile(
                    leading: const Icon(Symbols.expand_more_rounded),
                    title: Text(context.loc.settings.theme.viewMoreFonts),
                    onTap: () => setState(() => showAllFonts = true),
                  );
                }

                // "Custom font" option (when expanded, at the end)
                if (showAllFonts && index == fontsToShow.length) {
                  final isCustomSelected =
                      !widget.defaultFonts.contains(selectedFont) &&
                      !extendedFonts.contains(selectedFont) &&
                      selectedFont != 'System';

                  return ListTile(
                    leading: isCustomSelected ? const Icon(Symbols.check_rounded) : const SizedBox(width: 24),
                    title: Text(context.loc.settings.theme.customFont),
                    subtitle: Text(context.loc.settings.theme.customFontSubtitle),
                    trailing: const Icon(Symbols.edit_rounded),
                    selectedTileColor: Theme.of(context).colorScheme.secondary,
                    selectedColor: Theme.of(context).colorScheme.onSecondary,
                    selected: isCustomSelected,
                    onTap: () => _showCustomFontDialog(context),
                  );
                }

                final font = fontsToShow[index];
                final isSelected = font == selectedFont;
                final fontStyle = _getExtendedFontStyle(font);

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: isSelected ? const Icon(Symbols.check_rounded) : const SizedBox(width: 24),
                    title: Text(
                      font == 'System' ? context.loc.settings.theme.systemDefault : font,
                      style: fontStyle?.copyWith(fontSize: 16),
                    ),
                    selectedTileColor: Theme.of(context).colorScheme.secondary,
                    selectedColor: Theme.of(context).colorScheme.onSecondary,
                    selected: isSelected,
                    onTap: () => setState(() => selectedFont = font),
                  ),
                );
              },
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final fontStyle = _getExtendedFontStyle(selectedFont);

            String text = context.loc.settings.theme.fontPreviewText;
            final settings = SettingsHandler.instance;
            if (settings.locale.value == null
                ? PlatformDispatcher.instance.locale.languageCode != 'en'
                : settings.locale.value != AppLocale.en) {
              text =
                  '${LocaleSettings.instance.translationMap[AppLocale.en]?.settings.theme.fontPreviewText}\n\n${context.loc.settings.theme.fontPreviewText}';
            }

            return Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    spacing: 12,
                    children: [
                      const Icon(Symbols.check_rounded),
                      Expanded(
                        child: Text(
                          selectedFont == 'System' ? context.loc.settings.theme.systemDefault : selectedFont,
                          style: fontStyle?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    text,
                    style: fontStyle?.copyWith(
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => widget.onFontSelected(selectedFont),
                    child: Text(context.loc.tabs.filters.apply),
                  ),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomFontDialog extends StatefulWidget {
  const _CustomFontDialog({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  State<_CustomFontDialog> createState() => _CustomFontDialogState();
}

class _CustomFontDialogState extends State<_CustomFontDialog> {
  String _previewText = '';
  TextStyle? _previewStyle;
  bool _fontError = false;

  @override
  void initState() {
    super.initState();
    _previewText = widget.controller.text;
    _updatePreview(_previewText);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text.trim();
    if (text != _previewText) {
      _previewText = text;
      _updatePreview(text);
    }
  }

  void _updatePreview(String fontName) {
    if (fontName.isEmpty) {
      setState(() {
        _previewStyle = null;
        _fontError = false;
      });
      return;
    }

    try {
      final style = GoogleFonts.getFont(fontName);
      setState(() {
        _previewStyle = style;
        _fontError = false;
      });
    } catch (_) {
      setState(() {
        _previewStyle = null;
        _fontError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.settings.theme.customFont),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: context.loc.settings.theme.fontName,
              hintText: 'Noto Sans',
              errorText: _fontError ? context.loc.settings.theme.fontNotFound : null,
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty && !_fontError) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          const SizedBox(height: 12),
          if (_previewStyle != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(
                builder: (context) {
                  String text = context.loc.settings.theme.fontPreviewText;
                  final settings = SettingsHandler.instance;
                  if (settings.locale.value == null
                      ? PlatformDispatcher.instance.locale.languageCode != 'en'
                      : settings.locale.value != AppLocale.en) {
                    text =
                        '${LocaleSettings.instance.translationMap[AppLocale.en]?.settings.theme.fontPreviewText}\n\n${context.loc.settings.theme.fontPreviewText}';
                  }

                  return Text(
                    text,
                    style: _previewStyle?.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: () {
              launchUrlString(
                'https://fonts.google.com/',
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              context.loc.settings.theme.customFontHint,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
      actions: [
        const CancelButton(withIcon: true),
        OkButton(
          withIcon: true,
          action: _fontError || widget.controller.text.trim().isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(widget.controller.text.trim());
                },
        ),
      ],
    );
  }
}
