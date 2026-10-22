import '../../../core/network/strapi.dart';
import 'profile_models.dart';

/// Where a host stands with the Verification Badge, in order.
enum VerificationStep {
  /// Nothing paid yet.
  fee,

  /// Paid, form not submitted.
  form,

  /// Submitted, waiting for review.
  review,

  /// Badge granted.
  success,
}

/// An `/expert-verifications` row. [raw] keeps every field.
class VerificationRecord {
  const VerificationRecord(this.raw);

  final JsonMap raw;

  static VerificationRecord? from(dynamic row) {
    final m = Strapi.map(row);
    return m == null ? null : VerificationRecord(m);
  }

  static VerificationRecord? fromResponse(dynamic body) =>
      from(Strapi.body(body));

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// documentId first: what GET/PUT address.
  String get key => documentId ?? J.str(raw['id']) ?? '';

  bool get paymentReceived => HostFlag.isTruthy(raw['Payment_Received']);
  bool get formSubmitted => HostFlag.isTruthy(raw['is_form_submitted']);
  bool get verifiedBadge => HostFlag.isTruthy(raw['Verified_Badge']);

  VerificationStep get nextStep => nextStepOf(raw);

  /// RN `getVerificationNextStep`: unpaid always means `fee`, even with the
  /// badge flag set.
  static VerificationStep nextStepOf(JsonMap? row) {
    final v = Strapi.map(row);
    if (v == null || !HostFlag.isTruthy(v['Payment_Received'])) {
      return VerificationStep.fee;
    }
    if (HostFlag.isTruthy(v['Verified_Badge'])) return VerificationStep.success;
    if (HostFlag.isTruthy(v['is_form_submitted'])) {
      return VerificationStep.review;
    }
    return VerificationStep.form;
  }

  /// RN `pickPreferredVerification`: the furthest row (badge > submitted >
  /// paid), then the most recently updated, created, highest id. Keeps an old
  /// abandoned row from hiding the one the host actually completed.
  static VerificationRecord? pickPreferred(Iterable<VerificationRecord> rows) {
    VerificationRecord? best;
    for (final row in rows) {
      if (best == null || _compare(row, best) < 0) best = row;
    }
    return best;
  }

  static int _compare(VerificationRecord a, VerificationRecord b) {
    final byPriority = b._priority.compareTo(a._priority);
    if (byPriority != 0) return byPriority;
    final byUpdated = _time(
      b.raw['updatedAt'],
    ).compareTo(_time(a.raw['updatedAt']));
    if (byUpdated != 0) return byUpdated;
    final byCreated = _time(
      b.raw['createdAt'],
    ).compareTo(_time(a.raw['createdAt']));
    if (byCreated != 0) return byCreated;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  int get _priority => verifiedBadge
      ? 4
      : formSubmitted
      ? 3
      : paymentReceived
      ? 2
      : 1;

  static int _time(dynamic v) =>
      DateTime.tryParse(J.str(v) ?? '')?.millisecondsSinceEpoch ?? 0;

  /// Where a resumed form should open (RN `getVerificationFormProgress`).
  /// Only the identity step is live: RN commented out address, education,
  /// bank and GST.
  VerificationFormProgress get formProgress => VerificationFormProgress([
    (
      id: 'identity',
      complete:
          _text('identity_doc_file') &&
          _text('identity_document_number') &&
          _hasMedia(raw['identity_doc_frontside']) &&
          _hasMedia(raw['identity_doc_backside']),
    ),
  ]);

  bool _text(String k) => (J.str(raw[k]) ?? '').trim().isNotEmpty;

  static bool _hasMedia(dynamic v) => Strapi.list(v).any(
    (m) =>
        m['id'] != null ||
        m['documentId'] != null ||
        J.str(m['url']) != null ||
        J.str(m['name']) != null,
  );

  // ── Identity / social fields the form resumes from ──────────────────────
  String get identityDocType => J.str(raw['identity_doc_file']) ?? '';
  String get identityDocumentNumber =>
      J.str(raw['identity_document_number']) ?? '';
  String get linkedInUrl => J.str(raw['LinkedIn_Url']) ?? '';

  /// First media node of a media field (single or multiple).
  JsonMap? media(String field) {
    final list = Strapi.list(raw[field]);
    return list.isEmpty ? null : list.first;
  }

  /// The social profile on file (Instagram, then Facebook, then Snapchat).
  SocialPlatform? get socialPlatform {
    for (final p in SocialPlatform.values) {
      if (J.str(raw[p.field]) != null) return p;
    }
    return null;
  }

  String get socialUrl =>
      socialPlatform == null ? '' : J.str(raw[socialPlatform!.field]) ?? '';
}

class VerificationFormProgress {
  const VerificationFormProgress(this.steps);

  final List<({String id, bool complete})> steps;

  int get _firstIncomplete => steps.indexWhere((s) => !s.complete);

  bool get complete => _firstIncomplete == -1;

  int get nextStepIndex =>
      _firstIncomplete == -1 ? steps.length - 1 : _firstIncomplete;

  String get nextStepId => steps.isEmpty
      ? 'identity'
      : steps[nextStepIndex.clamp(0, steps.length - 1)].id;
}

enum SocialPlatform {
  instagram('insta_url', 'instagram.com'),
  facebook('facebook_url', 'facebook.com'),
  snapchat('snapchat_url', 'snapchat.com');

  const SocialPlatform(this.field, this.domain);

  /// Verification field holding this platform's profile URL.
  final String field;
  final String domain;
}

/// `PUT /expert-verifications/:id?status=…` built the way the RN form did.
class VerificationUpdate {
  const VerificationUpdate(
    this.verificationId,
    this.data, {
    this.status = 'draft',
  });

  final String verificationId;
  final JsonMap data;

  /// `draft` while filling the form; `published` on final submit.
  final String status;

  /// Whether this write can move the badge step (session needs a refresh).
  bool get changesBadgeStep =>
      data.containsKey('Payment_Received') ||
      data.containsKey('is_form_submitted') ||
      data.containsKey('Verified_Badge');

  /// Fee is 0: mark paid without a gateway (VerificationFeeScreen).
  factory VerificationUpdate.markPaid(String verificationId) =>
      VerificationUpdate(verificationId, const {'Payment_Received': true});

  /// Identity step. The number is sanitized for its document type and an
  /// invalid LinkedIn URL is sent as null.
  factory VerificationUpdate.identity(
    String verificationId, {
    required String docType,
    required String docNumber,
    Object? frontMediaId,
    Object? backMediaId,
    String? linkedInUrl,
  }) => VerificationUpdate(verificationId, {
    'identity_doc_file': docType,
    'identity_document_number': sanitizeIdentityNumber(docType, docNumber),
    'identity_doc_frontside': frontMediaId,
    'identity_doc_backside': backMediaId,
    'LinkedIn_Url': normalizeLinkedIn(linkedInUrl),
    'Identity_Verified': false,
    'LinkedIn_Verified': false,
  });

  /// Social step: only the chosen platform keeps a URL.
  factory VerificationUpdate.social(
    String verificationId, {
    required SocialPlatform platform,
    required String url,
  }) => VerificationUpdate(verificationId, _socialFields(platform, url));

  /// Final submit, published. Non-influencers clear every social URL.
  factory VerificationUpdate.submit(
    String verificationId, {
    SocialPlatform? platform,
    String url = '',
  }) => VerificationUpdate(verificationId, {
    'is_form_submitted': true,
    ..._socialFields(platform, url),
  }, status: 'published');

  static JsonMap _socialFields(SocialPlatform? platform, String url) => {
    for (final p in SocialPlatform.values)
      p.field: p == platform ? url.trim() : null,
  };

  static final _linkedIn = RegExp(
    r'^(https?://)?(www\.)?linkedin\.com/in/[a-zA-Z0-9-]+/?$',
    caseSensitive: false,
  );

  /// Aadhaar keeps 12 digits; other IDs drop spaces, uppercase, max 12.
  static String sanitizeIdentityNumber(String docType, String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final clean = docType.toUpperCase() == 'AADHAR CARD'
        ? v.replaceAll(RegExp(r'\D+'), '')
        : v.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return clean.length > 12 ? clean.substring(0, 12) : clean;
  }

  /// A valid `linkedin.com/in/…` URL, else null.
  static String? normalizeLinkedIn(String? value) {
    final v = (value ?? '').trim();
    return v.isNotEmpty && _linkedIn.hasMatch(v) ? v : null;
  }
}

/// `POST /expert-verification/initiate-payment` answer (PayU).
class VerificationPaymentInit {
  const VerificationPaymentInit(this.raw);

  final JsonMap raw;

  bool get alreadyPaid => J.boolean(raw['alreadyPaid']);
  String? get payuUrl => J.str(raw['payuUrl']);
  JsonMap? get payuData => Strapi.map(raw['payuData']);

  /// PayU cannot start without a transaction id and hash.
  bool get isValid =>
      alreadyPaid ||
      (J.str(payuData?['txnid']) != null && J.str(payuData?['hash']) != null);
}
