import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/instant_call/instant_call_api.dart';
import 'package:vibelive/app/homescreen/discover/talk_now_button.dart';
import 'package:vibelive/core/network/api_exception.dart';

import 'host_onboarding_support/harness.dart';

/// Talk Now: shown only while the server has it on for this user, and its
/// refusals in the user's own words.
void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });

  Future<void> open(WidgetTester tester) async {
    phone(tester);
    await pumpRoutes(
      tester,
      const Scaffold(body: Column(children: [TalkNowButton()])),
    );
    await pumpFor(tester, 400);
  }

  Finder button() => find.byType(GestureDetector);

  testWidgets('hidden while the server has Talk Now off', (tester) async {
    await resetHost();
    await open(tester);
    expect(button(), findsNothing);
    await finishHost(tester);
  });

  testWidgets('shown once the server has it on', (tester) async {
    final backend = await resetHost();
    backend.instantConfig = {
      'enabled': true,
      'allowedCallTypes': 'voice_only',
      'callerVoiceRate': 10,
    };
    await open(tester);
    expect(button(), findsWidgets);
    await finishHost(tester);
  });

  test('nobody free: "no one is free", not "invalid response"', () async {
    await resetHost();
    await expectLater(
      InstantCallApi.initiate(callerId: 1),
      throwsA(
        isA<ApiException>().having(
          (e) => e.messageKey,
          'messageKey',
          InstantCallErrorKeys.noHosts,
        ),
      ),
    );
  });

  test("the server's refusals map to our own translated copy", () {
    ApiException e(ApiErrorType t, String msg, [Object? data]) =>
        ApiException(t, serverMessage: msg, data: data);
    expect(
      InstantCallApi.knownErrorKey(
        e(ApiErrorType.rejected, 'Insufficient balance.', {
          'code': 'LOW_BALANCE',
        }),
      ),
      InstantCallErrorKeys.lowBalance,
    );
    expect(
      InstantCallApi.knownErrorKey(
        e(ApiErrorType.rejected, 'Talk Now is currently disabled.'),
      ),
      InstantCallErrorKeys.disabled,
    );
    expect(
      InstantCallApi.knownErrorKey(e(ApiErrorType.forbidden, 'Forbidden')),
      InstantCallErrorKeys.disabled,
    );
    expect(
      InstantCallApi.knownErrorKey(
        e(
          ApiErrorType.rejected,
          'You already have an active Talk Now session.',
        ),
      ),
      InstantCallErrorKeys.alreadyActive,
    );
    expect(
      InstantCallApi.knownErrorKey(e(ApiErrorType.server, 'boom')),
      isNull,
    );
  });
}
