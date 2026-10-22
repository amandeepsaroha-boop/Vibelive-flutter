import 'dart:convert';

import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/log.dart';
import 'call_api.dart';
import 'call_errors.dart';

/// Declines (and hang-ups) whose `/call/Callend` failed (e.g. the request
/// was killed while the phone sat locked), kept on disk and replayed on the next VoIP push and
/// app foreground, so the backend learns about the decline even across
/// process death (RN `pendingDeclineQueue.js`).
abstract final class PendingDeclineQueue {
  static const storageKey = 'pending_decline_queue';
  static const maxItems = 20;

  /// Older declines are dropped instead of replayed.
  static const maxAge = Duration(hours: 6);

  static const _tag = 'PendingDeclineQueue';
  static Future<int>? _flushing;

  /// Queued declines, oldest first.
  static List<PendingDecline> get pending => _read();

  /// Queues [input]; replaces an earlier entry for the same call.
  static Future<void> enqueue(CallEndInput input, {DateTime? now}) async {
    if (input.callId.isEmpty) return;
    final at = now ?? DateTime.now();
    // Read-modify-write with no await in between: atomic in this isolate.
    final list = _read().where((d) => d.callId != input.callId).toList()
      ..add(
        PendingDecline(
          body: input.toJson(now: at),
          enqueuedAt: at,
        ),
      );
    await _write(list);
    Log.d(_tag, 'queued decline ${input.callId}');
  }

  /// Queues a `/call/Callend` body built elsewhere (iOS native CallKit
  /// decline / end whose request failed, drained from the native stash).
  /// Replaces an earlier entry for the same call; a body without a call id is
  /// ignored.
  static Future<void> enqueueRaw(
    Map<dynamic, dynamic> body, {
    DateTime? now,
  }) async {
    final copy = <String, dynamic>{
      for (final e in body.entries) '${e.key}': e.value,
    };
    final callId = J.str(copy['callId']);
    if (callId == null) return;
    final at = now ?? DateTime.now();
    final list = _read().where((d) => d.callId != callId).toList()
      ..add(PendingDecline(body: copy, enqueuedAt: at));
    await _write(list);
    Log.d(_tag, 'queued native end $callId');
  }

  /// Replays every queued decline through [send] (default
  /// [CallApi.endCall]) and returns how many reached the backend.
  ///
  /// Failures stay queued. Expired entries are dropped, and so are entries
  /// the backend reports as already closed (replaying them can never
  /// succeed). Concurrent calls share one run.
  static Future<int> flush({
    Future<void> Function(CallEndInput input)? send,
    DateTime Function()? clock,
  }) => _flushing ??= _flush(
    send ?? CallApi.endCall,
    clock ?? DateTime.now,
  ).whenComplete(() => _flushing = null);

  static Future<int> _flush(
    Future<void> Function(CallEndInput input) send,
    DateTime Function() clock,
  ) async {
    final snapshot = _read();
    if (snapshot.isEmpty) return 0;

    final done = <PendingDecline>{};
    var sent = 0;
    for (final item in snapshot) {
      if (clock().difference(item.enqueuedAt) > maxAge) {
        Log.d(_tag, 'dropping expired decline ${item.callId}');
        done.add(item);
        continue;
      }
      try {
        await send(item.input);
        sent++;
        done.add(item);
        Log.d(_tag, 'flushed decline ${item.callId}');
      } catch (e) {
        if (e is ApiException && (e.isBenignDecline || e.isCallAlreadyEnded)) {
          done.add(item);
        }
      }
    }

    // Re-read: a decline may have been queued while we were sending.
    await _write(_read().where((d) => !done.contains(d)).toList());
    return sent;
  }

  static List<PendingDecline> _read() {
    final raw = AppPrefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final item in list) ?PendingDecline.tryParse(item)];
    } on FormatException {
      return [];
    }
  }

  static Future<void> _write(List<PendingDecline> list) {
    if (list.isEmpty) return AppPrefs.remove(storageKey);
    final kept = list.length > maxItems
        ? list.sublist(list.length - maxItems)
        : list;
    return AppPrefs.setString(
      storageKey,
      jsonEncode([for (final d in kept) d.toJson()]),
    );
  }
}

/// One queued decline, stored as `{postData, enqueuedAt}` like RN.
class PendingDecline {
  const PendingDecline({required this.body, required this.enqueuedAt});

  /// The `/call/Callend` body as first built (timestamps included).
  final Map<String, dynamic> body;
  final DateTime enqueuedAt;

  String get callId => J.str(body['callId']) ?? '';

  CallEndInput get input => CallEndInput.fromJson(body);

  static PendingDecline? tryParse(Object? json) {
    if (json is! Map) return null;
    final body = json['postData'];
    if (body is! Map || J.str(body['callId']) == null) return null;
    return PendingDecline(
      body: Map<String, dynamic>.from(body),
      enqueuedAt: DateTime.fromMillisecondsSinceEpoch(
        J.integer(json['enqueuedAt']) ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'postData': body,
    'enqueuedAt': enqueuedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is PendingDecline &&
      other.callId == callId &&
      other.enqueuedAt.millisecondsSinceEpoch ==
          enqueuedAt.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(callId, enqueuedAt.millisecondsSinceEpoch);
}
