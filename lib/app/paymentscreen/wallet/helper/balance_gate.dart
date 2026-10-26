import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/config/runtime_config.dart';

/// What the person picked on the balance gate.
enum BalanceGateAction { addMoney, transferEarnings }

/// The figures of the pre-call balance gate (RN ProfileModal →
/// `BalanceGateSheet`), all derived from config: raise the joining bonus to
/// cover the call minimum and the gap is zero, so the gate never shows.
@immutable
class BalanceGate {
  const BalanceGate({
    required this.balance,
    required this.required,
    required this.gap,
    required this.suggestedAmount,
    required this.earnings,
    required this.rate,
    required this.minutes,
  });

  /// Null when the call may go ahead.
  static BalanceGate? check({
    required double rate,
    required double cash,
    required double earnings,
    required RuntimeConfig config,
  }) {
    final minutes = config.pricing.minMinutesToInitiate;
    final need = CallRequirement.of(
      rate: rate,
      minMinutes: minutes,
      balance: cash,
    );
    if (need.canCall) return null;
    final gap = math.max(0.0, need.required - math.max(0.0, cash));
    return BalanceGate(
      balance: math.max(0, cash),
      required: need.required,
      gap: gap,
      suggestedAmount: topUpSuggestion(
        gap: gap,
        minAmountToAdd: config.pricing.minAmountToAddWallet,
      ),
      earnings: earnings,
      rate: rate,
      minutes: minutes,
    );
  }

  final double balance;
  final double required;
  final double gap;

  /// The gap lifted to the wallet minimum, whole rupees.
  final int suggestedAmount;
  final double earnings;
  final double rate;
  final double minutes;

  /// 0–100, how much of the requirement the wallet already covers.
  int get progressPercent => required > 0
      ? math.min(100, (balance / required * 100).round()).clamp(0, 100)
      : 0;

  bool get hasEarnings => earnings > 0;

  /// Only then is "use earnings instead" worth offering.
  bool get earningsCoversGap => earnings >= gap;

  /// The suggestion is above the gap because of the wallet minimum.
  bool get liftedToMinimum => suggestedAmount > gap;

  Map<String, Object?> get analytics => {
    'required': required,
    'balance': balance,
    'gap': gap,
    'suggested_amount': suggestedAmount,
  };
}
