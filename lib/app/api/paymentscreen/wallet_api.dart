import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'payment_json.dart';
import 'wallet_models.dart';

/// Wallet rows and the earnings → cash transfer.
abstract final class WalletApi {
  /// `GET /wallets?filters[user]…` — every wallet of [userId] (documentId,
  /// or numeric id).
  static Future<WalletBalance> fetchBalance(String userId) async {
    final body = await ApiClient.get(
      '/wallets',
      query: {
        'filters[user][${userFilterField(userId)}][\$eq]': userId,
        'populate': '*',
      },
    );
    return WalletBalance.fromResponse(body);
  }

  /// `GET /public-users/:documentId` with its wallets: the wallet transfer
  /// notifications are matched against (null when the user has none).
  static Future<Wallet?> fetchPreferredWallet(String userDocumentId) async {
    final body = await ApiClient.get(
      '/public-users/${Uri.encodeComponent(userDocumentId)}',
      query: {'populate[wallet]': 'true', 'populate[wallets]': 'true'},
    );
    return Wallet.preferredOf(Strapi.map(Strapi.body(body)));
  }

  /// `POST /wallet-transfer/earnings-to-cash`. The backend debits earnings
  /// by [amount] + GST and credits cash by [amount].
  static Future<JsonMap> transferEarningsToCash(double amount) async {
    if (!amount.isFinite || amount <= 0) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'payment:errors.invalid_amount',
      );
    }
    try {
      final body = await ApiClient.post(
        '/wallet-transfer/earnings-to-cash',
        data: {'amount': amount},
      );
      return body is Map
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{'status': 'success'};
    } on ApiException catch (e) {
      throw paymentError(e, 'payment:errors.transfer_failed');
    }
  }
}
