import 'package:permission_handler/permission_handler.dart';

import '../../component/c_alert.dart';
import 'call_alerts.dart';

/// Mic (+ camera) access, collapsed: blocked > denied > granted > unknown.
enum CallAccess {
  granted,
  denied,
  blocked,

  /// The state could not be read: never blocks a call (RN, CE).
  unknown;

  bool get isMissing => this == denied || this == blocked;
}

/// The permission plugin behind [CallPermissions] (a seam for tests).
abstract class CallPermissionBackend {
  Future<CallAccess> check({required bool video});
  Future<CallAccess> request({required bool video});
  Future<void> openSettings();
}

/// Call permission gate (RN `ensureCallPermissionsForCall`): placing a
/// call, an in-app accept, and the first resume after a system-UI accept.
abstract final class CallPermissions {
  static CallPermissionBackend backend = PermissionHandlerBackend();

  /// [ensureForOutgoing] for any call (the receiver's Accept too, A2).
  static Future<bool> ensureForCall({required bool video}) =>
      ensureForOutgoing(video: video);

  /// After a system-UI accept, with the app in front: true only when
  /// access WAS missing and is granted now (the engine must restart its
  /// capture). Missing → asks; still missing → the RN alert. Never throws.
  static Future<bool> grantedAfterAsking({required bool video}) async {
    try {
      final access = await backend.check(video: video);
      if (!access.isMissing) return false;
      return await ensureForOutgoing(video: video);
    } catch (_) {
      return false;
    }
  }

  /// Granted / unknown → true. Denied → asks; still missing → the RN alert
  /// (blocked: Cancel + Open Settings; denied: OK) and false. Never throws.
  static Future<bool> ensureForOutgoing({required bool video}) async {
    try {
      var access = await backend.check(video: video);
      if (!access.isMissing) return true;
      if (access == CallAccess.denied) {
        access = await backend.request(video: video);
        if (!access.isMissing) return true;
      }
      if (access == CallAccess.blocked) {
        final open = await CallAlerts.show(
          title: CallFlowKeys.permissionTitle(video: video),
          message: CallFlowKeys.permissionBlocked(video: video),
          variant: CAlertVariant.warning,
          primaryLabel: CallFlowKeys.permissionOpenSettings,
          secondaryLabel: 'actions.cancel',
        );
        if (open == true) await backend.openSettings();
      } else {
        await CallAlerts.show(
          title: CallFlowKeys.permissionTitle(video: video),
          message: CallFlowKeys.permissionDenied(video: video),
          variant: CAlertVariant.warning,
        );
      }
      return false;
    } catch (_) {
      return true;
    }
  }
}

/// `permission_handler` (CE `CallPermissions`). A read that fails is
/// [CallAccess.unknown]: a broken check must never cost a call.
class PermissionHandlerBackend implements CallPermissionBackend {
  static List<Permission> _needed(bool video) => [
    Permission.microphone,
    if (video) Permission.camera,
  ];

  @override
  Future<CallAccess> check({required bool video}) async {
    try {
      return _reduce([for (final p in _needed(video)) await p.status]);
    } catch (_) {
      return CallAccess.unknown;
    }
  }

  @override
  Future<CallAccess> request({required bool video}) async {
    try {
      final result = await _needed(video).request();
      return _reduce(result.values.toList());
    } catch (_) {
      return CallAccess.unknown;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  static CallAccess _reduce(List<PermissionStatus> statuses) {
    if (statuses.isEmpty) return CallAccess.unknown;
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return CallAccess.blocked;
    }
    if (statuses.any((s) => s.isDenied)) return CallAccess.denied;
    if (statuses.every((s) => s.isGranted || s.isLimited || s.isProvisional)) {
      return CallAccess.granted;
    }
    return CallAccess.unknown;
  }
}
