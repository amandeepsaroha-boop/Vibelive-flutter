import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/authscreen/auth_errors.dart';
import 'package:vibelive/app/api/authscreen/auth_models.dart';
import 'package:vibelive/app/authscreen/helper/login_format.dart';
import 'package:vibelive/app/authscreen/helper/sms_otp_autofill.dart';
import 'package:vibelive/core/network/api_exception.dart';

void main() {
  test('Indian mobile: 10 digits starting 6-9', () {
    expect(LoginFormat.isValidIndianMobile('9876543210'), isTrue);
    expect(LoginFormat.isValidIndianMobile('5876543210'), isFalse);
    expect(LoginFormat.isValidIndianMobile('987654321'), isFalse);
    expect(LoginFormat.formatMobile('9876543210'), '98765 43210');
  });

  test('email mask and validation', () {
    expect(LoginFormat.maskEmail('Tester@Mail.com'), 'te***@mail.com');
    expect(LoginFormat.maskEmail('ab@x.io'), 'a***@x.io');
    expect(LoginFormat.isValidEmail(' a@b.co '), isTrue);
    expect(LoginFormat.isValidEmail('a@b'), isFalse);
  });

  test('extractOtp takes the first standalone 4-digit group', () {
    expect(
      SmsOtpAutofill.extractOtp('Your OTP is 4821 for Vibe. h4Sk9xYz12'),
      '4821',
    );
    expect(SmsOtpAutofill.extractOtp('Code 123456'), isNull);
    expect(SmsOtpAutofill.extractOtp(null), isNull);
  });

  test('bypass answer of /otp/request is a session; a plain one is not', () {
    expect(LoginResult.fromBypass({'success': true}), isNull);
    expect(
      LoginResult.fromBypass({
        'bypassed': true,
        'accessToken': 'a',
        'user': {'documentId': 'u1'},
      })?.accessToken,
      'a',
    );
  });

  test('retry-after: body details, else the header, else 0', () {
    expect(
      AuthErrors.retryAfterSeconds(
        const ApiException(
          ApiErrorType.rateLimited,
          data: {
            'error': {
              'details': {'retryAfter': 12.2},
            },
          },
        ),
      ),
      13,
    );
    final options = RequestOptions(path: '/x');
    expect(
      AuthErrors.retryAfterSeconds(
        ApiException(
          ApiErrorType.rateLimited,
          cause: DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 429,
              headers: Headers.fromMap({
                'retry-after': ['20'],
              }),
            ),
          ),
        ),
      ),
      20,
    );
    expect(
      AuthErrors.retryAfterSeconds(const ApiException(ApiErrorType.network)),
      0,
    );
  });
}
