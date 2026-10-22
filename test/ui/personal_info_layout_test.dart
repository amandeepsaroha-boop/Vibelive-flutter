import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/client/personal_info/helper/photo_source.dart';
import 'package:vibelive/app/client/personal_info/personal_info_screen.dart';
import 'package:vibelive/app/client/personal_info/widgets/geo_picker_sheet.dart';
import 'package:vibelive/core/theme/app_colors.dart';

import 'personal_info_support/harness.dart';

void main() {
  setUpPersonalInfoMocks();
  setUp(() => PersonalInfoPhotoSource.instance = FakePhotoSource());

  Finder field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );

  Color? textColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  Color? screenBackground(WidgetTester tester) => tester
      .widget<Scaffold>(
        find.descendant(
          of: find.byType(PersonalInfoScreen),
          matching: find.byType(Scaffold),
        ),
      )
      .backgroundColor;

  testWidgets('iPhone SE: focused field and Save clear of the keyboard', (
    tester,
  ) async {
    const size = Size(375, 667);
    const keyboard = 260.0;
    final backend = await openPersonalInfo(tester, size: size);

    await tester.ensureVisible(field('personal_info.mobile'));
    await tester.tap(field('personal_info.mobile'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    await pumpFor(tester, 500);

    final mobile = tester.getRect(field('personal_info.mobile'));
    expect(mobile.bottom, lessThanOrEqualTo(size.height - keyboard));
    expect(mobile.top, greaterThan(0));

    final saveButton = tester.getRect(
      find.byKey(const ValueKey('personal_info.save')),
    );
    expect(saveButton.top, greaterThanOrEqualTo(20)); // under the status bar
    expect(saveButton.bottom, lessThan(size.height - keyboard));

    await enter(tester, 'personal_info.mobile', '9123456780');
    await tester.tap(find.byKey(const ValueKey('personal_info.save')));
    await pumpFor(tester, 500);
    final put = backend.where('PUT', '/api/public-users/u1').single;
    expect(((put.data as Map)['data'] as Map)['mobile'], '9123456780');
    await finish(tester);
  });

  testWidgets('last field scrolls clear of the home indicator', (tester) async {
    const size = Size(390, 844);
    await openPersonalInfo(tester, size: size, bottomInset: 34);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await pumpFor(tester, 400);
    final district = tester.getRect(
      find.byKey(const ValueKey('personal_info.district')),
    );
    expect(district.bottom, lessThanOrEqualTo(size.height - 34));
    await finish(tester);
  });

  testWidgets('dark and light themes', (tester) async {
    await openPersonalInfo(tester);
    expect(screenBackground(tester), DarkColors.bg);
    expect(textColor(tester, 'Personal Info'), AppColors.white);
    await tapKey(tester, 'personal_info.state');
    await pumpFor(tester, 600);
    expect(find.byType(GeoPickerSheet), findsOneWidget);
    await finish(tester);

    await openPersonalInfo(tester, theme: ThemeMode.light);
    expect(screenBackground(tester), LightColors.bg);
    expect(textColor(tester, 'Personal Info'), LightColors.text);
    await tapKey(tester, 'personal_info.state');
    await pumpFor(tester, 600);
    expect(find.byType(GeoPickerSheet), findsOneWidget);
    await finish(tester);
  });

  testWidgets('320 px wide in Hindi: no overflow, Hindi copy', (tester) async {
    const size = Size(320, 568);
    await openPersonalInfo(tester, size: size, locale: const Locale('hi'));

    expect(find.text('व्यक्तिगत जानकारी'), findsOneWidget);
    expect(find.text('बुनियादी जानकारी'), findsOneWidget);
    expect(find.text('पूरा नाम'), findsWidgets); // label (+ hidden hint)

    await enter(tester, 'personal_info.name', '');
    await tapKey(tester, 'personal_info.save');
    await pumpFor(tester, 400);
    expect(find.text('कृपया अपना पूरा नाम लिखें।'), findsOneWidget);
    await tester.tap(find.text('ठीक है'));
    await pumpFor(tester, 300);

    await tapKey(tester, 'personal_info.state');
    await pumpFor(tester, 600);
    expect(find.text('राज्य खोजें...'), findsOneWidget);
    // Keyboard up in the sheet on the smallest phone.
    await tester.tap(find.byKey(const ValueKey('personal_info.picker.search')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 250 * 3);
    await pumpFor(tester, 400);
    final row = find.descendant(
      of: find.byType(GeoPickerSheet),
      matching: find.text('Delhi'),
    );
    expect(row, findsOneWidget);
    expect(tester.getRect(row).bottom, lessThanOrEqualTo(size.height - 250));
    await finish(tester);
  });
}
