import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/client/personal_info/helper/photo_source.dart';
import 'package:vibelive/app/client/personal_info/personal_info_screen.dart';
import 'package:vibelive/app/client/personal_info/widgets/geo_picker_sheet.dart';
import 'package:vibelive/app/client/personal_info/widgets/personal_info_skeleton.dart';
import 'package:vibelive/core/session/session_store.dart';

import 'personal_info_support/harness.dart';

void main() {
  setUpPersonalInfoMocks();

  late FakePhotoSource photos;
  setUp(() => PersonalInfoPhotoSource.instance = photos = FakePhotoSource());

  /// Taps the ✓ and waits for the request(s) and the alert.
  Future<void> save(WidgetTester tester) async {
    await tapKey(tester, 'personal_info.save');
    await pumpFor(tester, 500);
  }

  Future<void> expectAlert(WidgetTester tester, String message) async {
    expect(find.text(message), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 300);
  }

  testWidgets('skeleton, then the profile fills the form', (tester) async {
    await openPersonalInfo(tester, settle: false);
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(PersonalInfoSkeleton), findsOneWidget);

    await pumpFor(tester, 600);
    expect(find.byType(PersonalInfoSkeleton), findsNothing);
    expect(find.text('Personal Info'), findsOneWidget);
    expect(find.text('BASIC INFO'), findsOneWidget);
    expect(fieldText(tester, 'personal_info.name'), 'Asha Verma');
    expect(fieldText(tester, 'personal_info.email'), 'asha@b.co');
    expect(fieldText(tester, 'personal_info.mobile'), '9876543210');
    expect(find.text('Delhi'), findsOneWidget);
    expect(find.text('New Delhi'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // avatar letter, no photo
    await finish(tester);
  });

  testWidgets('validation: one alert per problem, nothing sent', (
    tester,
  ) async {
    final backend = await openPersonalInfo(tester);

    await enter(tester, 'personal_info.name', 'A');
    await save(tester);
    await expectAlert(tester, 'Please enter your full name.');

    await enter(tester, 'personal_info.name', 'Asha');
    await enter(tester, 'personal_info.email', '');
    await save(tester);
    await expectAlert(tester, 'Please enter your email address.');

    await enter(tester, 'personal_info.email', 'asha@b');
    await save(tester);
    await expectAlert(tester, 'Please enter a valid email address.');

    await enter(tester, 'personal_info.email', 'asha@b.co');
    await enter(tester, 'personal_info.mobile', '');
    await save(tester);
    await expectAlert(tester, 'Please enter your mobile number.');

    await enter(tester, 'personal_info.mobile', '98765');
    await save(tester);
    await expectAlert(tester, 'Please enter a valid 10-digit mobile number.');

    // Letters never get in; a pasted +91 number is normalised.
    await enter(tester, 'personal_info.mobile', '+91 98765 43210');
    expect(fieldText(tester, 'personal_info.mobile'), '9876543210');

    expect(backend.where('PUT', '/api/public-users/u1'), isEmpty);
    await finish(tester);
  });

  testWidgets('save: RN body, session updated, success, then back', (
    tester,
  ) async {
    final backend = await openPersonalInfo(tester);
    await enter(tester, 'personal_info.name', '  Asha Rao ');
    await enter(tester, 'personal_info.email', 'Asha.New@B.co');
    await save(tester);

    final put = backend.where('PUT', '/api/public-users/u1').single;
    final data = (put.data as Map)['data'] as Map;
    expect(data['name'], 'Asha Rao');
    expect(data['email'], 'asha.new@b.co');
    expect(data.containsKey('mobile'), isFalse); // unchanged: not sent
    expect(data['state'], {
      'connect': [
        {'id': 1},
      ],
    });
    expect(data['district'], {
      'connect': [
        {'id': 11},
      ],
    });
    expect(data['country'], {
      'connect': [
        {'id': 99},
      ],
    });
    expect(data['city'], isNull);
    expect(data.containsKey('city'), isTrue);
    expect(data['address_JSON'], {
      'state': 'Delhi',
      'district': 'New Delhi',
      'city': '',
      'country': 'India',
    });

    // The rest of the app (ME tab, call gates) sees the new data.
    final session = SessionStore.instance.value.user!;
    expect(session['name'], 'Asha Rao');
    expect(session['email'], 'asha.new@b.co');

    expect(find.text('Profile Saved'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await pumpFor(tester, 600);
    expect(find.byType(PersonalInfoScreen), findsNothing);
    expect(find.text('OPEN'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a taken email names the field and keeps the screen', (
    tester,
  ) async {
    final backend = await openPersonalInfo(tester);
    backend.emailTaken = true;
    await enter(tester, 'personal_info.email', 'taken@b.co');
    await save(tester);

    expect(find.text('This email is already in use.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 300);
    expect(find.byType(PersonalInfoScreen), findsOneWidget);
    expect(fieldText(tester, 'personal_info.email'), 'taken@b.co');
    await finish(tester);
  });

  testWidgets('photo: picked through the seam, linked, stays on screen', (
    tester,
  ) async {
    final backend = await openPersonalInfo(tester);
    // An unsaved edit survives the photo update.
    await enter(tester, 'personal_info.name', 'Asha Edited');

    await tapKey(tester, 'personal_info.photo');
    await pumpFor(tester, 600);

    expect(photos.uploads, ['/tmp/picked.jpg']);
    final put = backend.where('PUT', '/api/public-users/u1').single;
    expect(put.data, {
      'data': {'profilePic': 501},
    });
    expect(find.text('Photo Updated'), findsOneWidget);
    expect(SessionStore.instance.value.user!['profilePic'], isNotNull);

    await tester.tap(find.text('CONTINUE'));
    await pumpFor(tester, 300);
    expect(find.byType(PersonalInfoScreen), findsOneWidget);
    expect(fieldText(tester, 'personal_info.name'), 'Asha Edited');

    // Cancelled picker: nothing happens.
    photos.next = null;
    await tapKey(tester, 'personal_info.photo');
    await pumpFor(tester, 300);
    expect(photos.uploads, hasLength(1));

    photos.fail = true;
    await tapKey(tester, 'personal_info.photo');
    await pumpFor(tester, 300);
    expect(find.text('Failed to pick image.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 300);
    await finish(tester);
  });

  testWidgets('state → districts of that state, search debounced', (
    tester,
  ) async {
    final user = completeUser()
      ..remove('state')
      ..remove('district')
      ..remove('address_JSON');
    final backend = await openPersonalInfo(tester, user: user);
    expect(find.text('Select State'), findsOneWidget);
    expect(find.text('Select District'), findsOneWidget);

    // District is locked until a state is picked.
    await tapKey(tester, 'personal_info.district');
    await pumpFor(tester, 300);
    expect(find.byType(GeoPickerSheet), findsNothing);

    await tapKey(tester, 'personal_info.state');
    await pumpFor(tester, 600);
    expect(find.byType(GeoPickerSheet), findsOneWidget);
    expect(find.text('STATE'), findsOneWidget);
    expect(find.text('Maharashtra'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('personal_info.picker.search')),
      'Maha',
    );
    await pumpFor(tester, 100);
    final before = backend.where('GET', '/api/states').length;
    await pumpFor(tester, 400);
    final searches = backend.where('GET', '/api/states').skip(before);
    expect(
      searches.map((c) => c.query[r'filters[name][$containsi]']),
      contains('Maha'),
    );
    expect(find.text('Delhi'), findsNothing);

    await tester.tap(find.text('Maharashtra'));
    await pumpFor(tester, 600);
    expect(find.byType(GeoPickerSheet), findsNothing);
    expect(find.text('Maharashtra'), findsOneWidget);
    expect(find.text('Select District'), findsOneWidget);

    await tapKey(tester, 'personal_info.district');
    await pumpFor(tester, 600);
    final districtCall = backend.where('GET', '/api/districts').last;
    expect(districtCall.query[r'filters[state][documentId][$eq]'], 'st-mh');
    expect(find.text('Pune'), findsOneWidget);
    expect(find.text('Mumbai'), findsOneWidget);

    await tester.tap(find.text('Pune'));
    await pumpFor(tester, 600);
    expect(find.text('Pune'), findsOneWidget);

    // A new state clears the district again.
    await tapKey(tester, 'personal_info.state');
    await pumpFor(tester, 600);
    await tester.tap(find.text('Delhi'));
    await pumpFor(tester, 600);
    expect(find.text('Select District'), findsOneWidget);
    await finish(tester);
  });
}
