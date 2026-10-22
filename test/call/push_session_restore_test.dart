import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/storage/token_storage.dart';

/// I10: a VoIP push can boot the app on a locked phone, where prefs and the
/// keychain read as empty. A restore then must never wipe the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
    await AppPrefs.remove('session_user');
  });

  tearDown(() => SessionStore.protectedDataAvailable = null);

  test('locked, prefs unreadable: the tokens are kept', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok'});
    SessionStore.protectedDataAvailable = () async => false;
    await SessionStore.instance.restore();
    expect(await TokenStorage.instance.readAccessToken(), 'tok');
  });

  test('unlocked, no user: leftover tokens are cleared', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok'});
    SessionStore.protectedDataAvailable = () async => true;
    await SessionStore.instance.restore();
    expect(await TokenStorage.instance.readAccessToken(), isNull);
  });

  test('locked, user but no readable token: the user is kept', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPrefs.setString('session_user', '{"id": 9}');
    SessionStore.protectedDataAvailable = () async => false;
    await SessionStore.instance.restore();
    expect(AppPrefs.getString('session_user'), isNotNull);
  });

  test('unlocked, user and token: signed in', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok'});
    await AppPrefs.setString('session_user', '{"id": 9}');
    SessionStore.protectedDataAvailable = () async => true;
    await SessionStore.instance.restore();
    expect(SessionStore.instance.value.isAuthenticated, isTrue);
  });
}
