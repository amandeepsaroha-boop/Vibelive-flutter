import 'package:intl/intl.dart';

import '../../../core/network/strapi.dart';

/// Host dashboard figures from `/user-statistics` (RN `normalizeHostStats`).
/// Everything is aggregated server-side; percentages arrive as bare numbers
/// (42.5 = 42.5%). A renamed or missing field reads as 0, never NaN.
class HostStats {
  const HostStats(this.raw, {this.hasRecord = true});

  /// Zeros, so the dashboard renders its structure before the first fetch.
  static const empty = HostStats({}, hasRecord: false);

  final JsonMap raw;

  /// False when the backend has no stats row (non-host, or no activity yet).
  final bool hasRecord;

  /// v4 (`attributes`) or v5 (flat) row.
  factory HostStats.fromRow(dynamic row) {
    final m = Strapi.map(row);
    return m == null ? empty : HostStats(m);
  }

  factory HostStats.fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json! as Map);
    final raw = m['raw'];
    return HostStats(
      raw is Map ? Map<String, dynamic>.from(raw) : const {},
      hasRecord: m['hasRecord'] == true,
    );
  }

  Object toJson() => {'raw': raw, 'hasRecord': hasRecord};

  double _n(String k) => _finite(J.number(raw[k]));

  // Insights
  double get profileViews => _n('total_profile_views');
  double get averageRating => _n('average_rating');
  double get totalReferrals => _n('total_referrals');
  double get conversion => _n('profile_view_to_call_conversion');
  double get missedCallPct => _n('missed_call_percentage');
  double get declinedCallPct => _n('declined_call_percentage');
  // Revenue
  double get totalEarnings => _n('total_earnings');
  double get withdrawals => _n('total_amount_withdrawal');
  double get videoEarnings => _n('total_earnings_from_video_calls');
  double get audioEarnings => _n('total_earnings_from_audio_calls');
  double get referralEarnings => _n('total_earnings_from_referrals');
  // Calls
  double get totalCalls => _n('total_incoming_calls');
  double get avgIncomingMinutes => _n('avg_incoming_call_minutes');
  double get avgOutgoingMinutes => _n('avg_outgoing_call_minutes');
  double get audioCalls => _n('total_incoming_audio_calls');
  double get videoMinutes => _n('total_incoming_video_minutes');
  // Retention
  double get repeatCallerPct => _n('repeat_caller_percentage');
  double get repeatCalls => _n('total_repeat_incoming_calls');
  double get repeatCallers => _n('total_repeat_callers');
  double get repeatCallPct => _n('repeat_incoming_call_percentage');

  // ── Formatters (en-IN grouping, like the rest of the app: 1,00,000) ────
  static String formatNumber(num value) =>
      NumberFormat.decimalPattern('en_IN').format(_finite(value));

  /// Whole rupees unless there are paise.
  static String formatCurrency(num value) {
    final n = _finite(value);
    final hasPaise = (n * 100).round() % 100 != 0;
    final f = NumberFormat.decimalPattern('en_IN')
      ..minimumFractionDigits = hasPaise ? 2 : 0
      ..maximumFractionDigits = 2;
    return '₹${f.format(n)}';
  }

  /// One decimal at most: 42.46 → `42.5%`, 42 → `42%`.
  static String formatPercent(num value) {
    final r = (_finite(value) * 10).round() / 10;
    return '${r == r.truncateToDouble() ? r.toInt() : r}%';
  }

  /// Fractional minutes → whole minutes and seconds (UI adds the units).
  static ({int minutes, int seconds}) splitMinutes(num minutes) {
    final total = (_finite(minutes) * 60).round();
    return (minutes: total ~/ 60, seconds: total % 60);
  }

  static double _finite(num? v) => v != null && v.isFinite ? v.toDouble() : 0;
}
