import 'package:intl/intl.dart';

import '../../../../core/network/strapi.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../authscreen/helper/link_parser.dart';

enum SocialKind { instagram, facebook, snapchat, website }

/// A link chip under the call buttons.
class SocialLink {
  const SocialLink(this.kind, this.url, {this.verified = false});

  final SocialKind kind;
  final String url;
  final bool verified;
}

/// Topic chips and spoken languages of the specialization card.
typedef Specialization = ({List<String> topics, List<String> languages});

/// Pure rules of the host profile (RN `ProfileModal`): who is looking, what
/// to show, which link to share.
abstract final class HostProfileRules {
  /// RN `MIN_CALL_MINUTES`: the cash wallet must cover this many minutes.
  static const minCallMinutes = 5;

  /// Longest report note (RN `maxLength`).
  static const maxReportNote = 600;

  /// A card mapped from a populated `/expert-profiles` read (feed, search
  /// detail, shared link) carries its rates and service areas. A summary
  /// (call log, favourites) does not, so the full profile is fetched.
  static bool isComplete(HostCard host) => host.hasFullProfile;

  /// Reviews / favourites key: expert-profile documentId first (RN order).
  static String expertKey(HostCard host) =>
      host.expertProfileDocumentId ?? host.documentId ?? '${host.id}';

  /// The signed-in user is looking at their own profile.
  static bool isMe(HostCard host, SessionState session) {
    if (!session.isAuthenticated) return false;
    final expertId = session.expertDocumentId;
    if (expertId != null && expertId == host.expertProfileDocumentId) {
      return true;
    }
    return host.refersTo(session.userDocumentId ?? session.userId);
  }

  /// Company accounts call for free (RN checked every spelling of the flag).
  static bool isCompanyUser(JsonMap? user) =>
      user != null &&
      (J.boolean(user['is_company_account']) ||
          J.boolean(user['isCompanyAccount']) ||
          J.boolean(user['is_company']));

  /// Plain `/{handler}` link (no referral marker: we never hold another
  /// host's referral code).
  static String shareUrl(HostCard host) => LinkParser.shareLink(
    host.handler.isNotEmpty ? host.handler : (host.documentId ?? ''),
  );

  /// Who a block targets: the public user first.
  static String? blockTarget(HostCard host) =>
      host.userDocumentId ??
      host.receiverId?.toString() ??
      host.documentId ??
      J.str(host.raw['id']);

  /// `20` / `20.5`, as RN printed a rate.
  static String price(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// `120.00`, for balance messages.
  static String money(double v) => v.toStringAsFixed(2);

  // ── Social links ─────────────────────────────────────────────────────

  /// Instagram / Facebook / Snapchat chips (a website pointing at one of
  /// them counts as that network), plus any other website. Instagram is
  /// never linked on iOS (RN).
  static List<SocialLink> socialLinks(HostCard host, {required bool ios}) {
    final website = _nonEmpty(host.websiteUrl);
    final lower = (website ?? '').toLowerCase();
    String? pick(String? own, String domain) =>
        _nonEmpty(own) ?? (lower.contains(domain) ? website : null);

    final insta = pick(host.instaUrl, 'instagram.com');
    final fb = pick(host.facebookUrl, 'facebook.com');
    final snap = pick(host.snapchatUrl, 'snapchat.com');
    final other =
        website != null &&
        !lower.contains('instagram.com') &&
        !lower.contains('facebook.com') &&
        !lower.contains('snapchat.com');
    return [
      if (insta != null && !ios)
        SocialLink(SocialKind.instagram, insta, verified: host.instaVerified),
      if (fb != null)
        SocialLink(SocialKind.facebook, fb, verified: host.facebookVerified),
      if (snap != null)
        SocialLink(SocialKind.snapchat, snap, verified: host.snapchatVerified),
      if (other) SocialLink(SocialKind.website, website),
    ];
  }

  /// URL of one network for the influencer sheet: its own field, else a
  /// matching entry of the (comma / space separated) website field.
  static String? platformUrl(HostCard host, SocialKind kind) {
    final own = switch (kind) {
      SocialKind.instagram => host.instaUrl,
      SocialKind.facebook => host.facebookUrl,
      SocialKind.snapchat => host.snapchatUrl,
      SocialKind.website => host.websiteUrl,
    };
    if (_nonEmpty(own) != null) return own;
    final website = _nonEmpty(host.websiteUrl);
    if (website == null) return null;
    final domain = '${kind.name}.com';
    for (final url in website.split(RegExp(r'[\s,]+'))) {
      if (url.toLowerCase().contains(domain)) return url;
    }
    return null;
  }

  /// `instagram.com/x` → `https://instagram.com/x`.
  static Uri? externalUri(String url) {
    final u = url.trim();
    if (u.isEmpty) return null;
    final lower = u.toLowerCase();
    return Uri.tryParse(
      lower.startsWith('http://') || lower.startsWith('https://')
          ? u
          : 'https://$u',
    );
  }

  // ── Specialization ───────────────────────────────────────────────────

  /// RN `SpecializationCard`: role fallbacks, demographics, age brackets,
  /// availability and call-type answers are dropped; `LANG_*` codes and
  /// known language names move to the languages list.
  static Specialization specialization(
    List<String> tags,
    List<String> languages,
  ) {
    String stripLang(String s) => s
        .replaceFirst(RegExp('^LANGUAGE_', caseSensitive: false), '')
        .replaceFirst(RegExp('^LANG_', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .trim();

    final langs = [
      for (final l in languages)
        if (stripLang(l) case final s when s.isNotEmpty) s,
    ];
    final seen = {for (final l in langs) l.toUpperCase()};
    // The host's own languages are the truth (stored in their script,
    // "हिंदी"); a language-looking interest tag ("Hindi") would only add a
    // second, English copy or a language they never chose. Tags fill in
    // only when the host has none.
    final fromTags = langs.isEmpty;
    final topics = <String>[];

    for (final tag in tags) {
      final raw = tag.trim();
      final clean = raw.toUpperCase();
      if (clean.isEmpty || _excludedTags.contains(clean)) continue;
      if (clean.startsWith('LANG_') || clean.startsWith('LANGUAGE_')) {
        final parsed = stripLang(clean);
        if (fromTags && parsed.isNotEmpty && seen.add(parsed)) {
          langs.add(parsed);
        }
        continue;
      }
      if (_knownLanguages.contains(clean)) {
        if (fromTags && seen.add(clean)) langs.add(raw);
        continue;
      }
      if (_ageBracket.hasMatch(clean) || _agePlus.hasMatch(clean)) continue;
      if (seen.contains(clean)) continue;
      topics.add(raw);
    }
    return (topics: topics, languages: langs);
  }

  // ── Reviews ──────────────────────────────────────────────────────────

  /// Review date in the app language (RN `toLocaleDateString()`), `en_US`
  /// when that locale's date symbols are not loaded.
  static String reviewDate(DateTime at, String localeTag) {
    final format = _dateFormats[localeTag] ??= _yMd(localeTag);
    return format.format(at);
  }

  static final _dateFormats = <String, DateFormat>{};

  static DateFormat _yMd(String tag) {
    try {
      return DateFormat.yMd(tag);
    } catch (_) {
      return DateFormat.yMd('en_US');
    }
  }

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : s;
  }

  static final _ageBracket = RegExp(r'^\d+\s*[-–—]\s*\d+');
  static final _agePlus = RegExp(r'^\d+\+$');

  static const _excludedTags = {
    'CLIENT', 'USER', 'PROFESSIONAL', 'HOST', 'EXPERT', 'ADMIN', //
    'MALE', 'MAN', 'BOY', 'MEN',
    'FEMALE', 'WOMAN', 'GIRL', 'WOMEN',
    'NON-BINARY', 'NON BINARY', 'OTHER',
    'SINGLE', 'MARRIED', 'DIVORCED', 'IN A RELATIONSHIP',
    'PREFER NOT TO SAY', 'ANY', 'ALL',
    'VOICE CALL', 'VIDEO CALL', 'AUDIO CALL', 'CHAT', 'CALL',
    'ANYTIME', 'ANYTIME, I JUST NEED SUPPORT', 'THIS WEEK', 'TODAY', //
    'TOMORROW', 'WEEKENDS', 'WEEKDAYS',
    'MORNING', 'EVENING', 'NIGHT', 'ASAP', 'RIGHT NOW',
  };

  static const _knownLanguages = {
    'ENGLISH', 'HINDI', 'PUNJABI', 'BENGALI', 'MARATHI', 'TELUGU', 'TAMIL', //
    'GUJARATI', 'URDU', 'KANNADA', 'ODIA', 'MALAYALAM', 'BHOJPURI', //
    'RAJASTHANI', 'HARYANVI', 'ASSAMESE', 'SANSKRIT', 'SPANISH', 'FRENCH', //
    'GERMAN', 'ARABIC', 'MANDARIN', 'RUSSIAN', 'PORTUGUESE', 'JAPANESE', //
    'KOREAN', 'ITALIAN', 'CHINESE',
  };
}
