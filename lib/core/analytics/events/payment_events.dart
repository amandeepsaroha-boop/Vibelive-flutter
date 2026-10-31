import '../analytics.dart';

/// Payment events (Firebase + Meta): wallet, add money, checkout, offers,
/// payment status, transactions, earnings transfer and the payout account.
/// Catalog: docs/analytics_events.md.
///
/// RN event names and params are kept as they were (`wallet_opened`,
/// `initiate_payment`, `payment_success`, …): same Firebase project and
/// Meta app as the RN build, so reports stay continuous.
abstract final class PaymentEvents {
  static const _currency = 'INR';

  /// Transactions whose purchase was already sent in this app session.
  static final _purchased = <String>{};

  // ── Wallet ─────────────────────────────────────────────────────────────

  /// RN `logWalletOpened`: every wallet load (open, refresh, after a
  /// payment), with the first wallet row's balance.
  static void walletOpened({String? userId, num? balance}) =>
      Analytics.log('wallet_opened', {'user_id': userId, 'balance': balance});

  /// A wallet button: `add_money`, `transfer`, `bank`, `back`.
  static void walletAction(String action, {num? balance}) => Analytics.log(
    'wallet_action_tapped',
    {'action': action, 'balance': balance},
  );

  /// Pull to refresh on the transaction list.
  static void walletRefreshed({required String tab}) =>
      Analytics.log('wallet_refreshed', {'tab': tab});

  /// "Complete your profile" before paying ([step]: `add` before the
  /// amount screen, `pay` after it). [updateProfile]: they went to fix it.
  static void profileIncomplete({
    required String step,
    required bool updateProfile,
  }) => Analytics.log('wallet_profile_incomplete', {
    'step': step,
    'result': updateProfile ? 'update_profile' : 'cancel',
  });

  // ── Add money ──────────────────────────────────────────────────────────

  /// The Add Money screen opened. [source]: `wallet`, `balance_gate`
  /// (prefilled from the call gate), `first_topup_offer`, `abandon_offer`.
  static void addMoneyOpened({
    required String source,
    num? prefillAmount,
    num? balance,
    String? bonusKind,
    num? bonusPercent,
    int? presetCount,
  }) => Analytics.log('add_money_opened', {
    'source': source,
    'prefill_amount': prefillAmount,
    'balance': balance,
    'bonus_kind': bonusKind,
    'bonus_percent': bonusPercent,
    'preset_count': presetCount,
  });

  /// A bonus is previewed on the amount cards (`first_topup`, `comeback`).
  static void topupBonusShown({required String kind, required num percent}) =>
      Analytics.log('topup_bonus_shown', {'kind': kind, 'percent': percent});

  /// An amount card tapped. [kind]: `preset` or `prefill` (the handed-in
  /// amount's own card); [selected] false when the tap cleared it.
  static void amountSelected({
    required int amount,
    required String kind,
    required bool selected,
    num? bonusPercent,
    int? position,
  }) => Analytics.log('add_money_amount_selected', {
    'amount': amount,
    'kind': kind,
    'action': selected ? 'selected' : 'deselected',
    'bonus_percent': bonusPercent,
    'position': position,
  });

  /// "Proceed to pay" on Add Money.
  static void payTapped({
    required int amount,
    required num gstPercent,
    required num total,
    num? bonus,
  }) => Analytics.log('add_money_pay_tapped', {
    'amount': amount,
    'gst_percent': gstPercent,
    'total': total,
    'bonus': bonus,
  });

  /// Add Money closed without an order ([selectedAmount]: what was picked).
  static void addMoneyClosed({int? selectedAmount}) =>
      Analytics.log('add_money_closed', {'selected_amount': selectedAmount});

  /// The backend created the order.
  static void orderCreated({
    required num amount,
    required String gateway,
    String? orderId,
  }) => Analytics.log('payment_order_created', {
    'amount': amount,
    'gateway': gateway,
    'order_id': orderId,
  });

  /// The order could not be created (shown as an alert).
  static void orderFailed({required num amount, required String error}) =>
      Analytics.log('payment_order_failed', {'amount': amount, 'error': error});

  // ── Checkout ───────────────────────────────────────────────────────────

  /// RN `logInitiatePayment` (after the order, before checkout opens):
  /// Meta AddedPaymentInfo + InitiatedCheckout and `initiate_payment`, plus
  /// Firebase's recommended `begin_checkout` / `add_payment_info`.
  static void initiatePayment({
    required double amount,
    required String paymentMethod,
    required String orderId,
  }) {
    Analytics.meta('fb_mobile_add_payment_info', {
      'payment_method': paymentMethod,
      'currency': _currency,
      'amount': amount,
    });
    Analytics.meta('fb_mobile_initiated_checkout', {
      'content_id': orderId,
      'content_type': 'wallet_recharge',
      'currency': _currency,
      'amount': amount,
    }, valueToSum: amount);
    Analytics.log('initiate_payment', {
      'amount': amount > 0 ? amount : null,
      'payment_method': paymentMethod,
      'order_id': orderId,
    });
    Analytics.firebase('begin_checkout', {
      'currency': _currency,
      'value': amount,
      'transaction_id': orderId,
      'item_category': 'wallet_recharge',
    });
    Analytics.firebase('add_payment_info', {
      'currency': _currency,
      'value': amount,
      'payment_type': paymentMethod,
    });
  }

  /// A checkout opened. [gateway]: `razorpay_native`, `razorpay_web`
  /// (native could not open), `payu_web`.
  static void checkoutOpened({
    required String gateway,
    required num amount,
    String? orderId,
  }) => Analytics.log('checkout_opened', {
    'gateway': gateway,
    'amount': amount,
    'order_id': orderId,
  });

  /// RN `payment_abandoned` (closed unpaid) / `checkout_failed_to_open`.
  static void checkoutEnded({
    required bool dismissed,
    required String orderId,
    required num amount,
    int? errorCode,
    String? description,
  }) => Analytics.log(
    dismissed ? 'payment_abandoned' : 'checkout_failed_to_open',
    {
      'order_id': orderId,
      'amount': amount,
      'error_code': errorCode,
      'description': description,
    },
  );

  /// Razorpay handed off to an external wallet app (the wallet catches up).
  static void externalWallet({
    required String orderId,
    required num amount,
    String? wallet,
  }) => Analytics.log('payment_external_wallet', {
    'order_id': orderId,
    'amount': amount,
    'wallet': wallet,
  });

  /// The backend's verification answer (`success`, `pending`, `failed`).
  static void verificationResult({
    required String result,
    required String orderId,
    required num amount,
    String? error,
  }) => Analytics.log('payment_verification_result', {
    'result': result,
    'order_id': orderId,
    'amount': amount,
    'error': error,
  });

  /// RN `logPaymentSuccess`: Meta Purchase + `payment_success`, plus
  /// Firebase's recommended `purchase`, once per transaction; and the first
  /// top-up of [userKey] ever (`first_topup`, once per install).
  static void paymentSuccess({
    required String transactionId,
    required double amount,
    required String paymentMethod,
    String? userKey,
  }) {
    // Revenue counts once per transaction on both platforms.
    if (_purchased.add(transactionId)) {
      Analytics.metaPurchase(amount, {
        'transaction_id': transactionId,
        'payment_method': paymentMethod,
      });
      Analytics.firebase('purchase', {
        'currency': _currency,
        'value': amount,
        'transaction_id': transactionId,
        'payment_type': paymentMethod,
        'item_category': 'wallet_recharge',
      });
    }
    Analytics.logOnce('payment_success_$transactionId', 'payment_success', {
      'amount': amount,
      'payment_method': paymentMethod,
      'currency': _currency,
    });
    if (userKey != null) {
      Analytics.logOncePersisted('first_topup_$userKey', 'first_topup', {
        'amount': amount,
        'payment_method': paymentMethod,
        'currency': _currency,
      });
    }
  }

  /// Paid, but the backend has not confirmed it yet.
  static void paymentPending({
    required String orderId,
    required num amount,
    String? reason,
  }) => Analytics.log('payment_pending', {
    'order_id': orderId,
    'amount': amount,
    'reason': reason,
  });

  /// RN `logPaymentFailed`, once per transaction.
  static void paymentFailed({
    required String transactionId,
    required String reason,
    required String paymentMethod,
    num? amount,
  }) => Analytics.logOnce('payment_failed_$transactionId', 'payment_failed', {
    'reason': reason,
    'payment_method': paymentMethod,
    'amount': amount,
  });

  // ── Web checkout ───────────────────────────────────────────────────────

  /// The WebView checkout opened ([kind]: `razorpay`, `payu`).
  static void webCheckoutOpened({required String kind}) =>
      Analytics.log('web_checkout_opened', {'kind': kind});

  /// It closed: `paid`, `failed`, `closed` (by the person), `polled_paid`
  /// / `polled_failed` (PayU polling found the result).
  static void webCheckoutEnded({
    required String kind,
    required String result,
    String? reason,
  }) => Analytics.log('web_checkout_ended', {
    'kind': kind,
    'result': result,
    'reason': reason,
  });

  // ── Payment status ─────────────────────────────────────────────────────

  /// The result card ([status]: `success`, `pending`, `failure`).
  static void paymentStatusShown({
    required String status,
    required String source,
    num? amount,
  }) => Analytics.log('payment_status_shown', {
    'status': status,
    'source': source,
    'amount': amount,
  });

  /// The result card closed (Continue or the backdrop).
  static void paymentStatusClosed({
    required String status,
    required String source,
  }) => Analytics.log('payment_status_closed', {
    'status': status,
    'source': source,
  });

  /// The success burst landed (coin sound + haptic).
  static void celebrationShown() => Analytics.log('payment_celebration_shown');

  // ── Offers ─────────────────────────────────────────────────────────────

  /// RN `logFirstTopupOfferShown`.
  static void firstTopupOfferShown({required num percent, int? suggested}) =>
      Analytics.log('first_topup_offer_shown', {
        'percent': percent,
        'suggested_amount': suggested,
      });

  /// An amount picked inside the first-top-up sheet.
  static void firstTopupOfferOption({required int amount, num? percent}) =>
      Analytics.log('first_topup_offer_option', {
        'amount': amount,
        'percent': percent,
      });

  /// RN `logFirstTopupOfferTapped`.
  static void firstTopupOfferTapped({
    required num percent,
    required int amount,
  }) => Analytics.log('first_topup_offer_tapped', {
    'percent': percent,
    'amount': amount,
  });

  static void firstTopupOfferDismissed({required num percent}) =>
      Analytics.log('first_topup_offer_dismissed', {'percent': percent});

  /// RN `abandon_offer_shown` / `abandon_offer_accepted`, plus dismissed.
  static void abandonOffer({
    required String action,
    required String orderId,
    required num amount,
    required num percent,
  }) => Analytics.log('abandon_offer_$action', {
    'order_id': orderId,
    'amount': amount,
    'percent': percent,
  });

  // ── Transactions ───────────────────────────────────────────────────────

  static void transactionsTab(String tab) =>
      Analytics.log('transactions_tab_selected', {'tab': tab});

  static void transactionsLoadMore({required String tab, required int page}) =>
      Analytics.log('transactions_load_more', {'tab': tab, 'page': page});

  /// The tab loaded with nothing in it.
  static void transactionsEmpty(String tab) =>
      Analytics.log('transactions_empty', {'tab': tab});

  /// A page could not be loaded ([page] 1: the list shows a retry).
  static void transactionsLoadFailed({
    required String tab,
    required int page,
    required String error,
  }) => Analytics.log('transactions_load_failed', {
    'tab': tab,
    'page': page,
    'error': error,
  });

  /// "Invoice" on a transaction. [result]: `opened`, `shown_url`
  /// (no app could open it), `not_ready`, `failed`.
  static void invoiceTapped({
    required String type,
    required String result,
    String? error,
  }) => Analytics.log('transaction_invoice_tapped', {
    'type': type,
    'result': result,
    'error': error,
  });

  // ── Earnings → cash transfer (hosts) ───────────────────────────────────

  static void transferOpened({
    String? source,
    required num earnings,
    required num cash,
  }) => Analytics.log('transfer_sheet_opened', {
    'source': source,
    'earnings': earnings,
    'cash': cash,
  });

  /// A quick amount: a percent of earnings (100 = Max).
  static void transferPreset(int percent) =>
      Analytics.log('transfer_amount_preset', {'percent': percent});

  /// Confirm refused locally (`below_min`, `exceeds_earnings`).
  static void transferInvalid({required String reason, required num amount}) =>
      Analytics.log('transfer_invalid', {'reason': reason, 'amount': amount});

  /// The "cash is call credit" warning answered.
  static void transferWarning({required bool accepted, required num amount}) =>
      Analytics.log('transfer_warning', {
        'result': accepted ? 'accepted' : 'cancelled',
        'amount': amount,
      });

  static void transferSubmitted({required num amount, num? gstPercent}) =>
      Analytics.log('transfer_submitted', {
        'amount': amount,
        'gst_percent': gstPercent,
      });

  static void transferSuccess({required num amount}) =>
      Analytics.log('transfer_success', {'amount': amount});

  static void transferFailed({required num amount, required String error}) =>
      Analytics.log('transfer_failed', {'amount': amount, 'error': error});

  static void transferClosed({required bool done}) => Analytics.log(
    'transfer_sheet_closed',
    {'result': done ? 'done' : 'closed'},
  );

  // ── Payout account (no account / IFSC / UPI values, ever) ──────────────

  /// [state]: `form`, `pending`, `verified`, `loading`, `error`.
  static void bankSheetOpened({required String state}) =>
      Analytics.log('bank_sheet_opened', {'state': state});

  /// Local validation stopped the submit ([fields]: which ones, by name).
  static void bankFormInvalid({required List<String> fields}) => Analytics.log(
    'bank_form_invalid',
    {'fields': fields.join(','), 'count': fields.length},
  );

  static void bankSubmitted({required bool hasUpi}) =>
      Analytics.log('bank_details_submitted', {'has_upi': hasUpi});

  static void bankSaved({required bool hasUpi}) =>
      Analytics.log('bank_details_saved', {'has_upi': hasUpi});

  static void bankSaveFailed({required String error}) =>
      Analytics.log('bank_details_save_failed', {'error': error});

  /// A proof photo ([doc]: `bank_proof`, `pan_front`, `pan_back`) was picked
  /// from the [origin] (`gallery`/`camera`); [picked] false = cancelled.
  static void bankDocPicked({
    required String doc,
    required String origin,
    required bool picked,
  }) => Analytics.log('bank_doc_picked', {
    'doc': doc,
    'origin': origin,
    'picked': picked,
  });

  static void bankDocUploaded({required String doc}) =>
      Analytics.log('bank_doc_uploaded', {'doc': doc});

  static void bankDocUploadFailed({
    required String doc,
    required String error,
  }) => Analytics.log('bank_doc_upload_failed', {'doc': doc, 'error': error});

  /// A saved account's status ([status]: `pending`, `verified`).
  static void bankStatusViewed({
    required String status,
    required bool hasUpi,
  }) => Analytics.log('bank_status_viewed', {
    'status': status,
    'has_upi': hasUpi,
  });

  /// "Contact support" to change the payout account (Meta `Contact`).
  static void bankSupportTapped({required bool mailOpened}) {
    Analytics.log('bank_support_tapped', {'mail_opened': mailOpened});
    Analytics.meta('Contact', {'topic': 'bank_account'});
  }
}
