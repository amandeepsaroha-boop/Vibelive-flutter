import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/profile_models.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/app/component/pressable.dart';
import 'package:vibelive/app/hosthub/approved/host_status_section.dart';
import 'package:vibelive/app/hosthub/edit/host_edit_screen.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

import 'host_onboarding_support/harness.dart';

JsonMap _host({bool approved = true, bool active = false}) => {
  'id': 5,
  'documentId': 'exp1',
  'handler': 'aanyatalks',
  'isApproved': approved,
  'isActive': active,
  'callAnyTime': false,
  'vocationMode': false,
  'rates': {'voiceCallRate': 25, 'videoCallRate': 35},
  'schedule': [
    {
      'days': 'Monday',
      'timeSlots': [
        {'startTime': '18:00:00.000', 'endTime': '23:59:00.000'},
      ],
    },
  ],
};

/// The ME section on its own, with what it asked to open.
class _Section extends StatelessWidget {
  const _Section({required this.opened, required this.sections});
  final List<String> opened;
  final List<String> sections;

  // Re-reads the session like the ME tab does.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SessionState>(
    valueListenable: SessionStore.instance,
    builder: (_, session, _) => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: HostStatusSection(
          host: HostProfile.from(session.expert)!,
          open: (route) async => opened.add(route),
          onShowDashboard: () => sections.add('dashboard'),
          onShowSettings: () => sections.add('settings'),
          profileLink: 'https://vibelive.angrymamba.com/aanyatalks',
          name: 'Aanya Sharma',
          email: 'aanya@b.co',
        ),
      ),
    ),
  );
}

void main() {
  late HostBackend backend;

  setUpAll(setUpHostHarness);

  testWidgets('approved host: first steps, go online, share, stats, menu', (
    tester,
  ) async {
    backend = await resetHost(expert: _host());
    backend.stats = {
      'total_earnings': 2450,
      'total_incoming_calls': 18,
      'average_rating': 4.8,
    };
    final opened = <String>[];
    final sections = <String>[];
    phone(tester);
    await pumpRoutes(tester, _Section(opened: opened, sections: sections));
    await pumpFor(tester, 400);

    expect(find.text("You're approved! 🎉"), findsOneWidget);
    expect(find.text('Go online'), findsOneWidget);
    expectFlat(tester, 'after-approval panel');
    expect(
      find.text('Share your profile with friends and followers'),
      findsOneWidget,
    );
    expect(find.text('vibelive.angrymamba.com/aanyatalks'), findsOneWidget);
    expect(find.text('₹2,450'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    for (final row in [
      'My Schedule',
      'Call Rates',
      'Analytics',
      'Profile',
      'Settings',
    ]) {
      expect(find.text(row), findsOneWidget);
    }

    // Copy link.
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
    await tapVisible(tester, find.text('Copy link'));
    await pumpFor(tester, 200);
    expect(copied, 'https://vibelive.angrymamba.com/aanyatalks');
    expect(find.text('Link copied'), findsOneWidget);
    await pumpFor(tester, 4500); // the toast leaves

    // Go online = RN "Go live": isActive + the admin notice.
    await tapVisible(tester, find.byKey(const ValueKey('host-go-online')));
    await pumpFor(tester, 800);
    final put = backend.sent('PUT', '/expert-profiles/exp1').single;
    expect(put.data, {
      'data': {'isActive': true},
    });
    expect(
      backend.sent('POST', '/notify-admin-expert-onboarded'),
      hasLength(1),
    );
    expect(SessionStore.instance.value.expert?['isActive'], isTrue);
    expect(find.text("You're online 🎉"), findsOneWidget); // stays for now

    await tapVisible(tester, find.text('My Schedule'));
    await tapVisible(tester, find.text('Call Rates'));
    await tapVisible(tester, find.text('Analytics'));
    await tapVisible(tester, find.text('Settings'));
    expect(opened, [AppRoutes.hostSchedule, AppRoutes.hostRates]);
    expect(sections, ['dashboard', 'settings']);
    await finishHost(tester);
  });

  testWidgets('a live host sees nothing extra; a pending one, the review', (
    tester,
  ) async {
    backend = await resetHost(expert: _host(active: true));
    phone(tester);
    await pumpRoutes(tester, const _Section(opened: [], sections: []));
    expect(find.text("You're approved! 🎉"), findsNothing);
    expect(find.text('Profile under review'), findsNothing);
    await finishHost(tester);

    backend = await resetHost(expert: _host(approved: false));
    backend.approvals = [
      {'id': 1, 'documentId': 'ap1', 'status': 'pending'},
    ];
    await pumpRoutes(tester, const _Section(opened: [], sections: []));
    await pumpFor(tester, 400);
    expect(find.text('Profile under review'), findsOneWidget);
    expectFlat(tester, 'review status card');
    await finishHost(tester);

    final opened = <String>[];
    backend = await resetHost(expert: _host(approved: false));
    backend.approvals = [
      {'id': 1, 'documentId': 'ap1', 'status': 'rejected'},
    ];
    await pumpRoutes(tester, _Section(opened: opened, sections: const []));
    await pumpFor(tester, 400);
    expect(find.text('Changes needed'), findsOneWidget);
    await tapVisible(tester, find.text('Edit and resubmit'));
    expect(opened, [AppRoutes.hostOnboarding]);
    await finishHost(tester);
  });

  testWidgets('Call Rates edit screen saves the rates patch', (tester) async {
    backend = await resetHost(expert: _host(active: true));
    phone(tester);
    await pumpRoutes(
      tester,
      const HostEditScreen(section: HostEditSection.rates),
    );
    expect(find.text('₹ 25'), findsOneWidget);
    expect(find.text('₹ 35'), findsOneWidget);
    expectFlat(tester, 'Call Rates edit');
    await tester.tap(find.bySemanticsLabel('Increase rate').last);
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await pumpFor(tester, 600);
    final put = backend.sent('PUT', '/expert-profiles/exp1').single;
    expect(put.data, {
      'data': {
        'rates': {'voiceCallRate': 25.0, 'videoCallRate': 40.0},
      },
    });
    await finishHost(tester);
  });

  testWidgets('My Schedule: vacation mode saves like RN (no slots)', (
    tester,
  ) async {
    backend = await resetHost(expert: _host(active: true));
    phone(tester);
    await pumpRoutes(
      tester,
      const HostEditScreen(section: HostEditSection.schedule),
    );
    expectFlat(tester, 'My Schedule edit');
    expect(find.text('Vacation mode'), findsOneWidget);
    expect(find.text('Or set a weekly schedule'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hostflow-vacation')));
    await pumpFor(tester, 300);
    // RN: vacation hides the custom schedule.
    expect(find.text('Or set a weekly schedule'), findsNothing);
    await tester.tap(find.text('Save changes'));
    await pumpFor(tester, 600);
    final put = backend.sent('PUT', '/expert-profiles/exp1').single;
    expect(put.data, {
      'data': {'vocationMode': true, 'callAnyTime': false},
    });
    await finishHost(tester);
  });

  testWidgets('ME segments: Expert Hub and Settings, every host state', (
    tester,
  ) async {
    Future<void> openMe(JsonMap? expert, {List<JsonMap>? approvals}) async {
      backend = await resetHost(expert: expert);
      if (approvals != null) backend.approvals = approvals;
      backend.stats = {'total_earnings': 2450, 'total_incoming_calls': 18};
      phone(tester);
      await tester.pumpWidget(
        VibeLiveApp(
          themeController: ThemeController(ThemeMode.light),
          localeController: LocaleController(const Locale('en')),
        ),
      );
      appRouter.go('${AppRoutes.home}?tab=me');
      await pumpFor(tester, 1200);
    }

    final list = find.descendant(
      of: find.byType(InfiniteScroll),
      matching: find.byType(Scrollable),
    );

    // Live host: Expert Hub (figures, then rate / availability chips).
    await openMe(_host(active: true));
    expect(find.text('Expert Hub'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('₹2,450'), findsOneWidget); // lifetime earnings
    await tester.scrollUntilVisible(
      find.text('Custom hours'),
      300,
      scrollable: list,
    );
    expect(find.text('₹25/min'), findsOneWidget);
    expect(find.text('₹35/min'), findsOneWidget);
    // Side by side (the wide test font wraps the third one cleanly).
    expect(
      tester.getCenter(find.text('₹25/min')).dy,
      tester.getCenter(find.text('₹35/min')).dy,
    );
    expect(find.text('Approval Status'), findsNothing); // hub: Settings only
    await tester.scrollUntilVisible(
      find.text('Settings'),
      -300,
      scrollable: list,
    );
    await tester.tap(find.text('Settings'));
    await pumpFor(tester, 400);
    expect(find.text('MY WALLET'), findsOneWidget);
    expect(find.text('₹2,450'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Approval Status'),
      200,
      scrollable: list,
    );
    expect(find.text('Professional Details'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Expert Hub'),
      -300,
      scrollable: list,
    );
    await tester.tap(find.text('Expert Hub'));
    await pumpFor(tester, 400);
    expect(find.text('₹2,450'), findsOneWidget);
    expect(find.text('MY WALLET'), findsNothing);
    await finishHost(tester);

    // Pending review, rejected, on vacation: same segments, own status.
    await openMe(
      _host(approved: false),
      approvals: [
        {'id': 1, 'documentId': 'ap1', 'status': 'pending'},
      ],
    );
    expect(find.text('Profile under review'), findsOneWidget);
    expect(find.text('Expert Hub'), findsOneWidget);
    await finishHost(tester);

    await openMe(
      _host(approved: false),
      approvals: [
        {'id': 1, 'documentId': 'ap1', 'status': 'rejected'},
      ],
    );
    expect(find.text('Changes needed'), findsOneWidget);
    await finishHost(tester);

    await openMe({..._host(active: true), 'vocationMode': true});
    await tester.scrollUntilVisible(
      find.text('Vacation mode'),
      200,
      scrollable: list,
    );
    expect(find.text('Vacation mode'), findsOneWidget); // My Schedule row
    await finishHost(tester);

    // A client keeps the client layout: no segments.
    await openMe(null);
    expect(find.text('Expert Hub'), findsNothing);
    expect(find.text('MY WALLET'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('segment labels are centred in the pill at 320 and 430 px', (
    tester,
  ) async {
    for (final width in [320.0, 430.0]) {
      backend = await resetHost(expert: _host(active: true));
      phone(tester, size: Size(width, 860));
      await tester.pumpWidget(
        VibeLiveApp(
          themeController: ThemeController(ThemeMode.light),
          localeController: LocaleController(const Locale('en')),
        ),
      );
      appRouter.go('${AppRoutes.home}?tab=me');
      await pumpFor(tester, 1000);
      for (final label in ['Expert Hub', 'Settings']) {
        final text = tester.getRect(find.text(label));
        final pill = tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(Pressable))
              .first,
        );
        expect(
          (text.center.dy - pill.center.dy).abs(),
          lessThan(1.5),
          reason: '$label at $width px',
        );
        expect(text.top, greaterThan(pill.top));
        expect(text.bottom, lessThan(pill.bottom));
      }
      await finishHost(tester);
    }
  });

  testWidgets('ME: "Become a Host" opens the new flow', (tester) async {
    backend = await resetHost();
    phone(tester);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.light),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go('${AppRoutes.home}?tab=me');
    await pumpFor(tester, 900);

    final row = find.text('Become a Host');
    await Scrollable.ensureVisible(tester.element(row.first), alignment: 0.4);
    await tester.pump();
    await tester.tap(row.first);
    await pumpFor(tester, 900);
    expect(find.byType(HostOnboardingScreen), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    await finishHost(tester);
  });
}
