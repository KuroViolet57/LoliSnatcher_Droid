import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/ehentai_session_handler.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/ehentai_login_page.dart';
import 'package:lolisnatcher/src/pages/settings/furaffinity_login_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// r88: Settings → Sources → Accounts - the sign-ins in one place, with
/// whether each is signed in. The e-hentai and FurAffinity sessions belong
/// to the app; a RedGifs sign-in belongs to a RedGifs source (its token is
/// kept with that source), so its row opens that source's editor, where the
/// sign-in is. Each source's own settings still open them too.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool _ehentai() {
    try {
      return EHentaiSessionHandler.instance.isLoggedIn;
    } catch (_) {
      return false;
    }
  }

  ({bool signedIn, String? name}) _furaffinity() {
    try {
      final FurAffinitySessionHandler s = FurAffinitySessionHandler.instance;
      return (signedIn: s.isLoggedIn, name: s.username);
    } catch (_) {
      return (signedIn: false, name: null);
    }
  }

  List<Booru> get _redgifs => [for (final Booru b in SettingsHandler.instance.booruList) if (b.type == BooruType.RedGifs) b];

  Future<void> _openEhentai() async {
    final (bool, String)? result = await Navigator.of(context).push<(bool, String)>(MaterialPageRoute(builder: (_) => const EHentaiLoginPage()));
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      FlashElements.showSnackbar(context: context, title: Text(result.$2), duration: const Duration(seconds: 4), sideColor: result.$1 ? Colors.green : Colors.orange);
    }
  }

  Future<void> _openFuraffinity() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FurAffinityLoginPage()));
    if (mounted) setState(() {});
  }

  Future<void> _openRedgifs() async {
    final List<Booru> sources = _redgifs;
    if (sources.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('No RedGifs source'),
        content: const Text('Add a RedGifs source first (Settings → Boorus & Search); its editor has the sign-in.'),
        sideColor: Colors.orange,
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BooruEdit(sources.first)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool eh = _ehentai();
    final ({bool signedIn, String? name}) fa = _furaffinity();
    final List<Booru> rg = _redgifs;
    final int rgSigned = rg.where((b) => (b.apiKey ?? '').isNotEmpty).length;
    return Scaffold(
      appBar: const SettingsAppBar(title: 'Accounts'),
      body: ListView(
        children: [
          SettingsButton(
            key: const ValueKey('account-ehentai'),
            name: 'e-hentai / ExHentai',
            subtitle: Text(eh ? 'Signed in - galleries and ExHentai use your account' : 'Not signed in - tap to sign in on the forums'),
            icon: Icon(eh ? Symbols.verified_user_rounded : Symbols.login_rounded),
            action: _openEhentai,
          ),
          SettingsButton(
            key: const ValueKey('account-furaffinity'),
            name: 'FurAffinity',
            subtitle: Text(
              fa.signedIn ? 'Signed in${fa.name == null ? '' : ' as ${fa.name}'} - favourites, watches and the inbox sync' : 'Not signed in - tap to sign in',
            ),
            icon: Icon(fa.signedIn ? Symbols.verified_user_rounded : Symbols.login_rounded),
            action: _openFuraffinity,
          ),
          SettingsButton(
            key: const ValueKey('account-redgifs'),
            name: 'RedGifs',
            subtitle: Text(
              rg.isEmpty
                  ? 'No RedGifs source yet'
                  : '$rgSigned of ${rg.length} RedGifs source${rg.length == 1 ? '' : 's'} signed in - tap to open its editor, where the sign-in is',
            ),
            icon: Icon(rgSigned > 0 ? Symbols.verified_user_rounded : Symbols.login_rounded),
            action: _openRedgifs,
          ),
        ],
      ),
    );
  }
}
