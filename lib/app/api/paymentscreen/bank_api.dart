import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'billing_models.dart';
import 'payment_json.dart';

/// Payout bank account (withdrawals).
abstract final class BankApi {
  /// `GET /bank-details`: the newest row of [userId] (documentId, or numeric
  /// id), or null when none is saved yet.
  static Future<BankDetail?> fetchBankDetail(String userId) async {
    final body = await ApiClient.get(
      '/bank-details',
      query: {
        'filters[user][${userFilterField(userId)}][\$eq]': userId,
        'populate': '*',
        'sort[0]': 'createdAt:desc',
        'pagination[limit]': 1,
      },
    );
    final first = paymentRows(body).firstOrNull;
    return first == null ? null : BankDetail(first);
  }

  /// `PUT /bank-details/:key` when [BankDetailInput.bankDetailKey] is set,
  /// else `POST /bank-details`. The backend marks it for verification.
  static Future<BankDetail> save(BankDetailInput input) async {
    if (input.userDocumentId.trim().isEmpty) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'payment:errors.missing_user',
      );
    }
    final data = {'data': input.toJson()};
    final key = input.bankDetailKey;
    try {
      final body = key != null && key.isNotEmpty
          ? await ApiClient.put(
              '/bank-details/${Uri.encodeComponent(key)}',
              data: data,
            )
          : await ApiClient.post('/bank-details', data: data);
      final saved = Strapi.map(Strapi.body(body));
      if (saved == null) throw const ApiException(ApiErrorType.parse);
      return BankDetail(saved);
    } on ApiException catch (e) {
      throw paymentError(e, 'payment:errors.bank_save_failed');
    }
  }
}
