import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/approval/host_approval_screen.dart';
import 'package:vibelive/app/hosthub/badge/host_badge_screen.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

const _vacationTitle = 'Vacation mode';
const _vacationBody =
    "Pause all calls while you're away. Turn it off to start receiving "
    'calls again.';

JsonMap _host({bool vacation = false}) => {
  'id': 5,
  'documentId': 'exp1',
  'handler': 'aanyatalks',
  'isApproved': true,
  'isActive': true,
  'callAnyTime': !vacation,
  'vocationMode': vacation,
  'rates': {'voiceCallRate': 25, 'videoCallRate': 35},
  'expert_verifications': <Object>[],
};

/// Every English string of the namespace that Hindi translates differently.
Set<String> _englishOnly() {
  Map<String, String> flat(Object? n, [String p = '']) => {
    if (n is Map)
      for (final e in n.entries) ...flat(e.value, '$p${e.key}.'),
    if (n is String) p: n,
  };
  final en = flat(
    jsonDecode(File('assets/i18n/en/hostflow.json').readAsStringSync()),
  );
  final hi = flat(
    jsonDecode(File('assets/i18n/hi/hostflow.json').readAsStringSync()),
  );
  return {
    for (final e in en.entries)
      if (hi[e.key] != e.value &&
          !e.value.contains('{{') &&
          e.value.trim().length >= 3)
        e.value,
  };
}

/// Everything painted as text right now.
Set<String> _rendered(WidgetTester tester) => {
  for (final r in tester.allRenderObjects.whereType<RenderParagraph>())
    r.text.toPlainText().trim(),
};

void main() {
  late HostBackend backend;

  setUpAll(setUpHostHarness);
  setUp(() async => backend = await resetHost());

  Future<void> openAt(
    WidgetTester tester,
    String step, {
    Map<String, Object?> extra = const {},
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
  }) async {
    await AppPrefs.remove('hostflow_draft_v1:u1');
    await parkDraft(step, extra: extra);
    phone(tester, size: size);
    await pumpRoutes(
      tester,
      HostOnboardingScreen(key: ValueKey('$step$extra$locale')),
      locale: locale,
    );
    await pumpFor(tester, 300);
  }

  testWidgets('vacation copy: availability step and My Schedule', (
    tester,
  ) async {
    await openAt(tester, 'availability');
    expect(find.text(_vacationTitle), findsOneWidget);
    expect(find.text(_vacationBody), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hostflow-vacation')));
    await pumpFor(tester, 300);
    // RN: vacation turns "call any time" off and hides the schedule.
    expect(find.text('Your weekly schedule'), findsNothing);
    await finishHost(tester);

    backend = await resetHost(expert: _host(vacation: true));
    phone(tester);
    await pumpRoutes(
      tester,
      const HostOnboardingScreen(editStep: HostStep.availability),
    );
    expect(find.text(_vacationTitle), findsOneWidget);
    expect(find.text(_vacationBody), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('preview: every availability case, optional parts hidden', (
    tester,
  ) async {
    // Available now, one photo, video off.
    await openAt(tester, 'preview', extra: {'videoOn': false});
    expect(find.text('9 of 11'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Available to take calls now'), findsOneWidget);
    expect(find.text('Audio calls'), findsOneWidget);
    expect(find.text('Video calls'), findsNothing);
    expect(tester.takeException(), isNull);
    await finishHost(tester);

    // Vacation: the badge and the availability line follow it.
    await openAt(
      tester,
      'preview',
      extra: {'vacation': true, 'availableNow': false},
    );
    expect(find.text('On vacation'), findsOneWidget);
    expect(find.text('On vacation · calls are paused'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    await finishHost(tester);

    // Schedule only: no status badge, the days instead.
    await openAt(tester, 'preview', extra: {'availableNow': false});
    expect(find.text('Online'), findsNothing);
    expect(find.text('On vacation'), findsNothing);
    expect(find.text('Mon'), findsOneWidget);
    await finishHost(tester);

    // Nothing optional: no about / specialization blocks at all.
    await openAt(
      tester,
      'preview',
      extra: {
        'tagline': '',
        'bio': '',
        'topics': <Object>[],
        'languages': <Object>[],
      },
    );
    expect(find.byKey(const ValueKey('preview-edit-about')), findsNothing);
    expect(find.byKey(const ValueKey('preview-edit-topics')), findsNothing);
    expect(tester.takeException(), isNull);
    await finishHost(tester);

    // Long bio and Hindi at 320 px: no overflow.
    await openAt(
      tester,
      'preview',
      extra: {'bio': 'बातचीत ' * 120},
      locale: const Locale('hi'),
      size: const Size(320, 640),
    );
    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, -2500),
      3000,
    );
    await pumpFor(tester, 500);
    expect(tester.takeException(), isNull);
    await finishHost(tester);
  });

  testWidgets('a draft saved on the old review step resumes on the preview', (
    tester,
  ) async {
    await openAt(tester, 'review');
    expect(HostStep.fromName('review'), HostStep.preview);
    expect(find.text('Preview your profile'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('a failed submit stays on step 10 with the error', (
    tester,
  ) async {
    backend.failing.add('POST /api/expert-profiles');
    await openAt(tester, 'guidelines', extra: {'agreed': true});
    expect(find.text('10 of 11'), findsOneWidget);
    await tapContinue(tester, settle: 1500);
    expect(find.text('Something went wrong'), findsOneWidget); // the alert
    expect(find.text('10 of 11'), findsOneWidget);
    expect(find.text('Your profile is submitted!'), findsNothing);
    expect(savedDraft(), isNotNull); // nothing lost
    await finishHost(tester);
  });

  testWidgets('Hindi: no English UI text on any screen', (tester) async {
    // Server data (the interests form's own labels) may be English.
    final serverLabels = {
      for (final q in interestForm['questions']! as List) ...[
        '${(q as Map)['title']}',
        for (final o in q['options'] as List) '${(o as Map)['label']}',
      ],
    };
    final english = _englishOnly().difference(serverLabels);
    void check(String where) {
      final leaked = _rendered(tester).intersection(english);
      expect(leaked, isEmpty, reason: '$where shows English: $leaked');
    }

    for (final step in HostStep.values) {
      await openAt(tester, step.name, locale: const Locale('hi'));
      check('$step');
      await finishHost(tester);
    }

    for (final (name, screen) in [
      ('approval', const HostApprovalScreen()),
      ('expertise', const HostOnboardingScreen(editStep: HostStep.interests)),
      ('badge', const HostBadgeScreen()),
      ('schedule', const HostOnboardingScreen(editStep: HostStep.availability)),
      ('rates', const HostOnboardingScreen(editStep: HostStep.rates)),
    ]) {
      backend = await resetHost(expert: _host());
      phone(tester);
      await pumpRoutes(tester, screen, locale: const Locale('hi'));
      await pumpFor(tester, 500);
      check(name);
      await finishHost(tester);
    }
  });
}
