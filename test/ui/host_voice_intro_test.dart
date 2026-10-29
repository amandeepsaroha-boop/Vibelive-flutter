import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/profile_patch.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/voice_recorder.dart';
import 'package:vibelive/app/hosthub/onboarding/widgets/voice_intro_field.dart';

import 'host_onboarding_support/harness.dart';

/// The microphone, faked: each recording is a small real file.
class _FakeRecorder extends HostVoiceRecorder {
  static late Directory dir;
  static bool allow = true;
  static int made = 0;

  String? _path;

  @override
  Future<bool> hasPermission() async => allow;

  @override
  Future<String> start() async {
    final path = '${dir.path}/voice${made++}.m4a';
    File(path).writeAsBytesSync([1, 2, 3]);
    return _path = path;
  }

  @override
  Future<String?> stop() async => _path;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(() async {
    await setUpHostHarness();
    _FakeRecorder.dir = Directory.systemTemp.createTempSync('voice_intro');
    HostVoiceRecorder.create = _FakeRecorder.new;
  });

  late HostDraftController draft;

  setUp(() async {
    await resetHost();
    _FakeRecorder.allow = true;
    draft = HostDraftController('voice', persist: false);
  });

  Future<void> open(WidgetTester tester) async {
    phone(tester);
    await pumpRoutes(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [HostVoiceIntroField(draft: draft)],
        ),
      ),
    );
    await pumpFor(tester, 300);
  }

  testWidgets('record with a live timer, then listen, re-record or delete', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Voice intro (optional)'), findsOneWidget);
    await tester.tap(find.text('RECORD VOICE INTRO'));
    await tester.pump();
    expect(find.text('STOP  0:00 / 0:30'), findsOneWidget);

    await pumpFor(tester, 3000);
    expect(find.text('STOP  0:03 / 0:30'), findsOneWidget);
    await tester.tap(find.textContaining('STOP'));
    await pumpFor(tester, 200);

    final intro = draft.voiceIntro.value!;
    expect(intro.isNew, isTrue);
    expect(intro.seconds, inInclusiveRange(3, 4));
    expect(File(intro.path!).existsSync(), isTrue);
    expect(find.text('RE-RECORD'), findsOneWidget);
    expect(find.textContaining('New recording'), findsOneWidget);
    expect(find.bySemanticsLabel('Play voice intro'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete recording'));
    await pumpFor(tester, 200);
    expect(draft.voiceIntro.value, isNull);
    expect(find.text('RECORD VOICE INTRO'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('it stops by itself at 30 seconds', (tester) async {
    await open(tester);
    await tester.tap(find.text('RECORD VOICE INTRO'));
    await pumpFor(tester, 31000);
    expect(find.textContaining('STOP'), findsNothing);
    expect(draft.voiceIntro.value!.seconds, 30);
    await finishHost(tester);
  });

  testWidgets('a refused microphone records nothing and says why', (
    tester,
  ) async {
    _FakeRecorder.allow = false;
    await open(tester);
    await tester.tap(find.text('RECORD VOICE INTRO'));
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
    await tester.tap(find.text('RECORD VOICE INTRO'));
    await pumpFor(tester, 300);
    await tester.tap(find.textContaining('STOP'));
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
    expect(find.text('RE-RECORD'), findsOneWidget);
    expect(find.textContaining('Your current voice intro'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete recording'), findsNothing);
    expect(draft.voiceIntro.value!.upload, isNull); // nothing to re-send

    await tester.tap(find.text('RE-RECORD'));
    await pumpFor(tester, 2000);
    await tester.tap(find.textContaining('STOP'));
    await pumpFor(tester, 200);
    final upload = draft.voiceIntro.value!.upload;
    expect(upload, isA<HostMediaFile>());
    expect((upload! as HostMediaFile).mimeType, 'audio/mp4');

    // Dropping the new one brings the saved one back.
    await tester.tap(find.bySemanticsLabel('Delete recording'));
    await pumpFor(tester, 200);
    expect(draft.voiceIntro.value!.isNew, isFalse);
    expect(draft.voiceIntro.value!.savedUrl, url);
    await finishHost(tester);
  });
}
