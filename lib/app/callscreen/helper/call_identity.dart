import 'package:flutter/foundation.dart';

import '../../../core/network/device_info.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import 'call_session.dart';

/// Who this device is, for the call requests. Never `user.id` for the Agora
/// uid (that comes from the call, by role: mem #11, E-36).
abstract final class CallIdentity {
  static SessionState get _s => SessionStore.instance.value;

  /// Numeric public-user id (string).
  static String? get userId => _s.userId?.toString();
  static String? get userDocumentId => _s.userDocumentId;
  static String get role => J.str(_s.user?['role']) ?? 'Client';

  /// RN `is_company_account` / `isCompanyAccount` / `is_company`.
  static bool get isCompany {
    final u = _s.user;
    if (u == null) return false;
    return [
      u['is_company_account'],
      u['isCompanyAccount'],
      u['is_company'],
    ].any((v) => v == true || v == 'true');
  }

  /// Who ends [call] from this device: the session user, else this side's
  /// id from the call (a cold-start accept may run before the session is
  /// read). Always set (E-28: 400 "endedById is required").
  static Object endedBy(CallSession call) {
    final id =
        userId ?? (call.isCaller ? call.callerId : call.receiverId) ?? '';
    return int.tryParse(id) ?? id;
  }

  /// The stable install id (`answeredDeviceId`, E-76 / E-91).
  static Future<String?> deviceId() async {
    final override = debugDeviceId;
    if (override != null) return override;
    try {
      return J.str((await DeviceInfo.get())['deviceId']);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String? debugDeviceId;
}
