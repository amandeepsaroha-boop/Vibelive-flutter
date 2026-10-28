import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/hosthub/approval_api.dart';
import 'package:vibelive/app/api/hosthub/approval_models.dart';
import 'package:vibelive/app/api/hosthub/catalog_api.dart';
import 'package:vibelive/app/api/hosthub/catalog_models.dart';
import 'package:vibelive/app/api/hosthub/eligibility.dart';
import 'package:vibelive/app/api/hosthub/expertise_api.dart';
import 'package:vibelive/app/api/hosthub/expertise_models.dart';
import 'package:vibelive/app/api/hosthub/images_api.dart';
import 'package:vibelive/app/api/hosthub/profile_api.dart';
import 'package:vibelive/app/api/hosthub/profile_models.dart';
import 'package:vibelive/app/api/hosthub/profile_patch.dart';
import 'package:vibelive/app/api/hosthub/stats_api.dart';
import 'package:vibelive/app/api/hosthub/stats_models.dart';
import 'package:vibelive/app/api/hosthub/verification_api.dart';
import 'package:vibelive/app/api/hosthub/verification_models.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';

/// Records requests and answers them from [handler].
class _FakeBackend implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  ResponseBody Function(RequestOptions o) handler = (_) =>
      _json({'data': <Object>[]});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _notFound() => _json({
  'error': {'status': 404, 'message': 'Not Found'},
}, status: 404);

String _call(RequestOptions o) => '${o.method} ${o.path}';

/// Every key of a nested i18n JSON, dotted.
Set<String> _keys(Map<String, dynamic> json, [String prefix = '']) => {
  for (final e in json.entries)
    if (e.value is Map)
      ..._keys(Map<String, dynamic>.from(e.value as Map), '$prefix${e.key}.')
    else
      '$prefix${e.key}',
};

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostStats', () {
    test('normalizes v4 and v5 rows, defaults bad fields to 0', () {
      final v5 = HostStats.fromRow({
        'id': 1,
        'total_profile_views': '120',
        'average_rating': 4.5,
        'total_earnings': 'NaN',
        'missed_call_percentage': null,
      });
      expect(v5.hasRecord, isTrue);
      expect(v5.profileViews, 120);
      expect(v5.averageRating, 4.5);
      expect(v5.totalEarnings, 0);
      expect(v5.missedCallPct, 0);
      expect(v5.repeatCallers, 0);

      final v4 = HostStats.fromRow({
        'id': 2,
        'attributes': {'total_incoming_calls': 7, 'total_repeat_callers': 3},
      });
      expect(v4.totalCalls, 7);
      expect(v4.repeatCallers, 3);

      expect(HostStats.fromRow(null).hasRecord, isFalse);
      expect(HostStats.empty.totalEarnings, 0);
    });

    test('round-trips through the persisted JSON', () {
      final stats = HostStats.fromRow({'total_referrals': 9});
      final back = HostStats.fromJson(jsonDecode(jsonEncode(stats.toJson())));
      expect(back.totalReferrals, 9);
      expect(back.hasRecord, isTrue);
      expect(HostStats.fromJson(HostStats.empty.toJson()).hasRecord, isFalse);
    });

    test('formats en-IN numbers, rupees, percents and durations', () {
      expect(HostStats.formatNumber(100000), '1,00,000');
      expect(HostStats.formatCurrency(1234.5), '₹1,234.50');
      expect(HostStats.formatCurrency(250000), '₹2,50,000');
      expect(HostStats.formatPercent(42.46), '42.5%');
      expect(HostStats.formatPercent(42), '42%');
      expect(HostStats.formatPercent(double.nan), '0%');
      final d = HostStats.splitMinutes(3 + 1 / 3);
      expect((d.minutes, d.seconds), (3, 20));
    });
  });

  group('HostEligibility', () {
    const complete = {
      'name': 'Asha',
      'email': 'asha@example.com',
      'mobile': '+91 98765 43210',
      'state': {
        'data': {
          'id': 1,
          'attributes': {'name': 'Goa'},
        },
      },
      'address_JSON': {'district': 'North Goa'},
    };

    test('personal info: relations or address_JSON both count', () {
      expect(HostEligibility.missingPersonalInfo(complete), isEmpty);
      expect(
        HostEligibility.missingPersonalInfo({
          'name': ' ',
          'email': 'nope@x',
          'mobile': '12345',
          'district': [
            {'districtNames': 'Pune'},
          ],
        }),
        [
          PersonalInfoField.fullName,
          PersonalInfoField.email,
          PersonalInfoField.mobile,
          PersonalInfoField.state,
        ],
      );
      expect(PersonalInfoField.state.i18nKey, 'hosthub:personal_fields.state');
    });

    test('badge step follows approval and the furthest verification', () {
      expect(HostEligibility.badgeStep(null), isNull);
      expect(HostEligibility.badgeStep({'id': 1}), isNull);
      expect(HostEligibility.canApplyForBadge({'id': 1}), isFalse);

      final approved = {
        'id': 1,
        'attributes': {'isApproved': 'true'},
      };
      expect(HostEligibility.canApplyForBadge(approved), isTrue);
      expect(HostEligibility.badgeStep(approved), VerificationStep.fee);
      expect(HostEligibility.badgePromptKey(approved), 'hosthub:badge.apply');

      final rows = {
        'id': 1,
        'isApproved': true,
        'expert_verifications': [
          {'Payment_Received': false},
          {'Payment_Received': true, 'is_form_submitted': true},
          {'Payment_Received': true},
        ],
      };
      expect(HostEligibility.badgeStep(rows), VerificationStep.review);
      expect(HostEligibility.badgePromptKey(rows), isNull);
      expect(
        HostEligibility.badgeStep({'documentId': 'd', 'isVerified': 1}),
        VerificationStep.success,
      );
    });
  });

  group('VerificationRecord', () {
    test('next step: unpaid is always fee', () {
      expect(VerificationRecord.nextStepOf(null), VerificationStep.fee);
      expect(
        VerificationRecord.nextStepOf({'Verified_Badge': true}),
        VerificationStep.fee,
      );
      expect(
        VerificationRecord.nextStepOf({'Payment_Received': 'approved'}),
        VerificationStep.form,
      );
      expect(
        VerificationRecord.nextStepOf({
          'Payment_Received': 1,
          'Verified_Badge': 'verified',
        }),
        VerificationStep.success,
      );
    });

    test('prefers the furthest row, then the newest', () {
      VerificationRecord r(int id, JsonLike data) =>
          VerificationRecord({'id': id, ...data});
      final best = VerificationRecord.pickPreferred([
        r(1, {'Payment_Received': true, 'updatedAt': '2026-05-01T00:00:00Z'}),
        r(2, {'Payment_Received': true, 'updatedAt': '2026-06-01T00:00:00Z'}),
        r(3, {'updatedAt': '2026-09-01T00:00:00Z'}),
      ]);
      expect(best?.id, 2);
      expect(VerificationRecord.pickPreferred(const []), isNull);
    });

    test('form progress resumes on the identity step', () {
      final empty = const VerificationRecord({}).formProgress;
      expect(empty.complete, isFalse);
      expect(empty.nextStepId, 'identity');
      final done = const VerificationRecord({
        'identity_doc_file': 'PAN CARD',
        'identity_document_number': 'ABCDE1234F',
        'identity_doc_frontside': {
          'data': {'id': 5},
        },
        'identity_doc_backside': [
          {'url': '/u/b.jpg'},
        ],
      }).formProgress;
      expect(done.complete, isTrue);
      expect(done.nextStepIndex, 0);
    });

    test('update builders sanitize like the RN form', () {
      final id = VerificationUpdate.identity(
        'v1',
        docType: 'AADHAR CARD',
        docNumber: '1234 5678 9012 99',
        linkedInUrl: 'not a url',
      );
      expect(id.data['identity_document_number'], '123456789012');
      expect(id.data['LinkedIn_Url'], isNull);
      expect(id.status, 'draft');
      expect(
        VerificationUpdate.sanitizeIdentityNumber('PAN CARD', ' abcde 1234f '),
        'ABCDE1234F',
      );

      final submit = VerificationUpdate.submit(
        'v1',
        platform: SocialPlatform.facebook,
        url: ' https://facebook.com/me ',
      );
      expect(submit.status, 'published');
      expect(submit.changesBadgeStep, isTrue);
      expect(submit.data, {
        'is_form_submitted': true,
        'insta_url': null,
        'facebook_url': 'https://facebook.com/me',
        'snapchat_url': null,
      });
      expect(VerificationUpdate.markPaid('v1').changesBadgeStep, isTrue);
    });
  });

  group('HostProfile', () {
    final host = HostProfile.from({
      'data': {
        'id': 7,
        'attributes': {
          'documentId': 'exp7',
          'handler': 'asha_k',
          'tagline': 'Career coach',
          'descriptions': 'Ten years of hiring.',
          'language': {
            'data': [
              {
                'id': 1,
                'attributes': {'name': 'Hindi'},
              },
            ],
          },
          'rates': {'voiceCallRate': '12', 'videoCallRate': null},
          'schedule': [
            {
              'days': 'Tuesday ',
              'timeSlots': [
                {'startTime': '14:00:00.000', 'endTime': '15:30:00.000'},
                {'startTime': '9:00 AM', 'endTime': '10:00 AM'},
                {'startTime': null, 'endTime': '11:00:00'},
              ],
            },
          ],
          'host_profile_images': [
            {
              'id': 1,
              'priority': 2,
              'image': {'url': '/u/b.jpg'},
            },
            {'id': 2, 'priority': 1, 'image': null},
            {
              'id': 3,
              'priority': 3,
              'isprimary': 'true',
              'image': {
                'data': {
                  'id': 30,
                  'attributes': {'url': 'https://cdn/x.jpg'},
                },
              },
            },
          ],
        },
      },
    })!;

    test('normalizes v4 relations and reads typed fields', () {
      expect(host.key, 'exp7');
      expect(host.isSameRecord('7'), isTrue);
      expect(host.languages.single.label, 'Hindi');
      expect(host.rates.voiceCallRate, 12);
      expect(host.rates.videoCallRate, 0);
      expect(host.availability, HostAvailability.custom);
      expect(HostProfile.from({'handler': 'x'}), isNull);
    });

    test('schedule: trimmed weekday match, both time formats, sorted', () {
      final tuesday = host.weeklySchedule[HostWeekday.tuesday]!;
      expect(tuesday.map((s) => (s.startMinutes, s.endMinutes)), [
        (540, 600),
        (840, 930),
      ]);
      expect(host.weeklySchedule[HostWeekday.monday], isEmpty);
      expect(HostTimeSlot.parseTime('12:15 AM'), 15);
      expect(HostTimeSlot.parseTime('12:15 PM'), 735);
      expect(HostTimeSlot.parseTime('25:00'), isNull);
    });

    test('images: url only, primary first, then priority', () {
      expect(host.profileImages.map((i) => i.id), [3, 1]);
      expect(host.profileImages.first.imageId, 30);
      expect(host.profileImages.first.imageUrl, 'https://cdn/x.jpg');
      expect(host.profileImages.last.moderationStatus, 'pending');
    });

    test('completion lists sections in RN order', () {
      expect(host.completion().complete, isTrue);
      expect(host.completionWith(null).missing, [HostProfileSection.expertise]);
      const withAnswer = ExpertiseSelections(
        appKey: 'vibe_os',
        selections: {
          'service_area': ['law'],
        },
      );
      expect(host.completionWith(withAnswer).complete, isTrue);

      final bare = HostProfile.from({'id': 1, 'callAnyTime': 'false'})!;
      expect(bare.completion().missing, [
        HostProfileSection.professional,
        HostProfileSection.schedule,
        HostProfileSection.rates,
      ]);
      expect(bare.completion().nextSection, HostProfileSection.schedule);
      expect(
        HostProfile.from({'id': 1, 'vocationMode': true})!.hasSchedule,
        isTrue,
      );
    });

    test('merging a PUT response keeps populated relations', () {
      final merged = HostProfile.merge([
        host.raw,
        HostProfile.from({'id': 7, 'isActive': true})!.raw,
        HostProfilePatch.rates(voice: 20, video: 30).echo,
      ])!;
      expect(merged.isActive, isTrue);
      expect(merged.languages, hasLength(1));
      expect(merged.rates.videoCallRate, 30);
    });

    test('helpers sanitize handle and gender', () {
      expect(HostProfile.sanitizeHandle('Asha K. 2'), 'asha_k_');
      expect(HostProfile.normalizeGender(' female '), 'Female');
      expect(HostProfile.normalizeGender('x'), isNull);
    });
  });

  group('HostProfilePatch', () {
    test('schedule writes Strapi times, drops empty days', () {
      final patch = HostProfilePatch.schedule(
        vacation: false,
        callAnyTime: false,
        week: const {
          HostWeekday.tuesday: [HostTimeSlot(840, 900), HostTimeSlot(60, 90)],
          HostWeekday.friday: [],
        },
      );
      expect(patch.data, {
        'vocationMode': false,
        'callAnyTime': false,
        'schedule': [
          {
            'days': 'Tuesday ',
            'timeSlots': [
              {'startTime': '01:00:00.000', 'endTime': '01:30:00.000'},
              {'startTime': '14:00:00.000', 'endTime': '15:00:00.000'},
            ],
          },
        ],
      });
      expect(
        HostProfilePatch.schedule(
          vacation: true,
          callAnyTime: false,
        ).data.containsKey('schedule'),
        isFalse,
      );
    });

    test('professional connects languages and omits a missing intro', () {
      const hindi = HostOption(id: 1, label: 'Hindi', raw: {'id': 1});
      const tamil = HostOption(documentId: 'ta', label: 'Tamil');
      final patch = HostProfilePatch.professional(
        handler: 'Asha K',
        tagline: ' Coach ',
        gender: 'male',
        description: 'About',
        languages: const [hindi, tamil],
      );
      expect(patch.data['handler'], 'asha_k');
      expect(patch.data['tagline'], 'Coach');
      expect(patch.data['gender'], 'Male');
      expect(patch.data['language'], {
        'connect': [
          {'id': 1},
          {'documentId': 'ta'},
        ],
      });
      expect(patch.data.containsKey('audio_intro'), isFalse);
      expect(patch.echo['language'], [
        {'id': 1},
        <String, dynamic>{},
      ]);
      expect(HostProfilePatch.availability(HostAvailability.vacation).data, {
        'vocationMode': true,
        'callAnyTime': false,
      });
      expect(
        HostProfilePatch.categories([3, 4]).echo.containsKey('categories'),
        isTrue,
      );
    });
  });

  group('ApprovalRecord', () {
    test('status and the approved-profile override', () {
      expect(
        const ApprovalRecord({'status': 'Approved'}).status,
        ApprovalStatus.approved,
      );
      expect(
        const ApprovalRecord({'is_approved': 'true'}).status,
        ApprovalStatus.pending,
      );
      expect(
        const ApprovalRecord({'rejected': true}).status,
        ApprovalStatus.rejected,
      );
      final approved = HostProfile.from({'id': 1, 'isApproved': 1});
      expect(
        ApprovalRecord.effective(
          approved,
          const ApprovalRecord({'status': 'rejected'}),
        ),
        ApprovalStatus.approved,
      );
      expect(ApprovalRecord.effective(null, null), isNull);
    });
  });

  group('ExpertiseQuestions', () {
    final questions = <Map<String, dynamic>>[
      {
        'key': 'service_area',
        'title': 'Your expertise',
        'selectionMode': 'multi',
        'required': true,
        'options': [
          {'value': 'law', 'label': 'Law'},
          {'value': 'tax', 'label': ''},
          {'value': '', 'label': 'Broken'},
        ],
      },
      {
        'key': 'user_gender',
        'required': true,
        'options': [
          {'value': 'male'},
          {'value': 'any', 'isDefault': true},
        ],
      },
      {
        'key': 'interaction_mode',
        'selectionMode': 'single',
        'options': [
          {'value': 'voice', 'isDefault': true},
          {'value': 'video', 'isDefault': true},
        ],
      },
    ];

    test('draft keeps saved answers and defaults hidden questions', () {
      expect(ExpertiseQuestions.draft(questions, const {}), {
        'service_area': <String>[],
        'user_gender': ['any'],
        'interaction_mode': ['voice'],
      });
      expect(
        ExpertiseQuestions.draft(questions, const {
          'interaction_mode': ['video'],
        }),
        {
          'service_area': <String>[],
          'user_gender': ['any'],
          'interaction_mode': ['video'],
        },
      );
    });

    test('titles use option labels of expertise questions only', () {
      expect(
        ExpertiseQuestions.titles(questions, const {
          'service_area': ['law', 'tax', 'LAW'],
          'user_gender': ['male'],
        }),
        ['Law', 'tax'],
      );
    });

    test('validate skips hidden questions', () {
      expect(
        ExpertiseQuestions.validate(questions, const {
          'user_gender': <String>[],
        }),
        {'service_area': 'hosthub:expertise.errors.required'},
      );
      expect(
        ExpertiseQuestions.validate(questions, const {
          'service_area': ['gone'],
        }),
        {'service_area': 'hosthub:expertise.errors.unknown_option'},
      );
      expect(
        ExpertiseQuestions.visibleForHosts(questions).map((q) => q['key']),
        ['service_area'],
      );
    });

    test('selections normalize and hasAny', () {
      final s = ExpertiseSelections.fromResponse({
        'app': {'key': ''},
        'selections': {
          ' a ': [' x ', 'x', ''],
          '': ['y'],
          'b': 'not a list',
        },
      });
      expect(s.selections, {
        'a': ['x'],
        'b': <String>[],
      });
      expect(s.hasAny, isTrue);
      expect(s.appKey, isNotEmpty);
    });
  });

  group('Catalog models', () {
    test('options need an id and a label', () {
      expect(
        HostOption.language({'id': 1, 'languageNames': ' Hindi '})?.label,
        'Hindi',
      );
      expect(HostOption.language({'id': 1, 'name': ''}), isNull);
      expect(HostOption.category({'name': 'Law'}), isNull);
      final unique = HostOption.uniqueById([
        const HostOption(id: 1, label: 'A'),
        const HostOption(id: 1, label: 'A2'),
        const HostOption(documentId: 'b', label: 'B'),
      ]);
      expect(unique.map((o) => o.label), ['A', 'B']);
    });

    test('platform filter order and page hasMore', () {
      expect(const CategoryPlatform(id: 3, documentId: 'd').filter, {
        'filters[platform][id][\$eq]': 3,
      });
      expect(CategoryPlatform.parse('12')?.id, 12);
      expect(CategoryPlatform.parse('vibe_os')?.filter, {
        'filters[platform][documentId][\$eq]': 'vibe_os',
      });
      expect(
        const CategoryPage(
          items: [],
          page: 1,
          pageSize: 45,
          pagination: {'page': 1, 'pageCount': 2},
        ).hasMore,
        isTrue,
      );
      expect(
        const CategoryPage(items: [], page: 1, pageSize: 45).hasMore,
        isFalse,
      );
    });
  });

  group('API (fake backend)', () {
    late _FakeBackend backend;
    late HttpClientAdapter original;

    setUp(() {
      original = ApiClient.dio.httpClientAdapter;
      backend = _FakeBackend();
      ApiClient.dio.httpClientAdapter = backend;
    });
    tearDown(() => ApiClient.dio.httpClientAdapter = original);

    test(
      'latest approval reads drafts and published, keeps the newer',
      () async {
        backend.handler = (o) => _json({
          'data': [
            o.queryParameters['status'] == 'draft'
                ? {
                    'id': 1,
                    'status': 'pending',
                    'updatedAt': '2026-09-02T00:00:00Z',
                  }
                : {
                    'id': 2,
                    'status': 'rejected',
                    'updatedAt': '2026-09-01T00:00:00Z',
                  },
          ],
        });
        final latest = await HostApprovalApi.fetchLatest('exp7');
        expect(latest?.status, ApprovalStatus.pending);
        expect(backend.requests, hasLength(2));
        expect(
          backend.requests.first.queryParameters.keys,
          contains('filters[expert_profile][documentId][\$eq]'),
        );
        expect(
          backend.requests.first.queryParameters.keys,
          isNot(contains('filters[expert_profile][id][\$eq]')),
        );
      },
    );

    test('numeric ids try [id] first, then [documentId]', () async {
      backend.handler = (o) => _json({'data': <Object>[]});
      expect(await HostApprovalApi.fetchLatest('42'), isNull);
      // 2 reads (draft, published) × 2 filters.
      expect(backend.requests, hasLength(4));
    });

    test(
      'photo sync updates in place, deletes emptied and stray rows',
      () async {
        backend.handler = (o) => _json({
          'data': {'id': 99},
        });
        await HostImagesApi.sync(
          expertId: 'exp7',
          slots: [11, null, 33],
          existing: [
            HostProfileImage.fromRow({'documentId': 'a', 'priority': 1}, 0),
            HostProfileImage.fromRow({'documentId': 'b', 'priority': 2}, 1),
            HostProfileImage.fromRow({'id': 9, 'priority': 5}, 2),
          ],
        );
        expect(backend.requests.map(_call), [
          'PUT /api/profile-images/a',
          'DELETE /api/profile-images/b',
          'POST /api/profile-images',
          'DELETE /api/profile-images/9',
        ]);
        expect(backend.requests.first.data, {
          'data': {
            'host_image': 'exp7',
            'image': 11,
            'priority': 1,
            'isprimary': true,
          },
          'status': 'published',
        });
        expect((backend.requests[2].data as Map)['data']['priority'], 3);
      },
    );

    test('update retries with the numeric id after a documentId 404', () async {
      backend.handler = (o) {
        if (o.method == 'PUT' && o.path.endsWith('/docX')) return _notFound();
        if (o.method == 'GET') {
          return _json({
            'data': [
              {'id': 42, 'documentId': 'docX'},
            ],
          });
        }
        return _json({
          'data': {'id': 42, 'documentId': 'docX', 'isActive': true},
        });
      };
      final saved = await HostProfileApi.update('docX', {'isActive': true});
      expect(saved?.id, 42);
      expect(backend.requests.map(_call), [
        'PUT /api/expert-profiles/docX',
        'GET /api/expert-profiles',
        'PUT /api/expert-profiles/42',
      ]);
    });

    test('a numeric-id 404 on update is not retried', () async {
      backend.handler = (_) => _notFound();
      await expectLater(
        HostProfileApi.update('42', const {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.notFound,
          ),
        ),
      );
      expect(backend.requests, hasLength(1));
    });

    test('fetchById recovers a 404 via the list, then the owner', () async {
      backend.handler = (o) {
        if (o.path == '/api/expert-profiles/fresh') return _notFound();
        if (o.queryParameters.containsKey('filters[documentId][\$eq]')) {
          return _json({'data': <Object>[]});
        }
        return _json({
          'data': [
            {'id': 5, 'documentId': 'other'},
          ],
        });
      };
      expect(
        await HostProfileApi.fetchById('fresh', ownerUserDocumentId: 'u1'),
        isNull,
        reason: 'owner profile is a different record',
      );

      backend.handler = (o) {
        if (o.path == '/api/expert-profiles/fresh') return _notFound();
        return _json({
          'data': [
            {'id': 5, 'documentId': 'fresh', 'handler': 'h'},
          ],
        });
      };
      final mine = await HostProfileApi.fetchById('fresh');
      expect(mine?.handler, 'h');
    });

    test('a lookup answered with another host is not taken as ours', () async {
      // Signed in, the list returned the viewer's personalized feed with the
      // filter ignored: its first host, not the one asked for (prod bug).
      backend.handler = (_) => _json({
        'data': [
          {
            'id': 9,
            'documentId': 'nisha',
            'handler': 'i_am_nisha',
            'user': {'documentId': 'u-nisha'},
          },
        ],
      });
      expect(
        await HostProfileApi.fetchById('mine', ownerUserDocumentId: 'u1'),
        isNull,
      );
      expect(await HostProfileApi.fetchByUser('u1'), isNull);
      expect(
        backend.requests.last.queryParameters,
        containsPair('populate[user][fields][0]', 'documentId'),
      );

      backend.handler = (_) => _json({
        'data': [
          {
            'id': 3,
            'documentId': 'mine',
            'handler': 'dc_vibe',
            'user': {'documentId': 'u1'},
          },
        ],
      });
      expect((await HostProfileApi.fetchByUser('u1'))?.handler, 'dc_vibe');
    });

    test('stats: no row is the empty record', () async {
      backend.handler = (_) => _json({'data': <Object>[]});
      final none = await HostStatsApi.fetch('u1');
      expect(none.hasRecord, isFalse);
      expect(
        backend.requests.single.queryParameters,
        containsPair('filters[public_profile][documentId][\$eq]', 'u1'),
      );

      backend.handler = (_) => _json({
        'data': [
          {'id': 1, 'total_earnings': 1500.5},
        ],
      });
      expect((await HostStatsApi.fetch('u1')).totalEarnings, 1500.5);
    });

    test('categories send the platform filter and drop blank rows', () async {
      backend.handler = (_) => _json({
        'data': [
          {'id': 1, 'name': 'Law'},
          {'id': 2, 'name': ''},
        ],
        'meta': {
          'pagination': {'page': 1, 'pageCount': 1},
        },
      });
      final page = await HostCatalogApi.fetchCategoriesPage(
        platform: const CategoryPlatform(id: 3),
        search: ' la ',
      );
      expect(page.items.map((c) => c.label), ['Law']);
      expect(page.hasMore, isFalse);
      expect(backend.requests.single.queryParameters, {
        'sort': 'name:asc',
        'pagination[page]': 1,
        'pagination[pageSize]': 45,
        'filters[platform][id][\$eq]': 3,
        'filters[name][\$containsi]': 'la',
      });
    });

    test('ensure verification creates a blank published record', () async {
      backend.handler = (o) => o.method == 'GET'
          ? _json({'data': <Object>[]})
          : _json({
              'data': {'id': 8, 'documentId': 'v8'},
            });
      final record = await HostVerificationApi.ensure('exp7');
      expect(record.key, 'v8');
      final post = backend.requests.last;
      expect(_call(post), 'POST /api/expert-verifications');
      expect((post.data as Map)['status'], 'published');
      expect((post.data as Map)['data']['Payment_Received'], false);
      expect((post.data as Map)['data']['expert_profile'], 'exp7');
    });

    test('initiate payment rejects a response PayU cannot use', () async {
      backend.handler = (_) => _json({
        'payuData': {'txnid': 't1'},
      });
      await expectLater(
        HostVerificationApi.initiatePayment(userId: 1, verificationId: 'v8'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageKey,
            'messageKey',
            'hosthub:errors.invalid_payment_response',
          ),
        ),
      );
      backend.handler = (_) => _json({'alreadyPaid': true});
      final init = await HostVerificationApi.initiatePayment(
        userId: 1,
        verificationId: 'v8',
      );
      expect(init.alreadyPaid, isTrue);
    });

    test('expertise save sends normalized selections for this app', () async {
      backend.handler = (_) => _json({
        'savedCount': 2,
        'selections': {
          'a': ['x'],
        },
      });
      final result = await ExpertiseApi.save(const {
        'a': [' x ', 'x'],
      }, source: 'professional-details');
      expect(result.savedCount, 2);
      final put = backend.requests.single;
      expect(put.queryParameters.keys, containsAll(['app', 'appKey']));
      expect(put.data, {
        'selections': {
          'a': ['x'],
        },
        'source': 'professional-details',
      });
    });
  });

  test('every hosthub i18n key exists in en and hi', () {
    final en = _keys(_readJson('assets/i18n/en/hosthub.json'));
    final hi = _keys(_readJson('assets/i18n/hi/hosthub.json'));
    expect(hi, en);

    final used = <String>{
      for (final file in Directory('lib/app/api/hosthub').listSync())
        if (file is File)
          for (final m in RegExp(
            r"'hosthub:([a-z_.]+)'",
          ).allMatches(file.readAsStringSync()))
            m[1]!,
      for (final s in HostProfileSection.values)
        s.i18nKey.replaceFirst('hosthub:', ''),
      for (final f in PersonalInfoField.values)
        f.i18nKey.replaceFirst('hosthub:', ''),
    };
    expect(en, containsAll(used));
  });
}

typedef JsonLike = Map<String, dynamic>;
