import 'package:flutter/foundation.dart';

import '../../../../core/network/strapi.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/client/client_models.dart';
import '../../../api/hosthub/eligibility.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../api/hosthub/verification_models.dart';
import '../../../authscreen/helper/link_parser.dart';

/// Status dot of a host's own avatar.
enum MeStatus { online, busy, offline }

/// Everything the ME tab shows about the signed-in user, derived once per
/// session change (RN MeCard's inline derivations).
@immutable
class MeData {
  const MeData._({
    required this.profile,
    required this.host,
    required this.status,
    required this.badgeStep,
    required this.missingPersonalInfo,
  });

  factory MeData.of(SessionState s) {
    final profile = UserWithExpert(user: s.user ?? const {}, expert: s.expert);
    final host = profile.isExpert ? HostProfile.from(s.expert) : null;
    return MeData._(
      profile: profile,
      host: host,
      status: _statusOf(host),
      badgeStep: HostEligibility.badgeStep(host?.raw),
      missingPersonalInfo: HostEligibility.missingPersonalInfo(profile.user),
    );
  }

  final UserWithExpert profile;

  /// The host profile; null for a client account.
  final HostProfile? host;
  final MeStatus status;

  /// Verification Badge progress; null before approval / for a client.
  final VerificationStep? badgeStep;

  /// Personal Info still missing (gates "Become a Host").
  final List<PersonalInfoField> missingPersonalInfo;

  bool get isExpert => host != null;
  bool get isCompany => profile.isCompanyAccount;
  String? get name => profile.name;
  String? get avatarUrl => profile.profilePicUrl;

  /// The navbar's Profile avatar: a host's primary photo, else the account
  /// picture.
  String? get navAvatarUrl =>
      host?.profileImages.firstOrNull?.imageUrl ?? avatarUrl;
  String? get userDocumentId => profile.documentId;

  /// Per-account key for one-time UI (documentId, else id).
  String get userKey => profile.documentId ?? '${profile.id ?? ''}';

  /// RN shows `@{expert.handler}` only.
  String? get handler {
    final h = host?.handler.trim() ?? '';
    return h.isEmpty ? null : h;
  }

  String? get expertId {
    final id = host?.key ?? '';
    return id.isEmpty ? null : id;
  }

  HostAvailability get availability =>
      host?.availability ?? HostAvailability.custom;

  /// Name, email and mobile set (the ⋮ menu's "Become a Host" gate).
  bool get hasBasics => profile.isPersonalInfoComplete;

  bool get isPersonalInfoComplete => missingPersonalInfo.isEmpty;

  /// `hosthub:badge.apply|finish`, or null when nothing is left to do.
  String? get badgePromptKey => switch (badgeStep) {
    VerificationStep.fee => 'hosthub:badge.apply',
    VerificationStep.form => 'hosthub:badge.finish',
    _ => null,
  };

  /// Applied hosts see their status; everyone else starts at the fee
  /// screen (which explains the approval gate).
  String get verificationRoute => switch (badgeStep) {
    VerificationStep.review ||
    VerificationStep.success => AppRoutes.verificationBadge,
    _ => AppRoutes.verificationBadgeFee,
  };

  /// Public profile link (RN `buildProfileLink`): handler, else an id.
  String? get profileLink {
    final slug = profile.shareSlug;
    return slug == null ? null : LinkParser.shareLink(slug);
  }

  /// The avatar preview's link (RN: expert handler, else user documentId).
  String? get previewLink {
    final slug = handler ?? userDocumentId;
    return slug == null ? null : LinkParser.shareLink(slug);
  }

  /// RN MeCard: a host switched off (`isActive: false`) is offline whatever
  /// the socket says; unknown counts as offline too.
  static MeStatus _statusOf(HostProfile? host) {
    final raw = host?.raw;
    if (raw == null) return MeStatus.offline;
    final active = raw['isActive'];
    if (active == false || active == 0 || active == 'false') {
      return MeStatus.offline;
    }
    return switch ((J.str(raw['user_status']) ?? '').toLowerCase()) {
      'online' => MeStatus.online,
      'busy' => MeStatus.busy,
      _ => MeStatus.offline,
    };
  }
}
