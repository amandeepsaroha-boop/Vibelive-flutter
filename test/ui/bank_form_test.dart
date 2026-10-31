import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/component/c_button.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/bank_doc.dart';
import 'package:vibelive/app/paymentscreen/wallet/widgets/bank_form_view.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/strapi.dart';

import 'host_onboarding_support/harness.dart';

/// The payout-account form asks for the proof photos the backend requires
/// (passbook / cheque, PAN front and back), uploads each as it is picked,
/// and sends their ids with the account.
class _Server implements HttpClientAdapter {
  final posted = <Map<String, Object?>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    Object reply = {'data': <Object>[]};
    if (o.method == 'POST' && o.path == '/api/bank-details') {
      final data = Map<String, Object?>.from((o.data as Map)['data'] as Map);
      posted.add(data);
      reply = {
        'data': {'id': 3, 'documentId': 'b3', ...data},
      };
    }
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDocs extends BankDocSource {
  String? nextPath = '/tmp/doc.jpg';
  bool failUpload = false;
  int nextId = 11;
  final picked = <BankDocOrigin>[];

  @override
  Future<String?> pick(BankDocOrigin origin) async {
    picked.add(origin);
    return nextPath;
  }

  @override
  Future<JsonMap> upload(String path) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (failUpload) throw Exception('offline');
    return {'id': nextId++};
  }
}

void main() {
  late _Server server;
  late _FakeDocs docs;

  setUpAll(() async {
    await setUpHostHarness();
  });

  setUp(() async {
    await resetHost();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    docs = _FakeDocs();
    BankDocSource.instance = docs;
  });

  Future<void> open(WidgetTester tester) async {
    phone(tester);
    await pumpRoutes(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: BankFormView(),
        ),
      ),
    );
  }

  Future<void> fillAccount(WidgetTester tester) async {
    final fields = find.byType(TextField);
    for (final (i, text) in [
      'Asha Verma',
      'State Bank of India',
      '123456789012',
      '123456789012',
      'SBIN0001234',
    ].indexed) {
      await tester.enterText(fields.at(i), text);
    }
    await tester.pump();
  }

  /// Taps the [kind] tile and picks from the gallery.
  Future<void> addPhoto(WidgetTester tester, BankDocKind kind) async {
    await tapVisible(tester, find.byKey(ValueKey('bank-doc-${kind.key}')));
    await pumpFor(tester, 300);
    await tester.tap(find.text('Choose from gallery'));
    await pumpFor(tester, 400);
  }

  Future<void> submit(WidgetTester tester) async {
    await tapVisible(tester, find.byType(CButton));
    await pumpFor(tester, 400);
  }

  testWidgets('the three photos are asked for and required', (tester) async {
    await open(tester);
    expect(find.text('Bank passbook or cancelled cheque'), findsOneWidget);
    expect(find.text('PAN card – front'), findsOneWidget);
    expect(find.text('PAN card – back'), findsOneWidget);

    await fillAccount(tester);
    await submit(tester);
    expect(
      find.text('Add a photo of your passbook or a cancelled cheque.'),
      findsOneWidget,
    );
    expect(
      find.text('Add a photo of the front of your PAN card.'),
      findsOneWidget,
    );
    expect(
      find.text('Add a photo of the back of your PAN card.'),
      findsOneWidget,
    );
    expect(server.posted, isEmpty);
    await finishHost(tester);
  });

  testWidgets('picked photos upload at once and are sent with the account', (
    tester,
  ) async {
    await open(tester);
    await fillAccount(tester);
    for (final kind in BankDocKind.values) {
      await addPhoto(tester, kind);
    }
    expect(docs.picked, hasLength(3));
    expect(find.text('Tap to change'), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await submit(tester);
    expect(server.posted, hasLength(1));
    final data = server.posted.single;
    expect(data['Bank_Proof'], 11);
    expect(data['PAN_Front'], 12);
    expect(data['PAN_Back'], 13);
    expect((data['BankAccount'] as Map)['Account_IFSC'], 'SBIN0001234');
    expect(find.text('Bank details submitted'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets('a failed upload blocks the submit and retries on tap', (
    tester,
  ) async {
    await open(tester);
    await fillAccount(tester);
    docs.failUpload = true;
    await addPhoto(tester, BankDocKind.panFront);
    expect(find.text('Upload failed. Tap to retry'), findsOneWidget);
    // The error alert.
    await tester.tap(find.text('OK'));
    await pumpFor(tester, 300);

    await submit(tester);
    expect(
      find.text("This photo didn't upload. Tap it to try again."),
      findsOneWidget,
    );
    expect(server.posted, isEmpty);

    // Tapping the failed tile re-uploads the same picture: no chooser.
    docs.failUpload = false;
    await tapVisible(tester, find.byKey(const ValueKey('bank-doc-pan_front')));
    await pumpFor(tester, 400);
    expect(find.text('Choose from gallery'), findsNothing);
    expect(docs.picked, hasLength(1));
    expect(find.text('Upload failed. Tap to retry'), findsNothing);
    expect(find.text('Tap to change'), findsOneWidget);
    expect(
      find.text("This photo didn't upload. Tap it to try again."),
      findsNothing,
    );
    await finishHost(tester);
  });

  testWidgets('a cancelled pick changes nothing', (tester) async {
    await open(tester);
    docs.nextPath = null;
    await addPhoto(tester, BankDocKind.bankProof);
    expect(find.text('ADD PHOTO'), findsNWidgets(3));
    expect(find.text('Uploading…'), findsNothing);
    await finishHost(tester);
  });
}
