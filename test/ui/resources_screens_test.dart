import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibelive/app/component/c_back_button.dart';
import 'package:vibelive/app/component/c_button.dart';
import 'package:vibelive/app/component/c_state_view.dart';
import 'package:vibelive/app/resourcesscreen/categories/categories_screen.dart';
import 'package:vibelive/app/resourcesscreen/categories/categories_widgets.dart';
import 'package:vibelive/app/resourcesscreen/helper/resource_palette.dart';
import 'package:vibelive/app/resourcesscreen/webview/webview_screen.dart';
import 'package:vibelive/app/resourcesscreen/widgets/page_body.dart';
import 'package:vibelive/app/resourcesscreen/widgets/page_header.dart';
import 'package:vibelive/app/resourcesscreen/widgets/resource_row.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';

import 'resources_support/harness.dart';

/// The PageCard's fill.
Color? _cardColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find
        .descendant(of: find.byType(PageCard), matching: find.byType(Container))
        .first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  late ResourcesBackend backend;
  late FakeOpener opener;

  setUpAll(setUpResourcesSuite);
  setUp(() => (backend, opener) = setUpResourcesTest());

  testWidgets('RESOURCES menu: CMS rows load, dropdown, a page opens', (
    tester,
  ) async {
    await openRoute(tester, '${AppRoutes.categoryMenu}?id=resources');
    expect(find.text('RESOURCES'), findsOneWidget);
    expect(find.text('PROFILE SETTINGS'), findsOneWidget);
    expect(find.text('About Vibe'), findsOneWidget);
    // CMS rows still loading: skeleton rows above Logout.
    expect(find.byType(ResourceRowSkeleton), findsNWidgets(2));

    await pumpFor(tester, 600);
    expect(find.byType(ResourceRowSkeleton), findsNothing);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms'), findsNothing); // never listed (RN rule)
    expect(
      tester.getTopLeft(find.text('Privacy Policy')).dy,
      lessThan(tester.getTopLeft(find.text('Logout Session')).dy),
    );

    // Account Privacy opens its sub-rows.
    expect(find.text('Blocked Users'), findsNothing);
    await tester.tap(find.text('Account Privacy'));
    await pumpFor(tester, 200);
    expect(find.text('Blocked Users'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);

    // A CMS page: skeleton, then the HTML content.
    await tester.tap(find.text('Privacy Policy'));
    await pumpFor(tester, 100);
    expect(location, contains('/me/dynamic-page?slug=privacy-policy'));
    expect(find.byType(PageSkeleton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PageHeader),
        matching: find.text('Privacy Policy'),
      ),
      findsOneWidget,
    ); // title from the route, until the page loads
    await pumpFor(tester, 600);
    expect(find.byType(PageSkeleton), findsNothing);
    expect(find.text('Your data'), findsOneWidget);
    expect(
      find.textContaining('We keep it safe.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('No selling', findRichText: true), findsOneWidget);
    expect(_cardColor(tester), ResourcePalette.dark.card);

    // Links go through the url_launcher seam.
    await tester.tapOnText(find.textRange.ofSubstring('the full policy'));
    await tester.pump();
    expect(opener.opened.single.$1.toString(), 'https://vibe.example/policy');
    expect(opener.opened.single.$2, LaunchMode.externalApplication);

    // Back to the menu.
    await tester.tap(find.byType(CBackButton).last);
    await pumpFor(tester, 600);
    expect(location, '${AppRoutes.categoryMenu}?id=resources');
    expect(find.text('Blocked Users'), findsOneWidget); // still open
    await finish(tester);
  });

  testWidgets('About shows rich-text blocks', (tester) async {
    await openRoute(tester, AppRoutes.aboutApp);
    expect(find.byType(PageSkeleton), findsOneWidget);
    expect(find.text('About App'), findsOneWidget); // until the page loads
    await pumpFor(tester, 600);
    expect(find.text('About Vibe Live'), findsOneWidget); // server title
    expect(
      find.text('Talk to experts, live.', findRichText: true),
      findsOneWidget,
    );

    await finish(tester);
  });

  testWidgets('Support: the email, "Email us" opens the mail app, Copy', (
    tester,
  ) async {
    await openRoute(tester, AppRoutes.support);
    await pumpFor(tester, 600);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text("We're here to help"), findsOneWidget);
    expect(find.text('help@vibe.example'), findsOneWidget);

    await tester.tap(find.text('EMAIL US'));
    await pumpFor(tester, 100);
    final mail = opener.opened.single.$1;
    expect(mail.scheme, 'mailto');
    expect(mail.path, 'help@vibe.example');
    expect(mail.queryParameters['subject'], 'VibeLive support');

    // No mail app: the address goes on the clipboard instead.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    opener.result = false;
    await tester.tap(find.text('help@vibe.example'));
    await pumpFor(tester, 100);
    expect(opener.opened, hasLength(2));
    expect(copied, 'help@vibe.example');
    await finish(tester);
  });

  testWidgets('a failed page shows the error with Retry', (tester) async {
    backend.failPages = true;
    await openRoute(
      tester,
      '${AppRoutes.dynamicPage}?slug=privacy-policy&title=Privacy',
    );
    await pumpFor(tester, 800);
    expect(find.byType(CStateView), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget); // the route's title

    backend.failPages = false;
    await tester.tap(
      find.descendant(
        of: find.byType(CStateView),
        matching: find.byType(CButton),
      ),
    );
    await pumpFor(tester, 800);
    expect(find.byType(CStateView), findsNothing);
    expect(find.text('Your data'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an unknown slug says there is no content', (tester) async {
    await openRoute(tester, '${AppRoutes.dynamicPage}?slug=missing');
    await pumpFor(tester, 800);
    expect(find.text('No content available.'), findsOneWidget);
    expect(find.text('Page'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('webview opens the in-app browser, then steps aside', (
    tester,
  ) async {
    await openRoute(
      tester,
      '${AppRoutes.webview}?url=https%3A%2F%2Fvibe.example%2Foffer&title=Offer',
    );
    await pumpFor(tester, 800);
    expect(opener.opened.single.$1.toString(), 'https://vibe.example/offer');
    expect(opener.opened.single.$2, LaunchMode.inAppBrowserView);
    expect(find.byType(WebviewScreen), findsNothing); // left for Home
    expect(location, startsWith(AppRoutes.home));
    await finish(tester);
  });

  testWidgets('webview: a failed open offers Retry; a bad url leaves', (
    tester,
  ) async {
    opener.result = false;
    await openRoute(
      tester,
      '${AppRoutes.webview}?url=vibe.example/offer',
      theme: ThemeMode.light,
    );
    await pumpFor(tester, 200);
    expect(find.text("This page couldn't load"), findsOneWidget);
    expect(find.text('Offer'), findsNothing);
    expect(find.text('vibe.example'), findsWidgets); // header title + host

    opener.result = true;
    await tester.tap(
      find.descendant(
        of: find.byType(CStateView),
        matching: find.byType(CButton),
      ),
    );
    await pumpFor(tester, 800);
    expect(opener.opened, hasLength(2));
    expect(find.byType(WebviewScreen), findsNothing);

    appRouter.go('${AppRoutes.webview}?url=javascript:alert(1)');
    await pumpFor(tester, 900);
    expect(find.byType(WebviewScreen), findsNothing);
    expect(opener.opened, hasLength(2));
    await finish(tester);
  });

  testWidgets('categories: skeleton, saved picks first, save moves on', (
    tester,
  ) async {
    await openRoute(tester, AppRoutes.categories);
    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(find.byType(CategoriesSkeleton), findsOneWidget);
    await pumpFor(tester, 900);
    expect(find.byType(CategoriesSkeleton), findsNothing);
    expect(find.text('SELECTED (1/10)'), findsOneWidget);
    final astrology = tester.getTopLeft(find.text('Astrology')).dy;
    expect(astrology, lessThan(tester.getTopLeft(find.text('Career')).dy));

    await tester.tap(find.text('Yoga'));
    await tester.pump();
    expect(find.text('SELECTED (2/10)'), findsOneWidget);
    expect(find.text('SAVE CHANGES (2/10)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'car');
    await pumpFor(tester, 600);
    expect(find.text('Career'), findsOneWidget);
    expect(find.text('Astrology'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.text('SAVE CHANGES (2/10)'));
    await pumpFor(tester, 1500);
    expect(backend.puts.single['categories'], [
      {'id': 11},
      {'id': 13},
    ]);
    expect(find.text('Categories updated successfully.'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await pumpFor(tester, 400);
    // The saved profile has no schedule yet: that is the next step.
    expect(location, AppRoutes.schedule);
    await finish(tester);
  });

  testWidgets('light theme, 320 wide, Hindi: no overflow', (tester) async {
    await openRoute(
      tester,
      '${AppRoutes.categoryMenu}?id=resources',
      theme: ThemeMode.light,
      size: const Size(320, 640),
      locale: const Locale('hi'),
      bottomInset: 34,
    );
    await pumpFor(tester, 800);
    expect(tester.takeException(), isNull);
    expect(find.text('संसाधन'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('लॉग आउट करें'), 200);
    expect(tester.takeException(), isNull);

    unawaited(appRouter.push('${AppRoutes.dynamicPage}?slug=privacy-policy'));
    await pumpFor(tester, 800);
    expect(tester.takeException(), isNull);
    expect(_cardColor(tester), ResourcePalette.light.card);
    await finish(tester);
  });

  testWidgets('Logout asks first, then signs out', (tester) async {
    await openRoute(tester, '${AppRoutes.categoryMenu}?id=resources');
    await pumpFor(tester, 600);
    await tester.scrollUntilVisible(find.text('Logout Session'), 200);
    await tester.tap(find.text('Logout Session'));
    await pumpFor(tester, 300);
    expect(find.text('Are you sure you want to logout?'), findsOneWidget);
    await tester.tap(find.text('LOGOUT'));
    await pumpFor(tester, 1500);
    expect(SessionStore.instance.value.isAuthenticated, isFalse);
    await finish(tester);
  });
}
