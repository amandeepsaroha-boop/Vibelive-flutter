import 'local_notifier.dart';
import 'notification_channels.dart';
import 'push_envelope.dart';
import 'push_strings.dart';

/// RN `verificationNotifications.js`: host verification / approval pushes.
abstract final class VerificationNotifications {
  /// RN `VERIFICATION_TYPES` (compared lower-case here: RN also listed the
  /// upper-case backend spellings).
  static const types = {
    'verification',
    'expert_verification',
    'verification_badge',
    'verification_status',
    'approval',
    'expert_approval',
    'expert_profile_approved',
    'profile_approved',
    'expert_approved',
    'expert_profile_verified',
  };

  static const keywords = [
    'verification',
    'verified',
    'approval',
    'approved',
    'badge',
    'expert verification',
    'profile verification',
    'document verified',
    'host profile',
    'profile approved',
    'is now live',
  ];

  /// An explicit verification type (beats any keyword scan on tap).
  static bool isExplicit(PushEnvelope m) =>
      types.contains(m.type) || types.contains(m.signal);

  static bool matchesKeywords(PushEnvelope m) => keywords.any(
    (k) =>
        m.titleLower.contains(k) ||
        m.bodyLower.contains(k) ||
        m.type.contains(k),
  );

  /// RN `matchesVerificationTrigger`.
  static bool matches(PushEnvelope m) => isExplicit(m) || matchesKeywords(m);

  static Future<void> present(PushEnvelope m) async {
    final id = 'verification_${DateTime.now().millisecondsSinceEpoch}';
    await LocalNotifier.show(
      id: id,
      title: m.title ?? PushStrings.t('verification.title'),
      body: m.body ?? PushStrings.t('verification.body'),
      envelope: m.copyWith(
        data: {...m.data, '__isVerification': 'true'},
        notificationId: id,
      ),
      channelId: NotificationChannels.verification,
    );
  }
}
