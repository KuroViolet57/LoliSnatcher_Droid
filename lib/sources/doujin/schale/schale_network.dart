/// The Schale software runs on more than one network. niyaniya.moe and its
/// mirrors (shupogaki.moe) share `api.schale.network` and
/// `auth.schale.network`; hdoujin.org (probed 2026-09-09) runs the same
/// front and API on its own hosts, with its own Turnstile clearance from
/// `auth.hdoujin.org`. A clearance token is only good on the network that
/// issued it, so [key] is what the clearance store files tokens under.
class SchaleNetwork {
  const SchaleNetwork({
    required this.key,
    required this.name,
    required this.api,
    required this.auth,
    required this.defaultSite,
  });

  /// Storage key for clearance tokens and the like.
  final String key;

  /// The name used in messages.
  final String name;

  /// API origin, no trailing slash.
  final String api;

  /// Clearance origin, no trailing slash.
  final String auth;

  /// The site a fresh config of this network points at.
  final String defaultSite;

  static const SchaleNetwork schale = SchaleNetwork(
    key: 'schale',
    name: 'niyaniya',
    api: 'https://api.schale.network',
    auth: 'https://auth.schale.network',
    defaultSite: 'https://niyaniya.moe',
  );

  static const SchaleNetwork hdoujin = SchaleNetwork(
    key: 'hdoujin',
    name: 'hdoujin',
    api: 'https://api.hdoujin.org',
    auth: 'https://auth.hdoujin.org',
    defaultSite: 'https://hdoujin.org',
  );

  static const List<SchaleNetwork> all = [schale, hdoujin];

  /// The network a configured site (or any URL on it) belongs to. Anything
  /// that is not hdoujin is the Schale network, mirrors included.
  static SchaleNetwork forSite(String site) {
    final String host = (Uri.tryParse(site.trim())?.host ?? '').toLowerCase();
    if (host == 'hdoujin.org' || host.endsWith('.hdoujin.org')) return hdoujin;
    return schale;
  }

  static SchaleNetwork? byKey(String key) {
    for (final n in all) {
      if (n.key == key) return n;
    }
    return null;
  }
}
