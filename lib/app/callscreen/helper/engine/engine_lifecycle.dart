part of 'call_engine.dart';

/// Engine creation, audio setup, handler binding and release (RN
/// `ensureSharedEngine` / `teardownEngine`, §4.2–4.3, 4.8).
extension _EngineLifecycle on CallEngine {
  Future<RtcEngine?> _ensureEngine({String? token, bool audio = true}) async {
    _cancelRelease();
    final appId = await _appId(token);
    if (appId == null) {
      Log.w('CallEngine', 'no Agora app id');
      return null;
    }
    var eng = _engine;
    // Another Agora app in the token: rebuild (RN `teardownEngine`).
    if (eng != null && _initializedAppId != appId) {
      await _teardown();
      eng = null;
    }
    eng ??= await (_creating ??= _create(
      appId,
    ).whenComplete(() => _creating = null));
    if (eng != null && audio && !_audioReady) await _configureAudio(eng);
    return eng;
  }

  Future<RtcEngine?> _create(String appId) async {
    final RtcEngine eng;
    try {
      eng = CallEngine.factory();
      await eng.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } catch (e) {
      Log.e('CallEngine', 'initialize failed: $e');
      return null;
    }
    await CallEngine._quiet(
      () => eng.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 360, height: 640),
          frameRate: 15,
          bitrate: 1200,
        ),
      ),
    );
    await CallEngine._quiet(
      () =>
          eng.setChannelProfile(ChannelProfileType.channelProfileCommunication),
    );
    await CallEngine._quiet(
      () => eng.setClientRole(role: ClientRoleType.clientRoleBroadcaster),
    );
    _bind(eng);
    _engine = eng;
    _initializedAppId = appId;
    _initAt = DateTime.now();
    _audioReady = false;
    _hasVideo = false;
    _setMedia((m) => m.copyWith(engineReady: true));
    return eng;
  }

  /// Earpiece by default for audio AND video (RN). The live speaker route
  /// can only be set once joined (Agora answers -3 before, CE).
  Future<void> _configureAudio(RtcEngine eng) async {
    await CallEngine._quiet(
      () => eng.setDefaultAudioRouteToSpeakerphone(false),
    );
    await CallEngine._quiet(
      () => eng.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioMeeting,
      ),
    );
    await CallEngine._quiet(eng.enableAudio);
    await CallEngine._quiet(() => eng.enableLocalAudio(true));
    await CallEngine._quiet(() => eng.muteLocalAudioStream(false));
    await CallEngine._quiet(() => eng.adjustRecordingSignalVolume(100));
    await CallEngine._quiet(() => eng.adjustPlaybackSignalVolume(100));
    _audioReady = true;
  }

  /// Agora delivers callbacks to the messenger that registered last (a
  /// background isolate can steal them): one handler, re-bound per engine.
  void _bind(RtcEngine eng) {
    final previous = _handler;
    if (previous != null) {
      try {
        eng.unregisterEventHandler(previous);
      } catch (_) {}
    }
    final handler = _buildHandler();
    _handler = handler;
    eng.registerEventHandler(handler);
  }

  Future<void> _teardown() async {
    final eng = _engine;
    final handler = _handler;
    _engine = null;
    _handler = null;
    _initializedAppId = null;
    _audioReady = false;
    _hasVideo = false;
    _localVideoFailed = false;
    _media.value = CallMedia.initial;
    if (eng == null) return;
    await CallEngine._quiet(eng.leaveChannel);
    if (handler != null) {
      try {
        eng.unregisterEventHandler(handler);
      } catch (_) {}
    }
    await CallEngine._quiet(eng.release);
  }

  /// Token app id (`006…`/`007…` → chars 3–35), cached, `Env`, app-config.
  Future<String?> _appId(String? token) async {
    final fromToken = token == null ? null : CallEngine.appIdFromToken(token);
    if (fromToken != null) return _resolvedAppId = fromToken;
    if (_resolvedAppId != null) return _resolvedAppId;
    if (Env.agoraAppId.isNotEmpty) return _resolvedAppId = Env.agoraAppId;
    try {
      final config = await CallEngine.configAppId();
      if (config != null && config.isNotEmpty) return _resolvedAppId = config;
    } catch (_) {}
    return null;
  }
}
