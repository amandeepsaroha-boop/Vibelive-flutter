import 'package:permission_handler/permission_handler.dart';

import '../../../../core/utils/log.dart';

/// RN `CALL_PERMISSION_STATE`. Severity: blocked > denied > granted >
/// unknown; with several permissions the worst one is reported.
enum CallPermissionState { unknown, granted, denied, blocked }

/// One read: the state, and whether a "denied" may just be "never asked"
/// (iOS reports both as denied), which gets the first-read grace.
typedef CallPermissionRead = ({CallPermissionState state, bool undetermined});

const _unknown = (state: CallPermissionState.unknown, undetermined: false);

/// Mic, plus camera when [needsCamera] (RN `checkCallPermissions`). Never
/// prompts, never throws: a failed read is [CallPermissionState.unknown]
/// and fails open (no bar).
Future<CallPermissionRead> checkCallPermissions({
  required bool needsCamera,
}) async => _merge([
  await _read(Permission.microphone),
  if (needsCamera) await _read(Permission.camera),
]);

/// Prompts for whatever is still promptable, one at a time (iOS shows them
/// one by one), then reports (RN `requestCallPermissions`).
Future<CallPermissionRead> requestCallPermissions({
  required bool needsCamera,
}) async {
  Future<CallPermissionRead> ask(Permission p) async {
    final now = await _read(p);
    if (now.state == CallPermissionState.granted ||
        now.state == CallPermissionState.blocked) {
      return now;
    }
    return _read(p, request: true);
  }

  return _merge([
    await ask(Permission.microphone),
    if (needsCamera) await ask(Permission.camera),
  ]);
}

/// RN `openAppSettings` (never throws).
Future<void> openCallSettings() async {
  try {
    await openAppSettings();
  } catch (e) {
    Log.w('CallPermission', 'openSettings failed: $e');
  }
}

Future<CallPermissionRead> _read(Permission p, {bool request = false}) async {
  try {
    final status = request ? await p.request() : await p.status;
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited ||
      PermissionStatus.provisional => (
        state: CallPermissionState.granted,
        undetermined: false,
      ),
      PermissionStatus.denied => (
        state: CallPermissionState.denied,
        undetermined: true,
      ),
      PermissionStatus.permanentlyDenied || PermissionStatus.restricted => (
        state: CallPermissionState.blocked,
        undetermined: false,
      ),
    };
  } catch (_) {
    return _unknown;
  }
}

CallPermissionRead _merge(List<CallPermissionRead> reads) {
  var worst = _unknown;
  for (final r in reads) {
    if (r.state.index > worst.state.index) {
      worst = r;
    } else if (r.state == worst.state && r.undetermined) {
      worst = (state: worst.state, undetermined: true);
    }
  }
  return worst;
}
