import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

class ZoomButton extends StatelessWidget {
  const ZoomButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ViewerHandler viewerHandler = ViewerHandler.instance;

    return ValueListenableBuilder(
      valueListenable: viewerHandler.isZoomed,
      builder: (context, isZoomed, child) => IconButton(
        icon: Icon(isZoomed ? Symbols.zoom_out_rounded : Symbols.zoom_in_rounded),
        onPressed: viewerHandler.toggleZoom,
        color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.5),
        // visualDensity: VisualDensity.comfortable,
      ),
    );
  }
}
