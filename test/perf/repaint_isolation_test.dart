import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/component/c_input.dart';
import 'package:vibelive/app/component/c_loader.dart';
import 'package:vibelive/app/component/skeleton.dart';
import 'package:vibelive/app/homescreen/helper/home_controller.dart';
import 'package:vibelive/app/navbar/bottombar/bottom_navbar.dart';
import 'package:vibelive/app/navbar/bottombar/navbar_collapse.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

import 'perf_harness.dart';

/// Things that animate on every frame (shimmer, spinners, the navbar
/// collapse, a focused field) must repaint only themselves: at 120 Hz a
/// repaint that spreads to the page around them re-records the whole screen
/// 120 times a second.
void main() {
  const page = 'Page text next to the animation';

  setUp(rootBundle.clear);

  Future<void> pumpApp(WidgetTester tester, Widget body, {Widget? bar}) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [AppI18n.delegate],
        home: Scaffold(
          bottomNavigationBar: bar,
          body: Column(children: [const Text(page), body]),
        ),
      ),
    );
    await pumpFrames(tester, 10, ms: 50);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a shimmer sweep never repaints the page around it', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const Shimmer(child: SkeletonBox(width: 60, height: 16)),
    );
    final painted = await countTextPaints([page], () => pumpFrames(tester, 60));
    expect(painted[page], 0);
    await close(tester);
  });

  testWidgets('a spinner never repaints the page around it', (tester) async {
    await pumpApp(tester, const CLoader());
    final painted = await countTextPaints([page], () => pumpFrames(tester, 60));
    expect(painted[page], 0);
    await close(tester);
  });

  testWidgets('the navbar collapse moves its own layer only', (tester) async {
    final home = HomeController();
    addTearDown(home.dispose);
    addTearDown(NavbarCollapse.instance.reset);
    await pumpApp(tester, const SizedBox(), bar: BottomNavbar(home: home));
    final painted = await countTextPaints([page], () async {
      NavbarCollapse.instance.value = true;
      await pumpFrames(tester, 30); // 220 ms collapse
      NavbarCollapse.instance.value = false;
      await pumpFrames(tester, 30);
    });
    expect(painted[page], 0);
    await close(tester);
  });

  testWidgets('focusing and typing in a CInput repaint the field only', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const CInput(type: CInputType.email, placeholder: 'auth:login.or'),
    );
    late Map<String, int> rebuilt;
    final painted = await countTextPaints([page], () async {
      rebuilt = await countRebuilds(() async {
        await tester.tap(find.byType(TextField));
        await pumpFrames(tester, 30);
        await tester.enterText(find.byType(TextField), 'a');
        await pumpFrames(tester, 30);
      });
    });
    // At most once per discrete change (focus, the character) for its
    // relayout; never once per frame of an animation.
    expect(painted[page], lessThanOrEqualTo(2));
    // No label to float: focus and the first character don't animate the
    // decorator (one rebuild each for the state change itself).
    expect(rebuilt['InputDecorator'] ?? 0, lessThanOrEqualTo(4));
    await close(tester);
  });
}
