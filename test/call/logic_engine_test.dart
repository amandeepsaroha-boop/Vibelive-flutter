import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_device.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/callscreen/helper/engine/engine_events.dart';
import 'package:vibelive/app/callscreen/helper/engine/headless_join.dart';

import 'logic_fakes.dart';

void main() {
  final engine = CallEngine.instance;
  late FakeRtcEngine Function() rtc;

  setUpAll(initCallTestEnv);
  setUp(() async => rtc = (await resetCallTestEnv()).engine);
  tearDown(resetCallState);

  Future<bool> join({
    String channel = 'call_5_9_1',
    String? token,
    int uid = 9,
    bool video = false,
    bool headless = false,
  }) => engine.join(
    channel: channel,
    token: token ?? agoraToken(),
    uid: uid,
    video: video,
    headless: headless,
  );

  test('app id from the token (006 / 007), else none', () {
    expect(
      CallEngine.appIdFromToken(agoraToken()),
      'abcdefabcdefabcdefabcdefabcdef12',
    );
    expect(CallEngine.appIdFromToken('006${'a' * 32}xyz'), 'a' * 32);
    expect(CallEngine.appIdFromToken('008${'a' * 40}'), isNull);
    expect(CallEngine.appIdFromToken('007short'), isNull);
  });

  test('init order, COMMUNICATION + BROADCASTER, earpiece, encoder', () async {
    expect(await join(token: '${agoraToken()} '.replaceFirst('x', ' ')), true);
    final fake = rtc();
    final order = fake.calls;
    expect(order.first, 'initialize');
    expect(order, contains('setVideoEncoderConfiguration'));
    expect(order, contains('setChannelProfile'));
    expect(order, contains('setClientRole'));
    expect(order, contains('setDefaultAudioRouteToSpeakerphone'));
    expect(order, contains('setAudioProfile'));
    expect(order.last, 'joinChannel:call_5_9_1:9');
    final o = fake.joins.single;
    expect(o.channelProfile, ChannelProfileType.channelProfileCommunication);
    expect(o.clientRoleType, ClientRoleType.clientRoleBroadcaster);
    expect(o.publishMicrophoneTrack, isTrue);
    expect(o.publishCameraTrack, isFalse);
    expect(fake.tokens.single, isNot(contains(' ')), reason: 'E-52');
    expect(engine.media.value.engineReady, isTrue);
  });

  test('the same join twice joins once (fingerprint, E-6)', () async {
    await join();
    expect(await join(), isTrue);
    expect(rtc().joins, hasLength(1));
  });

  test('-17 while connecting is a success; else one rejoin (E-53)', () async {
    // The fake is created by the first join: queue the error on creation.
    CallEngine.factory = () {
      final f = FakeRtcEngine()
        ..joinErrors.add(-17)
        ..state = ConnectionStateType.connectionStateConnecting;
      return lastFake = f;
    };
    expect(await join(), isTrue);
    expect(lastFake!.joins, hasLength(1));

    resetCallState();
    CallEngine.factory = () => lastFake = FakeRtcEngine()..joinErrors.add(-17);
    expect(await join(), isTrue);
    expect(lastFake!.joins, hasLength(2));
    expect(lastFake!.calls, contains('leaveChannel'));
  });

  test('a failed join reports and can be retried (E-56)', () async {
    CallEngine.factory = () => lastFake = FakeRtcEngine()..joinErrors.add(-2);
    final events = <CallEngineEvent>[];
    final sub = engine.events.listen(events.add);
    expect(await join(), isFalse);
    await settle();
    expect(events.whereType<EngineJoinFailed>(), hasLength(1));
    expect(await join(), isTrue, reason: 'fingerprint cleared');
    await sub.cancel();
  });

  test('headless join: audio only, camera published once in front', () async {
    CallDevice.debugForeground = false;
    await join(video: true, headless: true);
    final fake = rtc();
    expect(fake.joins.single.publishCameraTrack, isFalse);
    expect(fake.calls, contains('enableVideo'), reason: 'module on, CE');
    expect(engine.headlessActive, isTrue);
    fake.remoteJoined(5);

    // In front before the join returned: parked (-8, E-40)…
    CallDevice.debugForeground = true;
    await engine.ensureVideoIfNeeded();
    expect(fake.updates, isEmpty);
    // …replayed on join success; the early remote is unmuted (E-41).
    fake.joined('call_5_9_1', 9);
    await settle();
    expect(fake.updates.single.publishCameraTrack, isTrue);
    expect(fake.calls, contains('muteRemoteVideoStream:5:false'));
    // Publishing now: no second publish.
    await engine.ensureVideoIfNeeded();
    expect(fake.updates, hasLength(1));
  });

  test('a failed camera: never repaired in the background, recaptured on '
      'resume even while published (I5)', () async {
    CallDevice.debugForeground = true;
    await join(video: true);
    final fake = rtc();
    fake.joined('call_5_9_1', 9);
    await settle();
    int previews() => fake.calls.where((c) => c == 'startPreview').length;
    final before = previews();
    // Locked: the camera failed although the track is published (E-48).
    fake.handler?.onLocalVideoStateChanged?.call(
      VideoSourceType.videoSourceCameraPrimary,
      LocalVideoStreamState.localVideoStreamStateFailed,
      LocalVideoStreamReason.localVideoStreamReasonFailure,
    );
    CallDevice.debugForeground = false;
    await engine.repairVideo(); // unlocked with the app still behind
    expect(previews(), before, reason: 'no camera in the background');
    CallDevice.debugForeground = true;
    await engine.ensureVideoIfNeeded(); // resumed
    expect(previews(), before + 1);
    await engine.ensureVideoIfNeeded();
    expect(previews(), before + 1, reason: 'working camera: no-op');
  });

  test('connection failed after the join → connection lost (A7)', () async {
    final events = <CallEngineEvent>[];
    final sub = engine.events.listen(events.add);
    await join();
    final fake = rtc();
    fake.joined('call_5_9_1', 9);
    fake.connection(
      ConnectionStateType.connectionStateFailed,
      ConnectionChangedReasonType.connectionChangedSameUidLogin,
    );
    await settle();
    expect(events.whereType<EngineConnectionLost>(), hasLength(1));
    expect(events.whereType<EngineJoinFailed>(), isEmpty);
    await sub.cancel();
  });

  test('a failed publish is retried (checked return code)', () async {
    CallDevice.debugForeground = true;
    await join(video: true, headless: true);
    final fake = rtc()..updateErrors.add(-8);
    fake.joined('call_5_9_1', 9);
    await engine.ensureVideoIfNeeded();
    expect(fake.updates, isEmpty);
    await engine.ensureVideoIfNeeded();
    expect(fake.updates, hasLength(1));
  });

  test('media: remote uid published; quit vs drop events', () async {
    await join();
    final fake = rtc();
    final events = <CallEngineEvent>[];
    final sub = engine.events.listen(events.add);
    fake.joined('call_5_9_1', 9);
    fake.remoteJoined(5);
    expect(engine.media.value.joined, isTrue);
    expect(engine.media.value.remoteUid, 5);
    expect(engine.hasRemote, isTrue);
    fake.remoteLeft(5, UserOfflineReasonType.userOfflineDropped);
    expect(engine.media.value.remoteUid, isNull);
    fake.remoteJoined(5);
    fake.remoteLeft(5, UserOfflineReasonType.userOfflineQuit);
    await settle();
    final left = events.whereType<EngineRemoteLeft>().toList();
    expect(left.map((e) => e.quit), [false, true]);
    await sub.cancel();
  });

  test('toggles publish only real changes', () async {
    await join();
    var notified = 0;
    void count() => notified++;
    engine.media.addListener(count);
    await engine.toggleMute();
    expect(engine.media.value.muted, isTrue);
    await engine.toggleSpeaker();
    expect(engine.media.value.speakerOn, isTrue);
    expect(notified, 2);
    engine.media.removeListener(count);
  });

  test('released after the call, never while one is live', () async {
    await join();
    final fake = rtc();
    CallController.instance.receive(
      const CallSession(callId: '42', callerId: '5', receiverId: '9'),
    );
    await engine.leave();
    engine.scheduleRelease();
    await settle(1100);
    expect(fake.calls, isNot(contains('release')), reason: 'call is live');
    CallController.instance.reset();
    engine.scheduleRelease();
    await settle(1100);
    expect(fake.calls, contains('release'));
    expect(engine.rtc, isNull);
    expect(engine.media.value, CallMedia.initial);
  });

  test(
    'iOS headless join waits for the audio session (3 s fallback)',
    () async {
      CallDevice.debugIsIOS = true;
      final parked = HeadlessJoin.instance.joinWhenAudioReady(
        channel: 'call_5_9_1',
        token: agoraToken(),
        uid: 9,
        video: false,
      );
      await parked;
      expect(HeadlessJoin.instance.isParked, isTrue);
      expect(engine.rtc, isNull);
      HeadlessJoin.instance.onAudioSessionActivated();
      await settle(500);
      expect(HeadlessJoin.instance.isParked, isFalse);
      expect(rtc().joins, hasLength(1));
    },
  );
}

FakeRtcEngine? lastFake;
