import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/history/history_skeleton.dart';
import 'package:vibelive/app/component/c_loader.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/app/component/skeleton.dart';
import 'package:vibelive/app/listingflow/profile/profile_skeleton.dart';
import 'package:vibelive/app/listingflow/search/search_host_row.dart';
import 'package:vibelive/app/listingflow/widgets/host_grid_card.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/theme/app_colors.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

const _probe = ValueKey('probe');

/// Skeletons as the screens use them (first loads and load-more footers).
Widget _gallery() => SingleChildScrollView(
  child: Column(
    children: [
      Shimmer(
        child: Column(
          children: [
            const SkeletonBox(key: _probe, width: 120, height: 40),
            const SizedBox(height: 8),
            const SkeletonLines(lines: 3),
            const SearchHostRowSkeleton(),
            SizedBox(height: 120, child: Row(children: _cards())),
          ],
        ),
      ),
      const HistorySkeleton.more(),
      const SizedBox(height: 136, child: ReviewCardSkeleton()),
      const ReviewsSkeleton(height: 136),
      // No Shimmer at all: still the theme's color, never white.
      const SkeletonBox(width: 80, height: 20),
    ],
  ),
);

List<Widget> _cards() => const [
  Expanded(child: HostGridCardSkeleton()),
  SizedBox(width: 12),
  Expanded(child: HostGridCardSkeleton()),
];

Future<void> _pumpThemed(WidgetTester tester, bool dark, Widget body) async {
  tester.view
    ..physicalSize = const Size(390, 1600) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  Scale.update(const Size(390, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      locale: const Locale('en'),
      supportedLocales: AppI18n.supportedLocales,
      localizationsDelegates: [AppI18n.delegate],
      home: Scaffold(body: RepaintBoundary(child: body)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// What each SkeletonBox paints.
List<Color> _boxColors(WidgetTester tester) => [
  for (final e in find.byType(SkeletonBox).evaluate())
    ((tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byWidget(e.widget),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration)
        .color!),
];

void main() {
  setUp(rootBundle.clear);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('$mode: every box paints the theme skeleton color', (
      tester,
    ) async {
      await _pumpThemed(tester, dark, _gallery());
      final colors = _boxColors(tester);
      expect(colors.length, greaterThan(10));
      final fill = dark
          ? SkeletonColors.darkHighlight
          : SkeletonColors.lightBase;
      for (final c in colors) {
        expect(c, fill);
        expect(c.a, lessThan(0.15), reason: 'translucent, not a solid block');
        expect(c, isNot(AppColors.white));
      }
      await close(tester);
    });

    testWidgets('$mode: the sweep only modulates alpha (dstIn)', (
      tester,
    ) async {
      await _pumpThemed(tester, dark, _gallery());
      final masks = tester.widgetList<ShaderMask>(find.byType(ShaderMask));
      expect(masks, isNotEmpty);
      for (final m in masks) {
        expect(m.blendMode, BlendMode.dstIn);
      }
      // The probe is under the mask, past both of Shimmer's boundaries.
      expect(
        find.ancestor(
          of: find.byKey(_probe),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      await close(tester);
    });
  }

  testWidgets('dark: a shimmering box is never rendered white', (tester) async {
    await _pumpThemed(
      tester,
      true,
      const ColoredBox(
        color: Color(0xFF050508),
        child: Align(
          alignment: Alignment.topLeft,
          child: Shimmer(child: SkeletonBox(width: 300, height: 60)),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(ColoredBox).first,
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    // Sample across the sweep at several points of the animation.
    for (var frame = 0; frame < 4; frame++) {
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = image.width;
        image.dispose();
        return (data!, w);
      });
      final (data, width) = bytes!;
      var brightest = 0;
      for (var x = 10; x < 290; x += 10) {
        final i = (30 * width + x) * 4;
        brightest = [
          brightest,
          data.getUint8(i),
        ].reduce((a, b) => a > b ? a : b);
      }
      // White 12 % over #050508 is about 35; the old mask painted 255.
      expect(brightest, lessThan(60), reason: 'frame $frame');
      await tester.pump(const Duration(milliseconds: 320));
    }
    await close(tester);
  });

  group('InfiniteScroll footer', () {
    Widget list({WidgetBuilder? loadingBuilder}) => InfiniteScroll(
      hasMore: true,
      loadingMore: true,
      onLoadMore: () {},
      padding: const EdgeInsets.symmetric(horizontal: 10),
      loadingBuilder: loadingBuilder,
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 40))],
    );

    testWidgets('a list passes row skeletons for load-more', (tester) async {
      await _pumpThemed(
        tester,
        true,
        list(loadingBuilder: (_) => const HistorySkeleton.more()),
      );
      expect(find.byType(HistorySkeleton), findsOneWidget);
      expect(find.byType(CLoader), findsNothing);
      // The footer gets the list's horizontal padding.
      final left = tester.getTopLeft(find.byType(HistorySkeleton)).dx;
      expect(left, 10);
      await close(tester);
    });

    testWidgets('without one, the small spinner stays', (tester) async {
      await _pumpThemed(tester, true, list());
      expect(find.byType(CLoader), findsOneWidget);
      await close(tester);
    });
  });
}
