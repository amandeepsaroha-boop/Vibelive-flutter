import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'strapi_lookup.dart';
import 'verification_models.dart';

/// Verification Badge: `/expert-verifications` records, the fee payment and
/// education levels.
abstract final class HostVerificationApi {
  static const _endpoint = '/expert-verifications';

  static const _populate = <String, dynamic>{
    'populate[identity_doc_frontside]': 'true',
    'populate[identity_doc_backside]': 'true',
    'populate[Address_File]': 'true',
    'populate[Education_File]': 'true',
    'populate[passbook_cheque]': 'true',
    'populate[gst_detail][populate][GST][populate][0]': 'GST_File',
    'populate[gst_detail][populate][GST][populate][1]': 'Logo',
    'populate[gst_detail][populate][GST][populate][2]': 'state',
    'populate[gst_detail][populate][GST][populate][3]': 'city',
    'populate[gst_detail][populate][GST][populate][4]': 'country',
    'populate[gst_detail][populate][GST][populate][5]': 'district',
    'populate[bank_detail][populate]': '*',
    'populate[Related_Transactions]': 'true',
  };

  /// The host's furthest-along record (records belong to the expert
  /// profile; the schema has no user relation).
  static Future<VerificationRecord?> fetchLatest(String expertId) async {
    final rows = await StrapiLookup.fetchMany(
      _endpoint,
      StrapiLookup.relationFilters('expert_profile', expertId),
    );
    return VerificationRecord.pickPreferred(rows.map(VerificationRecord.new));
  }

  /// The host's record, created (all flags off, published) when missing.
  /// Call only once the host may apply (`HostEligibility.canApplyForBadge`).
  static Future<VerificationRecord> ensure(String expertId) async {
    final existing = await fetchLatest(expertId);
    if (existing != null && existing.key.isNotEmpty) return existing;
    final created = VerificationRecord.fromResponse(
      await ApiClient.post(
        _endpoint,
        data: {
          'data': {
            'expert_profile': expertId,
            'Payment_Received': false,
            'Identity_Verified': false,
            'Address_Verified': false,
            'Education_Verified': false,
            'LinkedIn_Verified': false,
            'GST_Verified': false,
            'Bank_Verified': false,
            'Verified_Badge': false,
            'is_form_submitted': false,
          },
          'status': 'published',
        },
      ),
    );
    if (created == null || created.key.isEmpty) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'hosthub:errors.missing_verification',
      );
    }
    return created;
  }

  /// With documents populated. A `draft` read that 404s (never saved as
  /// draft) falls back to the published version.
  static Future<VerificationRecord?> fetchById(
    String verificationId, {
    String? status,
  }) async {
    final path = '$_endpoint/${Uri.encodeComponent(verificationId)}';
    try {
      return VerificationRecord.fromResponse(
        await ApiClient.get(path, query: {'status': ?status, ..._populate}),
      );
    } on ApiException catch (e) {
      if (status != 'draft' || e.statusCode != 404) rethrow;
      return VerificationRecord.fromResponse(
        await ApiClient.get(path, query: _populate),
      );
    }
  }

  static Future<VerificationRecord?> update(VerificationUpdate u) async =>
      VerificationRecord.fromResponse(
        await ApiClient.put(
          '$_endpoint/${Uri.encodeComponent(u.verificationId)}',
          query: {'status': u.status},
          data: {'data': u.data},
        ),
      );

  static Future<List<String>> fetchEducationLevels() async {
    final body = await ApiClient.get('$_endpoint/education-levels');
    final list = body is Map && body['data'] is List
        ? body['data'] as List
        : const [];
    return [
      for (final v in list)
        if ((J.str(v) ?? '').trim().isNotEmpty) J.str(v)!.trim(),
    ];
  }

  /// PayU checkout data, or `alreadyPaid`. [userId] is the numeric user id.
  static Future<VerificationPaymentInit> initiatePayment({
    required int userId,
    required String verificationId,
  }) async {
    final body = await ApiClient.post(
      '/expert-verification/initiate-payment',
      data: {'userId': userId, 'expertVerificationId': verificationId},
    );
    final init = VerificationPaymentInit(
      body is Map ? Map<String, dynamic>.from(body) : const {},
    );
    if (!init.isValid) {
      throw ApiException(
        ApiErrorType.parse,
        messageKey: 'hosthub:errors.invalid_payment_response',
        data: body,
      );
    }
    return init;
  }

  /// Forwards the gateway result (PayU fields or Razorpay ids) to the
  /// backend.
  static Future<dynamic> postPaymentResponse(JsonMap payload) =>
      ApiClient.post('/expert-verification/payment-response', data: payload);

  /// The gateway result reaches the backend asynchronously: poll until the
  /// record is marked paid (RN: 18 tries, 2 s apart).
  static Future<bool> waitForPayment(
    String verificationId, {
    int attempts = 18,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final row = await fetchById(verificationId);
      if (row?.raw['Payment_Received'] == true) return true;
      if (i < attempts - 1) await Future<void>.delayed(interval);
    }
    return false;
  }
}
