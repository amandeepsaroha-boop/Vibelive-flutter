/// Every bundled asset path. Never hard-code `assets/...` strings elsewhere.
abstract final class AppImages {
  static const inAppLogo = 'assets/images/brand/inapp_logo.png';
  static const appIcon = 'assets/images/brand/app_icon.png';
  static const notificationIcon = 'assets/images/brand/notification_icon.png';
  static const googleLogo = 'assets/images/google_logo.png';
  static const facebookLogo = 'assets/images/facebook_logo.png';
  static const callEnd = 'assets/images/call_icons/phone_call_end.png';
  static const callMute = 'assets/images/call_icons/mute.png';

  /// Become-a-Host intro hero (Unsplash, photo HVbaH3p9B8k by IMANA,
  /// Unsplash License: free for commercial use, no attribution required).
  static const hostIntro = 'assets/images/onboarding/host_intro.jpg';
}

abstract final class AppSounds {
  /// Outgoing call: played to the caller while the other side rings.
  static const callerRing = 'assets/sounds/caller_ring_main.mp3';

  /// Incoming call ringtone.
  static const receiverRing = 'assets/sounds/receiver_side_ringing.mp3';

  /// Wallet credit / coin added.
  static const coinAdded = 'assets/sounds/coin_sound_add.wav';
}
