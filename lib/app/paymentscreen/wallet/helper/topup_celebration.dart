import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/log.dart';

/// Coin sound and a haptic tap when a top-up lands while the person is
/// watching (RN `useTopupCelebration`). The backend sends no push for that
/// case: telling someone about their own just-finished action is noise.
///
/// Never throws: a silent switch or a refused audio session must not turn a
/// successful payment into an error.
abstract final class TopupCelebration {
  /// Seam for tests (no platform channel there).
  static Future<void> Function() play = _play;

  static Future<void> celebrate() async {
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    try {
      await play();
    } catch (e) {
      Log.w('TopupCelebration', 'coin sound: $e');
    }
  }

  static Future<void> _play() async {
    final player = AudioPlayer();
    try {
      // `playback` plays over the silent switch: this answers the person's
      // own action. Mixes with other audio instead of stopping it.
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await player.setReleaseMode(ReleaseMode.release);
      unawaited(
        player.onPlayerComplete.first
            .then((_) => player.dispose())
            .catchError((Object _) {}),
      );
      // AssetSource paths are relative to `assets/`.
      await player.play(AssetSource(AppSounds.coinAdded.substring(7)));
    } catch (_) {
      unawaited(player.dispose().catchError((Object _) {}));
      rethrow;
    }
  }
}
