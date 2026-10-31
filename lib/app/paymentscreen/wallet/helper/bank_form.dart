import 'bank_doc.dart';

/// Fields of the payout-account form.
enum BankField {
  holder,
  bank,
  number,
  confirm,
  ifsc,
  upi,
  bankProof,
  panFront,
  panBack,
}

/// The payout-account form's rules (RN WithdrawalModal `validateForm`),
/// matching the backend's `BankAccount` / `UPIAccount` component regexes, so
/// a form that passes here is not then rejected by the server. The three
/// document photos are required too, as the backend requires them.
abstract final class BankForm {
  static final _holder = RegExp(r'^[a-zA-Z\s]+$');
  static final _number = RegExp(r'^[0-9]{9,18}$');
  static final _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _upi = RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$');

  /// The form field each document shows its error under.
  static BankField fieldOf(BankDocKind kind) => switch (kind) {
    BankDocKind.bankProof => BankField.bankProof,
    BankDocKind.panFront => BankField.panFront,
    BankDocKind.panBack => BankField.panBack,
  };

  /// Field → i18n error key. Empty when the form can be submitted.
  ///
  /// [docs]: each document as the form holds it (absent or null = not
  /// added yet). One still uploading, or one that failed, blocks the submit
  /// with its own message.
  static Map<BankField, String> validate({
    required String holder,
    required String bank,
    required String number,
    required String confirm,
    required String ifsc,
    required String upi,
    required Map<BankDocKind, BankDoc?> docs,
  }) {
    final errors = <BankField, String>{};
    final name = holder.trim();
    if (name.length < 2 || name.length > 100 || !_holder.hasMatch(name)) {
      errors[BankField.holder] = 'payment:bank.errors.holder';
    }
    final bankName = bank.trim();
    if (bankName.length < 2 || bankName.length > 100) {
      errors[BankField.bank] = 'payment:bank.errors.bank';
    }
    if (!_number.hasMatch(number.trim())) {
      errors[BankField.number] = 'payment:bank.errors.number';
    }
    if (confirm.trim() != number.trim()) {
      errors[BankField.confirm] = 'payment:bank.errors.confirm';
    }
    if (!_ifsc.hasMatch(ifsc.trim().toUpperCase())) {
      errors[BankField.ifsc] = 'payment:bank.errors.ifsc';
    }
    final upiId = upi.trim();
    if (upiId.isNotEmpty && !_upi.hasMatch(upiId)) {
      errors[BankField.upi] = 'payment:bank.errors.upi';
    }
    for (final kind in BankDocKind.values) {
      final doc = docs[kind];
      final String? problem =
          doc == null || (doc.localPath == null && !doc.uploaded)
          ? kind.errorKey
          : doc.failed
          ? 'payment:bank.errors.doc_failed'
          : doc.uploading
          ? 'payment:bank.errors.doc_uploading'
          : null;
      if (problem != null) errors[fieldOf(kind)] = problem;
    }
    return errors;
  }

  /// `••••••••1234`: the saved account is never shown in full.
  static String masked(String? number) {
    final digits = (number ?? '').trim();
    if (digits.length <= 4) return digits;
    return '••••••••${digits.substring(digits.length - 4)}';
  }
}
