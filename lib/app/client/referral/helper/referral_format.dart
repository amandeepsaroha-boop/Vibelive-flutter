import '../../../authscreen/helper/link_parser.dart';

/// Text of the referral screen, exactly as RN `ReferralScreen` /
/// `normalizeJoinedUser` build it.
abstract final class ReferralFormat {
  /// Shown instead of a missing code (RN `'N/A'`).
  static const noCodeKey = 'client:referral.no_code';

  /// Name of a referred user without name, username or mobile (RN `'User'`).
  /// `JoinedUser.name` already falls back name → username → masked mobile.
  static const unnamedKey = 'client:fallback.user_name';

  /// The referral-funnel link (`?r=r`); the bare site without a code.
  static String link(String code) =>
      LinkParser.shareLink(code, ReferralIntent.refer);

  /// RN `avatarLetter`: first Latin letter, upper-cased; `U` without one
  /// (a masked mobile, a Devanagari name, no name).
  static String avatarLetter(String? name) {
    final m = RegExp('[A-Za-z]').firstMatch((name ?? '').trim());
    return m == null ? 'U' : m.group(0)!.toUpperCase();
  }

  /// RN `Number(x || 0)`: a plain integer, no grouping.
  static String count(int value) => '$value';
}
