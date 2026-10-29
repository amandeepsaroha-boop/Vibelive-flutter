import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// "HEAR THEIR VOICE" play / stop row (RN voice intro). The player lives
/// only while this row is mounted: closing the profile silences it, so it can
/// never leak into a call. Only the time label and the bars repaint.
class VoiceIntro extends StatefulWidget {
  const VoiceIntro({super.key, required this.url, this.hostId});
  final String url;

  /// The host's key, for analytics.
  final String? hostId;

  @override
  State<VoiceIntro> createState() => _VoiceIntroState();
}

class _VoiceIntroState extends State<VoiceIntro>
    with SingleTickerProviderStateMixin {
  static const _wave = [
    0.35,
    0.6,
    0.9,
    0.5,
    0.75,
    1.0,
    0.45,
    0.7,
    0.95,
    0.4,
    0.65,
    0.85,
    0.5,
    0.8,
    0.6,
    0.35,
    0.7,
    0.5,
    0.9,
    0.45,
    0.6,
    0.3,
  ];

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _state;
  final _playing = ValueNotifier(false);
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  Future<void> _toggle() async {
    if (_playing.value) {
      DiscoverEvents.voiceIntroStopped(
        hostId: widget.hostId,
        seconds: _player?.position.inSeconds ?? 0,
      );
      return _stop();
    }
    try {
      final player = _player ??= AudioPlayer();
      _state ??= player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          if (_playing.value) {
            DiscoverEvents.voiceIntroCompleted(
              hostId: widget.hostId,
              seconds: player.duration?.inSeconds,
            );
          }
          _stop();
        }
      });
      if (player.audioSource == null) await player.setUrl(widget.url);
      await player.seek(Duration.zero);
      _playing.value = true;
      DiscoverEvents.voiceIntroPlayed(hostId: widget.hostId);
      unawaited(_pulse.repeat());
      unawaited(player.play());
    } catch (e) {
      Log.w('VoiceIntro', 'playback failed: $e');
      DiscoverEvents.voiceIntroFailed(
        hostId: widget.hostId,
        error: Analytics.errorCode(e),
      );
      await _stop();
    }
  }

  Future<void> _stop() async {
    _playing.value = false;
    _pulse
      ..stop()
      ..value = 0;
    await _player?.stop();
  }

  @override
  void dispose() {
    _state?.cancel();
    _player?.dispose();
    _pulse.dispose();
    _playing.dispose();
    super.dispose();
  }

  static String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.55) : AppColors.blackA(0.5);
    final idleBar = c.isDark ? AppColors.whiteA(0.22) : AppColors.blackA(0.18);
    return Pressable(
      activeOpacity: 0.85,
      onPressed: _toggle,
      child: Container(
        margin: EdgeInsets.only(top: 12.ms),
        padding: EdgeInsets.only(top: 12.ms),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: c.isDark ? AppColors.whiteA(0.07) : AppColors.blackA(0.07),
            ),
          ),
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: _playing,
          builder: (_, playing, _) => Row(
            children: [
              Container(
                width: 38.ms,
                height: 38.ms,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 20.ms,
                  color: c.onAccent,
                ),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CText(
                            playing ? 'host:voice.playing' : 'host:voice.hear',
                            size: 9,
                            weight: FontWeight.w900,
                            letterSpacing: 1.6,
                            color: muted,
                          ),
                        ),
                        if (playing && _player != null)
                          StreamBuilder<Duration>(
                            stream: _player!.positionStream,
                            builder: (_, s) => CText.raw(
                              _time(s.data ?? Duration.zero),
                              size: 9,
                              weight: FontWeight.w900,
                              color: c.accent,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 6.ms),
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(double.infinity, 20.ms),
                        painter: _WavePainter(
                          _pulse,
                          heights: _wave,
                          color: playing ? c.accent : idleBar,
                          playing: playing,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bars pulse (staggered) while playing; flat and dim at rest.
class _WavePainter extends CustomPainter {
  _WavePainter(
    this.pulse, {
    required this.heights,
    required this.color,
    required this.playing,
  }) : super(repaint: pulse);

  final Animation<double> pulse;
  final List<double> heights;
  final Color color;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = 3.ms;
    final usable = size.width - 26.ms;
    final step = (usable - w) / (heights.length - 1);
    for (var i = 0; i < heights.length; i++) {
      final h = heights[i];
      var scale = h * 0.72;
      if (playing) {
        final t = (pulse.value + i * 0.055) % 1;
        // h → h+0.35 → h*0.55 → h over one cycle.
        scale = t < 1 / 3
            ? h + (0.35 * t * 3)
            : t < 2 / 3
            ? (h + 0.35) - ((h + 0.35) - h * 0.55) * ((t - 1 / 3) * 3)
            : h * 0.55 + (h * 0.45) * ((t - 2 / 3) * 3);
        scale = scale.clamp(0.1, 1.0);
      }
      final barH = size.height * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * step + w / 2, size.height / 2),
            width: w,
            height: barH,
          ),
          Radius.circular(2.ms),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color || old.playing != playing;
}
