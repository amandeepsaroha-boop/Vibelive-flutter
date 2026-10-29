import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/voice_recorder.dart';

/// "Voice intro (optional)" on the Bio step (RN ProfessionalDetails): record
/// up to [HostVoiceIntro.maxSeconds] (it stops on its own), listen back,
/// record again, or drop a new recording. The draft keeps the file; the save
/// uploads it as the profile's `audio_intro`.
///
/// Leaving the step mid-recording discards it; the player and the recorder
/// live only while this field is on screen.
class HostVoiceIntroField extends StatefulWidget {
  const HostVoiceIntroField({super.key, required this.draft});
  final HostDraftController draft;

  @override
  State<HostVoiceIntroField> createState() => _HostVoiceIntroFieldState();
}

class _HostVoiceIntroFieldState extends State<HostVoiceIntroField> {
  /// Shorter than this is a slip of the finger, not an intro.
  static const _minimum = Duration(seconds: 1);
  static const _max = Duration(seconds: HostVoiceIntro.maxSeconds);

  late final HostVoiceRecorder _recorder = HostVoiceRecorder.create();
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerState;

  final _recording = ValueNotifier(false);
  final _playing = ValueNotifier(false);
  final _elapsed = ValueNotifier(Duration.zero);
  /// `package:clock`: real time in the app, test time in tests.
  final _clock = clock.stopwatch();
  Timer? _ticker;
  bool _busy = false;

  ValueNotifier<HostVoiceIntro?> get _intro => widget.draft.voiceIntro;

  Future<void> _start() async {
    if (_busy || _recording.value) return;
    _busy = true;
    try {
      await _stopPlayback();
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          await CAlert.show(
            title: 'hostflow:voice.title',
            message: 'hostflow:voice.permission',
            variant: CAlertVariant.warning,
          );
        }
        return;
      }
      await _recorder.start();
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      _clock
        ..reset()
        ..start();
      _elapsed.value = Duration.zero;
      _recording.value = true;
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final now = _clock.elapsed;
        _elapsed.value = now > _max ? _max : now;
        if (now >= _max) unawaited(_stop());
      });
    } catch (e) {
      Log.w('VoiceIntro', 'record failed: $e');
      _recording.value = false;
      CToast.show('hostflow:voice.failed', variant: CToastVariant.error);
    } finally {
      _busy = false;
    }
  }

  Future<void> _stop() async {
    if (!_recording.value) return;
    _ticker?.cancel();
    _clock.stop();
    _recording.value = false;
    final took = _clock.elapsed;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      Log.w('VoiceIntro', 'stop failed: $e');
    }
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    if (path == null) {
      CToast.show('hostflow:voice.failed', variant: CToastVariant.error);
      return;
    }
    if (took < _minimum) {
      _deleteQuietly(path);
      CToast.show('hostflow:voice.too_short');
      return;
    }
    final previous = _intro.value;
    if (previous?.path case final old? when old != path) _deleteQuietly(old);
    final seconds = took.inMilliseconds / 1000;
    _intro.value = (previous ?? const HostVoiceIntro()).withRecording(
      path,
      seconds.ceil().clamp(1, HostVoiceIntro.maxSeconds),
    );
  }

  Future<void> _togglePlayback() async {
    if (_playing.value) return _stopPlayback();
    final intro = _intro.value;
    if (intro == null || _recording.value) return;
    try {
      final player = _player ??= AudioPlayer();
      _playerState ??= player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          unawaited(_stopPlayback());
        }
      });
      if (intro.path case final path?) {
        await player.setFilePath(path);
      } else if (intro.savedUrl case final url?) {
        await player.setUrl(url);
      } else {
        return;
      }
      _playing.value = true;
      unawaited(player.play());
    } catch (e) {
      Log.w('VoiceIntro', 'playback failed: $e');
      await _stopPlayback();
      CToast.show('hostflow:voice.play_failed', variant: CToastVariant.error);
    }
  }

  Future<void> _stopPlayback() async {
    _playing.value = false;
    await _player?.stop();
  }

  /// Drops the new recording: back to the saved intro, or none.
  Future<void> _discard() async {
    await _stopPlayback();
    final intro = _intro.value;
    if (intro?.path case final path?) _deleteQuietly(path);
    _intro.value = intro?.withoutRecording();
  }

  static void _deleteQuietly(String path) {
    unawaited(File(path).delete().then((_) {}, onError: (Object _) {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording.value) unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    unawaited(_playerState?.cancel());
    unawaited(_player?.dispose());
    _recording.dispose();
    _playing.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  static String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _recording,
      builder: (_, recording, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(16.ms),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(
            width: recording ? 1.5 : 1,
            color: recording ? p.accent : p.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.mic, size: 16.ms, color: p.accent),
                SizedBox(width: 8.ms),
                Expanded(
                  child: CText(
                    'hostflow:voice.title',
                    size: 14,
                    weight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.ms),
            CText(
              'hostflow:voice.hint',
              size: 12,
              height: 17,
              weight: FontWeight.w500,
              color: p.muted,
            ),
            SizedBox(height: 14.ms),
            if (recording) ...[
              ValueListenableBuilder<Duration>(
                valueListenable: _elapsed,
                builder: (_, elapsed, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4.ms),
                  child: LinearProgressIndicator(
                    value: elapsed.inMilliseconds / _max.inMilliseconds,
                    minHeight: 4.ms,
                    color: p.accent,
                    backgroundColor: p.track,
                  ),
                ),
              ),
              SizedBox(height: 12.ms),
            ],
            ValueListenableBuilder<HostVoiceIntro?>(
              valueListenable: _intro,
              builder: (_, intro, _) => Row(
                children: [
                  Expanded(
                    child: _RecordButton(
                      recording: recording,
                      hasIntro: intro != null,
                      elapsed: _elapsed,
                      onPressed: recording ? _stop : _start,
                    ),
                  ),
                  if (intro != null && !recording) ...[
                    SizedBox(width: 10.ms),
                    ValueListenableBuilder<bool>(
                      valueListenable: _playing,
                      builder: (_, playing, _) => _SquareButton(
                        icon: playing ? LucideIcons.square : LucideIcons.play,
                        label: playing
                            ? 'hostflow:voice.stop'
                            : 'hostflow:voice.play',
                        color: p.text,
                        background: p.soft,
                        border: p.cardBorder,
                        onPressed: _togglePlayback,
                      ),
                    ),
                    // Only a new recording can be dropped: the saved intro
                    // stays until a new one replaces it.
                    if (intro.isNew) ...[
                      SizedBox(width: 10.ms),
                      _SquareButton(
                        icon: LucideIcons.trash2,
                        label: 'hostflow:voice.delete',
                        color: p.danger,
                        background: p.dangerTint,
                        border: p.danger.withValues(alpha: 0.25),
                        onPressed: _discard,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            ValueListenableBuilder<HostVoiceIntro?>(
              valueListenable: _intro,
              builder: (_, intro, _) => intro == null || recording
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.only(top: 10.ms),
                      child: CText(
                        intro.isNew
                            ? 'hostflow:voice.recorded'
                            : 'hostflow:voice.saved',
                        variables: {
                          'time': _time(Duration(seconds: intro.seconds)),
                        },
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Record / re-record, or stop with the running time while recording.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.hasIntro,
    required this.elapsed,
    required this.onPressed,
  });

  final bool recording;
  final bool hasIntro;
  final ValueListenable<Duration> elapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final fg = recording ? p.onAccent : p.accent;
    return Pressable(
      activeOpacity: 0.85,
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52.ms,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        decoration: BoxDecoration(
          color: recording ? p.accent : p.tint,
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(
            width: 1.5,
            color: recording ? Colors.transparent : p.tintBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recording ? LucideIcons.square : LucideIcons.mic,
              size: 18.ms,
              color: fg,
            ),
            SizedBox(width: 8.ms),
            Flexible(
              child: recording
                  ? ValueListenableBuilder<Duration>(
                      valueListenable: elapsed,
                      builder: (_, d, _) => CText(
                        'hostflow:voice.recording',
                        variables: {
                          'time': _HostVoiceIntroFieldState._time(d),
                          'max': _HostVoiceIntroFieldState._time(
                            _HostVoiceIntroFieldState._max,
                          ),
                        },
                        size: 13,
                        weight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: fg,
                        maxLines: 1,
                      ),
                    )
                  : CText(
                      hasIntro
                          ? 'hostflow:voice.rerecord'
                          : 'hostflow:voice.record',
                      size: 13,
                      weight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: fg,
                      maxLines: 1,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.border,
    required this.onPressed,
  });

  final IconData icon;

  /// i18n key, for screen readers.
  final String label;
  final Color color;
  final Color background;
  final Color border;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    activeOpacity: 0.85,
    semanticLabel: context.t(label),
    onPressed: onPressed,
    child: Container(
      width: 52.ms,
      height: 52.ms,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: 20.ms, color: color),
    ),
  );
}
