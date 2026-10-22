import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:vibelive/app/api/banner/banner_api.dart';
import 'package:vibelive/app/api/banner/banner_models.dart';
import 'package:vibelive/app/api/client/block_api.dart';
import 'package:vibelive/app/api/client/client_models.dart';
import 'package:vibelive/app/api/client/client_queries.dart';
import 'package:vibelive/app/api/client/favorite_api.dart';
import 'package:vibelive/app/api/client/geo_api.dart';
import 'package:vibelive/app/api/client/gst_api.dart';
import 'package:vibelive/app/api/client/profile_api.dart';
import 'package:vibelive/app/api/client/referral_api.dart';
import 'package:vibelive/app/api/resourcesscreen/resources_api.dart';
import 'package:vibelive/app/api/resourcesscreen/resources_models.dart';
import 'package:vibelive/app/api/splashscreen/splash_models.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/session/session_store.dart';

/// Answers requests from [handler] and records them.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  (int, Object?) Function(RequestOptions request) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

late _FakeAdapter _server;

void _respond((int, Object?) Function(RequestOptions request) handler) =>
    _server.handler = handler;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  });

  setUp(() {
    _server = _FakeAdapter((_) => (200, {'data': []}));
    ApiClient.dio.httpClientAdapter = _server;
  });

  group('GeoOption', () {
    test('reads the alternate name fields', () {
      expect(const GeoOption({'stateNames': ' Goa '}).name, 'Goa');
      expect(const GeoOption({'districtNames': 'Pune'}).name, 'Pune');
      expect(const GeoOption({'cityNames': 'Agra'}).name, 'Agra');
      expect(const GeoOption({}).name, '');
    });

    test('builds connect payloads like RN', () {
      expect(const GeoOption({'id': 7, 'documentId': 'd'}).connect, {
        'connect': [
          {'id': 7},
        ],
      });
      expect(const GeoOption({'documentId': 'doc'}).connect, {
        'connect': [
          {'documentId': 'doc'},
        ],
      });
      expect(const GeoOption({'slug': 'goa'}).connect, {
        'connect': [
          {'documentId': 'goa'},
        ],
      });
      expect(const GeoOption({'name': 'x'}).connect, isNull);
    });

    test('fromRelation handles v4, lists, bare ids and empty relations', () {
      final v4 = GeoOption.fromRelation({
        'data': {
          'id': 3,
          'attributes': {'name': 'Kerala', 'documentId': 'k1'},
        },
      });
      expect(v4?.id, 3);
      expect(v4?.documentId, 'k1');
      expect(v4?.name, 'Kerala');
      expect(v4?.filterField, GeoIdField.documentId);

      final list = GeoOption.fromRelation([
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
      ]);
      expect(list?.name, 'A');

      expect(GeoOption.fromRelation(5)?.id, 5);
      expect(GeoOption.fromRelation('12')?.id, 12);
      expect(GeoOption.fromRelation('abc')?.documentId, 'abc');
      expect(GeoOption.fromRelation({'data': null}), isNull);
      expect(GeoOption.fromRelation(null), isNull);
      expect(
        GeoOption.fromRelation(const GeoOption({'id': 9}).raw)?.filterId,
        '9',
      );
    });
  });

  group('UserWithExpert', () {
    JsonMap userFixture() => {
      'id': 10,
      'documentId': 'u1',
      'name': 'Asha',
      'email': 'asha@x.com',
      'mobile': '9876543210',
      'is_company_account': 'true',
      'profilePic': {'id': 55, 'url': '/uploads/a.jpg'},
      'state': {'id': 4, 'documentId': 's4', 'name': 'Goa'},
      'address_JSON': {'line1': 'Street 1', 'city': 'Old'},
      'expert': {
        'data': {
          'id': 77,
          'attributes': {
            'documentId': 'e77',
            'handler': ' asha_live ',
            'language': {
              'data': [
                {
                  'id': 1,
                  'attributes': {'name': 'Hindi'},
                },
              ],
            },
            'schedule': [
              {
                'days': ' Mon ',
                'timeSlots': [
                  {'startTime': '10:00', 'endTime': '11:00'},
                  {'startTime': '12:00'},
                ],
              },
            ],
          },
        },
      },
    };

    test('normalizes the expert relation', () {
      final p = UserWithExpert.fromUser(userFixture());
      expect(p.isExpert, isTrue);
      expect(p.expertId, 'e77');
      expect(p.expert!['language'], [
        {'id': 1, 'name': 'Hindi'},
      ]);
      final schedule = p.expert!['schedule'] as List;
      expect((schedule.first as Map)['days'], 'Mon');
      expect((schedule.first as Map)['timeSlots'], hasLength(1));
      expect(p.expert!['rates'], <String, dynamic>{});
      expect(p.expert!['host_profile_images'], isEmpty);
    });

    test('exposes profile fields', () {
      final p = UserWithExpert.fromUser(userFixture());
      expect(p.documentId, 'u1');
      expect(p.isCompanyAccount, isTrue);
      expect(p.isPersonalInfoComplete, isTrue);
      expect(p.profilePicId, 55);
      expect(p.profilePicUrl, endsWith('/uploads/a.jpg'));
      expect(p.state?.name, 'Goa');
      expect(p.handler, 'asha_live');
      expect(p.shareSlug, 'asha_live');
    });

    test('share slug falls back to ids', () {
      expect(
        UserWithExpert.fromUser({
          'id': 1,
          'documentId': 'u1',
          'expert': {'id': 2, 'documentId': 'e2'},
        }).shareSlug,
        'e2',
      );
      expect(
        UserWithExpert.fromUser({'id': 1, 'documentId': 'u1'}).shareSlug,
        'u1',
      );
      final client = UserWithExpert.fromUser({'id': 1, 'documentId': 'u1'});
      expect(client.isExpert, isFalse);
      expect(client.expert, isNull);
    });

    test('round-trips through JSON (persisted query)', () {
      final p = UserWithExpert.fromUser(userFixture());
      final back = UserWithExpert.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.toJson(), jsonDecode(jsonEncode(p.toJson())));
      final noExpert = UserWithExpert.fromJson({
        'user': {'id': 1},
        'expert': null,
      });
      expect(noExpert.expert, isNull);
    });
  });

  group('PersonalInfoInput', () {
    final current = UserWithExpert.fromUser({
      'documentId': 'u1',
      'email': 'Asha@X.com',
      'mobile': '98765 43210',
      'profilePic': {'id': 55},
      'address_JSON': {'line1': 'Street 1', 'city': 'Old'},
    });

    test('sends email / mobile only when they changed', () {
      final data = PersonalInfoInput(
        current: current,
        name: '  Asha K ',
        email: 'asha@x.com',
        mobile: '9876543210',
        state: const GeoOption({'id': 4, 'name': 'Goa'}),
        district: const GeoOption({
          'documentId': 'd9',
          'districtNames': 'North Goa',
        }),
      ).toData(country: const GeoOption({'id': 1, 'name': 'India'}));

      expect(data['name'], 'Asha K');
      expect(data.containsKey('email'), isFalse);
      expect(data.containsKey('mobile'), isFalse);
      expect(data['state'], {
        'connect': [
          {'id': 4},
        ],
      });
      expect(data['district'], {
        'connect': [
          {'documentId': 'd9'},
        ],
      });
      expect(data['country'], {
        'connect': [
          {'id': 1},
        ],
      });
      expect(data.containsKey('city'), isTrue);
      expect(data['city'], isNull);
      expect(data['profilePic'], 55);
      expect(data['address_JSON'], {
        'line1': 'Street 1',
        'city': '',
        'state': 'Goa',
        'district': 'North Goa',
        'country': 'India',
      });
    });

    test('includes changed email and mobile, normalized', () {
      final data = PersonalInfoInput(
        current: current,
        name: 'Asha',
        email: ' NEW@x.com ',
        mobile: '91234-56789',
        state: const GeoOption({'id': 4, 'name': 'Goa'}),
      ).toData();
      expect(data['email'], 'new@x.com');
      expect(data['mobile'], '9123456789');
      expect(data.containsKey('country'), isFalse);
      expect(data.containsKey('district'), isFalse);
    });
  });

  group('ProfileApi.mapSaveError', () {
    ApiException rejected(Object data) => ApiException(
      ApiErrorType.rejected,
      statusCode: 400,
      serverMessage: 'This attribute must be unique',
      data: data,
    );

    test('names a duplicate email or mobile', () {
      final email = ProfileApi.mapSaveError(
        rejected({
          'error': {
            'message': 'This attribute must be unique',
            'details': {
              'errors': [
                {
                  'path': ['email'],
                  'message': 'This attribute must be unique',
                },
              ],
            },
          },
        }),
      );
      expect(email.messageKey, 'client:errors.email_taken');
      expect(email.serverMessage, isNull);
      expect(email.statusCode, 400);

      final mobile = ProfileApi.mapSaveError(
        rejected({
          'error': {
            'message': 'Validation error',
            'details': {
              'errors': [
                {
                  'path': ['mobile'],
                  'message': 'mobile is already taken',
                },
              ],
            },
          },
        }),
      );
      expect(mobile.messageKey, 'client:errors.mobile_taken');
    });

    test('leaves other errors alone', () {
      final e = rejected({
        'error': {'message': 'name is too short'},
      });
      expect(identical(ProfileApi.mapSaveError(e), e), isTrue);
    });
  });

  group('Favourites', () {
    test('normalizes rows and dedupes by host', () {
      Map<String, dynamic> row(String id, String expertId, {String? name}) => {
        'documentId': id,
        'experts': [
          {
            'documentId': expertId,
            'handler': 'h_$expertId',
            'isVerified': 'TRUE',
            'user': {
              'name': ?name,
              'profilePic': {'url': 'https://cdn/x.jpg'},
            },
          },
        ],
      };
      final list = FavoriteExpert.dedupe([
        FavoriteExpert.fromRow(row('f1', 'e1', name: 'Ravi')),
        FavoriteExpert.fromRow(row('f2', 'e1')),
        FavoriteExpert.fromRow(row('f3', 'e2')),
        FavoriteExpert.fromRow(const {}),
      ]);
      expect(list.map((f) => f.id), ['f1', 'f3']);
      expect(list.first.expertName, 'Ravi');
      expect(list.first.expertVerified, isTrue);
      expect(list.first.profilePicUrl, 'https://cdn/x.jpg');
      expect(list.last.expertName, 'h_e2');
    });

    test('addFavorite returns the existing row without posting', () async {
      _respond(
        (_) => (
          200,
          {
            'data': [
              {
                'documentId': 'f1',
                'experts': [
                  {'documentId': 'e1'},
                ],
              },
            ],
          },
        ),
      );
      final fav = await FavoriteApi.addFavorite(
        userDocumentId: 'u1',
        expertDocumentId: 'e1',
      );
      expect(fav.id, 'f1');
      expect(_server.requests, hasLength(1));
      expect(_server.requests.single.method, 'GET');
      expect(
        _server
            .requests
            .single
            .queryParameters[r'filters[experts][documentId][$eq]'],
        'e1',
      );
    });

    test('removeFavorite falls back to the expert id', () async {
      _respond(
        (r) =>
            r.path.endsWith('/f1') ? (404, {'error': {}}) : (200, {'data': {}}),
      );
      await FavoriteApi.removeFavorite(favoriteId: 'f1', expertId: 'e1');
      expect(_server.requests.map((r) => '${r.method} ${r.path}'), [
        'DELETE /api/favorites/f1',
        'DELETE /api/favorites/e1',
      ]);
    });
  });

  group('Blocks', () {
    test('parses blocked users', () async {
      _respond(
        (_) => (
          200,
          {
            'data': [
              {
                'blockedAt': '2026-01-02T03:04:05.000Z',
                'user': {
                  'documentId': 'u9',
                  'name': 'Neha',
                  'role': 'client',
                  'profilePic': '/uploads/n.jpg',
                  'expert': {'handler': 'neha'},
                },
              },
              {'targetUserId': 't2'},
            ],
            'meta': {'total': 2},
          },
        ),
      );
      final list = await BlockApi.fetchBlockedUsers();
      expect(_server.requests.single.queryParameters, {
        'limit': 50,
        'offset': 0,
      });
      expect(list, hasLength(2));
      expect(list.first.targetUserId, 'u9');
      expect(list.first.handle, 'neha');
      expect(list.first.profilePicUrl, endsWith('/uploads/n.jpg'));
      expect(list.first.blockedAt, isNotNull);
      expect(list.last.targetUserId, 't2');
      expect(list.last.name, isNull);
    });

    test(
      'unblock falls back to DELETE, then reports the original error',
      () async {
        _respond((r) => r.method == 'POST' ? (404, {'error': {}}) : (200, {}));
        await BlockApi.unblockUser('u9');
        expect(_server.requests.map((r) => '${r.method} ${r.path}'), [
          'POST /api/user-blocks/unblock',
          'DELETE /api/user-blocks/u9',
        ]);

        _server.requests.clear();
        _respond((r) => r.method == 'POST' ? (400, {'error': {}}) : (404, {}));
        await expectLater(
          BlockApi.unblockUser('u9'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 400),
          ),
        );
      },
    );

    test('block sends the target and optional reason', () async {
      await BlockApi.blockUser(
        const BlockUserInput('u9', reason: ' live call '),
      );
      expect(_server.requests.single.data, {
        'targetUserId': 'u9',
        'reason': 'live call',
      });
      await expectLater(
        BlockApi.blockUser(const BlockUserInput(' ')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageKey,
            'key',
            'client:errors.missing_user',
          ),
        ),
      );
    });
  });

  group('Geo', () {
    test('states retry without the country filter when empty', () async {
      _respond(
        (r) => r.queryParameters.containsKey(r'filters[country][name][$eqi]')
            ? (200, {'data': []})
            : (
                200,
                {
                  'data': [
                    {'id': 1, 'name': 'Goa'},
                  ],
                },
              ),
      );
      final states = await GeoApi.fetchStates(search: 'go');
      expect(states.single.name, 'Goa');
      expect(_server.requests, hasLength(2));
      expect(
        _server.requests.first.queryParameters[r'filters[name][$containsi]'],
        'go',
      );
    });

    test('districts never send a documentId to the id filter', () async {
      await GeoApi.fetchDistricts(stateId: 'abc');
      expect(_server.requests, hasLength(1));

      _server.requests.clear();
      await GeoApi.fetchDistricts(stateId: '12');
      expect(_server.requests, hasLength(2));
      expect(
        _server.requests.last.queryParameters[r'filters[state][id][$eq]'],
        '12',
      );
    });
  });

  group('Profile requests', () {
    test('fetchUserWithExpert falls back to the filtered list on 404', () async {
      _respond(
        (r) => r.path == '/api/public-users/u1'
            ? (404, {'error': {}})
            : (
                200,
                {
                  'data': [
                    {
                      'id': 1,
                      'documentId': 'u1',
                      'expert': {'id': 2, 'documentId': 'e2'},
                    },
                  ],
                },
              ),
      );
      final p = await ProfileApi.fetchUserWithExpert('u1');
      expect(p.expertId, 'e2');
      final fallback = _server.requests.last;
      expect(fallback.path, '/api/public-users');
      expect(fallback.queryParameters[r'filters[documentId][$eq]'], 'u1');
      expect(
        fallback
            .queryParameters['populate[expert][populate][schedule][populate][0]'],
        'timeSlots',
      );
    });

    test('missing user is a not-found error with our key', () async {
      _respond((_) => (200, {'data': null}));
      await expectLater(
        ProfileApi.fetchUserWithExpert('u1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageKey,
            'key',
            'client:errors.profile_not_found',
          ),
        ),
      );
    });

    test('syncSessionWithProfile updates only the signed-in user', () async {
      final store = SessionStore.instance;
      store.value = const SessionState(
        user: {'documentId': 'u1', 'name': 'Old', 'token_hint': 1},
      );
      await syncSessionWithProfile(
        'u1',
        const UserWithExpert(
          user: {'documentId': 'u1', 'name': 'New'},
          expert: {'id': 5},
        ),
      );
      expect(store.value.user, {
        'documentId': 'u1',
        'name': 'New',
        'token_hint': 1,
      });
      expect(store.value.expertId, 5);

      await syncSessionWithProfile(
        'someone-else',
        const UserWithExpert(user: {'documentId': 'x', 'name': 'X'}),
      );
      expect(store.value.user?['name'], 'New');

      await syncSessionWithProfile(
        'u1',
        const UserWithExpert(user: {'documentId': 'u1'}),
      );
      expect(store.value.expert, isNull);
      store.value = SessionState.empty;
    });
  });

  group('GST', () {
    test('parses the gst_detail relation', () {
      final gst = GstDetails.fromUser({
        'gst_detail': {
          'documentId': 'g1',
          'Is_Verified': true,
          'gst_device_info': {
            'is_gst_registered': 'true',
            'declaration_statement': null,
          },
          'GST': {
            'GST_Number': '22AAAAA0000A1Z5',
            'Business_Name': 'Acme',
            'Address': 'Main Rd',
            'zipcode': '403001',
            'state': {'id': 4, 'documentId': 's4', 'name': 'Goa'},
            'district': {'id': 8, 'districtNames': 'North Goa'},
            'GST_File': {'id': 31, 'url': '/uploads/gst.pdf'},
          },
        },
      });
      expect(gst.isSubmitted, isTrue);
      expect(gst.documentId, 'g1');
      expect(gst.isVerified, isTrue);
      expect(gst.isGstRegistered, isTrue);
      expect(gst.address, 'Main Rd');
      expect(gst.state?.name, 'Goa');
      expect(gst.district?.name, 'North Goa');
      expect(gst.city?.id, 8);
      expect(gst.gstFileUrl, endsWith('/uploads/gst.pdf'));
      expect(gst.logoUrl, isNull);

      expect(GstDetails.fromUser({'gst_detail': null}).isSubmitted, isFalse);
      expect(GstDetails.fromUser(null).isSubmitted, isFalse);
    });

    test('builds the registered payload', () {
      final data = const GstDetailsInput(
        gstNumber: ' 22aaaaa0000a1z5 ',
        businessName: ' Acme ',
        address: ' Main Rd ',
        zipcode: '403001',
        state: GeoOption({'id': 4, 'documentId': 's4'}),
        district: GeoOption({'documentId': 'd8'}),
        gstFileId: 31,
      ).toData('u1', logoId: 32, now: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7));
      expect(data['user'], 'u1');
      final device = data['gst_device_info'] as Map;
      expect(device['is_gst_registered'], isTrue);
      expect(device['declaration_statement'], isNull);
      expect(device['declaration_date'], '2026-01-02T03:04:05.006Z');
      expect(data['GST'], {
        'GST_Number': '22AAAAA0000A1Z5',
        'Business_Name': 'Acme',
        'Address': 'Main Rd',
        'addressLine': 'Main Rd',
        'zipcode': '403001',
        'state': 4,
        'district': 'd8',
        'GST_File': 31,
        'Logo': 32,
      });
    });

    test('builds the declaration-only payload', () {
      final data = const GstDetailsInput(
        hasGstRegistration: false,
        declarationStatement: 'I am not registered',
        gstNumber: 'IGNORED',
      ).toData('u1');
      expect(data.containsKey('GST'), isFalse);
      expect(
        (data['gst_device_info'] as Map)['declaration_statement'],
        'I am not registered',
      );
    });

    test('updates when a record exists, creates otherwise', () async {
      _respond(
        (_) => (
          200,
          {
            'data': {'documentId': 'g1'},
          },
        ),
      );
      final saved = await GstApi.saveGstDetails(
        'u1',
        const GstDetailsInput(gstDetailId: 'g1', hasGstRegistration: false),
      );
      expect(saved?['documentId'], 'g1');
      expect(_server.requests.single.method, 'PUT');
      expect(_server.requests.single.path, '/api/gst-details/g1');

      _server.requests.clear();
      await GstApi.saveGstDetails(
        'u1',
        const GstDetailsInput(hasGstRegistration: false),
      );
      expect(_server.requests.single.method, 'POST');
    });
  });

  group('Referral', () {
    test('reads the code and counters', () {
      final dashboard = ReferralDashboard.fromUser(
        {
          'referrerCode': 'parent',
          'user_referral': [
            {'referralCode': 'abc12', 'copyCount': 4, 'joinedUserCount': 1},
          ],
        },
        const [JoinedUser(name: 'A'), JoinedUser(name: 'B')],
      );
      expect(dashboard.referralCode, 'ABC12');
      expect(dashboard.totalClicks, 4);
      expect(dashboard.joinedUserCount, 2);
      expect(ReferralDashboard.codeFrom({'referrerCode': ' xy '}), 'XY');
      expect(ReferralDashboard.codeFrom(null), '');
    });

    test('masks the mobile of a nameless joined user', () {
      expect(JoinedUser.fromRow({'mobile': '9876543210'}).name, '98******10');
      expect(JoinedUser.maskMobile('12345'), '12******45');
      expect(JoinedUser.maskMobile('123'), '123');
      expect(JoinedUser.fromRow({'username': 'ravi'}).name, 'ravi');
      expect(JoinedUser.fromRow(const {}).name, isNull);
    });

    test('dashboard survives a failing joined-users list', () async {
      _respond(
        (r) => r.path == '/api/public-users'
            ? (403, {'error': {}})
            : (
                200,
                {
                  'data': {
                    'documentId': 'u1',
                    'user_referral': {'referralCode': 'abc'},
                  },
                },
              ),
      );
      final d = await ReferralApi.fetchDashboard('u1');
      expect(d.referralCode, 'ABC');
      expect(d.joinedUsers, isEmpty);
      expect(
        _server.requests.last.queryParameters[r'filters[referrerCode][$eq]'],
        'ABC',
      );
    });

    test('share tracking sends the funnel marker', () async {
      _respond((_) => (200, {'copyCount': 9}));
      expect(await ReferralApi.trackShare('ABC', ReferralShareType.invite), 9);
      expect(_server.requests.single.path, '/api/referral/ABC/copy');
      expect(_server.requests.single.queryParameters, {'type': 'i'});
    });
  });

  group('Resources', () {
    test('menu pages skip unslugged and hidden pages', () async {
      _respond(
        (_) => (
          200,
          {
            'data': [
              {'documentId': 'p1', 'slug': 'faq', 'title': 'FAQ'},
              {'documentId': 'p2', 'slug': 'terms-and-conditions'},
              {'documentId': 'p3', 'slug': ''},
              {
                'id': 4,
                'attributes': {'slug': 'refunds', 'name': 'Refunds'},
              },
            ],
          },
        ),
      );
      final pages = await ResourcesApi.fetchMenuPages();
      expect(pages.map((p) => p.slug), ['faq', 'refunds']);
      expect(pages.last.title, 'Refunds');
      expect(pages.last.id, '4');
      expect(
        _server.requests.single.queryParameters[r'filters[show_in_menu][$eq]'],
        true,
      );
    });

    test('a missing page is not an error', () async {
      final page = await ResourcesApi.fetchPageBySlug(' support ');
      expect(page.exists, isFalse);
      expect(page.slug, 'support');
      expect(page.hasContent, isFalse);
    });

    test('content helpers', () {
      const plain = MenuPage(slug: 'a', content: 'Hello there');
      expect(plain.html, '<p>Hello there</p>');
      const html = MenuPage(slug: 'b', content: '<h1>Hi</h1><p>x  y</p>');
      expect(html.html, '<h1>Hi</h1><p>x  y</p>');
      expect(html.plainText, 'Hi x y');
      const blocks = MenuPage(
        slug: 'c',
        content: [
          {
            'type': 'paragraph',
            'children': [
              {'type': 'text', 'text': 'One'},
              {'type': 'text', 'text': 'two'},
            ],
          },
          {'type': 'paragraph', 'children': <Object>[]},
          {
            'type': 'heading',
            'children': [
              {'text': 'Three'},
            ],
          },
        ],
      );
      expect(blocks.blocks, hasLength(3));
      expect(blocks.html, isNull);
      expect(blocks.plainText, 'One two\n\nThree');

      final back = MenuPage.fromJson(jsonDecode(jsonEncode(blocks.toJson())));
      expect(back.plainText, blocks.plainText);
      expect(
        MenuPage.fromJson(const MenuPage.missing('x').toJson()).exists,
        isFalse,
      );
    });

    test('support contact from app config', () {
      final c = SupportContact.fromAppConfig(
        const AppConfig({
          'contact_email': 'help@x.com',
          'support_phone': '123',
        }),
      );
      expect(c.email, 'help@x.com');
      expect(c.phone, '123');
      expect(c.whatsapp, isNull);
      expect(SupportContact.fromAppConfig(const AppConfig({})).isEmpty, isTrue);
    });
  });

  group('Milestones', () {
    test('merges the milestone into the unlocked row', () async {
      _respond(
        (_) => (
          200,
          {
            'data': [
              {
                'documentId': 'um1',
                'title': 'Row title',
                'milestone': {
                  'documentId': 'm1',
                  'milestone_key': 'FirstCall',
                  'title': '',
                  'subtitle': 'Server subtitle',
                  'gradientColors': '["#111111", "#222222", "#333333"]',
                },
              },
            ],
          },
        ),
      );
      final list = await MilestoneApi.fetchUnviewed('u1');
      final q = _server.requests.single.queryParameters;
      expect(q[r'filters[isViewed][$eq]'], 'false');
      expect(q['populate[milestone][fields][1]'], 'milestone_key');
      expect(q['populate[milestone][fields][9]'], 'gradientColors');

      final m = list.single;
      expect(m.id, 'um1');
      expect(m.unlockedMilestoneDocumentId, 'um1');
      expect(m.milestoneDocumentId, 'm1');
      expect(m.title, 'Row title');
      expect(m.subtitle, 'Server subtitle');
      expect(m.preset, MilestonePreset.firstCall);
      expect(m.preset.titleKey, 'banner:milestones.first_call.title');
      expect(m.gradient, ['#111111', '#222222']);
      expect(m.accent, '#A8EC4A');
      expect(m.iconName, 'medal-outline');
      expect(m.iconFamily, 'MaterialCommunityIcons');
    });

    test('push payloads and the fallback preset', () {
      final m = UnlockedMilestone.fromPush({
        'type': 'milestone_unlocked',
        'unlockedMilestoneDocumentId': 'um2',
        'milestoneDocumentId': 'moneyrecived',
        'primaryColor': '#000000',
      });
      expect(m.id, 'um2');
      expect(m.preset, MilestonePreset.moneyReceived);
      expect(m.accent, '#000000');
      expect(m.gradient, ['#3b82f6', '#1d4ed8']);

      final unknown = UnlockedMilestone.fromPush({'milestoneKey': 'nope'});
      expect(unknown.preset, MilestonePreset.fallback);
      expect(unknown.preset.badgeKey, 'banner:milestones.default.badge');
      expect(UnlockedMilestone.parseGradient('not json'), isNull);
      expect(UnlockedMilestone.parseGradient(['#1']), isNull);
    });

    test('markViewed is a no-op without an id', () async {
      await MilestoneApi.markViewed(' ');
      expect(_server.requests, isEmpty);
      await MilestoneApi.markViewed('um1');
      expect(_server.requests.single.method, 'PUT');
      expect(_server.requests.single.data, {
        'data': {'isViewed': true},
      });
    });
  });
}
