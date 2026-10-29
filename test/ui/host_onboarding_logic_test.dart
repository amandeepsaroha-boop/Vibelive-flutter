import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/onboarding_models.dart';
import 'package:vibelive/app/api/hosthub/profile_patch.dart';
import 'package:vibelive/app/api/authscreen/interests_models.dart';
import 'package:vibelive/app/api/client/client_models.dart';
import 'package:vibelive/app/api/hosthub/catalog_models.dart';
import 'package:vibelive/app/api/hosthub/profile_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_controller.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/draft_models.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/prefill.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/schedule_format.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/submit_plan.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/suggestions.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/validation.dart';
import 'package:vibelive/app/hosthub/onboarding/steps/rates_step.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

/// The English templates, straight from the namespace file.
HostTranslate _en() {
  final file = File('assets/i18n/en/hostflow.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (key, vars) {
    Object? node = json;
    for (final part in key.split(':').last.split('.')) {
      node = (node as Map)[part];
    }
    var s = node as String;
    vars.forEach((k, v) => s = s.replaceAll('{{$k}}', '$v'));
    return s;
  };
}

HostDraftController _complete() {
  final d = HostDraftController('t', persist: false)
    ..name.text = 'Aanya Sharma'
    ..handle.text = 'aanyatalks'
    ..tagline.text = 'Good conversations, music and everyday stories.'
    ..bio.text = 'I love meeting new people and having real conversations.';
  d.gender.value = 'Female';
  d.voiceIntro.value = const HostVoiceIntro(
    savedMediaId: 7,
    savedUrl: 'https://cdn.example/intro.m4a',
  );
  d.languages.value = const [HostOption(id: 5, label: 'English')];
  d.state.value = const GeoOption({'id': 4, 'name': 'Assam'});
  d.district.value = const GeoOption({'id': 9, 'name': 'Baksa'});
  d.topics.value = const [HostTopic(value: 'topic_a', label: 'Dating advice')];
  d.photos.value = const [HostDraftPhoto(key: 'm1', mediaId: 1)];
  return d;
}

void main() {
  setUpAll(setUpHostHarness);

  group('validation', () {
    test('a complete draft passes every step', () {
      final d = _complete();
      d.agreed.value = true;
      for (final s in HostStep.values) {
        expect(HostValidation.check(s, d), isNull, reason: '$s');
      }
    });

    test('handle: 3–30 of a–z and _', () {
      final d = _complete();
      for (final bad in ['ab', 'Aanya', 'aanya1', 'a-b-c', '']) {
        d.handle.text = bad;
        expect(HostValidation.basic(d)?.key, 'hostflow:errors.handle_invalid');
      }
      d.handle.text = 'a' * 31;
      expect(HostValidation.basic(d)?.key, 'hostflow:errors.handle_invalid');
      d.handle.text = 'aanya_talks';
      expect(HostValidation.basic(d), isNull);
    });

    test('basic step: gender, languages and location are required', () {
      final d = _complete()..gender.value = null;
      expect(HostValidation.basic(d)?.key, 'hostflow:errors.gender');
      d.gender.value = 'Others';
      d.languages.value = const [];
      expect(HostValidation.basic(d)?.key, 'hostflow:errors.languages');
      d.languages.value = const [HostOption(id: 5, label: 'English')];
      d.district.value = null;
      expect(HostValidation.basic(d)?.key, 'hostflow:errors.location');
    });

    test('photos: at least one uploaded, none still uploading', () {
      final d = _complete()..photos.value = const [];
      expect(HostValidation.photos(d)?.key, 'hostflow:errors.photos');
      d.photos.value = const [HostDraftPhoto(key: 'l1', localPath: '/x.jpg')];
      expect(HostValidation.photos(d)?.key, 'hostflow:errors.photos_uploading');
      d.photos.value = const [
        HostDraftPhoto(key: 'l1', localPath: '/x.jpg', failed: true),
      ];
      expect(HostValidation.photos(d)?.key, 'hostflow:errors.photos');
    });

    test('interests: at least one', () {
      final d = _complete()..topics.value = const [];
      expect(
        HostValidation.check(HostStep.interests, d)?.key,
        'hostflow:errors.interests',
      );
    });

    test('rates: one format on, each above the pricing floor', () {
      final d = _complete();
      d.audioOn.value = false;
      d.videoOn.value = false;
      expect(HostValidation.rates(d, 7, 12)?.key, 'hostflow:errors.rates_none');
      d.audioOn.value = true;
      d.audioRate.value = 5;
      final issue = HostValidation.rates(d, 7, 12)!;
      expect(issue.key, 'hostflow:errors.rate_audio_min');
      expect(issue.variables, {'min': 10}); // 7 rounded up to a ₹5 step
      d.audioRate.value = 10;
      expect(HostValidation.rates(d, 7, 12), isNull);
      expect(HostValidation.ratesOf(d).toJson(), {
        'voiceCallRate': 10.0,
        'videoCallRate': 0.0,
      });
    });

    test('availability: now, or at least one day', () {
      final d = _complete()
        ..availableNow.value = false
        ..week.value = {
          for (final day in HostWeekday.values)
            day: const HostDaySlot(enabled: false),
        };
      expect(
        HostValidation.availability(d)?.key,
        'hostflow:errors.availability',
      );
      d.setDay(HostWeekday.friday, const HostDaySlot(enabled: true));
      expect(HostValidation.availability(d), isNull);
      d.setDay(HostWeekday.friday, const HostDaySlot(enabled: false));
      d.vacation.value = true; // RN: vacation needs no slots
      expect(HostValidation.availability(d), isNull);
    });
  });

  group('suggestions', () {
    final t = _en();

    test('taglines: three, within 60 characters, paged', () {
      final topics = ['Dating advice', 'Self-love & confidence', 'Music'];
      final first = HostSuggestions.taglines(t, topics, 0);
      expect(first, hasLength(3));
      expect(first.every((s) => s.length <= 60), isTrue);
      expect(first.where((s) => s.contains('dating advice')), isNotEmpty);
      final next = HostSuggestions.taglines(t, topics, 1);
      expect(next, isNot(equals(first)));
      expect(HostSuggestions.taglines(t, topics, 0), first); // deterministic
    });

    test('no topics: general ideas only', () {
      final ideas = HostSuggestions.taglines(t, const [], 0);
      expect(ideas, hasLength(3));
      expect(
        ideas.first,
        'A safe space to share stories, laugh and be '
        'yourself.',
      );
    });

    test('bios: two, the first names a topic', () {
      final ideas = HostSuggestions.bios(t, const ['Music', 'Movies'], 0);
      expect(ideas, hasLength(2));
      expect(ideas.first, contains('music'));
      expect(ideas.every((s) => s.length <= 500), isTrue);
    });

    test('topic words keep acronyms', () {
      expect(HostSuggestions.topicWord('Self-love'), 'self-love');
      expect(HostSuggestions.topicWord('AI & tech'), 'AI & tech');
    });
  });

  group('submit plan', () {
    final form = InterestForm.fromJson(interestForm);

    test('every question is answered from the draft', () {
      final d = _complete();
      d.videoOn.value = true;
      d.audioOn.value = false;
      d.gender.value = 'Male';
      d.languages.value = const [
        HostOption(id: 22, label: 'हिंदी'),
        HostOption(id: 5, label: 'English'),
      ];
      d.topics.value = const [
        HostTopic(value: 'topic_feeling_low', label: 'Feeling low'),
        HostTopic(value: 'gone', label: 'Removed topic'),
      ];
      expect(HostSubmitPlan.expertise(form, d), {
        'gender_pref': ['gender_pref_any'],
        'user_gender': ['user_gender_male'],
        'support_topic': ['topic_feeling_low'],
        'interaction_mode': ['mode_video'],
        'expert_language': ['English', 'lang_hindi'],
      });
    });

    test('user patch only carries what changed', () {
      final me = UserWithExpert.fromUser(meUser());
      final d = _complete();
      d.state.value = const GeoOption({
        'id': 4,
        'documentId': 'st4',
        'name': 'Assam',
      });
      d.district.value = const GeoOption({
        'id': 9,
        'documentId': 'd9',
        'name': 'Baksa',
      });
      expect(HostSubmitPlan.userPatch(d, me), isEmpty);
      d.name.text = 'Aanya S.';
      d.district.value = const GeoOption({'id': 10, 'name': 'Barpeta'});
      final patch = HostSubmitPlan.userPatch(d, me);
      expect(patch['name'], 'Aanya S.');
      expect(patch['district'], {
        'connect': [
          {'id': 10},
        ],
      });
      expect((patch['address_JSON'] as Map)['district'], 'Barpeta');
    });

    test('vacation is sent, and turns "call any time" off', () {
      final d = _complete()
        ..availableNow.value = true
        ..vacation.value = true;
      final input = HostSubmitPlan.build(
        d,
        userDocumentId: 'u1',
        form: form,
        me: UserWithExpert.fromUser(meUser()),
      );
      expect(input.vacation, isTrue);
      expect(input.callAnyTime, isFalse);
    });

    test('a new voice recording is uploaded; a saved one is left alone', () {
      final d = _complete();
      HostOnboardingInput build() => HostSubmitPlan.build(
        d,
        userDocumentId: 'u1',
        form: form,
        me: UserWithExpert.fromUser(meUser()),
      );
      expect(build().audioIntro, isNull); // optional

      d.voiceIntro.value = const HostVoiceIntro(
        savedMediaId: 7,
        savedUrl: 'https://cdn.example/old.m4a',
      );
      expect(build().audioIntro, isNull); // re-sending would re-queue review

      d.voiceIntro.value = d.voiceIntro.value!.withRecording(
        '/tmp/new.m4a',
        12,
      );
      final upload = build().audioIntro! as HostMediaFile;
      expect(upload.path, '/tmp/new.m4a');
      expect(upload.mimeType, 'audio/mp4');
      expect(upload.fileName, endsWith('.m4a'));

      // Uploaded in the background: the save sends its id, not the file.
      d.voiceIntro.value = d.voiceIntro.value!.withUploaded(801);
      expect((build().audioIntro! as HostMediaId).id, 801);
      final kept = HostDraftController('k', persist: false)
        ..restore(jsonDecode(jsonEncode(d.toJson())) as Map);
      expect(kept.voiceIntro.value?.uploadedId, isNull); // file gone: dropped
    });

    test('a disabled day is not saved; midnight is 23:59', () {
      final d = _complete();
      final week = HostSubmitPlan.week(d);
      expect(week.keys, hasLength(5));
      expect(week[HostWeekday.monday]!.single.toJson(), {
        'startTime': '18:00:00.000',
        'endTime': '23:59:00.000',
      });
      expect(HostScheduleFormat.parts(HostDaySlot.endOfDay), (
        h: 12,
        m: '00',
        pm: false,
      ));
      expect(HostScheduleFormat.parts(18 * 60), (h: 6, m: '00', pm: true));
    });

    test('earnings follow the RN commission rule', () {
      expect(hostEarnings(25, 40, 3), 15); // 40% beats the ₹3 minimum
      expect(hostEarnings(5, 40, 3), 2); // the ₹3 minimum wins
      expect(hostEarnings(2, 40, 3), 0); // never more than the rate
    });
  });

  group('prefill and draft', () {
    test('voice intro: prefilled from the profile, kept by the draft', () {
      final d = HostDraftController('v', persist: false);
      HostPrefill.apply(
        d,
        UserWithExpert.fromUser(meUser()),
        host: HostProfile.from({
          'documentId': 'exp1',
          'audio_intro': {'id': 7, 'url': 'https://cdn.example/old.m4a'},
        }),
      );
      expect(d.voiceIntro.value!.savedUrl, 'https://cdn.example/old.m4a');
      expect(d.voiceIntro.value!.isNew, isFalse);

      // A recording whose file is gone falls back to the saved intro.
      final file = File('${Directory.systemTemp.path}/voice_draft_test.m4a')
        ..writeAsBytesSync([1]);
      d.voiceIntro.value = d.voiceIntro.value!.withRecording(file.path, 5);
      final saved = jsonDecode(jsonEncode(d.toJson())) as Map;
      final again = HostDraftController('v2', persist: false)..restore(saved);
      expect(again.voiceIntro.value!.path, file.path);
      expect(again.voiceIntro.value!.seconds, 5);

      file.deleteSync();
      final gone = HostDraftController('v3', persist: false)..restore(saved);
      expect(gone.voiceIntro.value!.isNew, isFalse);
      expect(gone.voiceIntro.value!.savedUrl, 'https://cdn.example/old.m4a');
    });

    test('Personal Info fills an empty draft once', () {
      final d = HostDraftController('p', persist: false);
      HostPrefill.apply(
        d,
        UserWithExpert.fromUser(meUser()),
        answers: const {
          'user_gender': ['user_gender_female'],
        },
      );
      expect(d.name.text, 'Aanya Sharma');
      expect(d.handle.text, 'aanyasharma');
      expect(d.gender.value, 'Female');
      expect(d.state.value?.name, 'Assam');
      expect(d.district.value?.name, 'Baksa');
      d.name.text = 'Changed';
      HostPrefill.apply(d, UserWithExpert.fromUser(meUser()));
      expect(d.name.text, 'Changed'); // never overwritten
    });

    test('a host resubmitting starts from the saved profile', () {
      final d = HostDraftController('p', persist: false);
      final host = HostProfile.from({
        'documentId': 'exp9',
        'handler': 'riya',
        'tagline': 'Hello there friends',
        'gender': 'female',
        'callAnyTime': false,
        'rates': {'voiceCallRate': 20, 'videoCallRate': 0},
      });
      HostPrefill.apply(d, UserWithExpert.fromUser(meUser()), host: host);
      expect(d.expertId, 'exp9');
      expect(d.handle.text, 'riya');
      expect(d.gender.value, 'Female');
      expect(d.audioRate.value, 20);
      expect(d.videoOn.value, isFalse);
      expect(d.availableNow.value, isFalse);
    });

    test('the draft round-trips through prefs', () async {
      final d = _complete()..step.value = HostStep.rates;
      final json = jsonDecode(jsonEncode(d.toJson())) as Map;
      final back = HostDraftController('r', persist: false)..restore(json);
      expect(back.step.value, HostStep.rates);
      expect(back.handle.text, 'aanyatalks');
      expect(back.languages.value.single.connectRef, {'id': 5});
      expect(back.photos.value.single.mediaId, 1);
      expect(back.state.value?.name, 'Assam');

      final saved = HostDraftController('u9');
      saved.tagline.text = 'Saved line';
      saved.flush();
      expect(
        AppPrefs.getString('hostflow_draft_v1:u9'),
        contains('Saved line'),
      );
      expect(HostDraftController.load('u9').tagline.text, 'Saved line');
      await saved.clear();
      expect(AppPrefs.getString('hostflow_draft_v1:u9'), isNull);
    });
  });
  test('every hostflow / client key in the source exists in en and hi', () {
    Object? resolve(String lang, String ns, String path) {
      Object? node = jsonDecode(
        File('assets/i18n/$lang/$ns.json').readAsStringSync(),
      );
      for (final part in path.split('.')) {
        node = node is Map ? node[part] : null;
      }
      return node;
    }

    final literal = RegExp(r"'(hostflow|client):([A-Za-z0-9_.]+)'");
    final keys = <String>{
      // Built as `hostflow:errors.$issue` (HostDaySlot.check).
      for (final e in ['slot_order', 'slot_short', 'slot_overlap'])
        'hostflow:errors.$e',
    };
    for (final dir in ['lib/app/hosthub', 'lib/app/client/personal_info']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in literal.allMatches(f.readAsStringSync())) {
          keys.add(m[0]!.replaceAll("'", ''));
        }
      }
    }
    expect(keys.length, greaterThan(100));
    final missing = <String>[];
    for (final key in keys) {
      final [ns, path] = key.split(':');
      final en = resolve('en', ns, path);
      final hi = resolve('hi', ns, path);
      // A map is a prefix the code completes (`hostflow:suggest.tagline`).
      final ok = (en is String && hi is String) || (en is Map && hi is Map);
      if (!ok) missing.add(key);
    }
    expect(missing, isEmpty, reason: 'keys missing in en or hi');
  });
}
