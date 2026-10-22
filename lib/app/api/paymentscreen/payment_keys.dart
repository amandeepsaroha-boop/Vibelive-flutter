import 'wallet_models.dart';

/// Query keys for the payment feature. Same key ⇒ same data type everywhere.
abstract final class PaymentKeys {
  static const all = ['payment'];

  /// `WalletBalance` per user.
  static const wallets = ['payment', 'wallets'];
  static List<Object?> wallet(String? userDocumentId) => [
    ...wallets,
    userDocumentId,
  ];

  /// `List<WalletTransaction>` per user, tab and page.
  static const transactions = ['payment', 'transactions'];
  static List<Object?> transactionPage(
    String? userDocumentId,
    TransactionFilter filter,
    int page,
    int pageSize,
  ) => [...transactions, userDocumentId, filter.name, page, pageSize];

  static const gst = ['payment', 'gst'];
  static const pricingConfig = ['payment', 'pricing-config'];

  /// `BankDetail?` per user.
  static const bankDetails = ['payment', 'bank-details'];
  static List<Object?> bankDetail(String? userDocumentId) => [
    ...bankDetails,
    userDocumentId,
  ];

  /// Everything a top-up, verification or transfer changes.
  static const walletData = [wallets, transactions];
}
