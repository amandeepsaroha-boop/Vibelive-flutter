import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/paymentscreen/billing_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_payout.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/rates_step.dart';
import 'package:vibelive/core/config/runtime_config.dart';

import 'host_onboarding_support/harness.dart';

/// What a host earns at their rate: billed the way the backend settles a
/// call (`src/api/call/controllers/call.js`), and shown on the Rates step.
void main() {
  group('payout, as the backend bills it', () {
    const voice = HostPayoutTerms(percent: 40, minimumPerCall: 3);

    test('the fee is a percentage of the call, at least the minimum', () {
      expect(voice.forCall(10, 1), 6); // 40% of ₹10 = ₹4 beats ₹3
      expect(voice.forCall(10, 10), 60);
      // At ₹7/min 40% is ₹2.80: a 1-minute call pays the ₹3 minimum...
      expect(voice.forCall(7, 1), closeTo(4, 1e-9));
      // ...but the minimum is per call, so 2 minutes are back to 60%.
      expect(voice.forCall(7, 2), closeTo(8.4, 1e-9));
      expect(voice.perMinute(7), closeTo(4.2, 1e-9));
      expect(voice.minutesBeforePercentApplies(7), 2);
      expect(voice.minutesBeforePercentApplies(10), 1);
    });

    test('never below zero', () {
      const steep = HostPayoutTerms(percent: 40, minimumPerCall: 50);
      expect(steep.forCall(10, 1), 0);
    });

    test('invite-link callers: referral fields, each falling back', () {
      const runtime = RuntimeConfig();
      final full = HostRatePayout.from(
        runtime,
        const PricingConfig({
          'VoiceCall_Percentage_Commission': 40,
          'Minimum_VoiceCall_Commission_Fixed': 3,
          'Referral_VoiceCall_Percentage_Commission': 30,
          'Referral_Minimum_VoiceCall_Commission_Fixed': 1,
        }),
        video: false,
      );
      expect(
        full.invite,
        const HostPayoutTerms(percent: 30, minimumPerCall: 1),
      );
      expect(full.inviteIsBetter, isTrue);

      // No referral fee set: invite callers pay the standard one.
      final none = HostRatePayout.from(
        runtime,
        const PricingConfig({'Minimum_VoiceCall_Commission_Fixed': 3}),
        video: false,
      );
      expect(none.invite, none.standard);
      expect(none.inviteIsBetter, isFalse);
    });

    test("the standard % is app-config's (an app's override), as billing", () {
      final runtime = RuntimeConfig.resolve(const {
        'pricing': {'videoCommissionPercent': 25},
      });
      final video = HostRatePayout.from(
        runtime,
        const PricingConfig({'VideoCall_Percentage_Commission': 40}),
        video: true,
      );
      expect(video.standard.percent, 25);
    });

    test('rupees: whole amounts plain, others with paise', () {
      expect(rupees(60), '60');
      expect(rupees(4.2), '4.20');
    });
  });

  group('the Rates step', () {
    setUpAll(() async {
      await setUpHostHarness();
    });

    late HostDraftController draft;
    setUp(() async {
      await resetHost();
      draft = HostDraftController('rates', persist: false)
        ..audioOn.value = true
        ..videoOn.value = true
        ..audioRate.value = 10
        ..videoRate.value = 20;
    });

    Future<void> open(WidgetTester tester, {Size? size, Locale? locale}) async {
      phone(tester, size: size ?? const Size(390, 844));
      await pumpRoutes(
        tester,
        Scaffold(body: RatesStep(draft: draft)),
        locale: locale ?? const Locale('en'),
      );
      await pumpFor(tester, 400);
    }

    testWidgets('under each rate: what the host earns, live', (tester) async {
      await open(tester);
      expect(find.text('YOU EARN'), findsNWidgets(2));
      // Audio ₹10: 40% fee → ₹6/min; invite link 30% → ₹7/min.
      expect(find.text('₹6'), findsOneWidget);
      expect(
        find.text('Customer pays ₹10/min  •  Platform fee (40%) ₹4/min'),
        findsOneWidget,
      );
      expect(find.text('₹7'), findsOneWidget);
      expect(find.text('INVITE LINK EARNINGS'), findsNWidgets(2));
      // Video ₹20: ₹12/min, ₹14/min by invite.
      expect(find.text('₹12'), findsOneWidget);
      expect(find.text('₹14'), findsOneWidget);

      draft.audioRate.value = 15;
      await tester.pump();
      expect(find.text('₹9'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('off by default; on starts at the backend minimum', (
      tester,
    ) async {
      draft
        ..audioOn.value = false
        ..videoOn.value = false;
      await open(tester);
      expect(find.text('YOU EARN'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('hostflow-switch-hostflow:rates.audio')),
      );
      await pumpFor(tester, 300);
      expect(draft.audioRate.value, 7); // pricing config minimum
      expect(find.text('₹ 7'), findsOneWidget);
      // "−" stops at the minimum; "+" goes to round numbers.
      await tester.tap(find.bySemanticsLabel('Decrease rate').first);
      await tester.pump();
      expect(draft.audioRate.value, 7);
      await tester.tap(find.bySemanticsLabel('Increase rate').first);
      await tester.pump();
      expect(draft.audioRate.value, 10);
      await tester.tap(find.bySemanticsLabel('Increase rate').first);
      await tester.pump();
      expect(draft.audioRate.value, 15);
      await tester.tap(find.bySemanticsLabel('Decrease rate').first);
      await tester.pump();
      expect(draft.audioRate.value, 10);
      await finishHost(tester);
    });

    testWidgets('"How earnings work": the call-length table', (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('See how earnings work'));
      await tester.pump();
      await tester.tap(find.text('See how earnings work'));
      await pumpFor(tester, 600);
      expect(find.text('Audio calls at ₹10/min'), findsOneWidget);
      expect(
        find.text('Platform fee: 40% of each call, at least ₹3 per call.'),
        findsOneWidget,
      );
      expect(find.text('30 min'), findsNWidgets(2));
      expect(find.text('₹300'), findsOneWidget); // audio, 30 min, caller
      expect(find.text('₹180'), findsOneWidget); // audio, 30 min, host
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });

    testWidgets('320 wide in Hindi: no overflow', (tester) async {
      await open(
        tester,
        size: const Size(320, 700),
        locale: const Locale('hi'),
      );
      expect(find.text('आपकी कमाई'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });
  });
}
