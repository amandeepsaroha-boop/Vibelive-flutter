import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/authscreen/auth_api.dart';
import 'package:vibelive/app/api/authscreen/auth_errors.dart';
import 'package:vibelive/app/api/authscreen/auth_models.dart';
import 'package:vibelive/app/api/authscreen/auth_queries.dart';
import 'package:vibelive/app/api/authscreen/interests_models.dart';
import 'package:vibelive/app/api/authscreen/interests_queries.dart';
import 'package:vibelive/app/api/authscreen/onboarding_queries.dart';
import 'package:vibelive/app/api/authscreen/push_api.dart';
import 'package:vibelive/app/api/authscreen/push_queries.dart';
import 'package:vibelive/app/api/authscreen/referrer_api.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/network/device_info.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/storage/token_storage.dart';

/// Answers requests from [handler] and records them in order.
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

  RequestOptions only(String method, String path) =>
      requests.singleWhere((r) => r.method == method && r.path == path);

  int indexOf(String method, String path) =>
      requests.indexWhere((r) => r.method == method && r.path == path);
}

late _FakeAdapter _server;

/// Routes by `'METHOD /api/path'`; anything else is a 404.
void _routes(Map<String, (int, Object?)> routes) =>
    _server.handler = (r) =>
        routes['${r.method} ${r.path}'] ?? (404, {'error': {}});

Future<void> _signedIn(JsonMap user) => SessionStore.instance.signIn(
  user: user,
  accessToken: 'acc-1',
  refreshToken: 'ref-1',
);

JsonMap _languageForm({List<JsonMap>? extra}) => {
  'app': {'id': 1, 'name': 'Vibe', 'key': 'vibe_os'},
  'questions': [
    {
      'key': 'expert_language',
      'title': 'Which languages should your expert speak?',
      'selectionMode': 'multi',
      'required': true,
      'maxSelect': 2,
      'options': [
        {'value': 'en', 'label': 'English', 'isDefault': true},
        {'value': 'hi', 'label': 'Hindi'},
        {'value': 'old', 'label': 'Old', 'isDeprecated': true},
      ],
    },
    ...?extra,
  ],
};

/// `/languages`: the Languages collection the step offers.
JsonMap _languages() => {
  'data': [
    {'id': 5, 'documentId': 'en-doc', 'languageNames': 'English'},
    {'id': 22, 'documentId': 'hi-doc', 'languageNames': 'Hindi'},
  ],
  'meta': {
    'pagination': {'page': 1, 'pageSize': 100, 'pageCount': 1},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    _server = _FakeAdapter((_) => (404, {}));
    ApiClient.dio.httpClientAdapter = _server;
    ApiClient.resetLogoutFlag();
    SessionStore.instance.value = SessionState.empty;
    queryCache.clear();
    await QueryPersist.clearAll();
    for (final k in AppPrefs.keysWithPrefix('language_step_done:')) {
      await AppPrefs.remove(k);
    }
  });

  group('LoginResult', () {
    test('reads tokens and user, with the legacy aliases', () {
      final a = LoginResult.fromResponse({
        'accessToken': 'a',
        'refreshToken': 'r',
        'user': {'documentId': 'u1'},
        'requiresPhoneVerification': true,
      })!;
      expect(a.accessToken, 'a');
      expect(a.refreshToken, 'r');
      expect(a.user?['documentId'], 'u1');
      expect(a.requiresPhoneVerification, isTrue);

      final b = LoginResult.fromResponse({
        'token': 'legacy',
        'session': {
          'id': 3,
          'user': {'documentId': 'u2', 'name': 'B'},
        },
      })!;
      expect(b.accessToken, 'legacy');
      expect(b.user?['documentId'], 'u2');
      expect(b.isNewUser, isFalse);

      final c = LoginResult.fromResponse({
        'data': {
          'tokens': {'accessToken': 'x', 'refreshToken': 'y'},
        },
      })!;
      expect((c.accessToken, c.refreshToken), ('x', 'y'));
      expect(c.isNewUser, isTrue);
    });

    test('is null without an access token', () {
      expect(LoginResult.fromResponse({'user': {}}), isNull);
      expect(LoginResult.fromResponse('nope'), isNull);
    });

    test('AuthUser.normalize sets both company flags', () {
      final u = AuthUser.normalize({'id': 1, 'is_company': 'true'});
      expect(u['is_company_account'], isTrue);
      expect(u['isCompanyAccount'], isTrue);
      expect(AuthUser.normalize({'id': 1})['isCompanyAccount'], isFalse);
    });
  });

  group('AgeGate', () {
    test('server verdict wins, then the fields', () {
      expect(
        AgeGate.resolve({'ageGateStatus': 'OK', 'date_of_birth': null}),
        AgeGateStatus.ok,
      );
      expect(AgeGate.resolve({'age_blocked': 1}), AgeGateStatus.blocked);
      expect(
        AgeGate.resolve({'date_of_birth': '1990-01-01'}),
        AgeGateStatus.ok,
      );
      expect(
        AgeGate.resolve({'age_verified_at': '2026-01-01T00:00:00Z'}),
        AgeGateStatus.ok,
      );
      expect(AgeGate.resolve({'date_of_birth': null}), AgeGateStatus.required);
      expect(AgeGate.resolve({'name': 'old payload'}), AgeGateStatus.unknown);
      expect(AgeGate.resolve(null), AgeGateStatus.unknown);
    });

    test('only required and blocked gate', () {
      expect(AgeGateStatus.required.gates, isTrue);
      expect(AgeGateStatus.blocked.gates, isTrue);
      expect(AgeGateStatus.unknown.gates, isFalse);
      expect(AgeGateStatus.ok.gates, isFalse);
    });
  });

  group('DateOfBirthCheck', () {
    final now = DateTime.utc(2026, 10, 19);
    DateOfBirthCheck check(String d, String m, String y) =>
        DateOfBirthCheck.validate(day: d, month: m, year: y, now: now);

    test('builds a padded ISO date', () {
      expect(check('5', '3', '1990').isoDate, '1990-03-05');
      expect(
        DateOfBirthCheck.fromDate(DateTime(2000, 12, 31), now: now).isoDate,
        '2000-12-31',
      );
    });

    test('rejects incomplete, impossible, too old and future dates', () {
      expect(check('', '3', '1990').errorKey, AuthErrorKeys.dobIncomplete);
      expect(check('5', '3', '90').errorKey, AuthErrorKeys.dobIncomplete);
      expect(check('31', '2', '1990').errorKey, AuthErrorKeys.dobInvalid);
      expect(check('1', '13', '1990').errorKey, AuthErrorKeys.dobInvalid);
      expect(check('x', '1', '1990').errorKey, AuthErrorKeys.dobInvalid);
      expect(check('1', '1', '1899').errorKey, AuthErrorKeys.dobInvalid);
      expect(check('20', '10', '2026').errorKey, AuthErrorKeys.dobFuture);
      expect(check('19', '10', '2026').isValid, isTrue);
    });
  });

  group('AuthErrors', () {
    ApiException http(int status, [Object? data]) {
      final req = RequestOptions(path: '/api/x');
      return ApiException.from(
        DioException(
          requestOptions: req,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: req,
            statusCode: status,
            data: data,
          ),
        ),
      );
    }

    test('login: 401 is a refused code, 5xx keeps the common copy', () {
      final refused = AuthErrors.login(
        http(401, {'message': 'INVALID_OTP'}),
        rejectedKey: AuthErrorKeys.invalidOtp,
        fallbackKey: AuthErrorKeys.signInFailed,
      );
      expect(refused.type, ApiErrorType.rejected);
      expect(refused.i18nKey, AuthErrorKeys.invalidOtp);

      final readable = AuthErrors.login(
        http(400, {
          'error': {'message': 'OTP expired, request a new one'},
        }),
        rejectedKey: AuthErrorKeys.invalidOtp,
        fallbackKey: AuthErrorKeys.signInFailed,
      );
      expect(readable.serverMessage, 'OTP expired, request a new one');

      final server = AuthErrors.login(
        http(503),
        rejectedKey: AuthErrorKeys.invalidOtp,
        fallbackKey: AuthErrorKeys.signInFailed,
      );
      expect(server.i18nKey, 'errors.server');

      final other = AuthErrors.login(
        http(404),
        rejectedKey: AuthErrorKeys.invalidOtp,
        fallbackKey: AuthErrorKeys.signInFailed,
      );
      expect(other.i18nKey, AuthErrorKeys.signInFailed);
    });

    test('date of birth: known codes, no server text', () {
      final invalid = AuthErrors.dateOfBirth(
        http(400, {
          'error': {'message': 'DATE_OF_BIRTH_INVALID'},
        }),
      );
      expect(invalid.i18nKey, AuthErrorKeys.dobInvalid);
      final other = AuthErrors.dateOfBirth(
        http(400, {'message': 'Something odd happened here'}),
      );
      expect(other.serverMessage, isNull);
      expect(other.i18nKey, AuthErrorKeys.dobSaveFailed);
      expect(
        AuthErrors.dateOfBirth(http(401)).i18nKey,
        'errors.session_expired',
      );
      expect(AuthErrors.dateOfBirth(http(429)).i18nKey, 'errors.rate_limited');
    });

    test('language save: anything but transport is on our side', () {
      expect(AuthErrors.languageSave(http(404)).i18nKey, 'errors.server');
      expect(AuthErrors.languageSave(http(429)).i18nKey, 'errors.rate_limited');
    });

    test('interest error details', () {
      final e = http(400, {
        'error': {
          'name': 'REQUIRED_QUESTION_MISSING',
          'details': {'user_gender': 'required'},
        },
      });
      expect(e.interestErrorCode, 'REQUIRED_QUESTION_MISSING');
      expect(e.interestErrorDetails, {'user_gender': 'required'});
    });
  });

  group('Interests models', () {
    test('normalizes the form and round-trips through JSON', () {
      final form = InterestForm.fromResponse({
        'app': {'key': ''},
        'questions': [
          {
            'key': ' topics ',
            'selectionMode': 'MULTI',
            'maxSelect': 0,
            'minSelect': '1',
            'options': [
              {'value': ' a ', 'label': ''},
              {'value': '', 'label': 'dropped'},
            ],
          },
          {'title': 'no key, dropped'},
        ],
      });
      expect(form.app.key, 'vibe_os');
      expect(form.questions, hasLength(1));
      final q = form.questions.single;
      expect(q.key, 'topics');
      expect(q.isMulti, isTrue);
      expect(q.maxSelect, isNull);
      expect(q.minSelect, 1);
      expect(q.options.single.value, 'a');
      expect(q.options.single.label, 'a');
      expect(q.type, InterestQuestionType.interest);

      final copy = InterestForm.fromJson(jsonDecode(jsonEncode(form.toJson())));
      expect(copy.toJson(), form.toJson());
    });

    test('selections: trimmed, de-duplicated, empties dropped', () {
      expect(
        normalizeInterestSelections({
          ' a ': [' x', 'x', '', null, 'y'],
          '': ['z'],
          'b': 'not a list',
        }),
        {
          'a': ['x', 'y'],
          'b': <String>[],
        },
      );
      expect(normalizeInterestSelections(['nope']), isEmpty);
    });

    test('language question keeps live options only', () {
      final form = InterestForm.fromJson(_languageForm());
      final q = form.languageQuestion!;
      expect(q.options.map((o) => o.value), ['en', 'hi']);

      final deprecated = InterestForm.fromJson({
        'questions': [
          {
            'key': 'expert_language',
            'isDeprecated': true,
            'options': [
              {'value': 'en'},
            ],
          },
        ],
      });
      expect(deprecated.languageQuestion, isNull);
    });

    test('neutral answer: default, then opt-out, never invented', () {
      InterestQuestion q(List<JsonMap> options) =>
          InterestQuestion.fromJson({'key': 'k', 'options': options});
      expect(
        q([
          {'value': 'male'},
          {'value': 'any', 'isDefault': false},
          {'value': 'female', 'isDefault': true},
        ]).neutralAnswer,
        ['female'],
      );
      expect(
        q([
          {'value': 'male'},
          {'value': 'no_preference'},
        ]).neutralAnswer,
        ['no_preference'],
      );
      expect(
        q([
          {'value': 'male'},
          {'value': 'company'},
        ]).neutralAnswer,
        isEmpty,
      );
    });

    test('language payload keeps answers and fills required gaps', () {
      final form = InterestForm.fromJson(
        _languageForm(
          extra: [
            {
              'key': 'gender_pref',
              'required': true,
              'options': [
                {'value': 'male'},
                {'value': 'any'},
              ],
            },
            {
              'key': 'mode',
              'required': true,
              'options': [
                {'value': 'audio'},
              ],
            },
            {
              'key': 'answered',
              'required': true,
              'options': [
                {'value': 'any'},
              ],
            },
          ],
        ),
      );
      final payload = LanguageStep.buildSelections(
        existing: {
          'answered': ['x'],
          'expert_language': ['old'],
        },
        languages: ['hi'],
        form: form,
      );
      expect(payload, {
        'answered': ['x'],
        'expert_language': ['hi'],
        'gender_pref': ['any'],
      });
    });

    test('initial selection: saved live values, else defaults', () {
      final q = InterestForm.fromJson(_languageForm()).languageQuestion!;
      expect(LanguageStep.initialSelection(q, ['hi', 'old']), ['hi']);
      expect(LanguageStep.initialSelection(q, null), ['en']);
    });
  });

  group('Referrals', () {
    test('ReferralCheck and ReferrerTarget read v4 and v5 rows', () {
      final v5 = ReferralCheck.fromResponse({
        'data': [
          {
            'referralCode': 'ABC',
            'user': {'name': 'Asha'},
          },
        ],
      });
      expect((v5.isValid, v5.referrerName), (true, 'Asha'));
      expect(ReferralCheck.fromResponse({'data': []}).isValid, isFalse);

      final v4 = ReferrerTarget.fromResponse({
        'data': [
          {
            'id': 1,
            'attributes': {
              'user': {
                'data': {
                  'id': 2,
                  'attributes': {
                    'documentId': 'user-doc',
                    'expert': {
                      'data': {
                        'id': 9,
                        'attributes': {'documentId': 'expert-doc'},
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      }, handler: 'abc');
      expect(v4?.isExpert, isTrue);
      expect(v4?.documentId, 'expert-doc');
      expect(ReferrerTarget.fromResponse({'data': []}, handler: 'x'), isNull);
    });

    test('validateCode: upper-case filter, no token', () async {
      _routes({
        'GET /api/user-referrals': (
          200,
          {
            'data': [
              {
                'user': {'name': 'Ravi'},
              },
            ],
          },
        ),
      });
      final check = await ReferrerApi.validateCode(' abc12 ');
      expect(check.referrerName, 'Ravi');
      final req = _server.only('GET', '/api/user-referrals');
      expect(req.queryParameters[r'filters[referralCode][$eq]'], 'ABC12');
      expect(req.headers['Authorization'], isNull);
      expect(
        (await ReferrerApi.validateCode('  ')).isValid,
        isFalse,
        reason: 'empty code makes no request',
      );
      expect(_server.requests, hasLength(1));
    });
  });

  group('AuthApi', () {
    test('requestOtp: normalized identifier, device info, no token', () async {
      _routes({
        'POST /api/session-auth/otp/request': (200, {'message': 'sent'}),
      });
      await AuthApi.requestOtp(
        const OtpRequestInput(
          identifier: ' Asha@Mail.COM ',
          channel: OtpChannel.email,
        ),
      );
      final req = _server.only('POST', '/api/session-auth/otp/request');
      final body = req.data as Map;
      expect(body['identifier'], 'asha@mail.com');
      expect(body['channel'], 'email');
      expect(body['userPlatform'], 'vibe_os');
      expect(body['deviceInfo'], isA<Map>());
      expect(req.headers['Authorization'], isNull);
    });

    test(
      'verifyOtp: optional fields only when set; 401 = invalid code',
      () async {
        _routes({
          'POST /api/session-auth/otp/verify': (
            401,
            {'message': 'INVALID_OTP'},
          ),
        });
        await expectLater(
          AuthApi.verifyOtp(
            const OtpVerifyInput(
              identifier: '9999999999',
              code: '1234',
              referrerCode: 'ABC-R',
              fcmToken: '',
            ),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.type, 'type', ApiErrorType.rejected)
                .having((e) => e.i18nKey, 'key', AuthErrorKeys.invalidOtp),
          ),
        );
        final body = _server.requests.single.data as Map;
        expect(body['code'], '1234');
        expect(body['referrerCode'], 'ABC-R');
        expect(body.containsKey('fcmToken'), isFalse);
        expect(body.containsKey('voipToken'), isFalse);
      },
    );

    test('verifyOtp without a token is a sign-in failure', () async {
      _routes({
        'POST /api/session-auth/otp/verify': (200, {'message': 'ok'}),
      });
      await expectLater(
        AuthApi.verifyOtp(const OtpVerifyInput(identifier: 'x', code: '1')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.i18nKey,
            'key',
            AuthErrorKeys.signInFailed,
          ),
        ),
      );
    });

    test('socialLogin sends the provider token', () async {
      _routes({
        'POST /api/session-auth/social/exchange': (
          200,
          {
            'accessToken': 'a',
            'user': {'documentId': 'u'},
          },
        ),
      });
      final result = await AuthApi.socialLogin(
        const SocialLoginInput(provider: SocialProvider.apple, idToken: 'jwt'),
      );
      expect(result.accessToken, 'a');
      final body = _server.requests.single.data as Map;
      expect((body['provider'], body['idToken']), ('apple', 'jwt'));
    });

    test('submitDateOfBirth: AGE_BLOCKED is a verdict, not an error', () async {
      _routes({
        'PUT /api/me/date-of-birth': (
          403,
          {
            'error': {'message': 'AGE_BLOCKED'},
          },
        ),
      });
      expect(
        await AuthApi.submitDateOfBirth('2015-01-01'),
        AgeGateStatus.blocked,
      );
      expect(_server.requests.single.data, {'dateOfBirth': '2015-01-01'});

      _routes({
        'PUT /api/me/date-of-birth': (
          400,
          {
            'error': {'message': 'DATE_OF_BIRTH_IN_FUTURE'},
          },
        ),
      });
      await expectLater(
        AuthApi.submitDateOfBirth('2999-01-01'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.i18nKey,
            'key',
            AuthErrorKeys.dobFuture,
          ),
        ),
      );
    });

    test('fetchUser populates the profile picture', () async {
      _routes({
        'GET /api/public-users/u%201': (
          200,
          {
            'data': {'documentId': 'u 1', 'name': 'N'},
          },
        ),
      });
      expect((await AuthApi.fetchUser('u 1'))['name'], 'N');
      expect(
        _server.requests.single.queryParameters['populate[profilePic]'],
        'true',
      );
    });
  });

  group('sign-in and logout', () {
    test('signs in with the merged profile; login payload wins', () async {
      _routes({
        'POST /api/session-auth/otp/verify': (
          200,
          {
            'accessToken': 'acc-new',
            'refreshToken': 'ref-new',
            'user': {'id': 7, 'documentId': 'u1', 'name': 'Fresh'},
          },
        ),
        'GET /api/public-users/u1': (
          200,
          {
            'data': {
              'documentId': 'u1',
              'name': 'Stale',
              'profilePic': {'url': '/p.jpg'},
              'is_company_account': true,
            },
          },
        ),
      });
      final result = await signInWithOtp(
        const OtpVerifyInput(identifier: 'x', code: '1234'),
      );
      final session = SessionStore.instance.value;
      expect(session.isAuthenticated, isTrue);
      expect(session.user?['name'], 'Fresh');
      expect(session.user?['profilePic'], {'url': '/p.jpg'});
      expect(session.user?['isCompanyAccount'], isTrue);
      expect(result.user?['name'], 'Fresh');
      expect(await TokenStorage.instance.readAccessToken(), 'acc-new');
      expect(await TokenStorage.instance.readRefreshToken(), 'ref-new');
      // The profile read already carried the new user token.
      expect(
        _server.only('GET', '/api/public-users/u1').headers['Authorization'],
        'Bearer acc-new',
      );
    });

    test('uses the profile loader and survives its failure', () async {
      _routes({
        'POST /api/session-auth/social/exchange': (
          200,
          {
            'accessToken': 'a',
            'user': {'documentId': 'u1'},
          },
        ),
      });
      final withExpert = await signInWithSocial(
        const SocialLoginInput(provider: SocialProvider.google, idToken: 't'),
        loadProfile: (id) async => (
          user: {'documentId': id, 'name': 'From profile'},
          expert: {'id': 5, 'documentId': 'e5'},
        ),
      );
      expect(withExpert.expert?['documentId'], 'e5');
      expect(SessionStore.instance.value.expertDocumentId, 'e5');
      expect(SessionStore.instance.value.user?['name'], 'From profile');

      final noProfile = await signInWithSocial(
        const SocialLoginInput(provider: SocialProvider.google, idToken: 't'),
        loadProfile: (_) async =>
            throw const ApiException(ApiErrorType.network),
      );
      expect(noProfile.expert, isNull);
      expect(SessionStore.instance.value.isAuthenticated, isTrue);
    });

    test('a failed sign-in leaves no tokens behind', () async {
      _routes({
        'POST /api/session-auth/otp/verify': (200, {'accessToken': 'a'}),
        'GET /api/auth/verify-token': (200, {'valid': true}),
      });
      await expectLater(
        signInWithOtp(const OtpVerifyInput(identifier: 'x', code: '1')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.i18nKey,
            'key',
            AuthErrorKeys.signInFailed,
          ),
        ),
      );
      expect(await TokenStorage.instance.readAccessToken(), isNull);
      expect(SessionStore.instance.value.isAuthenticated, isFalse);
    });

    test('logout cleans up with the user token, then revokes', () async {
      await _signedIn({'id': 7, 'documentId': 'u1'});
      _server.handler = (_) => (200, {});
      await logout(const LogoutInput(fcmToken: 'fcm-1', voipToken: 'voip-1'));

      const unregister =
          '/api/app-notification-orchestrator/devices/unregister';
      final unregisterReq = _server.only('POST', unregister);
      expect(unregisterReq.headers['Authorization'], 'Bearer acc-1');
      expect(unregisterReq.data, {'fcmToken': 'fcm-1', 'voipToken': 'voip-1'});
      final clear = _server.only('PUT', '/api/public-users/u1/fcm-token');
      expect(clear.data, {
        'deviceId': (await DeviceInfo.get())['deviceId'],
        'firebaseTokens': <String>[],
        'voipToken': null,
      });
      final revoke = _server.only('POST', '/api/session-auth/logout');
      expect((revoke.data as Map)['refreshToken'], 'ref-1');

      final revokeAt = _server.indexOf('POST', '/api/session-auth/logout');
      expect(_server.indexOf('POST', unregister), lessThan(revokeAt));
      expect(
        _server.indexOf('PUT', '/api/public-users/u1/fcm-token'),
        lessThan(revokeAt),
      );
      expect(SessionStore.instance.value.isAuthenticated, isFalse);
      expect(await TokenStorage.instance.readAccessToken(), isNull);
    });

    test('logout signs out locally even when the server fails', () async {
      await _signedIn({'id': 7, 'documentId': 'u1'});
      _server.handler = (_) => (500, {});
      await logout();
      expect(SessionStore.instance.value.isAuthenticated, isFalse);
      expect(
        _server.indexOf(
          'POST',
          '/api/app-notification-orchestrator/devices/unregister',
        ),
        -1,
        reason: 'no push token, nothing to unregister',
      );
    });
  });

  group('onboarding', () {
    test('GET /me verdict is stored on the session user', () async {
      await _signedIn({'id': 7, 'documentId': 'u1'});
      _routes({
        'GET /api/me': (
          200,
          {
            'user': {'date_of_birth': null, 'ageGateStatus': 'required'},
          },
        ),
      });
      expect(await syncAgeGateStatus(), AgeGateStatus.required);
      expect(SessionStore.instance.value.ageGateStatus, AgeGateStatus.required);
      expect(
        await nextOnboardingStep(),
        OnboardingStep.ageGate,
        reason: 'stored verdict, no second /me',
      );
      expect(_server.requests, hasLength(1));
    });

    test('a failed /me keeps the stored verdict', () async {
      await _signedIn({'id': 7, 'documentId': 'u1', 'date_of_birth': null});
      _server.handler = (_) => (503, {});
      expect(await syncAgeGateStatus(), AgeGateStatus.required);
    });

    test('saving the date of birth clears the gate', () async {
      await _signedIn({
        'id': 7,
        'documentId': 'u1',
        'ageGateStatus': 'required',
      });
      _routes({'PUT /api/me/date-of-birth': (200, {})});
      expect(await saveDateOfBirth('1990-03-05'), AgeGateStatus.ok);
      final user = SessionStore.instance.value.user!;
      expect(user['date_of_birth'], '1990-03-05');
      expect(SessionStore.instance.value.ageGateStatus, AgeGateStatus.ok);
    });

    test('language step: required until answered, then done', () async {
      await _signedIn({
        'id': 7,
        'documentId': 'u1',
        'date_of_birth': '1990-01-01',
      });
      _routes({
        'GET /api/interests/form': (200, _languageForm()),
        'GET /api/languages': (200, _languages()),
        'GET /api/me/interests': (200, {'selections': {}}),
      });
      expect(await nextOnboardingStep(), OnboardingStep.language);
      final form = _server.only('GET', '/api/interests/form');
      expect(form.queryParameters, {'app': 'vibe_os', 'appKey': 'vibe_os'});

      // Choices: the Languages collection (documentIds), not the form's.
      final data = await loadLanguageQuestion();
      expect(data.question?.key, LanguageStep.questionKey);
      expect(
        [for (final o in data.question!.options) o.value],
        ['en-doc', 'hi-doc'],
      );
      expect(data.selected, ['en-doc'], reason: 'form default, by name');

      _routes({
        'GET /api/me/interests': (
          200,
          {
            'selections': {
              'other': ['x'],
            },
          },
        ),
        'PUT /api/me/interests': (200, {'savedCount': 2}),
      });
      expect(await saveLanguageStep(['hi-doc']), isTrue);
      final put = _server.only('PUT', '/api/me/interests');
      expect((put.data as Map)['selections'], {
        'other': ['x'],
        'expert_language': ['hi-doc'],
      });

      _server.requests.clear();
      expect(await ensureLanguageStepStatus(), LanguageStepStatus.done);
      expect(_server.requests, isEmpty, reason: 'completion is remembered');
    });

    test('a refused language answer still completes the step', () async {
      await _signedIn({'id': 7, 'documentId': 'u2'});
      _routes({
        'GET /api/me/interests': (200, {'selections': {}}),
        'PUT /api/me/interests': (
          422,
          {
            'error': {'name': 'REQUIRED_QUESTION_MISSING'},
          },
        ),
      });
      expect(await saveLanguageStep(['en']), isFalse);
      expect(await ensureLanguageStepStatus(), LanguageStepStatus.done);
    });

    test('a language save the server fails is retryable', () async {
      await _signedIn({'id': 7, 'documentId': 'u3'});
      _routes({
        'GET /api/me/interests': (200, {'selections': {}}),
        'PUT /api/me/interests': (500, {}),
      });
      await expectLater(
        saveLanguageStep(['en']),
        throwsA(
          isA<ApiException>().having((e) => e.i18nKey, 'key', 'errors.server'),
        ),
      );
    });

    test('an unreachable check never blocks the app', () async {
      await _signedIn({'id': 7, 'documentId': 'u4'});
      _routes({});
      expect(await ensureLanguageStepStatus(), LanguageStepStatus.done);
    });

    test('the form falls back to the disk copy', () async {
      await _signedIn({'id': 7, 'documentId': 'u5'});
      _routes({'GET /api/interests/form': (200, _languageForm())});
      await ensureInterestForm();
      queryCache.clear();
      _routes({'GET /api/languages': (200, _languages())});
      expect(cachedInterestForm()?.languageQuestion, isNotNull);
      final data = await loadLanguageQuestion();
      expect(data.question?.key, LanguageStep.questionKey);
      expect(data.selected, ['en-doc'], reason: 'no saved answer: defaults');
    });
  });

  group('push', () {
    test('token sync: per-user registry, then the orchestrator', () async {
      _server.handler = (_) => (200, {});
      await syncPushTokens(fcmToken: 'fcm-1', voipToken: 'v', userId: 7);
      expect(_server.requests.first.path, '/api/public-users/7/fcm-token');
      expect(_server.requests.first.data, {'firebaseTokens': 'fcm-1'});
      expect(
        _server.requests[1].path,
        '/api/app-notification-orchestrator/devices/register',
      );
      expect(_server.requests[1].data, {'fcmToken': 'fcm-1', 'voipToken': 'v'});
    });

    test('token sync is skipped when signed out and never throws', () async {
      await syncPushTokens(fcmToken: 'fcm-1');
      expect(_server.requests, isEmpty);
      _server.handler = (_) => (403, {});
      expect(await registerPushDevice(fcmToken: 'x'), isFalse);
    });

    test('push events are reported once per tracking id', () async {
      _server.handler = (_) => (200, {});
      final data = {'trackingId': 't-1', 'deeplink': 'vibecalling://home'};
      trackPushEvent(PushEvent.opened, data);
      trackPushEvent(PushEvent.opened, data);
      trackPushEvent(PushEvent.clicked, {'notificationTrackingId': 't-1'});
      trackPushEvent(PushEvent.opened, {'title': 'not a campaign'});
      await pumpEventQueue(times: 200);
      final tracked = _server.requests
          .where((r) => r.path.endsWith('/notifications/track'))
          .map((r) => (r.data as Map)['eventType'])
          .toList();
      expect(tracked, ['opened', 'clicked']);
      final first = _server.requests.first.data as Map;
      expect((first['metadata'] as Map)['deeplink'], 'vibecalling://home');
    });

    test('voip token route', () async {
      _server.handler = (_) => (200, {});
      await PushApi.updateVoipToken('u1', 'voip');
      expect(_server.requests.single.path, '/api/public-users/u1/voip-token');
      expect(_server.requests.single.data, {'voipToken': 'voip'});
    });
  });

  group('i18n', () {
    Map<String, String> flat(Object? node, [String prefix = '']) => {
      if (node is Map)
        for (final e in node.entries)
          ...flat(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}')
      else
        prefix: '$node',
    };
    Map<String, String> load(String lang) => flat(
      jsonDecode(File('assets/i18n/$lang/auth.json').readAsStringSync()),
    );

    test('en and hi have the same keys, Hindi in Devanagari', () {
      final en = load('en');
      final hi = load('hi');
      expect(hi.keys.toSet(), en.keys.toSet());
      const brands = {'Google', 'Apple'}; // never translated
      for (final value in hi.values.where((v) => !brands.contains(v))) {
        expect(value, matches(RegExp(r'[ऀ-ॿ]')));
      }
    });

    test('every auth: key used by the API layer exists', () {
      final en = load('en');
      final used = <String>{
        for (final f in Directory('lib/app/api/authscreen').listSync())
          if (f is File)
            for (final m in RegExp(
              r"'auth:([a-z_.]+)'",
            ).allMatches(f.readAsStringSync()))
              m.group(1)!,
      };
      expect(used, isNotEmpty);
      expect(en.keys.toSet().containsAll(used), isTrue, reason: '$used');
    });
  });
}
