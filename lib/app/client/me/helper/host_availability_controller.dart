import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_alert.dart';
import 'me_data.dart';

/// The signed-in host's availability, from anywhere (sheet, dock, Profile
/// card) and with no widget alive: the sheet closes on the tap and the save
/// carries on here.
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

  static Timer? _ticker;
  static bool _attached = false;
  static bool _saving = false;

  /// Once, from the host dock: resumes the countdown and catches a timer
  /// that ended while the app was closed or in the background.
  static void attach() {
    if (_attached) return;
    _attached = true;
    AppLifecycleListener(onResume: _check);
    _check();
  }

  /// The mode shown: the one being saved, else the session's.
  static HostAvailability current(MeData data) =>
      pending.value ?? data.availability;

  /// Saves [next]. Any explicit choice ends a running offline timer.
  static Future<void> set(HostAvailability next) async {
    await _clearTimer();
    await _save(next);
  }

  /// Offline for [duration] (null: until switched back by hand).
  static Future<void> goOffline(Duration? duration) async {
    await _clearTimer();
    if (duration != null) {
      final until = DateTime.now().add(duration);
      offlineUntil.value = until;
      await AppPrefs.setString(_untilKey, until.toIso8601String());
      _startTicker();
    }
    await _save(HostAvailability.vacation);
  }

  /// Until the next 9 AM (today's when it is still early, else tomorrow's).
  static Duration untilMorning([DateTime? now]) {
    final t = now ?? DateTime.now();
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
        } on ApiException catch (e) {
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

  static void _check() {
    final until = offlineUntil.value;
    if (until == null) return;
    if (DateTime.now().isBefore(until)) {
      _startTicker();
      return;
    }
    unawaited(_expire());
  }

  /// The timer ran out: back online, unless the host moved off offline.
  static Future<void> _expire() async {
    await _clearTimer();
    final data = MeData.of(SessionStore.instance.value);
    if (data.isExpert && data.availability == HostAvailability.vacation) {
      await _save(HostAvailability.available);
    }
  }

  static void _startTicker() {
    _ticker?.cancel();
    void tick() {
      final until = offlineUntil.value;
      if (until == null) return;
      final left = until.difference(DateTime.now());
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
    if (offlineUntil.value == null) return;
    offlineUntil.value = null;
    await AppPrefs.remove(_untilKey);
  }

  /// Tests: no timer, nothing saving.
  @visibleForTesting
  static Future<void> reset() async {
    pending.value = null;
    _saving = false;
    await _clearTimer();
  }

  static DateTime? _readUntil() {
    final raw = AppPrefs.getString(_untilKey);
    return raw == null ? null : DateTime.tryParse(raw);
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
