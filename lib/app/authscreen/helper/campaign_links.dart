import '../../../core/router/app_router.dart';

/// A query param a campaign screen accepts. [as] renames it to the param
/// the screen reads; [aliases] are accepted on the way in.
class CampaignParam {
  const CampaignParam(
    this.name, {
    this.as,
    this.required = false,
    this.aliases = const [],
  });

  final String name;
  final String? as;
  final bool required;
  final List<String> aliases;
}

/// One admin-panel preset (RN `PUSH_DEEPLINK_ROUTES`). [path] values are
/// referenced by live campaigns: never rename them.
class CampaignRoute {
  const CampaignRoute(
    this.path,
    this.route, {
    this.aliases = const [],
    this.params = const [],
    this.fixed = const {},
    this.hostOnly = false,
    this.public = false,
  });

  final String path;
  final String route;
  final List<String> aliases;
  final List<CampaignParam> params;

  /// Always sent (e.g. which Home tab to show).
  final Map<String, String> fixed;

  /// Only for users with an expert (host) profile.
  final bool hostOnly;

  /// Reachable signed out (login only).
  final bool public;

  bool get isWebview => route == AppRoutes.webview;
}

/// A resolved campaign link: route + params, or what was wrong with it.
class CampaignTarget {
  const CampaignTarget(this.route, this.params, this.missing);

  final CampaignRoute? route;
  final Map<String, String> params;
  final List<String> missing;
}

/// `vibecalling://` campaign / admin-panel links (RN `pushDeeplinks.js`).
/// Adding a screen = one row here + telling the backend the new preset.
abstract final class CampaignLinks {
  static const home = CampaignRoute(
    'home',
    AppRoutes.home,
    aliases: ['', 'discover'],
    fixed: {'tab': 'DISCOVER'},
  );
  static const search = CampaignRoute(
    'search',
    AppRoutes.search,
    params: [CampaignParam('q')],
  );

  static const routes = <CampaignRoute>[
    home,
    CampaignRoute('wallet', AppRoutes.wallet),
    search,
    CampaignRoute('history', AppRoutes.explore),
    CampaignRoute(
      'profile',
      AppRoutes.home,
      aliases: ['me'],
      fixed: {'tab': 'ME'},
    ),
    CampaignRoute('favourites', AppRoutes.favourites, aliases: ['favorites']),
    CampaignRoute('login', AppRoutes.login, public: true),
    CampaignRoute(
      'expert-profile.php',
      AppRoutes.home,
      aliases: ['expert-profile', 'expert'],
      fixed: {'tab': 'DISCOVER'},
      params: [
        CampaignParam(
          'userid',
          as: 'openUserId',
          required: true,
          aliases: ['documentId', 'handler'],
        ),
      ],
    ),
    // Also "Become a Host" for regular users.
    CampaignRoute('professional-account', AppRoutes.professionalDetails),
    CampaignRoute('approval', AppRoutes.approval, hostOnly: true),
    CampaignRoute('referral', AppRoutes.referral, aliases: ['invite']),
    CampaignRoute('personal-info', AppRoutes.personalInfo),
    CampaignRoute('expertise', AppRoutes.expertise, hostOnly: true),
    CampaignRoute('schedule', AppRoutes.schedule, hostOnly: true),
    CampaignRoute('call-rates', AppRoutes.callRates, hostOnly: true),
    CampaignRoute(
      'verification-badge',
      AppRoutes.verificationBadgeFee,
      hostOnly: true,
    ),
    CampaignRoute('profile-qr', AppRoutes.profileQr, hostOnly: true),
    CampaignRoute('gst-details', AppRoutes.gstDetails),
    CampaignRoute('blocked-users', AppRoutes.blockedUsers),
    CampaignRoute('about', AppRoutes.aboutApp),
    CampaignRoute('support', AppRoutes.support),
    CampaignRoute(
      'page',
      AppRoutes.dynamicPage,
      params: [CampaignParam('slug', required: true), CampaignParam('title')],
    ),
    // In-app browser; the url is validated before opening (see [webUrl]).
    CampaignRoute(
      'webview',
      AppRoutes.webview,
      params: [CampaignParam('url'), CampaignParam('title')],
    ),
  ];

  static final _byPath = {
    for (final r in routes)
      for (final p in [r.path, ...r.aliases]) p: r,
  };

  /// `vibecalling://wallet?x=1`, `https://x.com/wallet` or `/wallet` → target.
  /// The scheme is never trusted: only the path picks the screen.
  static CampaignTarget resolve(String url) {
    final rest = url
        .trim()
        .replaceFirst(RegExp(r'^https?://[^/?#]+', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^/+'), '')
        .split('#')
        .first;
    final q = rest.indexOf('?');
    final path = (q == -1 ? rest : rest.substring(0, q))
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
    final query = q == -1
        ? const <String, String>{}
        : Uri.splitQueryString(rest.substring(q + 1));

    final route = _byPath[path];
    if (route == null) return const CampaignTarget(null, {}, []);
    // home?q=… is a search: Home has no search box of its own.
    if (route == home && (query['q'] ?? '').isNotEmpty) {
      return CampaignTarget(search, {'q': query['q']!}, const []);
    }
    final params = {...route.fixed};
    final missing = <String>[];
    for (final spec in route.params) {
      final value = [spec.name, ...spec.aliases]
          .map((n) => query[n]?.trim())
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (value != null) {
        params[spec.as ?? spec.name] = value;
      } else if (spec.required) {
        missing.add(spec.name);
      }
    }
    return CampaignTarget(route, params, missing);
  }

  // ── In-app browser rules (RN `webUrl.js`) ──────────────────────────────

  /// Hosts a link from OUTSIDE the app may show inside our frame. Anything
  /// else opens in the system browser, where the real address is visible.
  static const _trustedHosts = ['angrymamba.com', 'vibelive.angrymamba.com'];

  /// `https://x.com`, `https%3A%2F%2Fx.com` or `x.com/page` → loadable
  /// http(s) URL, or null.
  static String? webUrl(String? raw) {
    var value = (raw ?? '').trim();
    for (
      var i = 0;
      i < 3 && RegExp(r'^https?%(25)*3A', caseSensitive: false).hasMatch(value);
      i++
    ) {
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {
        return null;
      }
    }
    if (value.isEmpty ||
        RegExp(r'^https?%', caseSensitive: false).hasMatch(value)) {
      return null;
    }
    final scheme = RegExp(
      r'^([a-z][a-z0-9+.-]*):',
      caseSensitive: false,
    ).firstMatch(value)?[1]?.toLowerCase();
    if (scheme != null && scheme != 'http' && scheme != 'https') return null;
    if (scheme == null) {
      value = 'https://${value.replaceFirst(RegExp(r'^/+'), '')}';
    }
    final host = hostOf(value);
    return host == null || !host.contains('.') ? null : value;
  }

  static String? hostOf(String url) => RegExp(
    r'^https?://([^/?#:]+)',
    caseSensitive: false,
  ).firstMatch(url)?[1]?.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  static bool isTrustedHost(String url) {
    final host = hostOf(url);
    return host != null &&
        _trustedHosts.any((s) => host == s || host.endsWith('.$s'));
  }
}
