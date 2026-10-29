import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'step_body.dart';

/// The Voice step's recorder (RN ProfessionalDetails "Voice Intro"): one big
/// round button records (a ring fills toward [HostVoiceIntro.maxSeconds],
/// where it stops on its own), stops, then plays it back. Re-record and
/// Delete sit below. The draft keeps the file; the save uploads it as the
/// profile's `audio_intro`.
///
/// Leaving the step mid-recording discards it; the player and the recorder
/// live only while this is on screen.
class HostVoiceIntroField extends StatefulWidget {
  const HostVoiceIntroField({super.key, required this.draft});
  final HostDraftController draft;

  @override
  State<HostVoiceIntroField> createState() => _HostVoiceIntroFieldState();
}

class _HostVoiceIntroFieldState extends State<HostVoiceIntroField>
    with SingleTickerProviderStateMixin {
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

  /// The halo breathing around the button while it records or plays.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  ValueNotifier<HostVoiceIntro?> get _intro => widget.draft.voiceIntro;

  void _breathe(bool on) {
    if (on && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_pulse.repeat(reverse: true));
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

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
      _breathe(true);
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final now = _clock.elapsed;
        _elapsed.value = now > _max ? _max : now;
        if (now >= _max) unawaited(_stop());
      });
    } catch (e) {
      Log.w('VoiceIntro', 'record failed: $e');
      _recording.value = false;
      _breathe(false);
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
    _breathe(false);
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
    unawaited(_uploadEarly(widget.draft, path));
  }

  /// Uploads [path] in the background, like a picked photo, so the save has
  /// nothing left to send. Only kept while it is still the draft's recording;
  /// on failure the save uploads the file itself.
  static Future<void> _uploadEarly(
    HostDraftController draft,
    String path,
  ) async {
    try {
      final id = (await HostVoiceRecorder.upload(path))['id'];
      final now = draft.voiceIntro.value;
      if (id == null || draft.isDisposed || now?.path != path) return;
      draft.voiceIntro.value = now!.withUploaded(id);
    } catch (e) {
      Log.w('VoiceIntro', 'background upload failed: $e');
    }
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
      _breathe(true);
      unawaited(player.play());
    } catch (e) {
      Log.w('VoiceIntro', 'playback failed: $e');
      await _stopPlayback();
      CToast.show('hostflow:voice.play_failed', variant: CToastVariant.error);
    }
  }

  Future<void> _stopPlayback() async {
    if (_playing.value) _breathe(false);
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

  /// The big button: record, stop, or listen.
  void _main() {
    if (_recording.value) {
      unawaited(_stop());
    } else if (_intro.value == null) {
      unawaited(_start());
    } else {
      unawaited(_togglePlayback());
    }
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
    _pulse.dispose();
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
    return HostCard(
      padding: EdgeInsets.fromLTRB(20.ms, 24.ms, 20.ms, 20.ms),
      child: ListenableBuilder(
        listenable: Listenable.merge([_recording, _playing, _intro]),
        builder: (context, _) {
          final recording = _recording.value;
          final playing = _playing.value;
          final intro = _intro.value;
          final (label, icon) = recording
              ? ('hostflow:voice.stop_label', LucideIcons.square)
              : intro == null
              ? ('hostflow:voice.record_label', LucideIcons.mic)
              : playing
              ? ('hostflow:voice.stop', LucideIcons.square)
              : ('hostflow:voice.play', LucideIcons.play);
          return Column(
            children: [
              _RecordDisc(
                semanticLabel: context.t(label),
                icon: icon,
                solid: recording || intro != null,
                pulse: _pulse,
                progress: recording ? _elapsed : null,
                onPressed: _main,
              ),
              SizedBox(height: 16.ms),
              if (recording)
                ValueListenableBuilder<Duration>(
                  valueListenable: _elapsed,
                  builder: (_, d, _) => CText(
                    'hostflow:voice.timer',
                    variables: {'time': _time(d), 'max': _time(_max)},
                    size: 24,
                    weight: FontWeight.w900,
                    color: p.text,
                  ),
                )
              else
                CText(
                  intro == null
                      ? 'hostflow:voice.tap_record'
                      : (playing
                            ? 'hostflow:voice.playing'
                            : 'hostflow:voice.tap_listen'),
                  size: 18,
                  weight: FontWeight.w800,
                  color: p.text,
                ),
              SizedBox(height: 4.ms),
              CText(
                recording
                    ? 'hostflow:voice.tap_stop'
                    : intro == null
                    ? 'hostflow:voice.limit'
                    : (intro.isNew
                          ? 'hostflow:voice.recorded'
                          : 'hostflow:voice.saved'),
                variables: {
                  'time': _time(Duration(seconds: intro?.seconds ?? 0)),
                },
                size: 12.5,
                weight: FontWeight.w600,
                color: p.muted,
                align: TextAlign.center,
              ),
              if (intro != null && !recording) ...[
                SizedBox(height: 16.ms),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10.ms,
                  runSpacing: 8.ms,
                  children: [
                    _Pill(
                      icon: LucideIcons.rotateCcw,
                      label: 'hostflow:voice.rerecord',
                      color: p.accent,
                      background: p.tint,
                      border: p.tintBorder,
                      onPressed: _start,
                    ),
                    // Only a new recording can be dropped: the saved intro
                    // stays until a new one replaces it.
                    if (intro.isNew)
                      _Pill(
                        icon: LucideIcons.trash2,
                        label: 'hostflow:voice.delete',
                        color: p.danger,
                        background: p.dangerTint,
                        border: p.danger.withValues(alpha: 0.25),
                        onPressed: _discard,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The round button: a soft halo breathes around it while it records or
/// plays, and while recording a ring fills toward the 30 s limit.
class _RecordDisc extends StatelessWidget {
  const _RecordDisc({
    required this.semanticLabel,
    required this.icon,
    required this.solid,
    required this.pulse,
    required this.progress,
    required this.onPressed,
  });

  final String semanticLabel;
  final IconData icon;

  /// Accent-filled (recording / has a recording); tinted otherwise.
  final bool solid;
  final Animation<double> pulse;
  final ValueListenable<Duration>? progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final size = 124.ms;
    final disc = 88.ms;
    // Its own node: a screen reader announces the button, not it merged
    // with the line under it.
    return Semantics(
      container: true,
      child: Pressable(
        activeOpacity: 0.85,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (_, _) => Container(
                    width: disc + (size - disc) * (0.55 + 0.45 * pulse.value),
                    height: disc + (size - disc) * (0.55 + 0.45 * pulse.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accent.withValues(
                        alpha: solid ? 0.10 + 0.10 * pulse.value : 0.08,
                      ),
                    ),
                  ),
                ),
              ),
              if (progress case final elapsed?)
                RepaintBoundary(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: elapsed,
                    builder: (_, d, _) => SizedBox.square(
                      dimension: disc + 18.ms,
                      child: CustomPaint(
                        painter: _RingPainter(
                          value: math.min(
                            1,
                            d.inMilliseconds /
                                (HostVoiceIntro.maxSeconds * 1000),
                          ),
                          color: p.accent,
                          track: p.track,
                          width: 4.ms,
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: solid ? p.accent : p.tint,
                  border: solid ? null : Border.all(color: p.tintBorder),
                ),
                child: Icon(
                  icon,
                  size: 34.ms,
                  color: solid ? p.onAccent : p.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.width,
  });

  final double value;
  final Color color;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(
        rect.deflate(width / 2),
        0,
        2 * math.pi,
        false,
        ring..color = track,
      )
      ..drawArc(
        rect.deflate(width / 2),
        -math.pi / 2,
        2 * math.pi * value,
        false,
        ring..color = color,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.border,
    required this.onPressed,
  });

  final IconData icon;

  /// i18n key.
  final String label;
  final Color color;
  final Color background;
  final Color border;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    activeOpacity: 0.85,
    onPressed: onPressed,
    child: Container(
      height: 42.ms,
      padding: EdgeInsets.symmetric(horizontal: 16.ms),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.ms, color: color),
          SizedBox(width: 8.ms),
          // A long label (Hindi, a narrow phone) shrinks, never overflows.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CText(
                label,
                size: 13.5,
                weight: FontWeight.w800,
                color: color,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
