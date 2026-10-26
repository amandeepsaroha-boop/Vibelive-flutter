import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../network/strapi.dart';

/// Pricing limits read from config (RN `runtime-config.js` `pricing`).
@immutable
class RuntimePricing {
  const RuntimePricing({
    this.voiceCommissionPercent = 40,
    this.videoCommissionPercent = 40,
    this.minVoiceCallRate = 7,
    this.minVideoCallRate = 12,
    this.minBalanceVoiceCall = 20,
    this.minBalanceVideoCall = 20,
    this.minMinutesToInitiate = 5,
    this.minAmountToAddWallet = 20,
    this.minAmountToWithdrawal = 100,
  });

  final double voiceCommissionPercent;
  final double videoCommissionPercent;
  final double minVoiceCallRate;
  final double minVideoCallRate;
  final double minBalanceVoiceCall;
  final double minBalanceVideoCall;

  /// The cash wallet must cover this many minutes before a call starts.
  final double minMinutesToInitiate;
  final double minAmountToAddWallet;
  final double minAmountToWithdrawal;
}

/// Bonus flags (RN `runtime-config.js` `bonus`). All off by default.
@immutable
class RuntimeBonus {
  const RuntimeBonus({
    this.joiningEnabled = false,
    this.joiningAmount = 0,
    this.joiningExpiryDays = 0,
    this.abandonOfferEnabled = false,
    this.abandonOfferPercent = 0,
    this.abandonOfferWindowMinutes = 0,
    this.firstTopupBonusEnabled = false,
    this.firstTopupBonusPercent = 0,
    this.bonusCreditHostPayoutEnabled = false,
  });

  final bool joiningEnabled;
  final double joiningAmount;
  final double joiningExpiryDays;
  final bool abandonOfferEnabled;
  final double abandonOfferPercent;
  final double abandonOfferWindowMinutes;
  final bool firstTopupBonusEnabled;
  final double firstTopupBonusPercent;
  final bool bonusCreditHostPayoutEnabled;

  bool get firstTopupOn => firstTopupBonusEnabled && firstTopupBonusPercent > 0;
  bool get abandonOfferOn => abandonOfferEnabled && abandonOfferPercent > 0;
}

/// The single source for every pricing-derived number (RN
/// `runtime-config.js`). Every default is the literal the app shipped with,
/// so a failed or missing fetch changes nothing and no figure can read 0 or
/// NaN. Derive, never duplicate: use [CallRequirement] and
/// [topUpSuggestion] instead of doing the arithmetic at a call site.
@immutable
class RuntimeConfig {
  const RuntimeConfig({
    this.pricing = const RuntimePricing(),
    this.bonus = const RuntimeBonus(),
    this.presetAmounts = defaultPresets,
    this.gstPercent = 18,
    this.configVersion,
    this.ttlSeconds = 900,
  });

  static const defaults = RuntimeConfig();
  static const defaultPresets = [50, 100, 500, 750, 1000, 1500];

  final RuntimePricing pricing;
  final RuntimeBonus bonus;

  /// Add-money quick-select amounts, ascending, never empty.
  final List<int> presetAmounts;

  /// GST added on top of a wallet top-up.
  final double gstPercent;
  final String? configVersion;

  /// How long a fetched config stays fresh (server-supplied).
  final double ttlSeconds;

  Duration get ttl => Duration(milliseconds: (ttlSeconds * 1000).round());

  /// Resolves the config from the `/app-config` body ([appConfig], RN's
  /// source) and the `/pricing-config` row ([pricingConfig]). The first one
  /// carrying a `pricing` / `bonus` / `presetAmounts` block wins; a legacy
  /// flat pricing row only fills the wallet minimum and rate floors.
  factory RuntimeConfig.resolve(Object? appConfig, [Object? pricingConfig]) {
    final server = _unwrap(appConfig) ?? _unwrap(pricingConfig);
    final legacy = Strapi.map(pricingConfig) ?? const <String, dynamic>{};
    const d = RuntimeConfig.defaults;
    const dp = RuntimePricing();
    const db = RuntimeBonus();
    final sp = Strapi.map(server?['pricing']) ?? const <String, dynamic>{};
    final sb = Strapi.map(server?['bonus']) ?? const <String, dynamic>{};

    double p(String key, double fallback, [String? legacyKey]) =>
        _num(_pick(sp, key)) ??
        (legacyKey == null ? null : _positive(legacy[legacyKey])) ??
        fallback;
    double b(String key, double fallback) => _num(_pick(sb, key)) ?? fallback;
    bool flag(String key, bool fallback) {
      final v = _pick(sb, key);
      return v == null ? fallback : J.boolean(v);
    }

    final presets = <int>{
      for (final v
          in (server?['presetAmounts'] is List
              ? server!['presetAmounts'] as List
              : const []))
        if (_positive(v) case final n?) n.round(),
    }.toList()..sort();

    return RuntimeConfig(
      pricing: RuntimePricing(
        voiceCommissionPercent: p(
          'voiceCommissionPercent',
          dp.voiceCommissionPercent,
        ),
        videoCommissionPercent: p(
          'videoCommissionPercent',
          dp.videoCommissionPercent,
        ),
        minVoiceCallRate: p(
          'minVoiceCallRate',
          dp.minVoiceCallRate,
          'Minimum_voiceCall_Rate',
        ),
        minVideoCallRate: p(
          'minVideoCallRate',
          dp.minVideoCallRate,
          'Minimum_videoCall_Rate',
        ),
        minBalanceVoiceCall: p('minBalanceVoiceCall', dp.minBalanceVoiceCall),
        minBalanceVideoCall: p('minBalanceVideoCall', dp.minBalanceVideoCall),
        minMinutesToInitiate: p(
          'minMinutesToInitiate',
          dp.minMinutesToInitiate,
        ),
        minAmountToAddWallet: p(
          'minAmountToAddWallet',
          dp.minAmountToAddWallet,
          'Minimum_Amount_to_add_wallet',
        ),
        minAmountToWithdrawal: p(
          'minAmountToWithdrawal',
          dp.minAmountToWithdrawal,
          'Minimum_Amount_To_Withdrawal',
        ),
      ),
      bonus: RuntimeBonus(
        joiningEnabled: flag('joiningEnabled', db.joiningEnabled),
        joiningAmount: b('joiningAmount', db.joiningAmount),
        joiningExpiryDays: b('joiningExpiryDays', db.joiningExpiryDays),
        abandonOfferEnabled: flag(
          'abandonOfferEnabled',
          db.abandonOfferEnabled,
        ),
        abandonOfferPercent: b('abandonOfferPercent', db.abandonOfferPercent),
        abandonOfferWindowMinutes: b(
          'abandonOfferWindowMinutes',
          db.abandonOfferWindowMinutes,
        ),
        firstTopupBonusEnabled: flag(
          'firstTopupBonusEnabled',
          db.firstTopupBonusEnabled,
        ),
        firstTopupBonusPercent: b(
          'firstTopupBonusPercent',
          db.firstTopupBonusPercent,
        ),
        bonusCreditHostPayoutEnabled: flag(
          'bonusCreditHostPayoutEnabled',
          db.bonusCreditHostPayoutEnabled,
        ),
      ),
      presetAmounts: presets.isEmpty ? d.presetAmounts : presets,
      gstPercent: _num(server?['gstPercent']) ?? d.gstPercent,
      configVersion: J.str(server?['configVersion']),
      ttlSeconds: _positive(server?['ttlSeconds']) ?? d.ttlSeconds,
    );
  }

  /// RN `isRuntimeConfigStale`: no timestamp counts as stale.
  bool isStale(DateTime? savedAt, {DateTime? now}) =>
      savedAt == null || (now ?? DateTime.now()).difference(savedAt) > ttl;

  /// The cache wrapper and the Strapi envelope alike.
  static Map<String, dynamic>? _unwrap(Object? node) {
    Object? current = node;
    for (var depth = 0; depth < 4; depth++) {
      if (current is! Map) return null;
      if (current['pricing'] != null ||
          current['bonus'] != null ||
          current['presetAmounts'] != null) {
        return Map<String, dynamic>.from(current);
      }
      current = current['data'] ?? current['attributes'];
    }
    return null;
  }

  /// `minMinutesToInitiate`, else its snake_case spelling.
  static Object? _pick(Map<String, dynamic> m, String key) =>
      m[key] ??
      m[key.replaceAllMapped(
        RegExp('[A-Z]'),
        (x) => '_${x.group(0)!.toLowerCase()}',
      )];

  /// RN `num`: null / blank / non-finite read as missing.
  static double? _num(Object? v) {
    final n = v is String && v.trim().isEmpty ? null : J.number(v);
    return n != null && n.isFinite ? n : null;
  }

  static double? _positive(Object? v) {
    final n = _num(v);
    return n != null && n > 0 ? n : null;
  }
}

/// The balance a call needs, and how far short the wallet is (RN
/// `computeCallRequirement`). Fails open: an unreadable rate or balance
/// lets the call through, like the gate always did.
@immutable
class CallRequirement {
  const CallRequirement._(this.required, this.gap);

  factory CallRequirement.of({
    required double rate,
    required double minMinutes,
    double? balance,
  }) {
    if (!rate.isFinite || rate <= 0 || !minMinutes.isFinite) {
      return const CallRequirement._(0, 0);
    }
    final required = rate * minMinutes;
    if (balance == null || !balance.isFinite) {
      return CallRequirement._(required, 0);
    }
    return CallRequirement._(required, math.max(0, required - balance));
  }

  final double required;
  final double gap;
  bool get canCall => gap == 0;
}

/// RN `computeTopUpSuggestion`: the gap, lifted to the wallet minimum, in
/// whole rupees. A zero gap still suggests the minimum.
int topUpSuggestion({required double gap, required double minAmountToAdd}) {
  final minimum = minAmountToAdd.isFinite && minAmountToAdd > 0
      ? minAmountToAdd
      : const RuntimePricing().minAmountToAddWallet;
  final target = gap.isFinite && gap > 0 ? gap : minimum;
  return math.max(target.ceil(), minimum.ceil());
}
