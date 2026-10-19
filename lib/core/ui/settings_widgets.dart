import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/html.dart';
import 'package:lolisnatcher/core/ui/loli_dropdown.dart';
import 'package:lolisnatcher/core/ui/long_press_repeater.dart';
import 'package:lolisnatcher/core/ui/text/marquee_text.dart';
import 'package:lolisnatcher/core/ui/booru_selector_item.dart';

part 'settings_widgets/settings_buttons.dart';
part 'settings_widgets/settings_toggles.dart';
part 'settings_widgets/settings_dropdowns.dart';
part 'settings_widgets/settings_text_input.dart';
part 'settings_widgets/settings_dialogs.dart';

const double borderWidth = 1;
