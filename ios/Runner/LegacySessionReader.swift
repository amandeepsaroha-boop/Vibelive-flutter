import CryptoKit
import Flutter
import Foundation
import Security

/// Read-only access to the session the React Native build left on this device, so the first
/// Flutter launch after the store update continues it instead of asking to log in.
/// Dart: `lib/core/session/legacy_session_migration.dart`.
///
/// Nothing here writes or deletes: RN's data stays as it was (a rollback keeps working).
///
/// - Tokens: `expo-secure-store` — Keychain generic passwords, service "app:no-auth" (older
///   builds: "app"), account = the key's UTF-8 bytes. Same bundle id and team, so readable.
/// - Everything else (and a copy of the tokens since 2026-05): AsyncStorage —
///   `Application Support/<bundle id>/RCTAsyncLocalStorage_V1/manifest.json`; values over
///   1024 characters live in a file named after the key's MD5.
///
/// `locked` is true when the data exists but can't be read yet (a VoIP push started the app
/// before the first unlock): Dart then tries again on the next launch.
enum LegacySessionReader {
  static let channelName = "com.angrymamba.vibelive/legacy_session"

  private static let tokenKeys = ["access_token", "refresh_token"]
  private static let asyncKeys = ["access_token", "refresh_token", "auth_user", "auth_expert", "device_id"]
  private static let keychainServices = ["app:no-auth", "app"]
  /// RN `languageStep.service`: the language question answered or skipped, per user.
  private static let languageDonePrefix = "@language_step_done:"

  static func install(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let out = read()
        DispatchQueue.main.async { result(out) }
      }
    }
  }

  private static func read() -> [String: Any] {
    var secure: [String: String] = [:]
    var locked = false
    for key in tokenKeys {
      switch keychainValue(key) {
      case .value(let v): secure[key] = v
      case .locked: locked = true
      case .missing: break
      }
    }
    let (async, asyncLocked) = asyncStorage()
    return ["secure": secure, "async": async, "locked": locked || asyncLocked]
  }

  private enum KeychainRead { case value(String), locked, missing }

  private static func keychainValue(_ key: String) -> KeychainRead {
    var sawLocked = false
    for service in keychainServices {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: Data(key.utf8),
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecSuccess, let data = item as? Data,
        let text = String(data: data, encoding: .utf8), !text.isEmpty
      {
        return .value(text)
      }
      if status == errSecInteractionNotAllowed { sawLocked = true }
    }
    return sawLocked ? .locked : .missing
  }

  /// (values, locked)
  private static func asyncStorage() -> ([String: String], Bool) {
    let fm = FileManager.default
    var dirs: [URL] = []
    if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      let bundle = Bundle.main.bundleIdentifier
    {
      dirs.append(support.appendingPathComponent(bundle).appendingPathComponent("RCTAsyncLocalStorage_V1"))
    }
    // Before AsyncStorage moved it (old installs not opened since).
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      dirs.append(docs.appendingPathComponent("RCTAsyncLocalStorage_V1"))
    }
    for dir in dirs {
      let manifestURL = dir.appendingPathComponent("manifest.json")
      guard fm.fileExists(atPath: manifestURL.path) else { continue }
      guard let data = try? Data(contentsOf: manifestURL) else { return ([:], true) }
      guard let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        continue
      }
      var out: [String: String] = [:]
      let keys = asyncKeys + manifest.keys.filter { $0.hasPrefix(languageDonePrefix) }
      for key in keys {
        guard let entry = manifest[key] else { continue }
        if let text = entry as? String {
          if !text.isEmpty { out[key] = text }
        } else if entry is NSNull {
          let file = dir.appendingPathComponent(md5(key))
          if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
            out[key] = text
          }
        }
      }
      return (out, false)
    }
    return ([:], false)
  }

  private static func md5(_ key: String) -> String {
    Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
