import 'package:flutter/foundation.dart' show immutable;

import '../../../core/network/strapi.dart';
import 'listing_models.dart';

/// Verification flags read on their own (RN search badge enrichment).
@immutable
class HostBadges {
  const HostBadges({
    this.verified = false,
    this.instaVerified = false,
    this.facebookVerified = false,
    this.snapchatVerified = false,
  });

  /// An `/expert-profiles` row with `expert_verifications` populated. Same
  /// gate as [HostCard]: social flags count only on a verified badge.
  factory HostBadges.fromRow(Object? row) {
    final node = Strapi.map(row) ?? const {};
    final verifications = Strapi.list(node['expert_verifications']);
    final ver = verifications.isEmpty
        ? const <String, dynamic>{}
        : verifications.first;
    final badge = ver['Verified_Badge'];
    final verified =
        node['isVerified'] == true ||
        badge == true ||
        J.str(badge)?.toLowerCase() == 'true';
    bool social(String key) =>
        verified && (ver[key] == true || ver[key] == 'true');
    return HostBadges(
      verified: verified,
      instaVerified: social('insta_verified'),
      facebookVerified: social('facebook_verified'),
      snapchatVerified: social('snapchat_verified'),
    );
  }

  final bool verified;
  final bool instaVerified;
  final bool facebookVerified;
  final bool snapchatVerified;

  /// A full card's flags (same gate).
  static HostBadges of(HostCard h) => HostBadges(
    verified: h.verified,
    instaVerified: h.instaVerified,
    facebookVerified: h.facebookVerified,
    snapchatVerified: h.snapchatVerified,
  );
}
