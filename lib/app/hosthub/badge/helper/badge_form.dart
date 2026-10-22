import 'package:flutter/widgets.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/hosthub/verification_models.dart';

/// A document photo: uploaded media, or a local file while it uploads.
@immutable
class BadgeDoc {
  const BadgeDoc({this.mediaId, this.url, this.localPath, this.failed = false});

  final Object? mediaId;
  final String? url;
  final String? localPath;
  final bool failed;

  bool get uploaded => mediaId != null;
  bool get uploading => mediaId == null && !failed && localPath != null;

  static BadgeDoc? fromMedia(JsonMap? m) {
    if (m == null) return null;
    final id = m['id'] ?? m['documentId'];
    return id == null
        ? null
        : BadgeDoc(mediaId: id, url: Strapi.mediaFromAsset(m));
  }
}

/// State of the Verification Badge form (RN VerificationFormScreen): the
/// identity step, plus the social step for influencers.
class BadgeFormController {
  /// RN `ID_TYPES` (backend values).
  static const idTypes = [
    'AADHAR CARD',
    'PAN CARD',
    'VOTER ID CARD',
    'DRIVING LICENSE',
  ];

  /// i18n label of an id type.
  static String idTypeKey(String type) => switch (type) {
    'AADHAR CARD' => 'hostflow:badge.doc.aadhar',
    'PAN CARD' => 'hostflow:badge.doc.pan',
    'VOTER ID CARD' => 'hostflow:badge.doc.voter',
    _ => 'hostflow:badge.doc.dl',
  };

  final step = ValueNotifier(0);
  final docType = ValueNotifier<String?>(null);
  final docNumber = TextEditingController();
  final front = ValueNotifier<BadgeDoc?>(null);
  final back = ValueNotifier<BadgeDoc?>(null);
  final linkedIn = TextEditingController();
  final influencer = ValueNotifier(false);
  final platform = ValueNotifier(SocialPlatform.instagram);
  final socialUrl = TextEditingController();

  bool seeded = false;

  List<String> get steps =>
      influencer.value ? ['identity', 'social'] : ['identity'];

  /// Resume from the saved (draft) record.
  void seed(VerificationRecord r) {
    if (seeded) return;
    seeded = true;
    if (r.identityDocType.isNotEmpty) docType.value = r.identityDocType;
    docNumber.text = r.identityDocumentNumber;
    front.value = BadgeDoc.fromMedia(r.media('identity_doc_frontside'));
    back.value = BadgeDoc.fromMedia(r.media('identity_doc_backside'));
    linkedIn.text = r.linkedInUrl;
    final social = r.socialPlatform;
    influencer.value = social != null;
    if (social != null) platform.value = social;
    socialUrl.text = r.socialUrl;
  }

  /// RN `validate`: an i18n key (with variables) or null.
  ({String key, Map<String, dynamic>? vars})? validate(String id) {
    ({String key, Map<String, dynamic>? vars}) issue(
      String k, [
      Map<String, dynamic>? v,
    ]) => (key: 'hostflow:badge.errors.$k', vars: v);
    if (id == 'identity') {
      final type = docType.value ?? '';
      if (type.isEmpty) return issue('doc_type');
      if (docNumber.text.trim().isEmpty) return issue('doc_number');
      if (front.value?.uploaded != true) return issue('front');
      if (back.value?.uploaded != true) return issue('back');
      final n = VerificationUpdate.sanitizeIdentityNumber(type, docNumber.text);
      if (type == 'AADHAR CARD' && !RegExp(r'^\d{12}$').hasMatch(n)) {
        return issue('aadhar');
      }
      if (type == 'PAN CARD' && !RegExp(r'^[A-Z0-9]{10}$').hasMatch(n)) {
        return issue('pan');
      }
      if ((type == 'VOTER ID CARD' || type == 'DRIVING LICENSE') &&
          (n.length < 10 || n.length > 12)) {
        return issue('id_length');
      }
      if (linkedIn.text.trim().isNotEmpty &&
          VerificationUpdate.normalizeLinkedIn(linkedIn.text) == null) {
        return issue('linkedin');
      }
      return null;
    }
    if (id == 'social') {
      if (socialUrl.text.trim().isEmpty) return issue('social_empty');
      if (!isValidSocialUrl(socialUrl.text, platform.value.domain)) {
        return issue('social_invalid', {'domain': platform.value.domain});
      }
    }
    return null;
  }

  /// RN `isValidSocialUrl`: a web URL on the platform's domain, with a
  /// profile path.
  static bool isValidSocialUrl(String raw, String domain) {
    var v = raw.trim();
    if (v.isEmpty) return false;
    if (!v.startsWith(RegExp('https?://'))) v = 'https://$v';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final onDomain = host == domain || host.endsWith('.$domain');
    return onDomain && uri.path.replaceAll('/', '').isNotEmpty;
  }

  void dispose() {
    for (final c in [docNumber, linkedIn, socialUrl]) {
      c.dispose();
    }
    for (final n in <ChangeNotifier>[
      step,
      docType,
      front,
      back,
      influencer,
      platform,
    ]) {
      n.dispose();
    }
  }
}
