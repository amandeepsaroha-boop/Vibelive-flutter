import 'package:flutter/services.dart';

import '../../../api/paymentscreen/billing_models.dart';
import 'wallet_format.dart';

/// JS `parseFloat`: the leading number of [text], or null (`'5.'` → 5,
/// `'.5'` → 0.5, `'.'` → null).
double? parseLeadingNumber(String text) {
  final match = RegExp(r'^\s*(\d*\.?\d*)').firstMatch(text);
  final head = match?.group(1) ?? '';
  if (head.isEmpty || head == '.') return null;
  return double.tryParse(head.endsWith('.') ? '${head}0' : head);
}

/// Add-money amount rules (RN WalletScreen).
abstract final class TopUpAmount {
  /// RN `PRESET_AMOUNTS`.
  static const presets = [50, 100, 500, 750, 1000, 1500];

  /// Add-money GST (RN `calculateGST` default).
  static const gstPercent = 18.0;

  /// RN `onChangeText`: digits and one dot, at most two decimals, leading
  /// zeros dropped (`'05'` → `'5'`, `'0.5'` kept).
  static String sanitize(String text) {
    var s = text.replaceAll(RegExp(r'[^\d.]'), '');
    final m = RegExp(r'^(\d*\.\d{0,2}).*$').firstMatch(s);
    if (m != null) s = m.group(1)!;
    if (s.startsWith('0') && !s.startsWith('0.')) {
      s = '${int.tryParse(RegExp(r'^\d*').stringMatch(s) ?? '') ?? 0}';
    }
    return s;
  }

  /// The preset matching typed [text] exactly (no decimals), else null.
  static int? presetFor(String text) {
    if (text.contains('.')) return null;
    final n = int.tryParse(text.isEmpty ? '0' : text);
    return n != null && presets.contains(n) ? n : null;
  }

  /// RN `effectiveAddAmount`: the typed amount, else the preset, else 0.
  static double effective(String text, int? preset) {
    final n = parseLeadingNumber(text.trim());
    if (n != null && n > 0) return n;
    if (preset != null && preset > 0) return preset.toDouble();
    return 0;
  }

  static GstBreakdown breakdown(double amount) =>
      GstBreakdown.of(amount, percent: gstPercent);
}

/// [TopUpAmount.sanitize] as a field formatter.
class TopUpAmountFormatter extends TextInputFormatter {
  const TopUpAmountFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = TopUpAmount.sanitize(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Earnings → cash numbers (RN TransferModal), for one amount and rate.
class TransferQuote {
  const TransferQuote({
    required this.amountText,
    required this.earnings,
    required this.gstPercent,
  });

  /// What the amount box shows (preset-filled string, '' when empty).
  final String amountText;
  final double earnings;
  final double gstPercent;

  /// Presets in percent of [max]; 100 is the same as MAX (RN).
  static const presets = [25, 50, 75, 100];

  double get amount => double.tryParse(amountText) ?? 0;
  double get gst => amount * (gstPercent / 100);
  double get debit => amount + gst;

  /// Largest amount whose amount + GST fits in the earnings.
  double get max => EarningsTransfer.maxTransferable(earnings, gstPercent);

  bool get isValid => EarningsTransfer.isValid(amount, earnings, gstPercent);
  bool get belowMinimum => amount < EarningsTransfer.minAmount;
  bool get exceedsEarnings => debit > earnings + 0.01;

  /// Amount text for a [percent] preset (floored to paise; '' for 0).
  String presetText(int percent) {
    final next = (max * percent / 100 * 100).floor() / 100;
    return next > 0 ? WalletFormat.js(next) : '';
  }

  /// Amount text for MAX.
  String get maxText => max > 0 ? WalletFormat.js(max) : '';

  TransferQuote withAmount(String text) => TransferQuote(
    amountText: text,
    earnings: earnings,
    gstPercent: gstPercent,
  );
}
