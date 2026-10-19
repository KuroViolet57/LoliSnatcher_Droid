part of '../booru_edit_page.dart';

class _HydrusAccessKeyWidget extends StatelessWidget {
  const _HydrusAccessKeyWidget({
    required this.urlController,
    required this.apiKeyController,
  });

  final TextEditingController urlController;
  final TextEditingController apiKeyController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final HydrusHandler hydrus = HydrusHandler(
                Booru(
                  'Hydrus',
                  BooruType.Hydrus,
                  'Hydrus',
                  urlController.text,
                  '',
                ),
                5,
              );
              final String accessKey = await hydrus.getAccessKey();
              if (accessKey != '') {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Symbols.warning_amber_rounded,
                  leadingIconColor: Colors.yellow,
                  sideColor: Colors.yellow,
                );
                apiKeyController.text = accessKey;
              } else {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyFailedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyFailedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Symbols.warning_amber_rounded,
                  leadingIconColor: Colors.red,
                  sideColor: Colors.red,
                );
              }
            },
            child: Text(context.loc.settings.booruEditor.getHydrusApiKey),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          width: double.infinity,
          child: Text(
            context.loc.settings.booruEditor.hydrusInstructions,
          ),
        ),
      ],
    );
  }
}
