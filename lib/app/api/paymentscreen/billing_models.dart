import 'dart:math' as math;

import '../../../core/network/strapi.dart';

/// RN `calculateGST`: GST on top of [base]. Zero for a missing or
/// non-positive base.
class GstBreakdown {
  const GstBreakdown({required this.base, required this.gst});

  static const zero = GstBreakdown(base: 0, gst: 0);

  factory GstBreakdown.of(
    num? base, {
    num percent = GstConfig.defaultIgstRate,
  }) {
    if (base == null || !base.isFinite || base <= 0) return zero;
    final b = base.toDouble();
    return GstBreakdown(base: b, gst: b * percent / 100);
  }

  final double base;
  final double gst;
  double get total => base + gst;
}

/// `/gst` (single type): tax applied to earnings → cash transfers.
class GstConfig {
  const GstConfig(this.raw);

  final JsonMap raw;

  /// Used when `IGST` is unset, and by the UI while `/gst` is loading or
  /// failed (RN TransferModal starts at 18 and keeps it on error).
  static const defaultIgstRate = 18.0;

  factory GstConfig.fromResponse(dynamic body) =>
      GstConfig(Strapi.map(Strapi.body(body)) ?? const {});

  double get igstRate {
    final v = J.number(raw['IGST']);
    return v != null && v.isFinite ? v : defaultIgstRate;
  }
}

/// Client-side limits of the earnings → cash transfer (RN TransferModal).
/// The backend debits earnings by amount + GST and credits cash by amount.
abstract final class EarningsTransfer {
  static const minAmount = 10.0;
  static const maxAmount = 100000.0;

  /// Rounding slack when comparing the debit with the earnings balance.
  static const _tolerance = 0.01;

  /// Largest amount whose amount + GST fits in [earnings], floored to paise.
  static double maxTransferable(double earnings, double gstRate) {
    final raw = earnings / (1 + gstRate / 100);
    return math.max((raw * 100).floor() / 100, 0);
  }

  static bool isValid(double amount, double earnings, double gstRate) =>
      amount >= minAmount &&
      amount <= maxAmount &&
      GstBreakdown.of(amount, percent: gstRate).total <= earnings + _tolerance;
}

/// `/pricing-config` (single type): call-rate floors, commissions, wallet
/// limits and the expert verification fee. Shared with hosthub.
class PricingConfig {
  const PricingConfig(this.raw);

  final JsonMap raw;

  static const empty = PricingConfig({});

  // RN `parseRate`: anything unparseable reads as 0.
  double _rate(String key) {
    final v = J.number(raw[key]);
    return v != null && v.isFinite ? v : 0;
  }

  double get minimumVoiceRate => _rate('Minimum_voiceCall_Rate');
  double get minimumVideoRate => _rate('Minimum_videoCall_Rate');
  double get videoCommissionPercent => _rate('VideoCall_Percentage_Commission');
  double get voiceCommissionPercent => _rate('VoiceCall_Percentage_Commission');
  double get minimumVideoCommissionFixed =>
      _rate('Minimum_videoCall_Commission_Fixed');
  double get minimumVoiceCommissionFixed =>
      _rate('Minimum_VoiceCall_Commission_Fixed');
  double get expertVerificationFees => _rate('expert_verification_fees');
  double get referralVideoCommissionPercent =>
      _rate('Referral_VideoCall_Percentage_Commission');
  double get referralVoiceCommissionPercent =>
      _rate('Referral_VoiceCall_Percentage_Commission');
  double get referralMinimumVideoCommissionFixed =>
      _rate('Referral_Minimum_videoCall_Commission_Fixed');
  double get referralMinimumVoiceCommissionFixed =>
      _rate('Referral_Minimum_VoiceCall_Commission_Fixed');
  double get minimumAmountToAddWallet => _rate('Minimum_Amount_to_add_wallet');
  double get minimumAmountToWithdrawal => _rate('Minimum_Amount_To_Withdrawal');
  double get minimumAmountPopup => _rate('Minimum_Amount_Popup');
}

/// Payout account (`/bank-details`). Reads the Strapi component names and
/// their snake_case variants.
class BankDetail {
  const BankDetail(this.raw);

  final JsonMap raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// Path key for `PUT /bank-details/:key`.
  String? get key => documentId ?? J.str(raw['id']);

  JsonMap get _bank =>
      Strapi.map(raw['BankAccount']) ??
      Strapi.map(raw['bank_account']) ??
      const {};
  JsonMap get _upi =>
      Strapi.map(raw['UPIAccount']) ??
      Strapi.map(raw['upi_account']) ??
      const {};

  String? get accountName => J.str(_bank['Account_Name']);
  String? get accountNumber => J.str(_bank['Account_Number']);
  String? get ifsc => J.str(_bank['Account_IFSC']);
  String? get bankName => J.str(_bank['Account_Bank']);
  String? get upiAddress => J.str(_upi['UPI_Address']);

  bool get isVerified =>
      J.boolean(raw['Is_Verified']) || J.boolean(raw['is_verified']);
}

/// Create (no [bankDetailKey]) or update a payout account.
class BankDetailInput {
  const BankDetailInput({
    required this.userDocumentId,
    required this.accountName,
    required this.accountNumber,
    required this.ifsc,
    required this.bankName,
    this.upiAddress = '',
    this.primary = true,
    this.bankDetailKey,
  });

  final String userDocumentId;
  final String accountName;
  final String accountNumber;
  final String ifsc;
  final String bankName;
  final String upiAddress;
  final bool primary;

  /// [BankDetail.key] of the row to update.
  final String? bankDetailKey;

  JsonMap toJson() => {
    'user': userDocumentId,
    'Primary': primary,
    'BankAccount': {
      'Account_Name': accountName.trim(),
      'Account_Number': accountNumber.trim(),
      'Account_IFSC': ifsc.trim().toUpperCase(),
      'Account_Bank': bankName.trim(),
    },
    if (upiAddress.trim().isNotEmpty)
      'UPIAccount': {'UPI_Address': upiAddress.trim()},
  };
}

enum InvoicePdfStatus {
  ready,

  /// No invoice row yet: the backend creates it shortly after payment.
  generating,

  /// Invoice exists, its PDF doesn't yet.
  processing;

  /// Title and message to show when not [ready].
  String get titleKey => 'payment:invoice.${name}_title';
  String get messageKey => 'payment:invoice.$name';
}

class InvoicePdfLookup {
  const InvoicePdfLookup(this.status, {this.url, this.invoice});

  final InvoicePdfStatus status;

  /// Absolute PDF URL when [status] is ready.
  final String? url;
  final JsonMap? invoice;
}
