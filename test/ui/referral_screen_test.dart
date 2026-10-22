import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/app/client/referral/helper/referral_format.dart';
import 'package:vibelive/app/client/referral/widgets/referral_skeleton.dart';
import 'package:vibelive/app/component/c_image.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'referral_support/harness.dart';

final _list = find.descendant(
  of: find.byType(InfiniteScroll),
  matching: find.byType(Scrollable),
);

void main() {
  late ReferralBackend backend;

  setUpAll(setUpReferralMocks);
  setUp(() => backend = installBackend());

  group('ReferralFormat', () {
    test('avatar letter: first Latin letter, else U (RN avatarLetter)', () {
      expect(ReferralFormat.avatarLetter('asha'), 'A');
      expect(ReferralFormat.avatarLetter('  _kiran'), 'K');
      expect(ReferralFormat.avatarLetter('98******10'), 'U');
      expect(ReferralFormat.avatarLetter('रवि'), 'U');
      expect(ReferralFormat.avatarLetter(null), 'U');
      expect(ReferralFormat.avatarLetter(''), 'U');
    });

    test('referral link carries ?r=r; no code is the bare site', () {
      expect(ReferralFormat.link('VIBE42'), endsWith('/VIBE42?r=r'));
      expect(ReferralFormat.link(''), LinkParser.shareLink(''));
      expect(ReferralFormat.count(0), '0');
      expect(ReferralFormat.count(12345), '12345'); // RN: no grouping
    });
  });

  testWidgets('skeleton, then code, link, counters and the referred users', (
    tester,
  ) async {
    backend.joined = [
      {'documentId': 'a', 'name': 'Asha Rao', 'createdAt': '2026-10-01'},
      {'documentId': 'b', 'username': 'kiran_k'},
      {'documentId': 'c', 'mobile': '9876543210'},
      {'documentId': 'd', 'mobile': '123'},
      {'documentId': 'e'},
      {
        'documentId': 'f',
        'name': 'Pic Person',
        'profilePic': {'url': 'https://cdn.example.com/p.jpg'},
      },
    ];
    await openApp(tester, backend, location: AppRoutes.referral);
    expect(find.byType(ReferralSkeleton), findsOneWidget);

    await pumpMs(tester, 600);
    expect(find.byType(ReferralSkeleton), findsNothing);
    expect(find.text('Referral'), findsOneWidget);
    expect(find.text('YOUR REFERRAL CODE'), findsOneWidget);
    expect(find.text('VIBE42'), findsOneWidget);
    expect(find.text(ReferralFormat.link('VIBE42')), findsOneWidget);
    expect(find.text('SHARE REFERRAL LINK'), findsOneWidget);
    expect(find.text('TOTAL CLICKS'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('JOINED USERS'), findsOneWidget);
    // max(joinedUserCount 2, 6 rows), like RN.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('REFERRED USERS'), findsOneWidget);

    // The joined-users read (RN: newest first, one page of 100).
    final read = backend.where('/api/public-users').single.query;
    expect(read[r'filters[referrerCode][$eq]'], 'VIBE42');
    expect(read['sort'], 'createdAt:desc');
    expect(read['pagination[pageSize]'], 100);

    // Each row text: name → username → masked mobile → short mobile as is
    // → "User", with "Referred user" under it.
    await tester.scrollUntilVisible(
      find.text('Pic Person'),
      200,
      scrollable: _list,
    );
    for (final name in [
      'Asha Rao',
      'kiran_k',
      '98******10',
      '123',
      'User',
      'Pic Person',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Referred user'), findsNWidgets(6));
    // Avatars: the photo, else the first Latin letter, else U.
    expect(find.byType(CImage), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(find.text('U'), findsNWidgets(3));
    expect(find.text('P'), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('share: ?r=r link in the OS sheet, counted as a referral', (
    tester,
  ) async {
    final spy = ShareSpy(tester);
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.text('SHARE REFERRAL LINK'));
    await pumpMs(tester, 600);
    expect(spy.text, ReferralFormat.link('VIBE42'));
    expect(spy.text, endsWith('/VIBE42?r=r'));
    expect(spy.subject, 'Vibe Live Referral');
    final copy = backend.where('/api/referral/VIBE42/copy').single;
    expect(copy.query['type'], 'r');
    // The backend's new count.
    expect(find.text('8'), findsOneWidget);
    expect(find.text('7'), findsNothing);
    await finish(tester);
  });

  testWidgets('a failed count still shows one more share (RN)', (tester) async {
    ShareSpy(tester);
    backend.copyFails = true;
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);

    await tester.tap(find.text('SHARE REFERRAL LINK'));
    await pumpMs(tester, 600);
    expect(backend.where('/api/referral/VIBE42/copy'), hasLength(1));
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
    await finish(tester);
  });

  testWidgets('empty: no referred users yet', (tester) async {
    backend.referral = {'referralCode': 'vibe42'};
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);
    expect(find.text('No referred users yet'), findsOneWidget);
    expect(find.text('Referred user'), findsNothing);
    expect(find.text('0'), findsNWidgets(2)); // clicks, joined
    await finish(tester);
  });

  testWidgets('no code: N/A, bare link, share explains why it cannot', (
    tester,
  ) async {
    final spy = ShareSpy(tester);
    backend.referral = null;
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);
    expect(find.text('N/A'), findsOneWidget);
    expect(find.text(LinkParser.shareLink('')), findsOneWidget);
    expect(find.text('No referred users yet'), findsOneWidget);
    // No code, no joined-users read.
    expect(backend.where('/api/public-users'), isEmpty);

    await tester.tap(find.text('SHARE REFERRAL LINK'));
    await pumpMs(tester, 400);
    expect(find.text('Referral code is not available yet.'), findsOneWidget);
    expect(spy.text, isNull);
    await finish(tester);
  });

  testWidgets('error before data: retry loads the screen', (tester) async {
    backend.userFailures = 1;
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('VIBE42'), findsNothing);

    await tester.tap(find.text('RETRY'));
    await pumpMs(tester, 600);
    expect(find.text('VIBE42'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('refresh button re-reads; a failed refresh keeps the data', (
    tester,
  ) async {
    await openApp(tester, backend, location: AppRoutes.referral);
    await pumpMs(tester, 600);
    final reads = backend.where('/api/public-users/u-host').length;

    backend.referral!['totalClicks'] = 11;
    await tester.tap(find.bySemanticsLabel('Refresh'));
    await pumpMs(tester, 600);
    expect(backend.where('/api/public-users/u-host').length, reads + 1);
    expect(find.text('11'), findsOneWidget);

    backend.userFailures = 1;
    await tester.tap(find.bySemanticsLabel('Refresh'));
    await pumpMs(tester, 600);
    expect(find.text('VIBE42'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('long list: rows are lazy and the end clears the home bar', (
    tester,
  ) async {
    backend.joined = [
      for (var i = 0; i < 100; i++) {'documentId': 'u$i', 'name': 'User $i'},
    ];
    await openApp(
      tester,
      backend,
      location: AppRoutes.referral,
      bottomInset: 34,
    );
    await pumpMs(tester, 600);
    expect(find.text('Referred user').evaluate().length, lessThan(20));

    await tester.fling(_list, const Offset(0, -20000), 8000);
    await pumpMs(tester, 1500);
    expect(find.text('User 99'), findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold).first);
    expect(
      tester.getRect(find.text('User 99')).bottom,
      lessThan(screen.height - 34),
    );
    await finish(tester);
  });

  testWidgets('320 wide, Hindi, light, big numbers: no overflow', (
    tester,
  ) async {
    backend.referral = {
      'referralCode': 'vibelongcode2026',
      'totalClicks': 987654321,
      'joinedUserCount': 123456789,
    };
    backend.joined = [
      {
        'documentId': 'a',
        'name': 'Venkata Lakshmi Narasimha Subrahmanyam Chakravarthy',
      },
      {'documentId': 'b'},
    ];
    await openApp(
      tester,
      backend,
      location: AppRoutes.referral,
      size: const Size(320, 667),
      locale: const Locale('hi'),
      theme: ThemeMode.light,
    );
    await pumpMs(tester, 600);
    expect(tester.takeException(), isNull);
    expect(find.text('आपका रेफ़रल कोड'), findsOneWidget);
    expect(find.text('रेफ़र किया गया यूज़र'), findsNWidgets(2));
    expect(find.text('यूज़र'), findsOneWidget);
    await tester.fling(_list, const Offset(0, -2000), 3000);
    await pumpMs(tester, 800);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
