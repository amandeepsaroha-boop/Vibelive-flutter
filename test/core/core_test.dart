import 'dart:ui' show Size;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/splashscreen/splash_models.dart';
import 'package:vibelive/app/banner/top_warn_bar.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/utils/scale.dart';

DioException _bad(int status, [Object? data]) {
  final req = RequestOptions(path: '/api/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  group('ApiException.from', () {
    test('maps HTTP status to type', () {
      expect(ApiException.from(_bad(400)).type, ApiErrorType.rejected);
      expect(ApiException.from(_bad(401)).type, ApiErrorType.unauthorized);
      expect(ApiException.from(_bad(404)).type, ApiErrorType.notFound);
      expect(ApiException.from(_bad(429)).type, ApiErrorType.rateLimited);
      expect(ApiException.from(_bad(503)).type, ApiErrorType.server);
    });

    test('maps transport failures', () {
      final req = RequestOptions(path: '/x');
      expect(
        ApiException.from(
          DioException(
            requestOptions: req,
            type: DioExceptionType.connectionError,
          ),
        ).type,
        ApiErrorType.network,
      );
      expect(
        ApiException.from(
          DioException(
            requestOptions: req,
            type: DioExceptionType.receiveTimeout,
          ),
        ).type,
        ApiErrorType.timeout,
      );
      expect(
        ApiException.from(const FormatException('x')).type,
        ApiErrorType.parse,
      );
    });

    test('keeps readable server messages, drops error codes', () {
      final readable = ApiException.from(
        _bad(400, {
          'error': {'message': 'OTP expired, request a new one'},
        }),
      );
      expect(readable.serverMessage, 'OTP expired, request a new one');
      final code = ApiException.from(_bad(400, {'message': 'INVALID_OTP'}));
      expect(code.serverMessage, isNull);
      expect(code.i18nKey, 'errors.rejected');
    });

    test('transient flag drives retries', () {
      expect(ApiException.from(_bad(500)).isTransient, isTrue);
      expect(ApiException.from(_bad(422)).isTransient, isFalse);
    });

    test('passes ApiException and wrapped ApiException through', () {
      const original = ApiException(ApiErrorType.loggingOut);
      expect(ApiException.from(original), same(original));
      final wrapped = DioException(
        requestOptions: RequestOptions(path: '/x'),
        error: original,
      );
      expect(ApiException.from(wrapped), same(original));
    });
  });

  group('Strapi', () {
    test('node unwraps v4 data/attributes and v5 flat', () {
      expect(
        Strapi.map({
          'data': {
            'id': 3,
            'attributes': {'name': 'A'},
          },
        }),
        {'id': 3, 'name': 'A'},
      );
      expect(Strapi.map({'id': 3, 'name': 'A'}), {'id': 3, 'name': 'A'});
    });

    test('list always returns a list of maps', () {
      expect(Strapi.list(null), isEmpty);
      expect(
        Strapi.list({
          'data': {'id': 1},
        }),
        [
          {'id': 1},
        ],
      );
      expect(
        Strapi.list({
          'data': [
            {
              'id': 1,
              'attributes': {'a': 1},
            },
            {'id': 2},
          ],
        }),
        [
          {'id': 1, 'a': 1},
          {'id': 2},
        ],
      );
    });

    test('media prefers card-sized formats for thumbs', () {
      final asset = {
        'url': '/uploads/o.jpg',
        'formats': {
          'small': {'url': '/uploads/s.jpg'},
          'medium': {'url': '/uploads/m.jpg'},
        },
      };
      expect(Strapi.mediaThumbFromAsset(asset), endsWith('/uploads/m.jpg'));
      expect(Strapi.mediaFromAsset(asset), endsWith('/uploads/o.jpg'));
      expect(Strapi.mediaUrl('https://cdn/x.png'), 'https://cdn/x.png');
    });

    test('J readers are lenient', () {
      expect(J.integer('12'), 12);
      expect(J.number('4.5'), 4.5);
      expect(J.boolean('true'), isTrue);
      expect(J.boolean(0), isFalse);
      expect(J.str(''), isNull);
    });
  });

  test('moderateScale matches the RN formula', () {
    Scale.update(const Size(414, 896));
    expect(moderateScale(16), closeTo(16 + (414 / 375 * 16 - 16) * 0.5, 1e-9));
    expect(16.ms, moderateScale(16));
    Scale.update(const Size(375, 812));
    expect(moderateScale(16), 16);
  });

  group(
    'AppVersionInfo.shouldPrompt (RN rule: differs, trailing zeros ignored)',
    () {
      test('equal versions do not prompt', () {
        const v = AppVersionInfo({'version': '3.0.0'});
        expect(v.shouldPrompt('3.0'), isFalse);
      });
      test('any difference prompts', () {
        const v = AppVersionInfo({'version': '3.0.47'});
        expect(v.shouldPrompt('3.0.48'), isTrue);
        expect(v.shouldPrompt(null), isFalse);
      });
    },
  );

  group('ProfileWarning (TopWarnBar rules)', () {
    test('missing personal fields come first', () {
      final w = ProfileWarning.from(
        const SessionState(user: {'id': 1, 'name': 'A'}),
      );
      expect(w?.type, ProfileWarningType.personal);
      expect(w?.missing, ['banner:fields.email', 'banner:fields.mobile']);
    });

    test('complete non-host user has no warning', () {
      expect(
        ProfileWarning.from(
          const SessionState(
            user: {'name': 'A', 'email': 'a@b.c', 'mobile': '9'},
          ),
        ),
        isNull,
      );
    });

    test('host without rates, then without approval', () {
      const user = {'name': 'A', 'email': 'a@b.c', 'mobile': '9'};
      final host = {
        'id': 7,
        'handler': 'abc',
        'tagline': 't',
        'descriptions': 'd',
        'language': [
          {'id': 1},
        ],
      };
      expect(
        ProfileWarning.from(SessionState(user: user, expert: host))?.type,
        ProfileWarningType.rates,
      );
      expect(
        ProfileWarning.from(
          SessionState(user: user, expert: {...host, 'voiceCallRate': 10}),
        )?.type,
        ProfileWarningType.approval,
      );
      expect(
        ProfileWarning.from(
          SessionState(
            user: user,
            expert: {
              ...host,
              'voiceCallRate': 10,
              'expert_profile_approvals': const [
                {'status': 'pending'},
              ],
            },
          ),
        ),
        isNull,
      );
    });

    test('live host never warns', () {
      expect(
        ProfileWarning.from(
          const SessionState(
            user: {'id': 1},
            expert: {'id': 2, 'isLive': true},
          ),
        ),
        isNull,
      );
    });
  });
}
