import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/callscreen/helper/push/push_dedupe.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

PushEnvelope msg(String? id, {DateTime? sentAt}) => PushEnvelope(
  data: const {'type': 'wallet_topup'},
  messageId: id,
  sentAt: sentAt,
);

void main() {
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
  });

  setUp(() => AppPrefs.remove(PushDedupe.storageKey));

  test('the same FCM message id is handled once', () async {
    expect(await PushDedupe.isDuplicate(msg('a')), isFalse);
    expect(await PushDedupe.isDuplicate(msg('a')), isTrue);
    expect(await PushDedupe.isDuplicate(msg('b')), isFalse);
  });

  test('a message without an id is never dropped here', () async {
    expect(await PushDedupe.isDuplicate(msg(null)), isFalse);
    expect(await PushDedupe.isDuplicate(msg(null)), isFalse);
    expect(await PushDedupe.isDuplicate(msg('')), isFalse);
    expect(await PushDedupe.isDuplicate(msg('')), isFalse);
  });

  test('keeps the newest 200 ids', () async {
    for (var i = 0; i < PushDedupe.maxTracked + 1; i++) {
      expect(await PushDedupe.isDuplicate(msg('m$i')), isFalse);
    }
    expect(await PushDedupe.isDuplicate(msg('m0')), isFalse, reason: 'evicted');
    expect(await PushDedupe.isDuplicate(msg('m200')), isTrue);
  });

  test('older than 24 h is too old to draw; unknown send time is fresh', () {
    final now = DateTime(2026, 10, 21, 12);
    expect(
      PushDedupe.isTooOld(
        msg('x', sentAt: now.subtract(const Duration(hours: 25))),
        now: now,
      ),
      isTrue,
    );
    expect(
      PushDedupe.isTooOld(
        msg('x', sentAt: now.subtract(const Duration(hours: 23))),
        now: now,
      ),
      isFalse,
    );
    expect(PushDedupe.isTooOld(msg('x'), now: now), isFalse);
  });
}
