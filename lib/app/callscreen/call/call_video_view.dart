import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/widgets.dart';

import '../helper/engine/call_engine.dart';

/// Own camera full-bleed (uid 0, cover). Null unless the engine is up: no
/// native view is ever built before that (nor in widget tests). [tag] keeps
/// the full-screen and PiP views apart; [viewKey] / [front] remount it on a
/// flip (RN render keys).
Widget? callLocalVideo({
  required bool engineReady,
  required int viewKey,
  required bool front,
  bool mirrored = true,
  String tag = 'full',
}) {
  final rtc = CallEngine.instance.rtc;
  if (!engineReady || rtc == null) return null;
  return _LocalVideo(
    key: ValueKey('local-$tag-$viewKey-${front ? 'front' : 'back'}'),
    rtc: rtc,
    // Mirrored only on the front camera (RN `localMirrorMode`).
    mirrored: mirrored && front,
  );
}

/// The other side's video (cover, never mirrored). Null unless the engine is
/// up and the remote is in the channel.
Widget? callRemoteVideo({
  required bool engineReady,
  required int? uid,
  required int viewKey,
  required String? channel,
  String tag = 'full',
}) {
  final rtc = CallEngine.instance.rtc;
  final channelId = CallEngine.instance.channelId ?? channel;
  if (!engineReady || rtc == null || uid == null || channelId == null) {
    return null;
  }
  return _RemoteVideo(
    key: ValueKey('remote-$tag-$uid-$viewKey'),
    rtc: rtc,
    uid: uid,
    channelId: channelId,
  );
}

class _LocalVideo extends StatefulWidget {
  const _LocalVideo({super.key, required this.rtc, required this.mirrored});

  final RtcEngine rtc;
  final bool mirrored;

  @override
  State<_LocalVideo> createState() => _LocalVideoState();
}

class _LocalVideoState extends State<_LocalVideo> {
  // One controller per mounted view: a new one each build would make the
  // plugin tear the render down and set it up again.
  late final _controller = VideoViewController(
    rtcEngine: widget.rtc,
    canvas: VideoCanvas(
      uid: 0,
      sourceType: VideoSourceType.videoSourceCamera,
      renderMode: RenderModeType.renderModeHidden,
      mirrorMode: widget.mirrored
          ? VideoMirrorModeType.videoMirrorModeEnabled
          : VideoMirrorModeType.videoMirrorModeDisabled,
    ),
  );

  @override
  Widget build(BuildContext context) => AgoraVideoView(controller: _controller);
}

class _RemoteVideo extends StatefulWidget {
  const _RemoteVideo({
    super.key,
    required this.rtc,
    required this.uid,
    required this.channelId,
  });

  final RtcEngine rtc;
  final int uid;
  final String channelId;

  @override
  State<_RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<_RemoteVideo> {
  late final _controller = VideoViewController.remote(
    rtcEngine: widget.rtc,
    canvas: VideoCanvas(
      uid: widget.uid,
      renderMode: RenderModeType.renderModeHidden,
    ),
    connection: RtcConnection(channelId: widget.channelId),
  );

  @override
  Widget build(BuildContext context) => AgoraVideoView(controller: _controller);
}
