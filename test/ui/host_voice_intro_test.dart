import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/profile_patch.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/voice_step.dart';
import 'package:vibelive/app/hosthub/onboarding/widgets/voice_intro_field.dart';

import 'host_onboarding_support/harness.dart';

void main() {
  setUpAll(() async {
    await setUpHostHarness();
  });

  late HostDraftController draft;

  setUp(() async {
    await resetHost();
    draft = HostDraftController('voice', persist: false);
  });

  Future<void> open(WidgetTester tester, {Widget? child}) async {
    phone(tester);
    await pumpRoutes(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [child ?? HostVoiceIntroField(draft: draft)],
        ),
      ),
    );
    await pumpFor(tester, 300);
  }

  Finder record() => find.bySemanticsLabel('Record voice intro');
  Finder stop() => find.bySemanticsLabel('Stop recording');

  testWidgets('record with a live timer, then listen, re-record or delete', (
    tester,
  ) async {
    await open(tester);
    // The guide: 1 Record, 2 Listen, 3 Done.
    for (final step in ['Record', 'Listen', 'Done']) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.text('Tap to record'), findsOneWidget);
    expect(find.text('Up to 30 seconds'), findsOneWidget);
    await tester.tap(record());
    await tester.pump();
    expect(find.text('0:00 / 0:30'), findsOneWidget);
    expect(find.text('Tap to stop'), findsOneWidget);

    await pumpFor(tester, 3000);
    expect(find.text('0:03 / 0:30'), findsOneWidget);
    await tester.tap(stop());
    await pumpFor(tester, 200);

    final intro = draft.voiceIntro.value!;
    expect(intro.isNew, isTrue);
    expect(intro.seconds, inInclusiveRange(3, 4));
    expect(File(intro.path!).existsSync(), isTrue);
    expect(find.text('Tap to listen'), findsOneWidget);
    // Next: listen to it once. Play, Re-record and Delete are buttons.
    expect(find.textContaining('Now listen to it once'), findsOneWidget);
    expect(find.bySemanticsLabel('Play voice intro'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Re-record'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await pumpFor(tester, 200);
    expect(draft.voiceIntro.value, isNull);
    expect(find.text('Tap to record'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('it stops by itself at 30 seconds', (tester) async {
    await open(tester);
    await tester.tap(record());
    await pumpFor(tester, 31000);
    expect(stop(), findsNothing);
    expect(draft.voiceIntro.value!.seconds, 30);
    await finishHost(tester);
  });

  testWidgets('a refused microphone records nothing and says why', (
    tester,
  ) async {
    FakeVoiceRecorder.allow = false;
    await open(tester);
    await tester.tap(record());
    await pumpFor(tester, 400);
    expect(
      find.text('Allow microphone access to record your voice intro.'),
      findsOneWidget,
    );
    expect(draft.voiceIntro.value, isNull);
    await finishHost(tester);
  });

  testWidgets('a slip under a second is dropped', (tester) async {
    await open(tester);
    await tester.tap(record());
    await pumpFor(tester, 300);
    await tester.tap(stop());
    await pumpFor(tester, 300);
    expect(draft.voiceIntro.value, isNull);
    expect(find.text('Too short. Hold on a little longer.'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('a saved intro stays until a new one replaces it', (
    tester,
  ) async {
    const url = 'https://cdn.example/intro.m4a';
    draft.voiceIntro.value = const HostVoiceIntro(
      savedMediaId: 9,
      savedUrl: url,
    );
    await open(tester);
    expect(find.text('Tap to listen'), findsOneWidget);
    expect(find.textContaining('Your current voice intro'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(draft.voiceIntro.value!.upload, isNull); // nothing to re-send

    await tester.tap(find.text('Re-record'));
    await pumpFor(tester, 2000);
    await tester.tap(stop());
    await pumpFor(tester, 200);
    // Uploaded in the background as soon as it stops: the save sends its id.
    expect((draft.voiceIntro.value!.upload! as HostMediaId).id, 801);

    // Dropping the new one brings the saved one back.
    await tester.tap(find.text('Delete'));
    await pumpFor(tester, 200);
    expect(draft.voiceIntro.value!.isNew, isFalse);
    expect(draft.voiceIntro.value!.savedUrl, url);
    await finishHost(tester);
  });

  testWidgets('the Voice step: an opener with their name and topics, tips', (
    tester,
  ) async {
    draft.name.text = 'Aanya Sharma';
    draft.topics.value = const [
      HostTopic(value: 'a', label: 'Dating advice'),
      HostTopic(value: 'b', label: 'Self-love'),
    ];
    await open(tester, child: VoiceStep(draft: draft));
    expect(find.text('Introduce yourself'), findsOneWidget);
    expect(
      find.textContaining(
        "Hi, I'm Aanya! I love talking about dating advice and self-love.",
      ),
      findsOneWidget,
    );
    expect(find.text('What to say'), findsOneWidget);
    expect(
      find.textContaining('You can re-record it as many times'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await finishHost(tester);
  });
}
