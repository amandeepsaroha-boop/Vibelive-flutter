import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/client/blocked_users/blocked_users_screen.dart';
import 'package:vibelive/app/client/blocked_users/widgets/blocked_user_tile.dart';
import 'package:vibelive/app/client/favourites/favourites_screen.dart';
import 'package:vibelive/app/client/favourites/widgets/favourite_tile.dart';
import 'package:vibelive/app/client/gst_details/gst_details_screen.dart';
import 'package:vibelive/app/client/gst_details/widgets/gst_fields.dart';
import 'package:vibelive/app/client/referral/referral_screen.dart';
import 'package:vibelive/app/component/app_logo.dart';
import 'package:vibelive/app/resourcesscreen/category_menu/category_menu_screen.dart';
import 'package:vibelive/app/resourcesscreen/dynamic_page/dynamic_page_screen.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'resources_support/harness.dart';

void main() {
  late ResourcesBackend backend;

  setUpAll(setUpResourcesSuite);
  setUp(() => (backend, _) = setUpResourcesTest());

  /// Scrolls the current screen until [f] is built.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 15 && f.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(200, 600), const Offset(0, -250));
      await pumpFor(tester, 200);
    }
    await tester.ensureVisible(f);
    await pumpFor(tester, 200);
  }

  testWidgets('ME tab → RESOURCES → every row opens its real screen', (
    tester,
  ) async {
    backend.isHost = false;
    await openRoute(tester, '${AppRoutes.home}?tab=me', host: false);
    await pumpFor(tester, 1500);
    await reveal(tester, find.text('RESOURCES'));
    await tester.tap(find.text('RESOURCES'));
    await pumpFor(tester, 1200);
    expect(find.byType(CategoryMenuScreen), findsOneWidget);

    final targets = <String, Type>{
      'GST Details': GstDetailsScreen,
      'Referral Program': ReferralScreen,
      'Favourites': FavouritesScreen,
      'About Vibe': DynamicPageScreen,
      'Help & Support': DynamicPageScreen,
      'Privacy Policy': DynamicPageScreen,
    };
    for (final MapEntry(key: row, value: screen) in targets.entries) {
      await reveal(tester, find.text(row));
      await tester.tap(find.text(row));
      await pumpFor(tester, 1200);
      expect(find.byType(screen), findsOneWidget, reason: row);
      expect(find.byType(AppLogo), findsNothing, reason: '$row: placeholder');
      expect(tester.takeException(), isNull, reason: row);
      appRouter.pop();
      await pumpFor(tester, 800);
    }

    await reveal(tester, find.text('Account Privacy'));
    await tester.tap(find.text('Account Privacy'));
    await pumpFor(tester, 300);
    await reveal(tester, find.text('Blocked Users'));
    await tester.tap(find.text('Blocked Users'));
    await pumpFor(tester, 1200);
    expect(find.byType(BlockedUsersScreen), findsOneWidget);
    expect(find.byType(AppLogo), findsNothing);
    appRouter.pop();
    await pumpFor(tester, 800);

    await reveal(tester, find.text('Delete Account'));
    await tester.tap(find.text('Delete Account'));
    await pumpFor(tester, 300);
    expect(find.textContaining('permanently delete'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await pumpFor(tester, 300);
    await finish(tester);
  });

  testWidgets('Blocked Users: skeleton, list, unblock after confirm', (
    tester,
  ) async {
    await openRoute(tester, AppRoutes.blockedUsers);
    expect(find.byType(BlockedUsersSkeleton), findsOneWidget);
    await pumpFor(tester, 600);
    expect(find.text('Kabir'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(find.textContaining('Blocked on'), findsOneWidget);

    await tester.tap(find.text('Unblock'));
    await pumpFor(tester, 300);
    expect(find.text('Unblock Kabir?'), findsOneWidget);
    await tester.tap(find.text('UNBLOCK'));
    await pumpFor(tester, 900);
    expect(backend.writes['POST /api/user-blocks/unblock'], {
      'targetUserId': 'u4',
    });
    expect(find.text('User unblocked.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 900);
    expect(find.text('Kabir'), findsNothing);
    expect(find.text('No Blocked Users'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Favourites: list, remove (light theme)', (tester) async {
    await openRoute(tester, AppRoutes.favourites, theme: ThemeMode.light);
    expect(find.byType(FavouritesSkeleton), findsOneWidget);
    await pumpFor(tester, 600);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('@meera'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove from favourites'));
    await pumpFor(tester, 900);
    expect(backend.writes.keys, contains('DELETE /api/favorites/fav1'));
    expect(find.text('Meera'), findsNothing);
    expect(find.text('No favourites yet'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('GST: validation, then save at 320 wide', (tester) async {
    await openRoute(
      tester,
      AppRoutes.gstDetails,
      size: const Size(320, 640),
      bottomInset: 34,
    );
    expect(find.byType(GstSkeleton), findsOneWidget);
    await pumpFor(tester, 900);
    expect(find.text('GST CONFIGURATION'), findsOneWidget);

    await reveal(tester, find.text('SAVE GST DETAILS'));
    await tester.tap(find.text('SAVE GST DETAILS'));
    await pumpFor(tester, 300);
    await reveal(tester, find.text('GST number is required'));
    expect(find.text('GST number is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(GstInput, 'Eg. 42AGFJH-JHJ1Z5'),
      '27aapfu0939f1zv',
    );
    await tester.enterText(
      find.widgetWithText(GstInput, 'Enter business name'),
      'Vibe Co',
    );
    await tester.enterText(
      find.widgetWithText(GstInput, 'Enter business address'),
      '1 MG Road',
    );
    await pumpFor(tester, 100);
    await reveal(tester, find.text('SAVE GST DETAILS'));
    await tester.tap(find.text('SAVE GST DETAILS'));
    await pumpFor(tester, 1200);
    final data =
        (backend.writes['POST /api/gst-details'] as Map)['data'] as Map;
    expect((data['GST'] as Map)['GST_Number'], '27AAPFU0939F1ZV');
    expect(find.text('GST details saved successfully.'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await pumpFor(tester, 400);
    expect(find.text('DETAILS SUBMITTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('GST not registered needs the declaration (Hindi)', (
    tester,
  ) async {
    await openRoute(
      tester,
      AppRoutes.gstDetails,
      locale: const Locale('hi'),
      theme: ThemeMode.light,
      size: const Size(320, 640),
    );
    await pumpFor(tester, 900);
    await tester.tap(find.byType(Switch));
    await pumpFor(tester, 300);
    await reveal(tester, find.text('GST विवरण सेव करें'));
    await tester.tap(find.text('GST विवरण सेव करें'));
    await pumpFor(tester, 300);
    expect(
      find.text('कृपया नॉन-रजिस्ट्रेशन घोषणा की पुष्टि करें'),
      findsOneWidget,
    );
    expect(backend.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
