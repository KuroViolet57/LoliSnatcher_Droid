part of '../main_search_query_editor_page.dart';

class _PrefixEditDialog extends StatelessWidget {
  const _PrefixEditDialog(this.controller);

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;

    return BottomSheet(
      onClosing: () {},
      builder: (context) => ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, child) {
          String text = value.text;
          bool isExclude = text.startsWith('-');
          bool isOr = text.startsWith('~');
          text = text.replaceAll(RegExp('^-'), '').replaceAll(RegExp('^~'), '').trim();

          final bool isNumberMod = text.startsWith(RegExp(r'\d+#'));
          final int? booruNumber = int.tryParse(isNumberMod ? text.split('#')[0] : '');
          final bool hasBooruNumber = booruNumber != null;
          final List<Booru> usedBoorus = [
            searchHandler.currentTab.selectedBooru.value,
            ...(searchHandler.currentTab.secondaryBoorus.value ?? <Booru>[]),
          ];
          final bool hasSecondaryBoorus = usedBoorus.length > 1;
          final bool isValidNumberMod =
              hasBooruNumber && booruNumber > 0 && hasSecondaryBoorus && booruNumber <= usedBoorus.length;
          final selectedBooru = isValidNumberMod ? usedBoorus[booruNumber - 1] : null;
          text = text.replaceAll(RegExp(r'^\d+#'), '').trim();

          // do it twitce because it will be false for mergebooru
          // (because proper tag query syntax is to place booru number in front of tag and all modifiers)
          isExclude = isExclude || text.startsWith('-');
          isOr = isOr || text.startsWith('~');
          text = text.replaceAll(RegExp('^-'), '').replaceAll(RegExp('^~'), '').trim();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(
                  context.loc.searchBar.prefix,
                  style: context.theme.textTheme.headlineMedium,
                ),
                ElevatedButton(
                  onPressed: () {
                    controller.text = isExclude ? text : '-$text';
                    if (isValidNumberMod) controller.text = '$booruNumber#${controller.text}';
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.loc.searchBar.exclude,
                        ),
                      ),
                      IgnorePointer(
                        ignoring: true,
                        child: Checkbox(
                          value: isExclude,
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
                //
                ElevatedButton(
                  onPressed: () {
                    controller.text = isOr ? text : '~$text';
                    if (isValidNumberMod) controller.text = '$booruNumber#${controller.text}';
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(context.loc.or),
                      ),
                      IgnorePointer(
                        ignoring: true,
                        child: Checkbox(
                          value: isOr,
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
                //
                if (hasSecondaryBoorus)
                  Container(
                    width: MediaQuery.sizeOf(context).width,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: SettingsBooruDropdown(
                      value: selectedBooru,
                      items: usedBoorus,
                      onChanged: (Booru? newBooru) {
                        if (selectedBooru == newBooru) {
                          newBooru = null;
                        }

                        controller.text =
                            '${newBooru == null ? '' : usedBoorus.indexOf(newBooru) + 1}${newBooru == null ? '' : '#'}${isExclude ? '-' : ''}${isOr ? '~' : ''}$text';
                      },
                      title: context.loc.searchBar.booruNumberPrefix,
                      titleAsLabel: true,
                      contentPadding: EdgeInsets.zero,
                      itemBuilder: (booru, _) {
                        if (booru == null) {
                          return const Text('');
                        }

                        return Row(
                          spacing: 6,
                          children: [
                            Text('${usedBoorus.indexOf(booru) + 1}#'),
                            BooruFavicon(booru),
                            Expanded(
                              child: Text(booru.name ?? ''),
                            ),
                          ],
                        );
                      },
                      selectedItemBuilder: (booru) {
                        if (booru == null) {
                          return const Text('');
                        }

                        return Row(
                          spacing: 6,
                          children: [
                            Text('${usedBoorus.indexOf(booru) + 1}#'),
                            BooruFavicon(booru),
                            Expanded(
                              child: Text(booru.name ?? ''),
                            ),
                          ],
                        );
                      },
                      drawBottomBorder: false,
                    ),
                  ),
                //
                const CancelButton(withIcon: true),
              ],
            ),
          );
        },
      ),
    );
  }
}
