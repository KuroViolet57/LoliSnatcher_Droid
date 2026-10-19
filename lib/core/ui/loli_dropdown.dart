import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/buttons/clear_button.dart';
import 'package:lolisnatcher/core/ui/buttons/ok_button.dart';
import 'package:lolisnatcher/core/ui/buttons/return_button.dart';

part 'loli_dropdown/single_sheet.dart';
part 'loli_dropdown/multiselect.dart';

class LoliDropdown<T> extends StatelessWidget {
  const LoliDropdown({
    required this.value,
    required this.onChanged,
    required this.items,
    required this.itemBuilder,
    required this.selectedItemBuilder,
    required this.labelText,
    this.labelColor,
    this.labelStyle,
    this.labelBuilder,
    this.itemExtent,
    this.withBorder = true,
    this.clearable = false,
    this.searchable = false,
    this.searchCheck,
    this.expandableByScroll = false,
    super.key,
  });

  final T? value;
  final void Function(T?) onChanged;
  final List<T> items;
  final Widget Function(T?) itemBuilder;

  final Widget Function(T?) selectedItemBuilder;
  final String labelText;
  final Color? labelColor;
  final TextStyle? labelStyle;
  final Widget Function()? labelBuilder;
  final double? itemExtent;
  final bool withBorder;
  final bool clearable;
  final bool searchable;
  final bool Function(String, T)? searchCheck;
  final bool expandableByScroll;

  Future<bool> showDialog(BuildContext context) async {
    final dynamic res = await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      builder: (BuildContext context) {
        if (expandableByScroll) {
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: ColoredBox(
              color: Colors.transparent,
              child: DraggableScrollableSheet(
                minChildSize: 0.3,
                initialChildSize: 0.7,
                maxChildSize: 1,
                shouldCloseOnMinExtent: true,
                builder: (context, controller) {
                  return LoliDropdownBottomSheet<T>(
                    controller: controller,
                    value: value,
                    onChanged: onChanged,
                    items: items,
                    itemBuilder: itemBuilder,
                    labelText: labelText,
                    itemExtent: itemExtent,
                    clearable: clearable,
                    searchable: searchable,
                    searchCheck: searchCheck,
                  );
                },
              ),
            ),
          );
        } else {
          return LoliDropdownBottomSheet<T>(
            value: value,
            onChanged: onChanged,
            items: items,
            itemBuilder: itemBuilder,
            labelText: labelText,
            itemExtent: itemExtent,
            clearable: clearable,
            searchable: searchable,
            searchCheck: searchCheck,
          );
        }
      },
    );

    if (res is bool) {
      return res;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final theme = Theme.of(context);
    final inputDecoration = theme.inputDecorationTheme;

    final bool isDesktop = settingsHandler.appMode.value.isDesktop;
    final EdgeInsetsGeometry contentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: isDesktop ? 2 : 12);

    const double radius = 10;

    return Stack(
      children: [
        InputDecorator(
          decoration: InputDecoration(
            label:
                labelBuilder?.call() ??
                RichText(
                  text: TextSpan(
                    style:
                        labelStyle ??
                        inputDecoration.labelStyle?.copyWith(
                          color: labelColor ?? inputDecoration.labelStyle?.color,
                        ),
                    children: [
                      TextSpan(
                        text: labelText,
                      ),
                    ],
                  ),
                ),
            labelStyle:
                labelStyle ??
                inputDecoration.labelStyle?.copyWith(
                  color: labelColor ?? inputDecoration.labelStyle?.color,
                ),
            contentPadding: contentPadding,
            border: inputDecoration.border?.copyWith(
              borderSide: BorderSide(
                color: withBorder
                    ? (inputDecoration.border?.borderSide.color ?? Colors.transparent)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            enabledBorder: inputDecoration.enabledBorder?.copyWith(
              borderSide: BorderSide(
                color: withBorder
                    ? (inputDecoration.enabledBorder?.borderSide.color ?? Colors.transparent)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            focusedBorder: inputDecoration.focusedBorder?.copyWith(
              borderSide: BorderSide(
                color: withBorder
                    ? (inputDecoration.focusedBorder?.borderSide.color ?? Colors.transparent)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(child: selectedItemBuilder.call(value)),
              const SizedBox(width: 8),
              Icon(
                Symbols.arrow_drop_down_rounded,
                color: theme.iconTheme.color,
              ),
            ],
          ),
        ),
        //
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: withBorder ? const BorderRadius.all(Radius.circular(radius)) : null,
              onTap: () async {
                await showDialog(context);
              },
            ),
          ),
        ),
      ],
    );
  }
}
