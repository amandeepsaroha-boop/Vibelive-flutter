import AVFoundation
import CallKit
import Foundation
import UIKit
import flutter_callkit_incoming

/// Every CallKit/PushKit decision of RN `IncomingCallManager` + `AppDelegate`, on top of the
/// one CXProvider owned by flutter_callkit_incoming. Main thread only: PushKit
/// (PKPushRegistry(queue: .main)), the CXProvider delegate (queue nil = main) and the
/// Flutter channels all run on main.
final class VibeCallKit {
  static let shared = VibeCallKit()

  enum Route: String { case probe, answeredElsewhere, termination, status, ring, unclassified }

  struct Push {
    let body: [String: Any]
    let route: Route
    let callId: String?
    let callerName: String
    let isVideo: Bool
    let ageMs: Int64?
  }

  // MARK: token buckets. Order: probe → answered-elsewhere → termination → status → ring.
  // Classified off type + status/callStatus + event/action/notificationType (RN), never off
  // "has a callId": every status/end push also carries one (memory #5).

  static let probeTokens: Set<String> = ["expert_presence_probe", "presence_probe", "heartbeat"]
  static let elsewhereTokens: Set<String> = [
    "call_answered_elsewhere", "callansweredelsewhere", "answered_elsewhere",
  ]
  static let terminalTokens: Set<String> = [
    "call_ended", "callended", "call_end", "end_call", "callend", "ended", "end",
    "cancel", "cancelled", "canceled", "call_canceled", "call_cancelled",
    "decline", "declined", "rejected", "call_rejected", "call_busy",
    "missed", "missed_call", "missed_call_history", "completed",
    "timeout", "unanswered", "no_answer", "hangup", "hang_up",
  ]
  /// Includes the CALLER-side "their phone is ringing" signals (call_ringing...). The backend
  /// sends CALL_RINGING over VoIP to the caller's devices (receiverRingingAck →
  /// notifyUserDevices voip:true). RN listed "call_ringing"/"ringing" as RINGING tokens, which
  /// would put a CallKit ringer for the caller's own outgoing call on a backgrounded iPhone.
  static let statusTokens: Set<String> = [
    "ongoing", "call_ongoing", "ongoing_call", "call_update", "update", "updated",
    "connected", "connect", "answered", "accepted", "call_accepted", "in_call", "incall",
    "call_status", "status_update", "calltimer", "call_timer",
    "call_ringing", "callringing", "call_ringing_legacy", "ringing",
  ]

  static let appName = "Vibe Live"
  /// Safety net only: the backend's CALL_ENDED normally ends a ring long before this.
  static let ringWindowMs = 60_000
  /// A VoIP push delayed longer than this (device offline, APNs queue) is not rung.
  /// Generous on purpose: clock skew must never block a genuine call. Dart applies 45 s.
  static let maxInviteAgeMs: Int64 = 120_000
  static let handledWindow: TimeInterval = 60

  private var plugin: SwiftFlutterCallkitIncomingPlugin? {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance
  }
  /// Requests go to the app's one CXProvider (the plugin's).
  private let callController = CXCallController()

  // MARK: live call (RN currentCall*). Set when we ring, re-adopted from the plugin's Call in
  // every delegate hook, cleared on every end path.
  private var liveUUID: String?
  private var liveCallId: String?
  private var livePayload: [String: Any] = [:]
  private var liveIsVideo = false
  private var isAnswered = false
  private var answeredAt: Date?
  private var lastCallerName: String?
  private var handled: [String: Date] = [:]  // RN ghost protection
  private var appEnding = Set<String>()
  private var pushSeq = 0
  /// Talk Now: ring id (the instant-call session) → the call record the host-accept created.
  /// A CallKit-UI end bills the record, never the ring id.
  private var instantRecords: [String: String] = [:]

  // MARK: - PushKit entry

  func handleVoipPush(_ raw: [AnyHashable: Any], completion: @escaping () -> Void) {
    pushSeq += 1
    let push = classify(Self.body(of: raw))
    let state = UIApplication.shared.applicationState
    // Suppress only when Dart can actually draw the in-app screen. A user who just
    // cold-launched the app can be .active before Dart listens; that ring goes to CallKit.
    let foreground = state == .active && VibeCallBridge.shared.dartReady
    NSLog(
      "[VibeCallKit] CALLTRACE VoIP #%d route=%@ callId=%@ state=%ld live=%@ answered=%d fg=%d",
      pushSeq, push.route.rawValue, push.callId ?? "nil", state.rawValue,
      liveCallId ?? "nil", isAnswered ? 1 : 0, foreground ? 1 : 0)

    // Dart sees every push: ringing-ack, in-app UI, teardown of a headless join (memory #15).
    VibeCallBridge.shared.emit([
      "event": "voipPush", "route": push.route.rawValue,
      "foreground": foreground, "data": push.body,
    ])

    // FOREGROUND-SUPPRESS (memory #1): iOS never kills an .active app for not reporting, and
    // no CallKit means no flash. Dart shows the in-app screen.
    if foreground {
      if push.route == .termination || (push.route == .answeredElsewhere && !isAnswered) {
        endLive(callId: push.callId, reason: push.route == .answeredElsewhere ? 4 : 2)
      }
      completion()
      return
    }

    // Background / suspended / killed / .inactive: EVERY push reports to CallKit. "Already
    // handled an earlier push" is no exemption (memory #14, the appIsAlive SIGKILL).
    // A dropped call is always worse than a flash.
    switch push.route {
    case .ring:
      if liveUUID != nil { return rereportLive(completion) }  // never a second ringer
      if let id = push.callId, isRecentlyHandled(id) {
        return reportCompliance(name: push.callerName, completion)  // ghost invite: report, don't ring
      }
      if let age = push.ageMs, age > Self.maxInviteAgeMs {
        return reportCompliance(name: push.callerName, completion)
      }
      reportRing(push, completion)

    case .termination, .answeredElsewhere:
      if let id = push.callId { markHandled(id) }
      guard liveUUID != nil else { return reportCompliance(name: lastCallerName, completion) }
      // Case A (memory #3): re-report the live UUID (satisfies this push, draws nothing), then
      // end it only if THIS callId is that call. An unrelated end must never kill a live
      // call, and answered-elsewhere never ends the device that answered.
      let matches = push.callId != nil && push.callId == liveCallId
      let shouldEnd = matches && (push.route == .termination || !isAnswered)
      let reason = push.route == .answeredElsewhere ? 4 : 2
      rereportLive { [weak self] in
        if shouldEnd { self?.endLive(callId: push.callId, reason: reason) }
        completion()
      }

    case .status, .probe, .unclassified:
      // Status/ongoing/CallTimer, presence probe, PING_CLIENT, unknown (memory #5, #9).
      if liveUUID != nil {
        rereportLive(completion)
      } else {
        reportCompliance(name: push.callerName, completion)
      }
    }
  }

  // MARK: - Classification

  func classify(_ b: [String: Any]) -> Push {
    let type = (Self.str(b["type"]) ?? "").lowercased()
    let status = (Self.str(b["status"]) ?? Self.str(b["callStatus"]) ?? "").lowercased()
    let event =
      (Self.str(b["event"]) ?? Self.str(b["action"])
      ?? Self.str(b["notificationType"]) ?? "").lowercased()
    func any(_ s: Set<String>) -> Bool { s.contains(type) || s.contains(status) || s.contains(event) }

    let callId = Self.str(b["callId"]) ?? Self.str(b["call_id"])
    let hasChannel =
      (Self.str(b["channelName"]) ?? Self.str(b["roomId"]) ?? Self.str(b["channel_name"])) != nil
    let hasToken = (Self.str(b["token"]) ?? Self.str(b["receiverToken"])) != nil
    let ongoingFlag = Self.flag(b["__isOngoingCall"]) || Self.flag(b["isOngoing"])

    let route: Route
    if any(Self.probeTokens) || b["triggerHeartbeat"] != nil {
      route = .probe
    } else if any(Self.elsewhereTokens) {
      route = .answeredElsewhere
    } else if Self.flag(b["dismissNotification"]) || any(Self.terminalTokens) {
      route = .termination
    } else if ongoingFlag || any(Self.statusTokens) {
      route = .status
    } else if callId != nil && hasChannel && hasToken {
      // A genuine ring is the ONLY push carrying fresh Agora join credentials (memory key fact).
      route = .ring
    } else {
      route = .unclassified
    }

    // VoIP payloads encode spaces as "+" ("Sharad+Singh").
    let name =
      (Self.str(b["callerName"]) ?? Self.str(b["caller_name"]) ?? Self.str(b["handle"])
      ?? Self.str(b["expertName"]) ?? Self.str(b["name"]) ?? Self.appName)
      .replacingOccurrences(of: "+", with: " ")
    // Backend sends hasVideo "0" even for type videoCall (initiateCall compares type === "video").
    let isVideo = Self.flag(b["hasVideo"]) || Self.flag(b["isVideo"]) || type.contains("video")  // memory #13
    let age = Self.ageMs(
      sent: Self.str(b["timestampMs"]) ?? Self.str(b["timestamp"]),
      nowMs: Int64(Date().timeIntervalSince1970 * 1000))
    return Push(
      body: b, route: route, callId: callId, callerName: name, isVideo: isVideo, ageMs: age)
  }

  /// Age of a push from its timestamp, nil when unknown (I9). Seconds or milliseconds by size
  /// (Dart's rule: > 2e10 is ms). A timestamp in the future (phone clock behind) or more than
  /// 30 days old (broken clock or unit) is clock skew, not delay: unknown, never "stale". Clock
  /// skew must never block a genuine call.
  static func ageMs(sent raw: String?, nowMs: Int64) -> Int64? {
    guard let raw, let n = Double(raw), n > 0, n.isFinite else { return nil }
    let sentMs = n > 2e10 ? Int64(n) : Int64(n * 1000)
    let age = nowMs - sentMs
    if age < 0 || age > 30 * 24 * 3_600_000 { return nil }
    return age
  }

  // MARK: - Reports

  /// A REAL CallKit ringer (Apple ringtone + system incoming UI). The only report that rings.
  private func reportRing(_ push: Push, _ completion: @escaping () -> Void) {
    guard let plugin, let callId = push.callId else {
      return reportCompliance(name: push.callerName, completion)
    }
    let uuid = Self.nativeId(for: callId)
    var extra = push.body  // the whole payload rides along: Dart joins from it
    extra["callId"] = callId
    if extra["timestamp"] == nil {
      extra["timestamp"] = String(Int64(Date().timeIntervalSince1970 * 1000))
    }
    setLive(uuid: uuid, callId: callId, payload: extra, name: push.callerName, isVideo: push.isVideo)
    let data = makeData(
      uuid: uuid, name: push.callerName, isVideo: push.isVideo,
      extra: extra, duration: Self.ringWindowMs)
    NSLog(
      "[VibeCallKit] CALLTRACE ROUTE=RING-BACKGROUND callId=%@ video=%d", callId,
      push.isVideo ? 1 : 0)
    plugin.showCallkitIncoming(data, fromPushKit: true) { completion() }
  }

  /// PushKit compliance with NO ring: throwaway UUID, ended instantly with .answeredElsewhere
  /// (no missed/ended chrome). Touches no live state. Only called when nothing is live.
  private func reportCompliance(name: String?, _ completion: @escaping () -> Void) {
    guard let plugin else {
      completion()
      return
    }
    let uuid = UUID().uuidString.lowercased()
    let display = (name?.isEmpty == false ? name! : (lastCallerName ?? Self.appName))
    // fromPushKit: true on purpose. Nothing is live, so overwriting the plugin's stored push
    // data is harmless, and it makes the plugin's configureAudioSession() read
    // configureAudioSession=false. With no stored data it would activate a .duckOthers session
    // and duck the user's music on every status push.
    let data = makeData(
      uuid: uuid, name: display, isVideo: false,
      extra: ["__compliance": true], duration: 1_000)
    NSLog("[VibeCallKit] CALLTRACE ROUTE=COMPLIANCE (report + instant .answeredElsewhere, no ring)")
    plugin.showCallkitIncoming(data, fromPushKit: true) {
      plugin.saveEndCall(uuid, 4)  // 4 = .answeredElsewhere
      completion()
    }
    plugin.saveEndCall(uuid, 4)  // same run loop: shrink the mandatory flash (RN)
  }

  /// Re-report the UUID CallKit already holds. CallKit answers callUUIDAlreadyExists, nothing
  /// is drawn, and the push counts as reported (CE "PushKit compliance"). Used instead of a
  /// throwaway while a call is live, because a NEW uuid always presents and rings over the
  /// live call (the "~1 s call notification right after answering").
  private func rereportLive(_ completion: @escaping () -> Void) {
    guard let plugin, let uuid = liveUUID else {
      completion()
      return
    }
    let data = makeData(
      uuid: uuid, name: lastCallerName ?? Self.appName, isVideo: liveIsVideo,
      extra: livePayload, duration: Self.ringWindowMs)
    // fromPushKit: true keeps the plugin's stored call data = the LIVE call. With false the
    // plugin kept whatever a compliance report stored last, and its later endCall /
    // callConnected acted on that throwaway (I6).
    plugin.showCallkitIncoming(data, fromPushKit: true) { completion() }
  }

  /// Dart asks to put a call on CallKit (in-app ring promoted when the app goes to the
  /// background). Never twice for one UUID (memory #14 ringtone ducking).
  @discardableResult
  func ringFromDart(_ payload: [String: Any]) -> Bool {
    guard liveUUID == nil, plugin != nil else { return false }
    let push = classify(payload)
    guard push.route == .ring, let id = push.callId, !isRecentlyHandled(id) else { return false }
    reportRing(push) {}
    return true
  }

  /// In-app Accept of the call CallKit is ringing (I6): request the CXAnswerCallAction for the
  /// live UUID, so CallKit, the audio session and onAccept (native /UpdateCall, the
  /// ACTION_CALL_ACCEPT event) all follow, exactly as an answer on the CallKit UI. The
  /// plugin's setCallConnected is NOT used: it overwrote the plugin's stored call data.
  func answerLive(callId: String?) -> Bool {
    guard let uuidString = liveUUID, !isAnswered, let uuid = UUID(uuidString: uuidString)
    else { return false }
    if let callId, let live = liveCallId, callId != live { return false }
    let answer = CXAnswerCallAction(call: uuid)
    let id = liveCallId ?? callId ?? ""
    callController.request(CXTransaction(action: answer)) { error in
      guard let error else { return }
      NSLog(
        "[VibeCallKit] CALLTRACE answerLive %@ failed: %@", uuidString, error.localizedDescription)
      // onAccept never runs, so native sends no /UpdateCall: Dart sends it (I1 path).
      if !id.isEmpty {
        VibeCallBridge.shared.emit(["event": "updateCallFailed", "callId": id])
      }
    }
    NSLog("[VibeCallKit] CALLTRACE answerLive callId=%@", liveCallId ?? "nil")
    return true
  }

  // MARK: - Ending (Dynamic Island cleanup, memory #10 / #12)

  /// App-initiated teardown: in-app hangup, remote end, caller's CALL_ENDED.
  /// reportCall(endedAt:) through the plugin's saveEndCall. It reliably clears the CallKit
  /// UI / Dynamic Island, never throws on a stale UUID, and does NOT fire CXEndCallAction, so
  /// the backend is not double-ended. A CXEndCallAction transaction failed with error 4 after
  /// background answers in RN.
  func endLive(callId: String?, reason: Int) {
    guard let uuid = liveUUID else { return }
    if let callId, let live = liveCallId, callId != live { return }
    if let id = liveCallId {
      markHandled(id)
      appEnding.insert(id)
    }
    plugin?.saveEndCall(uuid, reason)  // 2 = .remoteEnded, 4 = .answeredElsewhere
    clearPendingAccept()
    clearLive()
    NSLog("[VibeCallKit] CALLTRACE endLive uuid=%@ reason=%d", uuid, reason)
  }

  // MARK: - CallkitIncomingAppDelegate hooks

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    // FULFILL FIRST, unconditionally (memory #8): the answer succeeded, and gating fulfill on
    // anything else dropped calls. There is no accept deep link in Flutter at all
    // (memory #4/#8): Dart gets ACTION_CALL_ACCEPT from the plugin with the full extra.
    action.fulfill()
    let payload = Self.extra(of: call)
    if payload["__compliance"] != nil { return }
    adopt(call, payload: payload)
    isAnswered = true
    answeredAt = Date()
    if let id = liveCallId { markHandled(id) }
    savePendingAccept(payload)  // cold accept before Dart listened: Dart consumes it once
    // Talk Now: the ring is an instant-call SESSION; /instant-call/host-accept creates the
    // call record (and stops the other hosts' rings) instead of /UpdateCall. Any refusal goes
    // to Dart too (the call may be another host's now): Dart retries, or leaves the call.
    if Self.isInstant(payload), let ringId = Self.callId(of: call, payload: payload) {
      let session = Self.str(payload["instantCallSessionId"]) ?? ringId
      VibeCallNetwork.shared.instantHostAccept(
        sessionId: session,
        onSuccess: { [weak self] record in
          self?.instantRecords[ringId] = record
          VibeCallBridge.shared.emit([
            "event": "instantAccepted", "callId": ringId, "serverCallId": record,
          ])
        },
        onFailure: { [weak self] in
          NSLog("[VibeCallKit] CALLTRACE native host-accept FAILED callId=%@ → Dart", ringId)
          self?.markPendingAcceptUpdateFailed(callId: ringId)
          VibeCallBridge.shared.emit([
            "event": "updateCallFailed", "callId": ringId, "payload": payload,
          ])
        })
      NSLog("[VibeCallKit] CALLTRACE native ACCEPT (Talk Now) callId=%@", ringId)
      return
    }
    // CALL-BREAKING when lost (I1): the server never learns of the answer. A failure is put on
    // the accept snapshot (a cold start that has not read it yet) and sent to Dart (queued
    // until it listens), which sends /UpdateCall again.
    VibeCallNetwork.shared.updateCallStatus(payload: payload, status: "ongoing") {
      [weak self] callId in
      NSLog("[VibeCallKit] CALLTRACE native UpdateCall FAILED callId=%@ → Dart retries", callId)
      self?.markPendingAcceptUpdateFailed(callId: callId)
      VibeCallBridge.shared.emit([
        "event": "updateCallFailed", "callId": callId, "payload": payload,
      ])
    }
    NSLog("[VibeCallKit] CALLTRACE native ACCEPT callId=%@", liveCallId ?? "nil")
  }

  /// CallKit decline of an UNANSWERED call. Native-only on purpose: the app may be suspended
  /// or killed, and Dart may not run in time (memory #6).
  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    let payload = Self.extra(of: call)
    let callId = Self.callId(of: call, payload: payload)
    clearLive(ifUUID: call.uuid.uuidString.lowercased())
    clearPendingAccept()
    action.fulfill()
    guard payload["__compliance"] == nil, let callId else { return }
    markHandled(callId)
    if appEnding.remove(callId) != nil { return }
    NSLog(
      "[VibeCallKit] CALLTRACE native DECLINE callId=%@ endedById=%@",
      callId, Self.str(payload["receiverId"]) ?? "nil")
    // Talk Now: the server rings the next host now (a session has no call record).
    if Self.isInstant(payload) {
      VibeCallNetwork.shared.instantHostDecline(
        sessionId: Self.str(payload["instantCallSessionId"]) ?? callId)
      return
    }
    VibeCallNetwork.shared.endCall(
      callId: callId, payload: payload, status: "declined", durationSecs: 0)
  }

  /// CallKit-UI end of an ANSWERED call (memory #15). With the headless join the whole call
  /// can happen without the app ever opening, so native reports "completed" with the measured
  /// duration, and Dart only tears down (no second Callend).
  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    let payload = Self.extra(of: call)
    let callId = Self.callId(of: call, payload: payload)
    let secs = answeredAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
    clearLive(ifUUID: call.uuid.uuidString.lowercased())
    clearPendingAccept()
    action.fulfill()
    guard payload["__compliance"] == nil, let callId else { return }
    markHandled(callId)
    if appEnding.remove(callId) != nil { return }
    if Self.isInstant(payload) {
      // Talk Now bills the call record the accept created; when its reply has not come yet,
      // host-accept again: the backend repeats it for the host who has the call.
      let complete = { (record: String) in
        VibeCallNetwork.shared.endCall(
          callId: record, payload: payload, status: "completed", durationSecs: max(1, secs))
      }
      if let record = instantRecords.removeValue(forKey: callId) {
        complete(record)
      } else {
        VibeCallNetwork.shared.instantHostAccept(
          sessionId: Self.str(payload["instantCallSessionId"]) ?? callId,
          onSuccess: complete, onFailure: {})
      }
    } else {
      VibeCallNetwork.shared.endCall(
        callId: callId, payload: payload,
        status: "completed", durationSecs: max(1, secs))
    }
    VibeCallBridge.shared.emit([
      "event": "nativeEnded", "callId": callId, "status": "completed", "durationSecs": secs,
    ])
  }

  /// Plugin ring window elapsed. No API: the caller/backend own "missed". Also fires for a
  /// call we already ended via saveEndCall (the plugin keeps a stale entry and its
  /// endCallNotExist timer still runs), so ignore anything that is not the live unanswered call.
  func onTimeOut(_ call: Call) {
    let uuid = call.uuid.uuidString.lowercased()
    guard uuid == liveUUID, !isAnswered else { return }
    if let id = liveCallId { markHandled(id) }
    clearLive()
  }

  func providerDidReset() { clearLive() }

  // MARK: - Snapshots for Dart

  func liveSnapshot() -> [String: Any]? {
    guard let uuid = liveUUID else { return nil }
    return ["uuid": uuid, "callId": liveCallId ?? "", "answered": isAnswered, "payload": livePayload]
  }

  private static let pendingAcceptKey = "vibe_pending_accept"

  private func savePendingAccept(_ payload: [String: Any]) {
    let snap: [String: Any] = ["at": Date().timeIntervalSince1970 * 1000, "payload": payload]
    guard JSONSerialization.isValidJSONObject(snap),
      let json = (try? JSONSerialization.data(withJSONObject: snap)).flatMap({
        String(data: $0, encoding: .utf8)
      })
    else { return }
    UserDefaults.standard.set(json, forKey: Self.pendingAcceptKey)
  }

  /// Consumed ONCE (it cannot double-fire with the live ACTION_CALL_ACCEPT path). Cleared on
  /// every end, so an answered call ended from CallKit before the app opened never replays
  /// into a dead call screen.
  func consumePendingAccept() -> [String: Any]? {
    let d = UserDefaults.standard
    guard let json = d.string(forKey: Self.pendingAcceptKey) else { return nil }
    d.removeObject(forKey: Self.pendingAcceptKey)
    guard let raw = json.data(using: .utf8),
      let snap = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
      let at = snap["at"] as? Double,
      Date().timeIntervalSince1970 * 1000 - at < 10 * 60 * 1000
    else { return nil }
    return snap
  }

  /// The snapshot (if Dart has not consumed it yet) records that native's /UpdateCall failed.
  private func markPendingAcceptUpdateFailed(callId: String) {
    let d = UserDefaults.standard
    guard let json = d.string(forKey: Self.pendingAcceptKey),
      let raw = json.data(using: .utf8),
      var snap = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
      let payload = snap["payload"] as? [String: Any],
      (Self.str(payload["callId"]) ?? Self.str(payload["call_id"])) == callId
    else { return }
    snap["updateFailed"] = true
    guard JSONSerialization.isValidJSONObject(snap),
      let out = (try? JSONSerialization.data(withJSONObject: snap)).flatMap({
        String(data: $0, encoding: .utf8)
      })
    else { return }
    d.set(out, forKey: Self.pendingAcceptKey)
  }

  private func clearPendingAccept() {
    UserDefaults.standard.removeObject(forKey: Self.pendingAcceptKey)
  }

  /// The RN build stored its own accept snapshot and token in UserDefaults. Drop them on the
  /// first Flutter launch so an old snapshot can't replay as a ghost call.
  func migrateFromReactNativeOnce() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: "vibe_flutter_migrated_v1") else { return }
    [
      "pendingActiveCallId", "pendingActiveCallStatus", "pendingActiveCallTimestamp",
      "pendingActiveCallPayload", "voip_auth_token",
    ].forEach { d.removeObject(forKey: $0) }
    d.set(true, forKey: "vibe_flutter_migrated_v1")
  }

  // MARK: - State helpers

  private func setLive(
    uuid: String, callId: String, payload: [String: Any], name: String, isVideo: Bool
  ) {
    liveUUID = uuid
    liveCallId = callId
    livePayload = payload
    lastCallerName = name
    liveIsVideo = isVideo
    isAnswered = false
    answeredAt = nil
    // reportNewIncomingCall can fail (DND, filtered). Expire an unanswered live state, so a
    // later push never re-reports a UUID CallKit never accepted.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Self.ringWindowMs + 5_000)) {
      [weak self] in
      guard let self, self.liveUUID == uuid, !self.isAnswered else { return }
      self.clearLive()
    }
  }

  private func adopt(_ call: Call, payload: [String: Any]) {
    liveUUID = call.uuid.uuidString.lowercased()
    liveCallId = Self.callId(of: call, payload: payload) ?? liveCallId
    if !payload.isEmpty { livePayload = payload }
    if !call.data.nameCaller.isEmpty { lastCallerName = call.data.nameCaller }
    liveIsVideo = call.data.type > 0
  }

  private func clearLive(ifUUID uuid: String? = nil) {
    if let uuid, uuid != liveUUID { return }
    liveUUID = nil
    liveCallId = nil
    livePayload = [:]
    isAnswered = false
    answeredAt = nil  // lastCallerName is kept on purpose (compliance handle)
  }

  private func markHandled(_ id: String) {
    let now = Date()
    handled = handled.filter { now.timeIntervalSince($0.value) < Self.handledWindow }
    handled[id] = now
  }

  private func isRecentlyHandled(_ id: String) -> Bool {
    guard let at = handled[id] else { return false }
    return Date().timeIntervalSince(at) < Self.handledWindow
  }

  // MARK: - Plugin Data

  private static let iosArgs: [String: Any] = [
    "iconName": "CallKitLogo",
    "handleType": "generic",
    // Plain caller name as CXHandle (RN). 0 = encrypted JSON of the whole extra, tokens included.
    "normalHandle": 1,
    "supportsVideo": true,  // provider config must not flip per call
    "maximumCallGroups": 1, "maximumCallsPerCallGroup": 1,
    "supportsDTMF": false, "supportsHolding": false,
    "supportsGrouping": false, "supportsUngrouping": false,
    "includesCallsInRecents": false,  // RN
    "ringtonePath": "",  // system ringtone (RN). Or "ReciverSideRinging.caf"
    // Agora owns the session; otherwise the plugin re-applies it at ring, answer and +1.2 s
    // (CE: ~30 s with no join).
    "configureAudioSession": false,
  ]

  private func makeData(
    uuid: String, name: String, isVideo: Bool,
    extra: [String: Any], duration: Int
  ) -> flutter_callkit_incoming.Data {
    return flutter_callkit_incoming.Data(args: [
      "id": uuid,
      "nameCaller": name,
      "appName": Self.appName,
      "handle": name,
      "type": isVideo ? 1 : 0,  // → CXCallUpdate.hasVideo
      "duration": duration,
      "extra": extra,
      "missedCallNotification": ["showNotification": false],  // the backend sends "Missed Call"
      "ios": Self.iosArgs,
    ])
  }

  // MARK: - Parsing

  static func body(of raw: [AnyHashable: Any]) -> [String: Any] {
    if let inner = raw["data"] as? [String: Any] { return inner }
    var out: [String: Any] = [:]
    for (k, v) in raw {
      if let k = k as? String, k != "aps" { out[k] = v }
    }
    return out
  }

  static func extra(of call: Call) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, v) in call.data.extra {
      if let k = k as? String { out[k] = v }
    }
    return out
  }

  static func callId(of call: Call, payload: [String: Any]) -> String? {
    str(payload["callId"]) ?? str(payload["call_id"])
  }

  /// A Talk Now ring (`isInstantCall: "true"`): its callId is an instant-call session.
  static func isInstant(_ payload: [String: Any]) -> Bool {
    str(payload["isInstantCall"])?.lowercased() == "true"
  }

  static func str(_ v: Any?) -> String? {
    guard let v, !(v is NSNull) else { return nil }
    let s = ((v as? String) ?? "\(v)").trimmingCharacters(in: .whitespacesAndNewlines)
    return (s.isEmpty || s == "null") ? nil : s
  }

  static func flag(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b }
    let s = (str(v) ?? "").lowercased()
    return s == "1" || s == "true" || s == "yes"
  }

  /// CE `nativeId(for:)` with a VibeLive salt. Dart `CallKitIds.nativeIdFor` MUST be
  /// byte-identical (FNV-1a over UTF-16 code units, wrapping 64-bit, v4/RFC-4122 bits).
  static func nativeId(for callId: String) -> String {
    let uuidPattern =
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    if callId.range(of: uuidPattern, options: .regularExpression) != nil {
      return callId.lowercased()
    }
    let a = fnv1a(callId, seed: 0xcbf2_9ce4_8422_2325)
    let b = fnv1a("vibelive:\(callId)", seed: 0x8422_2325_cbf2_9ce4)
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<16 {
      let hash = i < 8 ? a : b
      bytes[i] = UInt8((hash >> UInt64(8 * (7 - (i % 8)))) & 0xff)
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    func s(_ f: Int, _ t: Int) -> Substring {
      hex[hex.index(hex.startIndex, offsetBy: f)..<hex.index(hex.startIndex, offsetBy: t)]
    }
    return "\(s(0, 8))-\(s(8, 12))-\(s(12, 16))-\(s(16, 20))-\(s(20, 32))"
  }

  private static func fnv1a(_ input: String, seed: UInt64) -> UInt64 {
    var hash = seed
    for unit in input.utf16 {
      hash ^= UInt64(unit)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
  }
}
