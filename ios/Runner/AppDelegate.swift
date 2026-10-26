import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  /// Held strongly. A PKPushRegistry that is deallocated silently stops VoIP delivery,
  /// which looks exactly like "the backend is not sending".
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Plugins are registered on the APP DELEGATE (FlutterLaunchEngine), NOT through
    // FlutterImplicitEngineDelegate. A VoIP push that cold-starts the app in the background
    // never creates a scene, so the implicit-engine path never registers plugins:
    // SwiftFlutterCallkitIncomingPlugin.sharedInstance stays nil, no call is reported, and
    // iOS kills the app (proven in CE on the same Flutter 3.41.2 revision).
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "VibeCallBridge") {
      VibeCallBridge.shared.install(messenger: registrar.messenger())
    }
    // The RN build's session, read once on the first Flutter launch.
    if let registrar = registrar(forPlugin: "LegacySessionReader") {
      LegacySessionReader.install(messenger: registrar.messenger())
    }
    // flutter_local_notifications: foreground presentation and taps.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

    VibeCallKit.shared.migrateFromReactNativeOnce()
    observeDeviceUnlock()
    registerForVoipPushes()  // last: the first push can arrive immediately
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: PushKit

  private func registerForVoipPushes() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: "voip_token")
    // Dart reads it with FlutterCallkitIncoming.getDevicePushTokenVoIP() and gets a
    // CallEventActionDidUpdateDevicePushTokenVoip event to re-register it.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    UserDefaults.standard.removeObject(forKey: "voip_token")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    VibeCallKit.shared.handleVoipPush(payload.dictionaryPayload, completion: completion)
  }

  // MARK: Device unlock (RN AppDelegate)

  /// iOS refuses the camera while the device is locked, yet Agora's startPreview reports
  /// success, so a video call answered on the lock screen captures nothing until repaired.
  /// AppLifecycleState cannot see the unlock (the app is already "active" behind the lock
  /// screen); protectedDataDidBecomeAvailable is the precise signal.
  private func observeDeviceUnlock() {
    NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification,
      object: nil, queue: .main
    ) { _ in
      VibeCallBridge.shared.emit(["event": "unlocked"], queueIfNotReady: false)
    }
  }

  // MARK: CallkitIncomingAppDelegate (flutter_callkit_incoming calls these on main)

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    VibeCallKit.shared.onAccept(call, action)
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    VibeCallKit.shared.onDecline(call, action)
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    VibeCallKit.shared.onEnd(call, action)
  }

  func onTimeOut(_ call: Call) {
    VibeCallKit.shared.onTimeOut(call)
  }

  func providerDidReset() {
    VibeCallKit.shared.providerDidReset()
  }

  /// Log only. Agora owns the AVAudioSession (configureAudioSession=false); reconfiguring it
  /// here fights the SDK. The plugin itself forwards ACTION_CALL_TOGGLE_AUDIO_SESSION to Dart,
  /// and that event is what releases the parked headless join.
  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    NSLog("[VibeCallKit] CALLTRACE audio session ACTIVATED (CallKit) — audio can flow")
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    NSLog("[VibeCallKit] CALLTRACE audio session deactivated")
  }
}
