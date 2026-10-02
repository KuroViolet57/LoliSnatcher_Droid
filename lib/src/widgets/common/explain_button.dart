import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// One choice in an [ExplainButton]'s window: what it is, what it is good
/// and bad at, and what this phone measured for it.
class ExplainChoice {
  const ExplainChoice({required this.name, required this.text, this.timing});

  final String name;
  final String text;

  /// "On this phone: …" or "Not tried yet on this phone."
  final String? timing;
}

/// r86: the info button the user asked for next to every new option
/// (2026-10-02): it opens a window that explains the choices, their
/// advantages and their timings. The content is built when the window
/// opens, so the timings are the latest; [note] adds a line read then (what
/// this build supports, for one).
class ExplainButton extends StatelessWidget {
  const ExplainButton({
    required this.title,
    required this.choices,
    this.intro,
    this.footer,
    this.note,
    super.key,
  });

  final String title;
  final List<ExplainChoice> Function() choices;
  final String? intro;
  final String? footer;
  final Future<String?> Function()? note;

  Future<void> show(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle muted = TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => SettingsDialog(
        title: Text(title),
        contentItems: [
          if (intro != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(intro!)),
          for (final ExplainChoice c in choices()) ...[
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(c.text),
            if (c.timing != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.timing!, style: muted)),
            const SizedBox(height: 14),
          ],
          if (footer != null) Text(footer!, style: muted),
          if (note != null)
            FutureBuilder<String?>(
              future: note!(),
              builder: (_, AsyncSnapshot<String?> s) => s.data == null
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.data!, style: muted)),
            ),
        ],
        actionButtons: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'What these choices mean',
    icon: const Icon(Symbols.info_rounded),
    onPressed: () => show(context),
  );
}
