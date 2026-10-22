import 'package:flutter/widgets.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_alert.dart';

/// Unblock with RN's confirm and result alerts.
abstract final class BlockedActions {
  /// Returns true once [unblock] succeeded.
  static Future<bool> confirmUnblock(
    BuildContext context,
    BlockedUser user,
    Future<void> Function(String targetUserId) unblock,
  ) async {
    final target = user.targetUserId;
    if (target == null) return false;
    final name = user.name ?? context.t('resources:blocked.user');
    final ok = await CAlert.confirm(
      title: 'resources:blocked.confirm_title',
      message: 'resources:blocked.confirm_message',
      variables: {'name': name},
      confirmLabel: 'resources:blocked.unblock',
      variant: CAlertVariant.warning,
    );
    if (!ok) return false;
    try {
      await unblock(target);
    } on ApiException catch (e) {
      await CAlert.error(e);
      return false;
    }
    await CAlert.show(
      title: 'resources:blocked.done_title',
      message: 'resources:blocked.done_message',
      variant: CAlertVariant.success,
    );
    return true;
  }
}
