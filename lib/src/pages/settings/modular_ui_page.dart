import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Settings → Modular UI (r41): one switch per part of the interface that
/// can be shown or hidden, grouped by where the part is.
class ModularUiPage extends StatelessWidget {
  const ModularUiPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> areas = [
      for (final ModularUiToggle t in ModularUi.all) t.area,
    ].toSet().toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Modular UI')),
      body: ValueListenableBuilder<int>(
        valueListenable: ModularUi.revision,
        builder: (context, _, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Each switch shows or hides one part of the interface, and it keeps working when it comes back. '
                'A part that is switched off is not built at all, so it does not slow the app down.',
                style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            for (final String area in areas) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                child: Text(
                  area,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.secondary),
                ),
              ),
              for (final ModularUiToggle t in ModularUi.all.where((t) => t.area == area))
                KeyedSubtree(
                  key: ValueKey('modular-ui-${t.key}'),
                  child: SettingsToggle(
                    value: ModularUi.isOn(t),
                    onChanged: (bool on) => ModularUi.set(t, on),
                    title: t.title,
                    subtitle: Text(t.description),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
