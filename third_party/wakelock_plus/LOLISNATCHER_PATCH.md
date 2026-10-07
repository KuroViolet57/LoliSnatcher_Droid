# LoliSnatcher patch (wakelock_plus 1.7.0)

A copy of wakelock_plus 1.7.0 (pub.dev), used through `dependency_overrides`
in the app's pubspec.yaml. better_player_plus 1.4.1 and media_kit both need
this major line. 1.8.0 needs Flutter >=3.44, and this tree is Flutter
3.42.0-0.4.pre.

The published 1.7.0 Android sources fail `:wakelock_plus:compileReleaseKotlin`
on Kotlin 2.2.20. `WakelockPlusMessages.g.kt` has no `package` line, so
`IsEnabledMessage`, `ToggleMessage`, and `WakelockPlusApi` land in the
default package. `Wakelock.kt` and `WakelockPlusPlugin.kt` import those
names. Kotlin 2.2.20 rejects an import from the default package into
`dev.fluttercommunity.plus.wakelock`. Upstream issue 141 describes the same
failure: https://github.com/fluttercommunity/wakelock_plus/issues/141

Changes:

- `WakelockPlusMessages.g.kt`: `package dev.fluttercommunity.plus.wakelock`
  after the file annotation.
- `Wakelock.kt` and `WakelockPlusPlugin.kt`: the default-package imports
  are removed. The classes are in the same package.
- `pigeons/messages.dart`: `kotlinOptions.package` is set to that package
  so a later pigeon run does not drop the line. The generated file was
  edited by hand. Pigeon was not re-run.

The Dart API is unchanged. The example app and the package tests were left
out of the copy.

To undo: remove the `wakelock_plus:` path override in pubspec.yaml and
delete this folder. The app then resolves hosted 1.7.0 again, which does
not compile on this Kotlin version until Flutter can take 1.8.x.
