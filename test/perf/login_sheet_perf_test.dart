import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/authscreen/login_screen.dart';
import 'package:vibelive/app/authscreen/widgets/auth_sheet.dart';
import 'package:vibelive/app/authscreen/widgets/login_form_step.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

import 'perf_harness.dart';

/// The login sheet at 120 Hz (8 ms frames): opening it and raising the
/// keyboard must not rebuild or repaint the page under it, and the keyboard
/// must not come up while the sheet is still sliding in.
void main() {
  const headline = 'Good\nconversations\nlive here.';
  const tagline = 'Call. Connect.\nAnytime, anywhere.';
  const title = 'Enter your\nmobile number';

  /// Everything outside the sheet, and the sheet's own content: none of it
  /// should rebuild for an animation or keyboard frame.
  const stable = [
    'LoginScreen',
    'LoginOptions',
    '_Hero',
    '_SocialButtons',
    '_OrRow',
    '_Legal',
    '_Logo',
    '_FadeRise',
    'AppLogo',
    'Image',
    'Spark',
    'Squiggle',
    'LoginReferralSection',
    'AuthOptionButton',
  ];

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Vibe Live',
      packageName: 'com.angrymamba.vibelive',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppPrefs.init();
  });

  // Assets load again in each test's fake-async zone.
  setUp(rootBundle.clear);

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3)
      ..viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [AppI18n.delegate],
        home: const LoginScreen(),
      ),
    );
    // Entrance animations and the text warm-up are done.
    await pumpFrames(tester, 20, ms: 50);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  bool fieldFocused(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byType(LoginFormStep),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  /// One keyboard frame: the inset grows, the home-indicator padding goes.
  void keyboardAt(WidgetTester tester, double inset) => tester.view
    ..viewInsets = FakeViewPadding(bottom: inset * 3)
    ..padding = FakeViewPadding(
      top: 47 * 3,
      bottom: (34 - inset).clamp(0, 34) * 3,
    );

  testWidgets('entrance: the logo and options page are painted once while '
      'they fade and rise', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844));
    final painted = await countTextPaints([headline, tagline], () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [AppI18n.delegate],
          home: const LoginScreen(),
        ),
      );
      await pumpFrames(tester, 70); // 560 ms: both entrances
    });
    expect(find.text(headline), findsOneWidget);
    expect(painted[headline], lessThanOrEqualTo(2));
    expect(painted[tagline], lessThanOrEqualTo(2));
    await close(tester);
  });

  testWidgets('slide-in: the sheet is built and painted once, the page '
      'under it never', (tester) async {
    await open(tester);
    late Map<String, int> rebuilt;
    // 36 frames = 288 ms: the slide (300 ms) up to its last frame.
    final painted = await countTextPaints([headline, tagline, title], () async {
      rebuilt = await countRebuilds(() async {
        await tester.tap(find.text('Continue with mobile number'));
        await pumpFrames(tester, 36);
      });
    });

    expect(find.text(title), findsOneWidget);
    expect(rebuilt['_SheetFrame'], 1);
    expect(rebuilt['LoginFormStep'], 1);
    expect(rebuilt['AuthStepTitle'], 1);
    for (final type in stable) {
      expect(rebuilt[type], isNull, reason: type);
    }
    // The page under the sheet isn't repainted; the sheet is painted when
    // it appears, then only its layer moves and fades.
    expect(painted[headline], 0);
    expect(painted[tagline], 0);
    expect(painted[title], 1);
    // The keyboard waits for the slide (raising it blocks frames).
    expect(fieldFocused(tester), isFalse);
    await pumpFrames(tester, 4);
    expect(fieldFocused(tester), isTrue);
    await close(tester);
  });

  testWidgets('keyboard frames rebuild only the insets, nothing in the page '
      'or the sheet content', (tester) async {
    await open(tester);
    await tester.tap(find.text('Continue with mobile number'));
    await pumpFrames(tester, 50); // slid in, field focused
    expect(fieldFocused(tester), isTrue);

    final perFrame = <Map<String, int>>[];
    final painted = await countTextPaints([headline, tagline], () async {
      // A 300 px keyboard over 30 frames (~250 ms at 120 Hz).
      for (var f = 1; f <= 30; f++) {
        keyboardAt(tester, 300 * f / 30);
        perFrame.add(
          await countRebuilds(
            () => tester.pump(const Duration(milliseconds: 8)),
          ),
        );
      }
    });

    for (final (f, rebuilt) in perFrame.indexed) {
      for (final type in [
        ...stable,
        'AuthSheet',
        '_SheetFrame',
        'LoginFormStep',
        'AuthStepTitle',
        '_TermsRow',
        'AuthPrimaryButton',
        'CInput',
      ]) {
        expect(rebuilt[type], isNull, reason: '$type, frame $f');
      }
    }
    // Only the sheet's bottom padding reads the inset that changes.
    expect(
      perFrame.fold<int>(0, (n, r) => n + (r['_BottomSafe'] ?? 0)),
      lessThanOrEqualTo(12), // 34 px of padding over 4 frames, at most
    );
    expect(painted[headline], 0);
    expect(painted[tagline], 0);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('focusing the field repaints the field, not the form', (
    tester,
  ) async {
    await open(tester);
    late Map<String, int> rebuilt;
    await tester.tap(find.text('Continue with mobile number'));
    await pumpFrames(tester, 36);
    expect(fieldFocused(tester), isFalse);
    // Focus lands (keyboard requested) and settles: no label animation
    // re-lays out the step, so its title isn't painted again.
    final painted = await countTextPaints([title], () async {
      rebuilt = await countRebuilds(() => pumpFrames(tester, 30));
    });
    expect(fieldFocused(tester), isTrue);
    expect(painted[title], lessThanOrEqualTo(1));
    expect(rebuilt['InputDecorator'] ?? 0, lessThanOrEqualTo(2));
    await close(tester);
  });

  testWidgets('switching email / mobile inside the open sheet focuses at '
      'once', (tester) async {
    await open(tester);
    await tester.tap(find.text('Continue with mobile number'));
    await pumpFrames(tester, 50);
    await tester.ensureVisible(find.text('Use email instead').last);
    await tester.pump();
    await tester.tap(find.text('Use email instead').last);
    await pumpFrames(tester, 2);
    expect(find.text('Enter your\nemail address'), findsOneWidget);
    expect(fieldFocused(tester), isTrue);
    await close(tester);
  });

  test('the sheet slides in over its fade', () {
    expect(AuthSheet.duration, const Duration(milliseconds: 300));
  });
}
