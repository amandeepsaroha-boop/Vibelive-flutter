import 'auth_credentials.dart';

/// Why a referral code was shared. The website turns `?r=r` / `?r=i` into a
/// `-R` / `-I` suffix on the Play install referrer, which is how the intent
/// survives a fresh install.
enum ReferralIntent {
  refer('-R'),
  invite('-I'),

  /// Plain `/{handler}` share: opens the profile, carries no attribution.
  hostProfile(''),

  /// `?code=` / `?referral=` without a marker.
  plain('');

  const ReferralIntent(this.suffix);
  final String suffix;
}

/// A referral code (pure, no suffix) and why it was shared.
class ReferralCapture {
  const ReferralCapture(this.handler, this.intent);

  final String handler;
  final ReferralIntent intent;

  /// What the backend expects: `CODE-R`, `CODE-I` or `CODE`.
  String get withSuffix => '$handler${intent.suffix}';
}

/// A parsed share link (RN `parseDeepLink`): path key + its params.
class ShareLink {
  const ShareLink(this.path, this.params);

  /// `expert`, `wallet`, `referral`, … ('' for the bare domain).
  final String path;
  final Map<String, String> params;

  bool get isExpert => path == 'expert' || path == 'expert-profile';

  /// Public-user documentId, expert documentId or handler to open.
  String? get openUserId => isExpert ? params['openUserId'] : null;
}

/// Pure parsers for share links, referral links and the Play install
/// referrer (RN `deepLinking.js` + `InstallReferrerHandler.js`).
abstract final class LinkParser {
  /// Root path words that are app sections, not handlers / referral codes.
  static const sections = {
    'home', 'discover', 'search', 'expert', 'expert-profile', 'wallet', //
    'profile', 'me', 'referral', 'invite', 'history', 'login',
    'app', // `/app/<screen>`: CampaignLinks.fromWeb
  };

  static final _withDomain = RegExp(
    '^${AuthCredentials.shareScheme}://${RegExp.escape(AuthCredentials.webDomain)}/(.*)\$',
    caseSensitive: false,
  );
  static final _schemeOnly = RegExp(
    '^${AuthCredentials.shareScheme}://([^/].*)\$',
    caseSensitive: false,
  );
  static final _web = RegExp(
    '^https?://(?:www\\.)?${RegExp.escape(AuthCredentials.webDomain)}/(.*)\$',
    caseSensitive: false,
  );

  /// `https://vibelive.angrymamba.com/{slug}?r=r` → [ShareLink]. Null for
  /// foreign URLs and junk slugs (utm_, gclid, google-play, > 50 chars).
  static ShareLink? parse(String url) {
    final rest =
        _withDomain.firstMatch(url)?.group(1) ??
        (_schemeOnly.firstMatch(url)?.group(1)).nonDomain ??
        _web.firstMatch(url)?.group(1);
    if (rest == null) return null;

    final q = rest.indexOf('?');
    final rawPath = q == -1 ? rest : rest.substring(0, q);
    final params = _query(q == -1 ? '' : rest.substring(q + 1));
    final segments = rawPath.replaceAll(RegExp(r'^/+|/+$'), '').split('/');
    var path = segments.first.toLowerCase().replaceAll('.php', '');

    String clean(String slug) {
      final s = slug.trim();
      final suffix = s.length > 2
          ? s.substring(s.length - 2).toUpperCase()
          : '';
      if (suffix == '-R' || suffix == '-I') {
        params['r'] = suffix == '-I' ? 'i' : 'r';
        return s.substring(0, s.length - 2);
      }
      return s;
    }

    final second = segments.length > 1 ? segments[1] : '';
    if ((path == 'invite' || path == 'referral') && second.isNotEmpty) {
      params['code'] ??= clean(second);
    }
    if ((path == 'expert' || path == 'expert-profile') && second.isNotEmpty) {
      params['handler'] ??= clean(second);
    }
    if (path.isNotEmpty && !sections.contains(path)) {
      final slug = segments.first, lower = slug.toLowerCase();
      if (slug.contains('=') ||
          lower.startsWith('utm_') ||
          lower.startsWith('gclid') ||
          lower.startsWith('google-play') ||
          slug.length > 50) {
        return null;
      }
      params['handler'] ??= clean(slug);
      path = 'expert';
    }
    if (params['userid'] != null) params['documentId'] ??= params['userid']!;
    if (path == 'expert' || path == 'expert-profile') {
      final open = params['documentId'] ?? params['handler'];
      if (open != null && open.isNotEmpty) params['openUserId'] = open;
    }
    return ShareLink(path, params);
  }

  /// Referral code + intent carried by a link (RN `parseReferralUrl`). A
  /// plain `/{handler}` share has no attribution and returns null.
  static ReferralCapture? referral(String url) {
    final link = parse(url);
    if (link == null) {
      final m = RegExp(
        r'[?&](?:code|referralCode|referral)=([^&#\s]+)',
        caseSensitive: false,
      ).firstMatch(url);
      return m == null
          ? null
          : ReferralCapture(Uri.decodeComponent(m[1]!), ReferralIntent.plain);
    }
    final p = link.params;
    final generic = p['code'] ?? p['referralCode'] ?? p['referral'];
    if (link.path == 'invite' && p['code'] != null) {
      return ReferralCapture(p['code']!, ReferralIntent.invite);
    }
    if (link.path == 'referral' && generic != null) {
      return ReferralCapture(generic, ReferralIntent.refer);
    }
    final r = p['r'], handler = p['handler'];
    if (link.isExpert && r != null && handler != null && handler.isNotEmpty) {
      return ReferralCapture(
        handler,
        r.toLowerCase() == 'i' ? ReferralIntent.invite : ReferralIntent.refer,
      );
    }
    return generic == null
        ? null
        : ReferralCapture(generic, ReferralIntent.plain);
  }

  /// `CODE-R` → refer, `CODE-I` → invite, `CODE` → hostProfile.
  static ReferralCapture splitHandler(String raw) {
    final m = RegExp(
      r'^(.*?)-([RI])$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) {
      return ReferralCapture(raw.trim(), ReferralIntent.hostProfile);
    }
    return ReferralCapture(
      m[1]!.trim(),
      m[2]!.toUpperCase() == 'I' ? ReferralIntent.invite : ReferralIntent.refer,
    );
  }

  /// Play / ad-network filler that is not a referral code.
  static bool isTechnical(String? code) {
    if (code == null || code.isEmpty) return true;
    final lower = code.toLowerCase();
    return lower.contains('(not set)') ||
        lower.contains('google-play') ||
        lower.contains('gclid') ||
        (code.length > 50 && !lower.contains('utm_'));
  }

  /// Raw Play install referrer (`referrer=CODE-R`, `utm_source=CODE-I`,
  /// `CODE`, possibly URL-encoded twice) → capture, or null.
  static ReferralCapture? installReferrer(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var value = raw;
    for (var i = 0; i < 3 && value.contains('%'); i++) {
      try {
        final decoded = Uri.decodeComponent(value);
        if (decoded == value) break;
        value = decoded;
      } catch (_) {
        break;
      }
    }
    value = value.trim();
    final m = RegExp(
      r'(?:^|[?&])(?:utm_source|referrer)=([^&#+\s]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (m != null) value = m[1]!;
    if (value.isEmpty ||
        isTechnical(value) ||
        value.toLowerCase().contains('utm_')) {
      return null;
    }
    final capture = splitHandler(value);
    return capture.handler.isEmpty ? null : capture;
  }

  /// Every share surface builds its link here (RN `buildShareLink`):
  /// referral code + `?r=r|i`, or a handler with no marker.
  static String shareLink(
    String slug, [
    ReferralIntent intent = ReferralIntent.hostProfile,
  ]) {
    const base = 'https://${AuthCredentials.webDomain}';
    final clean = slug.trim();
    if (clean.isEmpty) return base;
    final link = '$base/${Uri.encodeComponent(clean)}';
    return switch (intent) {
      ReferralIntent.invite => '$link?r=i',
      ReferralIntent.refer => '$link?r=r',
      _ => link,
    };
  }

  static Map<String, String> _query(String raw) {
    final out = <String, String>{};
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = _decode(eq == -1 ? pair : pair.substring(0, eq));
      if (key.isNotEmpty) {
        out[key] = eq == -1 ? '' : _decode(pair.substring(eq + 1));
      }
    }
    return out;
  }

  static String _decode(String v) {
    try {
      return Uri.decodeComponent(v.replaceAll('+', ' ')).trim();
    } catch (_) {
      return v.trim();
    }
  }
}

extension on String? {
  /// `vibeexpoapp://vibelive.angrymamba.com/x` is matched by the domain rule.
  String? get nonDomain =>
      this == null || this!.contains('angrymamba.com') ? null : this;
}
