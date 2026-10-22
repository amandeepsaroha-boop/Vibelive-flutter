import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/utils/log.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../api/paymentscreen/payment_queries.dart';
import 'call_alerts.dart';
import 'call_controller.dart';
import 'call_identity.dart';
import 'call_session.dart';
import 'call_timers.dart';
import 'state/call_constants.dart';

/// When a paid call must end (decision 8, spec §9.5). The server bills
/// `max(1, ceil(t/60)) × rate` at Callend and rolls back with a 500 (the
/// call then stays "ongoing" forever, E-83) when the cash wallet can't
/// cover it, so the caller ends inside the last affordable minute.
@immutable
class MaxDuration {
  const MaxDuration({required this.end, required this.warnAt});

  /// After connect: hang up here.
  final Duration end;

  /// After connect: the "about 5 minutes left" toast ([Duration.zero]:
  /// right away).
  final Duration warnAt;

  /// Null = no cap: a company caller, or no rate (free call).
  static MaxDuration? compute({
    required double cashBalance,
    required double ratePerMin,
    bool company = false,
  }) {
    if (company || !ratePerMin.isFinite || ratePerMin <= 0) return null;
    final cash = cashBalance.isFinite ? math.max(0.0, cashBalance) : 0.0;
    final affordableMinutes = (cash / ratePerMin).floor();
    var end =
        Duration(minutes: affordableMinutes) - CallTimings.maxDurationMargin;
    // The Agora token dies 1 h after initiate anyway (no renew route).
    final tokenCap = CallTimings.tokenLifetime - CallTimings.maxDurationMargin;
    if (end > tokenCap) end = tokenCap;
    if (end.isNegative) end = Duration.zero;
    final warn = end - CallTimings.lowBalanceWarning;
    return MaxDuration(
      end: end,
      warnAt: warn.isNegative ? Duration.zero : warn,
    );
  }
}

/// Arms the max-duration timer for the caller at connect.
abstract final class CallBilling {
  /// Per-minute rate of each outgoing call (the host card's), by call id.
  static final _rates = <String, double>{};
  static String? _warned;

  /// The "about 5 minutes left" toast, once per call (our timer or the
  /// backend's `LOW_BALANCE_WARNING` hint, whichever comes first).
  static void warnOnce(String callId) {
    if (_warned == callId) return;
    final live = CallController.instance.value;
    if (!live.isSameCall(callId) || !live.phase.isLive) return;
    _warned = callId;
    CallAlerts.toast(CallFlowKeys.lowBalanceWarning);
  }

  static void rememberRate(String callId, double ratePerMin) =>
      _rates[callId] = ratePerMin;

  /// Caller only; reads the cash balance now. [onLimit] hangs up. A failed
  /// read leaves the call uncapped (the backend's low-balance cron is the
  /// backstop).
  static Future<void> arm(
    CallSession call, {
    required void Function() onLimit,
  }) async {
    final callId = call.callId;
    final connectedAt = call.connectedAt;
    if (!call.isCaller || callId == null || connectedAt == null) return;
    final company = call.callerIsCompany || CallIdentity.isCompany;
    if (company) return;
    final uid = CallIdentity.userDocumentId;
    if (uid == null) return;
    try {
      final rate = _rates[callId] ?? await _lookupRate(call);
      if (rate == null || rate <= 0) return;
      final balance = await ensureWalletBalance(userDocumentId: uid);
      final cap = MaxDuration.compute(
        cashBalance: balance.cashBalance,
        ratePerMin: rate,
      );
      final live = CallController.instance.value;
      if (cap == null ||
          !live.isSameCall(callId) ||
          live.phase != CallPhase.ongoing) {
        return;
      }
      final elapsed = DateTime.now().difference(connectedAt);
      final timers = CallTimers.instance;
      timers.arm(CallTimers.maxDuration, cap.end - elapsed, () {
        if (!CallController.instance.value.isSameCall(callId)) return;
        CallAlerts.toast(CallFlowKeys.lowBalanceEnded);
        onLimit();
      });
      if (cap.end > Duration.zero) {
        timers.arm(
          CallTimers.lowBalance,
          cap.warnAt - elapsed,
          () => warnOnce(callId),
        );
      }
    } catch (e) {
      Log.w('CallBilling', 'max duration skipped: $e');
    }
  }

  /// Callback / redial calls have no host card: the host's rates by link.
  static Future<double?> _lookupRate(CallSession call) async {
    final id = call.remote.documentId ?? call.receiverDocId;
    if (id == null) return null;
    final host = await ensureHostByLink(id);
    return call.isVideo ? host.vPrice : host.aPrice;
  }

  static void forget(String? callId) {
    _rates.remove(callId);
    if (_warned == callId) _warned = null;
  }
}
