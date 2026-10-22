import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/utils/log.dart';

enum CallTone {
  /// Receiver, in-app incoming screen (no system ringer is up).
  incoming,

  /// Caller ringback while the other phone rings.
  ringback,
}

/// The player behind [CallRingtone] (a seam: tests never reach a platform
/// channel).
abstract class RingtoneBackend {
  Future<void> start(CallTone tone);

  /// Stops and releases; must not touch the audio session (mem #2).
  Future<void> stop();
}

/// Ringtones (RN `useRingtone`, CE `CallRingtone`). One loop at a time;
/// [silence] never throws and never resets the audio session (it belongs
/// to CallKit / Agora on the call path).
abstract final class CallRingtone {
  static RingtoneBackend backend = AudioplayersRingtone();

  static CallTone? _playing;
  static int _seq = 0;

  static CallTone? get playing => _playing;

  /// Loops [tone], replacing anything else. Plays in silent mode.
  static Future<void> play(CallTone tone) async {
    if (_playing == tone) return;
    final seq = ++_seq;
    _playing = tone;
    try {
      await backend.stop();
      if (seq != _seq) return;
      await backend.start(tone);
      // A stop arrived while the loop was loading: never leak it.
      if (seq != _seq) await backend.stop();
    } catch (e) {
      Log.w('CallRingtone', 'play ${tone.name}: $e');
      if (seq == _seq) _playing = null;
    }
  }

  /// Stops [tone] only if it is the one playing.
  static Future<void> stop(CallTone tone) async {
    if (_playing == tone) await silence();
  }

  /// Everything off. Never throws.
  static Future<void> silence() async {
    _seq++;
    _playing = null;
    try {
      await backend.stop();
    } catch (e) {
      Log.w('CallRingtone', 'stop: $e');
    }
  }

  @visibleForTesting
  static void debugReset() {
    _seq++;
    _playing = null;
  }
}

/// `audioplayers` with CE's proven audio contexts. A fresh player per loop:
/// a reused Android MediaPlayer gets stuck after the first stop (CE).
class AudioplayersRingtone implements RingtoneBackend {
  AudioPlayer? _player;

  @override
  Future<void> start(CallTone tone) async {
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      // iOS has one shared AVAudioSession: the ringback plays inside Agora's
      // session (the caller is already joined) instead of rewriting it.
      if (!(Platform.isIOS && tone == CallTone.ringback)) {
        await player.setAudioContext(_contextFor(tone));
      }
      await player.play(AssetSource(_asset(tone)), volume: 1);
    } catch (e) {
      if (identical(_player, player)) _player = null;
      await _dispose(player);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final player = _player;
    _player = null;
    if (player != null) await _dispose(player);
  }

  static String _asset(CallTone tone) {
    final path = tone == CallTone.incoming
        ? AppSounds.receiverRing
        : AppSounds.callerRing;
    // AssetSource paths are relative to `assets/`.
    return path.startsWith('assets/') ? path.substring(7) : path;
  }

  static Future<void> _dispose(AudioPlayer player) async {
    try {
      await player.release();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  static AudioContext _contextFor(CallTone tone) => switch (tone) {
    // Rides the call's own stream; takes no focus (the app's own Telecom
    // call would refuse it and the tone would never start, CE).
    CallTone.ringback => AudioContext(
      android: const AudioContextAndroid(
        audioMode: AndroidAudioMode.inCommunication,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.voiceCommunication,
        audioFocus: AndroidAudioFocus.none,
        stayAwake: true,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.allowBluetooth,
        },
      ),
    ),
    // A phone ringtone; `playback` ignores the silent switch.
    CallTone.incoming => AudioContext(
      android: const AudioContextAndroid(
        audioMode: AndroidAudioMode.ringtone,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransient,
        stayAwake: true,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    ),
  };
}
