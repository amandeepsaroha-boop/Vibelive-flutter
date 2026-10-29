import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

void main() {
  late HostBackend backend;

  setUpAll(setUpHostHarness);
  setUp(() async => backend = await resetHost());

  Future<void> open(WidgetTester tester) async {
    phone(tester, top: 47, bottom: 34);
    await pumpRoutes(tester, const HostOnboardingScreen());
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('hostflow-start')));
    await pumpFor(tester, 800);
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey('hostflow-$key')))
      .controller!
      .text;

  testWidgets('intro, then Basic Profile pre-filled from Personal Info', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Become a Host'), findsOneWidget);
    expect(find.text('Talk about what you love'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('Log in'), findsNothing);

    await start(tester);
    expect(find.text('Tell us about yourself'), findsOneWidget);
    expect(find.text('2 of 12'), findsOneWidget);
    expect(fieldText(tester, 'name'), 'Aanya Sharma');
    expect(fieldText(tester, 'handle'), 'aanyasharma');
    expect(find.text('Assam'), findsOneWidget);
    expect(find.text('Baksa'), findsOneWidget);
    expect(find.text('English'), findsOneWidget); // default language
    expect(find.textContaining('aanyasharma'), findsWidgets); // link preview

    await pumpFor(tester, 600); // debounced handle check + draft save
    expect(find.byKey(const ValueKey('handle-ok')), findsOneWidget);
    final draft = savedDraft()!;
    expect(draft['gender'], 'Female'); // from the interests answers
    expect(draft['state']['name'], 'Assam');
    expect((draft['languages'] as List).single['label'], 'English');
    await finishHost(tester);
  });

  testWidgets('handle validation: format and uniqueness', (tester) async {
    await open(tester);
    await start(tester);
    final handle = find.byKey(const ValueKey('hostflow-handle'));

    await tester.enterText(handle, 'Ab');
    await pumpFor(tester, 600);
    expect(fieldText(tester, 'handle'), 'ab'); // lower-cased as typed
    await tapContinue(tester);
    expect(
      find.text('Choose a handle of 3–30 lowercase letters or underscores.'),
      findsOneWidget,
    );

    await tester.enterText(handle, 'taken_name');
    await pumpFor(tester, 700);
    expect(find.byKey(const ValueKey('handle-taken')), findsOneWidget);
    await tapContinue(tester);
    expect(
      find.text('This handle is already taken. Try another one.'),
      findsWidgets,
    );
    expect(find.text('Tell us about yourself'), findsOneWidget);

    await tester.enterText(handle, 'aanyatalks');
    await pumpFor(tester, 700);
    await tapContinue(tester, settle: 900);
    expect(find.text('What do you enjoy talking about?'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('full flow: validation per step, then the submit bodies', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    await pumpFor(tester, 600);
    await tester.enterText(
      find.byKey(const ValueKey('hostflow-handle')),
      'aanyatalks',
    );
    await pumpFor(tester, 600);
    await tapContinue(tester, settle: 900);

    // Interests: at least one.
    await tapContinue(tester);
    expect(find.text('Choose at least one topic.'), findsOneWidget);
    await tapVisible(tester, find.text('Dating advice'));
    await tapVisible(tester, find.text('Self-love & confidence'));
    expect(find.text('2 selected'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Photos: at least one; picked through the seam, uploaded at once.
    expect(find.text('Add your photos'), findsOneWidget);
    await tapContinue(tester);
    expect(find.text('Add at least one photo.'), findsOneWidget);
    await tapVisible(tester, find.text('Add photo'));
    await pumpFor(tester, 400);
    await tester.tap(find.text('Choose from gallery'));
    await pumpFor(tester, 600);
    expect(find.text('Primary'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Voice: required. Continue without one says so; then record 3 s.
    expect(find.text('Introduce yourself'), findsOneWidget);
    expect(find.text('5 of 12'), findsOneWidget);
    await tapContinue(tester);
    expect(
      find.text('Record a short voice intro to continue.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Record voice intro'));
    await pumpFor(tester, 3000);
    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await pumpFor(tester, 300);
    expect(find.text('Tap to listen'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Tagline: suggestions from the topics; "Use" fills the field.
    expect(find.text('Write a short tagline'), findsOneWidget);
    expect(find.text('Based on your interests'), findsOneWidget);
    // Ideas name the chosen topics and fit the 60-character limit.
    expect(find.textContaining('dating advice'), findsWidgets);
    expect(find.text('Use'), findsNWidgets(3));
    await tapContinue(tester);
    expect(
      find.text('Write a tagline of at least 10 characters.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use').first);
    await tester.pump();
    final tagline = fieldText(tester, 'tagline');
    expect(tagline.length, inInclusiveRange(10, 60));
    expect(find.text('${tagline.length}/60'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Bio.
    expect(find.text('A little more about you'), findsOneWidget);
    await tester.tap(find.text('Use').first);
    await tester.pump();
    await tapContinue(tester, settle: 900);

    // Rates: at least one format, defaults ₹25 / ₹35.
    expect(find.text('How would you like to connect?'), findsOneWidget);
    expect(find.text('₹ 25'), findsOneWidget);
    expect(find.text('₹ 35'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Increase rate').first);
    await tester.pump();
    expect(find.text('₹ 30'), findsOneWidget);
    // Video off, then audio off: refused.
    final videoSwitch = find.byKey(
      const ValueKey('hostflow-switch-hostflow:rates.video'),
    );
    final audioSwitch = find.byKey(
      const ValueKey('hostflow-switch-hostflow:rates.audio'),
    );
    await tester.tap(videoSwitch);
    await pumpFor(tester, 300);
    expect(find.text('₹ 35'), findsNothing);
    await tester.tap(audioSwitch);
    await pumpFor(tester, 300);
    await tapContinue(tester);
    expect(
      find.text('Turn on audio calls, video calls or both.'),
      findsOneWidget,
    );
    await tester.tap(audioSwitch);
    await pumpFor(tester, 300);
    expect(find.text('₹ 30'), findsOneWidget); // kept while switched off
    await tapContinue(tester, settle: 900);

    // Availability: "Call any time" by default, so no schedule (RN).
    expect(find.text('When can people call you?'), findsOneWidget);
    expect(find.text('6:00 PM – 12:00 AM'), findsNothing);
    // Weekly slots: Mon–Fri evenings; Monday gets a second slot.
    await tapVisible(tester, find.byKey(const ValueKey('hostflow-weekly')));
    await pumpFor(tester, 300);
    expect(find.text('6:00 PM – 12:00 AM'), findsNWidgets(5));
    expect(find.text('Unavailable'), findsNWidgets(2));
    await tapVisible(tester, find.byKey(const ValueKey('slot-add-monday')));
    await pumpFor(tester, 500);
    await tester.tap(find.text('Save'));
    await pumpFor(tester, 500);
    expect(find.text('9:00 AM – 10:00 AM'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Preview: how clients see it; Edit goes to the step and comes back.
    expect(find.text('10 of 12'), findsOneWidget);
    expect(find.text('Preview your profile'), findsOneWidget);
    // The client sheet's own header: name in capitals, then the city.
    expect(find.text('AANYA SHARMA'), findsOneWidget);
    expect(find.text('BAKSA'), findsOneWidget);
    expect(find.text('Online'), findsNothing); // weekly slots, not "any time"
    expect(find.text('₹30/min'), findsOneWidget);
    expect(find.text('Video calls'), findsNothing); // video is off
    await tapVisible(tester, find.byKey(const ValueKey('preview-edit-about')));
    await pumpFor(tester, 500);
    expect(find.text('Write a short tagline'), findsOneWidget);
    await tapContinue(tester, settle: 700);
    expect(find.text('Preview your profile'), findsOneWidget);
    await tapContinue(tester, settle: 900);

    // Guidelines: Submit stays disabled until the box is ticked.
    expect(find.text('11 of 12'), findsOneWidget);
    expect(
      find.text('A few things to keep VibeLive welcoming'),
      findsOneWidget,
    );
    await tapContinue(tester);
    expect(find.text('11 of 12'), findsOneWidget);
    expect(backend.sent('POST', '/expert-profiles'), isEmpty);
    // Back from 10 is 9.
    await tester.tap(find.bySemanticsLabel('Back'));
    await pumpFor(tester, 500);
    expect(find.text('Preview your profile'), findsOneWidget);
    await tapContinue(tester, settle: 900);
    await tapVisible(tester, find.byKey(const ValueKey('hostflow-agree')));
    await tapContinue(tester, settle: 1500);

    // ── What was sent ────────────────────────────────────────────────────
    final created = backend.sent('POST', '/expert-profiles').single;
    final data = (created.data! as Map)['data'] as Map;
    // The voice intro: uploaded once recorded, attached as `audio_intro`.
    expect(data['audio_intro'], 801);
    expect(data['handler'], 'aanyatalks');
    expect(data['gender'], 'Female');
    expect(data['user'], 'u1');
    expect(data['tagline'], tagline);
    expect((data['descriptions'] as String).length, greaterThan(30));
    expect(data['language'], {
      'connect': [
        {'documentId': 'l5'},
      ],
    });

    final photo = backend.sent('POST', '/profile-images').single;
    expect((photo.data! as Map)['data'], {
      'host_image': 'exp50',
      'image': 77,
      'priority': 1,
      'isprimary': true,
    });

    final userPut = backend.sent('PUT', '/public-users/u1').single;
    expect((userPut.data! as Map)['data'], {
      'profilePic': 77,
      'role': 'Expert',
    });

    final areas = backend.sent('PUT', '/me/service-areas').single;
    expect((areas.data! as Map)['source'], 'professional-details');
    expect((areas.data! as Map)['selections'], {
      'gender_pref': ['gender_pref_any'],
      'user_gender': ['user_gender_female'],
      'support_topic': ['topic_dating_advice', 'topic_self_love'],
      'interaction_mode': ['mode_audio'],
      'expert_language': ['English'],
    });

    final settings = backend.sent('PUT', '/expert-profiles/exp50').single;
    final s = (settings.data! as Map)['data'] as Map;
    expect(s['rates'], {'voiceCallRate': 30.0, 'videoCallRate': 0.0});
    expect(s['callAnyTime'], isFalse);
    expect(s['vocationMode'], isFalse);
    final schedule = s['schedule'] as List;
    expect(schedule, hasLength(5));
    expect(schedule.first, {
      'days': 'Monday',
      'timeSlots': [
        {'startTime': '09:00:00.000', 'endTime': '10:00:00.000'},
        {'startTime': '18:00:00.000', 'endTime': '23:59:00.000'},
      ],
    });
    expect(schedule[1]['days'], 'Tuesday '); // backend enum value

    final approval = backend.sent('POST', '/expert-profile-approvals').single;
    expect(approval.data, {
      'data': {'expert_profile': 'exp50'},
    });

    // ── Submitted ────────────────────────────────────────────────────────
    expect(find.text('Your profile is submitted!'), findsOneWidget);
    expect(find.text('12 of 12'), findsOneWidget);
    expect(find.text('Profile submitted'), findsOneWidget);
    expect(find.text('We review your details'), findsOneWidget);
    expect(find.text("You'll be notified"), findsOneWidget);
    expect(find.text('Explore VibeLive'), findsOneWidget);
    expect(savedDraft(), isNull); // the draft is gone for good

    await tapContinue(tester, settle: 600);
    expect(find.text('HOME discover'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('a saved draft resumes on its step with its answers', (
    tester,
  ) async {
    await AppPrefs.setString(
      'hostflow_draft_v1:u1',
      jsonEncode({
        'step': 'tagline',
        'started': true,
        'seeded': true,
        'name': 'Aanya Sharma',
        'handle': 'aanyatalks',
        'tagline': 'Good conversations, music and everyday stories.',
        'gender': 'Female',
        'topics': [
          {'value': 'topic_feeling_low', 'label': 'Feeling low', 'emoji': ''},
        ],
        'photos': [
          {'key': 'm77', 'mediaId': 77},
        ],
      }),
    );
    await open(tester);
    expect(find.text('Write a short tagline'), findsOneWidget);
    expect(find.text('6 of 12'), findsOneWidget);
    expect(
      fieldText(tester, 'tagline'),
      'Good conversations, music and everyday stories.',
    );
    expect(find.text('47/60'), findsOneWidget);

    // Back walks the steps; the intro then offers "Continue setup".
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.bySemanticsLabel('Back'));
      await pumpFor(tester, 450);
    }
    expect(find.text('Continue setup'), findsOneWidget);
    expect(savedDraft()!['step'], 'intro');
    await finishHost(tester);
  });
}
