import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/client/me/widgets/referral_invite_card.dart';
import 'package:vibelive/app/client/referral/referral_screen.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'referral_support/harness.dart';

/// Scrolls [f] to the middle of the ME list (clear of the navbar), taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  late ReferralBackend backend;

  setUpAll(setUpReferralMocks);
  setUp(() => backend = installBackend());

  const me = '${AppRoutes.home}?tab=me';

  testWidgets('"Referral Activity Log" opens the referral screen', (
    tester,
  ) async {
    backend.joined = [
      {'documentId': 'a', 'name': 'Asha Rao'},
    ];
    await openApp(tester, backend, location: me);
    await pumpMs(tester, 800);
    final card = find.byType(MeReferralInviteCard);
    expect(card, findsOneWidget);
    final link = find.descendant(
      of: card,
      matching: find.text('Referral Activity Log'),
    );
    expect(link, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('client:')),
      findsNothing,
    );

    await _tap(tester, link);
    await pumpMs(tester, 800);
    // Was the logo placeholder: the route had no screen.
    expect(find.byType(ReferralScreen), findsOneWidget);
    expect(find.text('VIBE42'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Referred user'), findsOneWidget);

    // Back on ME, the dashboard's REFERRAL PROGRAM row opens it too.
    appRouter.pop();
    await pumpMs(tester, 800);
    expect(find.byType(ReferralScreen), findsNothing);
    await tester.scrollUntilVisible(
      find.text('REFERRAL PROGRAM'),
      300,
      scrollable: find.descendant(
        of: find.byType(InfiniteScroll),
        matching: find.byType(Scrollable),
      ),
    );
    await _tap(tester, find.text('REFERRAL PROGRAM'));
    await pumpMs(tester, 800);
    expect(find.byType(ReferralScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Hindi: the activity link reads as a log and opens the screen', (
    tester,
  ) async {
    await openApp(tester, backend, location: me, locale: const Locale('hi'));
    await pumpMs(tester, 800);
    final link = find.text('रेफ़रल गतिविधि लॉग');
    expect(link, findsOneWidget);

    await _tap(tester, link);
    await pumpMs(tester, 800);
    expect(find.byType(ReferralScreen), findsOneWidget);
    expect(find.text('आपका रेफ़रल कोड'), findsOneWidget);
    expect(find.text('अभी तक किसी को रेफ़र नहीं किया गया'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('INVITE ALL message interpolates the code and ?r=i link', (
    tester,
  ) async {
    final spy = ShareSpy(tester);
    await openApp(tester, backend, location: me);
    await pumpMs(tester, 800);
    await _tap(tester, find.text('INVITE ALL'));
    await pumpMs(tester, 400);
    expect(spy.text, startsWith('Join me on Vibe Live! Use my code VIBE42 '));
    expect(spy.text, endsWith('/VIBE42?r=i'));
    expect(spy.text, isNot(contains('{{')));
    final copy = backend.where('/api/referral/VIBE42/copy').single;
    expect(copy.query['type'], 'i');
    await finish(tester);
  });
}
