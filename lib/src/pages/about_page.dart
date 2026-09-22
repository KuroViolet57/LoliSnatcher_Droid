import 'dart:core';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:lolisnatcher/src/pages/settings/language_page.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/discord_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SettingsAppBar(title: context.loc.appName),
      body: Center(
        child: ListView(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Text(context.loc.settings.about.appDescription),
            ),
            SettingsButton(
              name: context.loc.settings.about.appOnGitHub,
              icon: const Icon(Symbols.public_rounded),
              trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              action: () {
                launchUrlString(
                  Constants.githubURL,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            DiscordButton(overrideText: context.loc.visitOurDiscord),
            SettingsButton(
              name: '${context.loc.settings.about.contact}: ${Constants.email}',
              icon: const Icon(Symbols.email_rounded),
              trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              action: () {
                launchUrlString(
                  'mailto:${Constants.email}',
                  mode: LaunchMode.externalApplication,
                );
              },
              onLongPress: () {
                Clipboard.setData(const ClipboardData(text: Constants.email));
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.copied,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(context.loc.settings.about.emailCopied),
                  sideColor: Colors.green,
                  leadingIcon: Symbols.check_rounded,
                  leadingIconColor: Colors.green,
                  duration: const Duration(seconds: 2),
                );
              },
            ),
            //
            if (!EnvironmentConfig.isFromStore) ...[
              const SizedBox(height: kMinInteractiveDimension),
              Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Text(context.loc.settings.about.logoArtistThanks),
              ),
              SettingsButton(
                name: 'Showers-U - Pixiv',
                icon: const Icon(Symbols.public_rounded),
                trailingIcon: const Icon(Symbols.exit_to_app_rounded),
                action: () {
                  launchUrlString(
                    'https://www.pixiv.net/en/users/28366691',
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
            //
            const SizedBox(height: kMinInteractiveDimension),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Text('${context.loc.settings.about.developers}:'),
            ),
            SettingsButton(
              name: 'NO-ob - Github',
              icon: const Icon(Symbols.public_rounded),
              trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              action: () {
                launchUrlString(
                  'https://github.com/NO-ob',
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            SettingsButton(
              name: 'NANI-SORE - Github',
              icon: const Icon(Symbols.public_rounded),
              trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              action: () {
                launchUrlString(
                  'https://github.com/NANI-SORE',
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            //
            const SizedBox(height: kMinInteractiveDimension),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Text('${context.loc.settings.about.localizers}:'),
            ),
            SettingsButton(
              name: 'Turkish',
              subtitle: const Text('kyomoe'),
              icon: buildFlag(context, AppLocale.trTr),
            ),
            SettingsButton(
              name: 'Japanese',
              subtitle: const Text('stardust248397'),
              icon: buildFlag(context, AppLocale.jaJp),
            ),
            //
            const SizedBox(height: kMinInteractiveDimension),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Text(context.loc.settings.about.releasesMsg),
            ),
            SettingsButton(
              name: context.loc.settings.about.releases,
              icon: const Icon(Symbols.public_rounded),
              trailingIcon: const Icon(Symbols.exit_to_app_rounded),
              action: () {
                launchUrlString(
                  'https://github.com/NO-ob/LoliSnatcher_Droid/releases',
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            SettingsButton(
              name: context.loc.settings.about.licenses,
              icon: const Icon(Symbols.document_scanner_rounded),
              action: () {
                showLicensePage(
                  context: context,
                  applicationName: context.loc.appName,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
