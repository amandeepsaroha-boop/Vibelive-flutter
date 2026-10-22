import AVFoundation
import Flutter
import UIKit

/// Dart <-> native call bridge. A method channel for commands, an event channel for native
/// events, and a queue for events that fire before Dart listens (RN
/// RNCallEventEmitter.pendingActions). Without the queue, a cold-launch VoIP relay is lost.
final class VibeCallBridge: NSObject, FlutterStreamHandler {
  static let shared = VibeCallBridge()
  static let methodChannel = "com.angrymamba.vibelive/callkit"
  static let eventChannel = "com.angrymamba.vibelive/callkit_events"

  private var sink: FlutterEventSink?
  private var pending: [[String: Any]] = []
  /// True once Dart has subscribed AND called `ready`. FOREGROUND-SUPPRESS requires it.
  private(set) var dartReady = false

  func install(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: Self.methodChannel, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    FlutterEventChannel(name: Self.eventChannel, binaryMessenger: messenger).setStreamHandler(self)
  }

  func emit(_ event: [String: Any], queueIfNotReady: Bool = true) {
    let send = {
      if self.dartReady, let sink = self.sink {
        sink(event)
        return
      }
      guard queueIfNotReady else { return }
      self.pending.append(event)
      if self.pending.count > 30 { self.pending.removeFirst() }
    }
    if Thread.isMainThread {
      send()
    } else {
      DispatchQueue.main.async(execute: send)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    dartReady = false
    return nil
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "ready":  // Dart listens; hand over everything queued
      dartReady = true
      let drained = pending
      pending.removeAll()
      result(drained)
    case "configure":  // {apiBaseUrl, appPlatform, defaultToken, deviceId, userId}
      VibeCallConfig.save(args)
      result(nil)
    case "setAuthToken":  // {token|null}: on login, every refresh, logout
      VibeCallConfig.setAuthToken(args["token"] as? String)
      result(nil)
    case "endCall":  // {callId, reason?}: in-app hangup / remote end
      VibeCallKit.shared.endLive(
        callId: args["callId"] as? String, reason: args["reason"] as? Int ?? 2)
      result(nil)
    case "liveCall":
      result(VibeCallKit.shared.liveSnapshot())
    case "consumePendingAccept":
      result(VibeCallKit.shared.consumePendingAccept())
    case "drainFailedEnds":  // native Callend bodies that failed → Dart PendingDeclineQueue
      result(VibeCallNetwork.shared.drainFailedEnds())
    case "isDeviceLocked":
      result(!UIApplication.shared.isProtectedDataAvailable)
    case "promoteToCallKit":  // {payload} → true when CallKit now rings it
      result(VibeCallKit.shared.ringFromDart(args["payload"] as? [String: Any] ?? [:]))
    case "answerLive":  // {callId}: in-app Accept of the CallKit-ringing call (I6)
      result(VibeCallKit.shared.answerLive(callId: args["callId"] as? String))
    case "isProtectedDataAvailable":  // false while locked / before the first unlock (I10)
      result(UIApplication.shared.isProtectedDataAvailable)
    case "bluetoothAvailable":  // CE audio-route channel, folded in
      let s = AVAudioSession.sharedInstance()
      let bt: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]
      result(
        s.currentRoute.outputs.contains { bt.contains($0.portType) }
          || (s.availableInputs ?? []).contains { bt.contains($0.portType) })
    case "setRoute":  // {route: speaker|bluetooth|earpiece}
      result(Self.setRoute(args["route"] as? String ?? "earpiece"))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// CE: CallKit never touches the session (configureAudioSession=false). The output is moved
  /// on Agora's session; Bluetooth is reached by preferring the headset input.
  private static func setRoute(_ route: String) -> Bool {
    let s = AVAudioSession.sharedInstance()
    do {
      switch route {
      case "speaker":
        try s.setPreferredInput(nil)
        try s.overrideOutputAudioPort(.speaker)
      case "bluetooth":
        try s.overrideOutputAudioPort(.none)
        let hfp: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothLE]
        if let headset = (s.availableInputs ?? []).first(where: { hfp.contains($0.portType) }) {
          try s.setPreferredInput(headset)
        }
      default:
        try s.setPreferredInput(nil)
        try s.overrideOutputAudioPort(.none)
      }
      return true
    } catch {
      NSLog("[VibeCallBridge] setRoute %@ failed: %@", route, error.localizedDescription)
      return false
    }
  }
}
