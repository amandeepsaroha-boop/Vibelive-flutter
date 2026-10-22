import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/native/callkit_params.dart';

/// Vectors produced by running `VibeCallKit.nativeId(for:)` copied verbatim
/// out of `ios/Runner/VibeCallKit.swift` with the Swift toolchain. Dart and
/// Swift MUST agree byte for byte, or Dart answers / ends a CallKit call
/// native never reported.
const swiftVectors = {
  '8500': 'c1246f3d-be8d-4ce6-9c2b-eb5ba3418fcf',
  '1': 'af63ac4c-8601-4afc-80a7-9996973d4b53',
  '42': '07ee7e07-b4b1-4223-9a1f-71e2fd2f8fba',
  'call_12_34_1729500000000': 'b38c7919-dc29-49ee-a8ad-09d4ad34f2cf',
  'ping_7_9_abc123': '1ade8fdc-4e8d-4d6c-a4f4-e98388983d9b',
  'E621E1F8-C36C-495A-93FC-0C247A3E6E5F':
      'e621e1f8-c36c-495a-93fc-0c247a3e6e5f',
  'हिंदी': '21ea005d-627e-4407-90d8-3843f0942a9c',
};

void main() {
  test('nativeIdFor matches the Swift implementation', () {
    swiftVectors.forEach((callId, uuid) {
      expect(CallKitIds.nativeIdFor(callId), uuid, reason: callId);
    });
  });

  test('ids are v4 / RFC-4122 shaped and stable', () {
    final id = CallKitIds.nativeIdFor('8500');
    expect(
      id,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]')),
    );
    expect(CallKitIds.nativeIdFor('8500'), id);
    expect(CallKitIds.nativeIdFor('8501'), isNot(id));
  });
}
