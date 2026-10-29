import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_alert.dart';
import '../../../hosthub/onboarding/helper/host_funnel.dart';
import 'me_data.dart';

/// The signed-in host's availability, from anywhere (the dock's sheet,
/// Discover's banner) and with no widget alive: the sheet closes on the tap
/// and the save carries on here.
///
/// - [pending]: the mode being saved, shown at once (optimistic) until the
///   re-read session carries it; a failure alerts and falls back.
/// - Offline timer: [goOffline] with a duration keeps [offlineUntil] (on disk,
///   so it survives a restart) and puts the host back online when it ends —
///   while the app runs, or on the next launch / resume after that. The
///   backend has no timed offline: a closed app can't come back on its own.
abstract final class HostAvailabilityController {
  static const _untilKey = 'host_offline_until';
  static const _tick = Duration(seconds: 1);

  static final pending = ValueNotifier<HostAvailability?>(null);
  static final offlineUntil = ValueNotifier<DateTime?>(_readUntil());

  /// Time left on the offline timer, ticking once a second while it runs.
  static final remaining = ValueNotifier<Duration?>(null);

  /// Tests move time forward with this.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Timer? _ticker;
  static bool _attached = false;
  static bool _saving = false;

  /// The user whose timer [offlineUntil] is. Stored with it: on a phone
  /// shared by several accounts, a timer must never put the next one online.
  static String? _owner;

  /// From the host dock, whenever it mounts (so after an account switch
  /// too): resumes the countdown and catches a timer that ended while the
  /// app was closed or in the background; on resume as well.
  static void attach() {
    if (!_attached) {
      _attached = true;
      AppLifecycleListener(onResume: _check);
    }
    _check();
  }

  /// The mode shown: the one being saved, else the session's.
  static HostAvailability current(MeData data) =>
      pending.value ?? data.availability;

  /// Saves [next]. Any explicit choice ends a running offline timer.
  /// [source]: where it was picked (analytics).
  static Future<void> set(
    HostAvailability next, {
    String source = 'unknown',
  }) async {
    HostEvents.statusChanged(
      status: hostStatusName(next),
      duration: 'indefinite',
      source: source,
    );
    await _clearTimer();
    await _save(next);
  }

  /// Offline for [duration] (null: until switched back by hand).
  /// [durationLabel]: its analytics name (`30m`, `till_9am`…).
  static Future<void> goOffline(
    Duration? duration, {
    String? durationLabel,
    String source = 'unknown',
  }) async {
    HostEvents.statusChanged(
      status: 'offline',
      duration: duration == null
          ? 'indefinite'
          : durationLabel ?? '${duration.inMinutes}m',
      source: source,
    );
    await _clearTimer();
    if (duration != null) {
      final until = clock().add(duration);
      _owner = SessionStore.instance.value.userDocumentId;
      offlineUntil.value = until;
      await AppPrefs.setString(_untilKey, '$_owner|${until.toIso8601String()}');
      _startTicker();
    }
    await _save(HostAvailability.vacation);
  }

  /// Until the next 9 AM (today's when it is still early, else tomorrow's).
  static Duration untilMorning([DateTime? now]) {
    final t = now ?? clock();
    final today = DateTime(t.year, t.month, t.day, 9);
    final next = t.isBefore(today)
        ? today
        : DateTime(t.year, t.month, t.day + 1, 9);
    return next.difference(t);
  }

  /// One save at a time: a choice made while one saves is saved after it
  /// (only the last of several), so the last tap is what the server keeps.
  static Future<void> _save(HostAvailability next) async {
    final data = MeData.of(SessionStore.instance.value);
    final expertId = data.expertId;
    if (expertId == null) {
      await CAlert.show(
        title: 'client:me.availability.error_title',
        message: 'client:me.availability.no_profile',
        variant: CAlertVariant.warning,
      );
      return;
    }
    if (pending.value == null && data.availability == next) return;
    pending.value = next;
    if (_saving) return;
    _saving = true;
    try {
      var want = next;
      while (true) {
        try {
          await updateHostAvailability(expertId, want);
          HostEvents.statusSaved(status: hostStatusName(want));
        } on ApiException catch (e) {
          HostEvents.statusSaveFailed(
            status: hostStatusName(want),
            error: Analytics.errorCode(e),
          );
          unawaited(
            CAlert.error(e, title: 'client:me.availability.error_title'),
          );
        }
        final latest = pending.value;
        if (latest == null || latest == want) break;
        want = latest;
      }
      pending.value = null;
    } finally {
      _saving = false;
    }
  }

  static bool get _mine =>
      _owner != null && _owner == SessionStore.instance.value.userDocumentId;

  static void _check() {
    final until = offlineUntil.value;
    if (until == null) return;
    if (!_mine) {
      unawaited(_clearTimer()); // another account's: drop it, change nothing
      return;
    }
    if (clock().isBefore(until)) {
      _startTicker();
      return;
    }
    unawaited(_expire());
  }

  /// The timer ran out: back online, unless the host moved off offline.
  static Future<void> _expire() async {
    final mine = _mine;
    await _clearTimer();
    if (!mine) return;
    final data = MeData.of(SessionStore.instance.value);
    if (data.isExpert && data.availability == HostAvailability.vacation) {
      HostEvents.autoBackOnline();
      await _save(HostAvailability.available);
    }
  }

  static void _startTicker() {
    _ticker?.cancel();
    void tick() {
      final until = offlineUntil.value;
      if (until == null) return;
      final left = until.difference(clock());
      if (left <= Duration.zero) {
        unawaited(_expire());
      } else {
        remaining.value = left;
      }
    }

    tick();
    _ticker = Timer.periodic(_tick, (_) => tick());
  }

  static Future<void> _clearTimer() async {
    _ticker?.cancel();
    _ticker = null;
    remaining.value = null;
    _owner = null;
    if (offlineUntil.value == null) return;
    offlineUntil.value = null;
    await AppPrefs.remove(_untilKey);
  }

  /// Tests: no timer, nothing saving.
  @visibleForTesting
  static Future<void> reset() async {
    clock = DateTime.now;
    pending.value = null;
    _saving = false;
    await _clearTimer();
  }

  /// `userDocumentId|ISO time`; anything else (no owner) is dropped.
  static DateTime? _readUntil() {
    final raw = AppPrefs.getString(_untilKey);
    final at = raw?.indexOf('|') ?? -1;
    if (raw == null || at <= 0) return null;
    _owner = raw.substring(0, at);
    return DateTime.tryParse(raw.substring(at + 1));
  }
}

/// "1h 20m", "29m 10s", "45s" (the mockup's countdown).
String formatOfflineLeft(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
