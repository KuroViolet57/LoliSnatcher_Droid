part of '../settings_widgets.dart';

class SettingsTextInput extends StatefulWidget {
  const SettingsTextInput({
    required this.controller,
    required this.title,
    this.focusNode,
    this.inputType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.hintText,
    this.subtitle,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onSubmittedLongTap,
    this.drawTopBorder = false,
    this.drawBottomBorder = true,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
    this.clearable = false,
    this.resetText,
    this.numberButtons = false,
    this.alwaysShowNumberButtons = false,
    this.numberStep = 1,
    this.numberMin = 0,
    this.numberMax = 100,
    this.trailingIcon,
    this.onlyInput = false,
    this.floatingLabelBehavior = FloatingLabelBehavior.auto,
    this.copyable = false,
    this.pasteable = false,
    this.obscureable = false,
    this.isObscuredByDefault = true,
    this.textInputAction,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.enableIMEPersonalizedLearning = true,
    this.submitIcon,
    this.showSubmitButton,
    this.titleAsLabel = false,
    this.prefixIcon,
    this.contextMenuBuilder,
    super.key,
  });

  final TextEditingController controller;
  final String title;
  final FocusNode? focusNode;
  final TextInputType inputType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final String? hintText;
  final Widget? subtitle;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onSubmittedLongTap;
  final bool drawTopBorder;
  final bool drawBottomBorder;
  final EdgeInsets margin;
  final bool clearable;
  final String Function()? resetText;
  final bool numberButtons;
  final bool alwaysShowNumberButtons;
  final double numberStep;
  final double numberMin;
  final double numberMax;
  final Widget? trailingIcon;
  final bool onlyInput;
  final FloatingLabelBehavior floatingLabelBehavior;
  final bool copyable;
  final bool pasteable;
  final bool obscureable;
  final bool isObscuredByDefault;
  final TextInputAction? textInputAction;
  final bool enableSuggestions;
  final bool autocorrect;
  final bool enableIMEPersonalizedLearning;
  final IconData? submitIcon;
  final bool Function(String)? showSubmitButton;
  final bool titleAsLabel;
  final Widget? prefixIcon;
  final Widget Function(BuildContext, EditableTextState)? contextMenuBuilder;

  @override
  State<SettingsTextInput> createState() => _SettingsTextInputState();
}

class _SettingsTextInputState extends State<SettingsTextInput> {
  bool isFocused = false, isObscured = false;
  late final FocusNode _focusNode;

  /// 1.0: the clipboard read that decides whether Paste shows, made once per
  /// focus. Read on every build, every keystroke read the clipboard again
  /// (Android 12+ shows its "pasted from your clipboard" toast each time).
  Future<ClipboardData?>? _clipboardRead;

  @override
  void initState() {
    super.initState();

    if (widget.obscureable) {
      isObscured = widget.isObscuredByDefault;
    }
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(focusListener);
  }

  void focusListener() {
    isFocused = _focusNode.hasFocus;
    _clipboardRead = null;
    setState(() {});
  }

  void toggleObscure() {
    isObscured = !isObscured;
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(focusListener);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void onChangedCallback(String value) {
    widget.onChanged?.call(value);
    setState(() {});
  }

  void stepNumberDown() {
    if (widget.numberButtons) {
      final double valueWithStep = (double.tryParse(widget.controller.text) ?? 0) - widget.numberStep;
      final double newValue = valueWithStep >= widget.numberMin ? valueWithStep : widget.numberMin;
      widget.controller.text = newValue.toStringAsFixed(newValue.truncateToDouble() == newValue ? 0 : 1);
      onChangedCallback(widget.controller.text);
    }
  }

  void stepNumberUp() {
    if (widget.numberButtons) {
      final double valueWithStep = (double.tryParse(widget.controller.text) ?? 0) + widget.numberStep;
      final double newValue = valueWithStep <= widget.numberMax ? valueWithStep : widget.numberMax;
      widget.controller.text = newValue.toStringAsFixed(newValue.truncateToDouble() == newValue ? 0 : 1);
      onChangedCallback(widget.controller.text);
    }
  }

  Widget buildNumberButton(VoidCallback stepFunc, IconData icon) {
    return LongPressRepeater(
      onStart: () async {
        stepFunc();
      },
      tick: 100,
      fastTick: 50,
      fasterAfter: 20,
      child: IconButton(
        icon: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
        onPressed: () {
          stepFunc();
        },
      ),
    );
  }

  Widget buildSuffixIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        if (widget.resetText != null && widget.controller.text != widget.resetText!())
          IconButton(
            key: const Key('reset-button'),
            icon: Icon(
              Symbols.refresh_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              widget.controller.text = widget.resetText!();
              onChangedCallback(widget.controller.text);
            },
          ),
        if (widget.numberButtons && (isFocused || widget.alwaysShowNumberButtons))
          Container(
            key: const Key('number-button-down'),
            child: buildNumberButton(stepNumberDown, Symbols.remove_rounded),
          ),
        if (widget.numberButtons && (isFocused || widget.alwaysShowNumberButtons))
          Container(
            key: const Key('number-button-up'),
            child: buildNumberButton(stepNumberUp, Symbols.add_rounded),
          ),
        if (widget.clearable && isFocused && widget.controller.text.isNotEmpty)
          IconButton(
            key: const Key('clear-button'),
            icon: Icon(
              Symbols.close_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              widget.controller.clear();
              onChangedCallback(widget.controller.text);
            },
          ),
        if (widget.copyable && isFocused)
          IconButton(
            key: const Key('copy-button'),
            icon: Icon(Symbols.content_copy_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.controller.text));
            },
          ),
        if (widget.pasteable && isFocused)
          FutureBuilder(
            future: _clipboardRead ??= Clipboard.getData(Clipboard.kTextPlain),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              return IconButton(
                key: const Key('paste-button'),
                icon: Icon(Symbols.content_paste_rounded, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () async {
                  // What is on the clipboard now, not at focus time.
                  final data = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                  if (!mounted) return;
                  if (data?.isNotEmpty == true) {
                    widget.controller.text = data!;
                    onChangedCallback(widget.controller.text);
                  }
                },
              );
            },
          ),
        //
        if (widget.obscureable)
          IconButton(
            key: const Key('obscure-button'),
            icon: Icon(
              isObscured ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: toggleObscure,
          )
        else if (isFocused && (widget.showSubmitButton?.call(widget.controller.text) ?? true))
          IconButton(
            key: const Key('submit-button'),
            icon: Icon(
              widget.submitIcon ?? (widget.onSubmitted != null ? Symbols.send_rounded : Symbols.done_rounded),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              if (widget.onSubmitted != null) {
                widget.onSubmitted?.call(widget.controller.text);
              } else {
                _focusNode.unfocus();
              }
            },
            onLongPress: widget.onSubmittedLongTap != null
                ? () => widget.onSubmittedLongTap?.call(widget.controller.text)
                : null,
          )
        else if (!isFocused)
          IconButton(
            key: const Key('edit-button'),
            icon: Icon(Symbols.edit_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: _focusNode.requestFocus,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget field = Container(
      margin: widget.margin,
      child: TextFormField(
        focusNode: _focusNode,
        controller: widget.controller,
        autofocus: widget.autofocus,
        keyboardType: widget.inputType,
        enableInteractiveSelection: true,
        inputFormatters: widget.inputFormatters,
        obscureText: isObscured,
        obscuringCharacter: '*',
        onChanged: onChangedCallback,
        onFieldSubmitted: widget.onSubmitted,
        textInputAction: widget.textInputAction,
        enableSuggestions: widget.enableSuggestions,
        autocorrect: widget.autocorrect,
        enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
        scrollPadding: const EdgeInsets.all(kToolbarHeight),
        contextMenuBuilder: widget.contextMenuBuilder,
        decoration: InputDecoration(
          labelText: widget.titleAsLabel ? widget.title : null,
          hintText: widget.hintText,
          errorMaxLines: 3,
          errorText: widget.validator?.call(widget.controller.text),
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          prefixIcon: widget.prefixIcon,
          suffixIcon: Padding(
            padding: const EdgeInsets.only(left: 2, right: 4),
            child: buildSuffixIcons(),
          ),
          floatingLabelBehavior: widget.floatingLabelBehavior,
        ),
      ),
    );

    // return only textfield, without tile wrapper (in this case: no dividers, title, subtitle, icon)
    if (widget.onlyInput) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.titleAsLabel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                widget.title,
                style: Theme.of(context).inputDecorationTheme.labelStyle?.copyWith(
                  fontSize: 16,
                ),
              ),
            ),
          //
          field,
          //
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.subtitle,
            ),
        ],
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
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.titleAsLabel) Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              field,
            ],
          ),
          subtitle: widget.subtitle,
          trailing: widget.trailingIcon,
          dense: false,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    );
  }
}
