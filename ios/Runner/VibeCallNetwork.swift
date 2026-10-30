import Foundation
import Security
import UIKit

/// Native config written by Dart (VibeCallBridge.configure / setAuthToken). Persisted so a
/// CallKit decline on a VoIP cold launch works before Dart has run.
enum VibeCallConfig {
  private static let d = UserDefaults.standard

  static func save(_ args: [String: Any]) {
    for key in ["apiBaseUrl", "appPlatform", "defaultToken", "deviceId", "userId"] {
      if let v = args[key] as? String, !v.isEmpty { d.set(v, forKey: "vibe_call_\(key)") }
    }
  }

  /// Memory #6: a TRAILING SLASH produced "...com//api/call/Callend". The angrymamba server
  /// redirects that and downgrades POST → GET → 405, so the decline was dropped and the call
  /// went "missed". Always normalise: host only, no trailing "/" and no "/api".
  static var apiBaseUrl: String {
    var s = d.string(forKey: "vibe_call_apiBaseUrl") ?? "https://manageapps.angrymamba.com"
    while s.hasSuffix("/") { s.removeLast() }
    if s.hasSuffix("/api") { s.removeLast(4) }
    while s.hasSuffix("/") { s.removeLast() }
    return s
  }
  static var appPlatform: String { d.string(forKey: "vibe_call_appPlatform") ?? "vibe_os" }
  static var defaultToken: String? { d.string(forKey: "vibe_call_defaultToken") }
  static var deviceId: String? { d.string(forKey: "vibe_call_deviceId") }
  static var userId: String? { d.string(forKey: "vibe_call_userId") }

  static var authToken: String? { NativeKeychain.get("access_token") }
  static func setAuthToken(_ token: String?) { NativeKeychain.set(token, account: "access_token") }
}

/// Our own keychain item (AfterFirstUnlock: readable on a locked phone after the first
/// unlock since boot, same as Dart's TokenStorage). flutter_secure_storage's item layout is
/// private and wraps keys, so it is not read directly.
enum NativeKeychain {
  private static let service = "com.angrymamba.vibelive.callkit"

  static func set(_ value: String?, account: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value, !value.isEmpty, let bytes = value.data(using: .utf8) else { return }
    var add = base
    add[kSecValueData as String] = bytes
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }

  static func get(_ account: String) -> String? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
      let bytes = out as? Foundation.Data
    else { return nil }
    return String(data: bytes, encoding: .utf8)
  }
}

final class VibeCallNetwork {
  static let shared = VibeCallNetwork()
  private let failedKey = "vibe_call_failed_ends"

  /// POST /api/call/Callend. `status` "declined" for a CallKit decline, "completed" for a
  /// CallKit-UI end of an answered call (memory #15). startTime is derived from the duration.
  func endCall(callId: String, payload: [String: Any], status: String, durationSecs: Int) {
    let end = Date()
    let secs = max(0, durationSecs)
    var body: [String: Any] = [
      "status": status,
      "startTime": Self.iso(end.addingTimeInterval(-Double(secs))),
      "endTime": Self.iso(end),
      "duration": secs,
      "totalCost": 0,
      "type": VibeCallKit.str(payload["type"]) ?? "voiceCall",
    ]
    if let n = Int(callId) { body["callId"] = n } else { body["callId"] = callId }
    // Backend 400 "endedById is required" without it (memory #6 follow-up). On this path the
    // RECEIVER ends the call.
    if let by = VibeCallKit.str(payload["receiverId"]) ?? VibeCallConfig.userId {
      body["endedById"] = by
    }
    if let doc = VibeCallKit.str(payload["calleridDocID"]) { body["calleridDocID"] = doc }
    // Same key as Dart's CallApi.endCall: the backend dedupes a native + Dart double end.
    post(
      "/api/call/Callend", body, idempotencyKey: "callend:\(callId)",
      label: "Callend[\(status)] \(callId)", queueOnFailure: true)
  }

  /// POST /api/UpdateCall {status: ongoing} right at CXAnswerCallAction (RN). answeredDeviceId
  /// lets the backend exclude THIS device from CALL_ANSWERED_ELSEWHERE even when the request
  /// falls back to the default token (no session sid to resolve). No startTime: the server
  /// stamps its own clock (E-87), a skewed phone clock must not move the billing start.
  /// `onFailure` (main thread) runs when the request did not land and a retry may: network,
  /// timeout, 5xx, or 401/403 after the default-token retry (I1: Dart sends it again).
  func updateCallStatus(
    payload: [String: Any], status: String, onFailure: ((String) -> Void)? = nil
  ) {
    guard
      let callId = VibeCallKit.str(payload["callId"]) ?? VibeCallKit.str(payload["call_id"])
    else { return }
    var body: [String: Any] = [
      "status": status,
      "callerId": VibeCallKit.str(payload["callerId"]) ?? "",
      "receiverId": VibeCallKit.str(payload["receiverId"]) ?? "",
      "type": VibeCallKit.str(payload["type"]) ?? "voiceCall",
      "category": VibeCallKit.str(payload["category"]) ?? "",
    ]
    if let n = Int(callId) { body["callId"] = n } else { body["callId"] = callId }
    if let device = VibeCallConfig.deviceId {
      body["answeredDeviceId"] = device
      body["deviceInfo"] = ["deviceId": device, "platform": "ios"]
    }
    post(
      "/api/UpdateCall", body, idempotencyKey: nil, label: "UpdateCall[\(status)] \(callId)",
      queueOnFailure: false,
      onFailure: onFailure.map { report in { DispatchQueue.main.async { report(callId) } } })
  }

  /// Talk Now: POST /api/instant-call/host-accept {sessionId} at CXAnswerCallAction (the ring is
  /// an instant-call session; the backend creates the call record, billed at the Talk Now
  /// rates). `onSuccess` (main thread) gets the record's id. `onFailure` (main thread) runs on
  /// ANY failure, a refusal too (another host took it, cancelled): Dart decides.
  func instantHostAccept(
    sessionId: String, onSuccess: @escaping (String) -> Void, onFailure: @escaping () -> Void
  ) {
    post(
      "/api/instant-call/host-accept", ["sessionId": sessionId], idempotencyKey: nil,
      label: "host-accept \(sessionId)", queueOnFailure: false,
      onFailure: { DispatchQueue.main.async { onFailure() } },
      reportAllFailures: true,
      onSuccess: { data in
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let record = VibeCallKit.str(json?["callId"]) else {
          DispatchQueue.main.async { onFailure() }
          return
        }
        DispatchQueue.main.async { onSuccess(record) }
      })
  }

  /// Talk Now: POST /api/instant-call/host-decline {sessionId}, so the server rings the next
  /// host at once. Best effort: its own ring window moves on anyway.
  func instantHostDecline(sessionId: String) {
    post(
      "/api/instant-call/host-decline", ["sessionId": sessionId], idempotencyKey: nil,
      label: "host-decline \(sessionId)", queueOnFailure: false)
  }

  func drainFailedEnds() -> [[String: Any]] {
    let list = UserDefaults.standard.array(forKey: failedKey) as? [[String: Any]] ?? []
    UserDefaults.standard.removeObject(forKey: failedKey)
    return list
  }

  // MARK: -

  private func post(
    _ path: String, _ body: [String: Any], idempotencyKey: String?, label: String,
    queueOnFailure: Bool, onFailure: (() -> Void)? = nil, token: String? = nil,
    isRetry: Bool = false, reportAllFailures: Bool = false,
    onSuccess: ((Data?) -> Void)? = nil
  ) {
    guard let url = URL(string: VibeCallConfig.apiBaseUrl + path),
      let json = try? JSONSerialization.data(withJSONObject: body)
    else {
      onFailure?()
      return
    }
    let bearer = token ?? VibeCallConfig.authToken ?? VibeCallConfig.defaultToken
    var req = URLRequest(url: url, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.httpBody = json
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // JS-parity headers (memory #6): the backend routes/parses these.
    req.setValue(VibeCallConfig.appPlatform, forHTTPHeaderField: "x-ce-app")
    req.setValue("ios", forHTTPHeaderField: "x-platform")
    req.setValue("ios", forHTTPHeaderField: "x-ce-platform")
    req.setValue("json", forHTTPHeaderField: "x-delivery-method")
    if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    if let idempotencyKey { req.setValue(idempotencyKey, forHTTPHeaderField: "x-idempotency-key") }

    var bg: UIBackgroundTaskIdentifier = .invalid
    bg = UIApplication.shared.beginBackgroundTask(withName: label) {
      UIApplication.shared.endBackgroundTask(bg)
      bg = .invalid
    }
    URLSession.shared.dataTask(with: req) { data, response, error in
      defer { UIApplication.shared.endBackgroundTask(bg) }
      let code = (response as? HTTPURLResponse)?.statusCode ?? -1
      // ALWAYS log the native HTTP status. It is what found the 405 (memory #6).
      NSLog(
        "[VibeCallNetwork] CALLTRACE %@ → HTTP %ld retry=%d err=%@",
        label, code, isRetry ? 1 : 0, error?.localizedDescription ?? "-")
      if (200..<300).contains(code) {
        onSuccess?(data)
        return
      }
      if code == 401 || code == 403, !isRetry,
        let fallback = VibeCallConfig.defaultToken, fallback != bearer
      {
        self.post(
          path, body, idempotencyKey: idempotencyKey, label: label,
          queueOnFailure: queueOnFailure, onFailure: onFailure, token: fallback, isRetry: true,
          reportAllFailures: reportAllFailures, onSuccess: onSuccess)
        return
      }
      if let data, let text = String(data: data, encoding: .utf8) {
        NSLog("[VibeCallNetwork] %@ body: %@", label, text)
      }
      // Network / 5xx / auth: keep it for Dart's PendingDeclineQueue. A 4xx like 400/404/409
      // is final (call already closed): replaying can never succeed.
      let retryable =
        code == -1 || code >= 500 || code == 401 || code == 403 || code == 408 || code == 429
      if queueOnFailure, retryable {
        DispatchQueue.main.async { self.rememberFailed(body) }
      }
      if retryable || reportAllFailures { onFailure?() }
    }.resume()
  }

  private func rememberFailed(_ body: [String: Any]) {
    var list = UserDefaults.standard.array(forKey: failedKey) as? [[String: Any]] ?? []
    list.append(body)
    if list.count > 20 { list.removeFirst(list.count - 20) }
    UserDefaults.standard.set(list, forKey: failedKey)  // plist-safe: strings and numbers only
  }

  private static func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
  }
}
