import 'package:lolisnatcher/gen/strings.g.dart';

extension AppLocaleExt on AppLocale {
  String get localeCode {
    return LocaleSettings.instance.translationMap[this]?.locale ?? '?';
  }

  String get localeName {
    return LocaleSettings.instance.translationMap[this]?.localeName ?? 'Loading...';
  }

  static List<AppLocale> get allowedValues => AppLocale.values
      .where(
        (l) => [
          // Other languages are disabled until they reach at least 80% of completion
          AppLocale.en,
          AppLocale.ruRu,
          AppLocale.trTr,
          AppLocale.jaJp,
        ].any((bl) => bl == l),
      )
      .toList();
}
