import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

import '../ui/host_onboarding_support/harness.dart';
import 'perf_harness.dart';

/// Scrolling the host's ME tab rebuilds nothing but newly revealed list
/// items (the Host Hub card and stat rows are items): the page, its header
/// cards, the segment switch and the dashboard sliver stay as they are.
void main() {
  setUpAll(setUpHostHarness);

  testWidgets('ME host view scrolls without rebuilding the page', (
    tester,
  ) async {
    final backend = await resetHost(
      expert: {
        'id': 5,
        'documentId': 'exp1',
        'handler': 'aanyatalks',
        'isApproved': true,
        'isActive': true,
        'callAnyTime': true,
        'rates': {'voiceCallRate': 25, 'videoCallRate': 35},
        'expert_verifications': <Object>[],
      },
    );
    backend.stats = {'total_earnings': 2450, 'total_incoming_calls': 18};
    phone(tester, bottom: 34);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go('${AppRoutes.home}?tab=me');
    await pumpFor(tester, 1200);

    final list = find.descendant(
      of: find.byType(InfiniteScroll),
      matching: find.byType(Scrollable),
    );
    var furthest = 0.0;
    final counts = await countRebuilds(() async {
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -120));
        await pumpFrames(tester, 4);
        final px = tester.state<ScrollableState>(list).position.pixels;
        if (px > furthest) furthest = px;
      }
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, 120));
        await pumpFrames(tester, 4);
      }
    });
    expect(furthest, greaterThan(600)); // it really scrolled
    for (final name in [
      'MeView',
      '_FirstLoadGate',
      'MeProfileCard',
      'MeAvailabilityCard',
      'HostStatusSection',
      'MeSegmented<MeSection>',
      'MeHostDashboard',
      'BottomNavbar',
    ]) {
      expect(counts[name], isNull, reason: '$name rebuilt while scrolling');
    }
    expect(tester.takeException(), isNull);
    await finishHost(tester);
  });
}
