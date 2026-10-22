part of 'call_engine.dart';

/// Camera capture and publish (RN `startLocalVideoCapture`,
/// `applyCameraPublish`, `ensureVideoIfNeeded`, `recoverVideoAfterUnlock`).
/// Capturing ([CallEngine._hasVideo]) and publishing
/// ([CallEngine._publishingCamera]) are different things: guarding the
/// publish on "capturing" left the remote without video after a headless
/// join (mem #14 sub-bug, E-39).
extension _EngineVideo on CallEngine {
  /// Idempotent. Never `enableVideo` inside a channel: it resets the
  /// subscriptions and reports the peer's video as stopped (CE).
  Future<void> _startCapture(RtcEngine eng) async {
    if (_hasVideo) return;
    try {
      if (_joined == null) await eng.enableVideo();
      await eng.enableLocalVideo(true);
      await eng.muteLocalVideoStream(false);
      await eng.startPreview();
      await eng.setLocalVideoMirrorMode(
        VideoMirrorModeType.videoMirrorModeEnabled,
      );
      _hasVideo = true;
    } catch (e) {
      // Expected on a locked device: audio carries the call until unlock.
      _localVideoFailed = true;
      Log.w('CallEngine', 'camera unavailable: $e');
    }
  }

  /// Publishes the camera in the current join. The return code is checked
  /// (the binding throws on non-zero): a failure leaves the flag off so a
  /// later attempt retries (E-40). Remotes that joined before video was on
  /// are unmuted explicitly (E-41).
  Future<bool> _applyCameraPublish() async {
    final eng = _engine;
    if (eng == null) return false;
    await _startCapture(eng);
    try {
      await eng.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          autoSubscribeVideo: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      Log.w('CallEngine', 'camera publish failed: $e');
      return false;
    }
    _publishingCamera = true;
    _pendingCameraPublish = false;
    for (final uid in _remoteUids.toList()) {
      await CallEngine._quiet(
        () => eng.muteRemoteVideoStream(uid: uid, mute: false),
      );
    }
    return true;
  }
}

/// Public video entry points (the call logic calls these when the app can
/// use the camera: in-app accept, app resumed, unlock).
extension CallEngineVideo on CallEngine {
  /// The call is video and the app is in front: capture + publish. Before
  /// the join returns this is parked and replayed on join success (-8,
  /// E-40). No-op when already publishing a working camera, or for an audio
  /// call. A camera that failed (locked device, E-48) is captured again
  /// even while the track is published (I5).
  Future<void> ensureVideoIfNeeded() async {
    final eng = _engine;
    final args = _args;
    if (eng == null || args == null || !args.video) return;
    if (_publishingCamera && !_localVideoFailed) return;
    if (!CallDevice.isForeground) return;
    _args = args.copyWith(headless: false);
    if (_localVideoFailed) {
      _hasVideo = false;
      _localVideoFailed = false;
    }
    await _startCapture(eng);
    if (_joining || _joined == null) {
      _pendingCameraPublish = true;
      return;
    }
    if (!_publishingCamera) await _applyCameraPublish();
  }

  /// iOS unlock: a video call answered on the lock screen got no camera
  /// (E-48). Re-capture and publish. Only in front: the camera is refused
  /// in the background, so an unlock with the app behind waits for the
  /// resume ([ensureVideoIfNeeded], I5).
  Future<void> repairVideo() async {
    final eng = _engine;
    final args = _args;
    if (eng == null || args == null || !args.video) return;
    if (!CallDevice.isForeground) return;
    if (_joined == null || _joining) return;
    if (!_localVideoFailed && _publishingCamera) return;
    _hasVideo = false;
    _localVideoFailed = false;
    _args = args.copyWith(headless: false);
    await _startCapture(eng);
    if (!_publishingCamera) await _applyCameraPublish();
  }

  /// Mic (and camera) access was granted after the join (A2: a system-UI
  /// accept never passed the in-app gate): restart the local capture.
  Future<void> restartLocalMedia() async {
    final eng = _engine;
    if (eng == null) return;
    final muted = _media.value.muted;
    await CallEngine._quiet(() => eng.enableLocalAudio(false));
    await CallEngine._quiet(() => eng.enableLocalAudio(!muted));
    await CallEngine._quiet(() => eng.muteLocalAudioStream(muted));
    if (_args?.video ?? false) {
      _localVideoFailed = true;
      await ensureVideoIfNeeded();
    }
  }
}
