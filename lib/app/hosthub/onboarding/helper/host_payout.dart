import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/config/runtime_config.dart';
import '../../../../core/network/strapi.dart';
import '../../../api/paymentscreen/billing_models.dart';

/// What the platform keeps from one call, as the backend bills it at call
/// end (`src/api/call/controllers/call.js`, "Commission & Payout"):
///
/// - fee = the larger of [percent] of the call's cost and [minimumPerCall];
/// - the host gets the rest.
///
/// The minimum is per call, not per minute: it only matters on very short
/// calls, where the percentage comes to less than it.
@immutable
class HostPayoutTerms {
  const HostPayoutTerms({required this.percent, required this.minimumPerCall});

  /// Platform fee, % of the call's cost.
  final double percent;

  /// The fee is never less than this, per call (₹).
  final double minimumPerCall;

  /// What the host gets for a call of [minutes] at [rate] ₹/min.
  double forCall(num rate, int minutes) {
    final cost = (rate * minutes).toDouble();
    final fee = math.min(math.max(cost * percent / 100, minimumPerCall), cost);
    return cost - fee;
  }

  /// Per minute, once the call is long enough for the percentage to apply
  /// (every call but the shortest).
  double perMinute(num rate) =>
      math.max(0, rate * (1 - percent / 100)).toDouble();

  /// The minimum fee bites on calls shorter than this many minutes.
  int minutesBeforePercentApplies(num rate) {
    final perMinuteFee = rate * percent / 100;
    if (perMinuteFee <= 0) return 0;
    return (minimumPerCall / perMinuteFee).ceil();
  }

  @override
  bool operator ==(Object other) =>
      other is HostPayoutTerms &&
      other.percent == percent &&
      other.minimumPerCall == minimumPerCall;

  @override
  int get hashCode => Object.hash(percent, minimumPerCall);
}

/// A call format's two fee levels: callers in general, and callers who
/// signed up with the host's own invite code (the backend's "referral
/// call"). Each referral field the admin left empty falls back to the
/// standard one, as billing does.
@immutable
class HostRatePayout {
  const HostRatePayout({required this.standard, required this.invite});

  /// From the config: the standard % from `/app-config` (it carries an
  /// app's own override, which billing uses), the per-call minimums and the
  /// invite-link fields from `/pricing-config`.
  factory HostRatePayout.from(
    RuntimeConfig runtime,
    PricingConfig pricing, {
    required bool video,
  }) {
    double? field(String key) {
      final v = J.number(pricing.raw[key]);
      return v != null && v.isFinite ? v : null;
    }

    final standard = HostPayoutTerms(
      percent: video
          ? runtime.pricing.videoCommissionPercent
          : runtime.pricing.voiceCommissionPercent,
      minimumPerCall: video
          ? pricing.minimumVideoCommissionFixed
          : pricing.minimumVoiceCommissionFixed,
    );
    final invite = HostPayoutTerms(
      percent:
          field(
            video
                ? 'Referral_VideoCall_Percentage_Commission'
                : 'Referral_VoiceCall_Percentage_Commission',
          ) ??
          standard.percent,
      minimumPerCall:
          field(
            video
                ? 'Referral_Minimum_videoCall_Commission_Fixed'
                : 'Referral_Minimum_VoiceCall_Commission_Fixed',
          ) ??
          standard.minimumPerCall,
    );
    return HostRatePayout(standard: standard, invite: invite);
  }

  final HostPayoutTerms standard;
  final HostPayoutTerms invite;

  /// Invite-link callers are worth showing apart only when they pay more.
  bool get inviteIsBetter => invite.percent < standard.percent;

  @override
  bool operator ==(Object other) =>
      other is HostRatePayout &&
      other.standard == standard &&
      other.invite == invite;

  @override
  int get hashCode => Object.hash(standard, invite);
}

/// ₹ amounts the way the earnings screens show them: whole rupees without
/// decimals, anything else with two.
String rupees(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
