import 'package:flutter/widgets.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/config/runtime_config.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../widgets/abandon_offer_sheet.dart';
import '../widgets/first_topup_sheet.dart';
import 'first_topup_offer.dart';

/// The wallet's two bonus prompts (RN WalletScreen). Both derive everything
/// from config: with their flag off, or the percent at 0, they never show.
abstract final class WalletOffers {
  /// First-top-up offer for someone who has never paid in. The amount they
  /// picked, else null.
  static Future<int?> firstTopup(
    BuildContext context, {
    required RuntimeConfig config,
    required Iterable<WalletTransaction> history,
  }) async {
    final bonus = config.bonus;
    if (!bonus.firstTopupOn || FirstTopupOffer.hasPaidTopup(history)) {
      return null;
    }
    final percent = bonus.firstTopupBonusPercent;
    if (!FirstTopupOffer.claimShow(enabled: true, percent: percent)) {
      return null;
    }
    Analytics.log('first_topup_offer_shown', {'percent': percent});
    final chosen = await showFirstTopupSheet(
      context,
      percent: percent,
      presets: config.presetAmounts,
      voiceRate: config.pricing.minVoiceCallRate,
    );
    if (chosen == null) {
      FirstTopupOffer.recordDismissal();
      return null;
    }
    Analytics.log('first_topup_offer_tapped', {
      'percent': percent,
      'amount': chosen,
    });
    return chosen;
  }

  /// Exit-intent offer right after a dismissed checkout, while the intent is
  /// still warm. The amount to check out again, else null.
  static Future<double?> afterAbandon(
    BuildContext context, {
    required RuntimeConfig config,
    required RazorpayCheckout order,
  }) async {
    final bonus = config.bonus;
    final amount = order.baseAmount;
    if (!bonus.abandonOfferOn || !(amount > 0)) return null;
    final percent = bonus.abandonOfferPercent;
    final offer = BonusPreview.of(amount, percent);
    if (offer.bonus <= 0) return null;
    final orderRef = order.txnId.isNotEmpty ? order.txnId : order.orderId;
    final params = {'order_id': orderRef, 'amount': amount, 'percent': percent};
    Analytics.log('abandon_offer_shown', params);
    final accepted = await showAbandonOfferSheet(
      context,
      offer: offer,
      percent: percent,
      windowMinutes: bonus.abandonOfferWindowMinutes,
    );
    if (!accepted) return null;
    Analytics.log('abandon_offer_accepted', params);
    return amount;
  }
}
