import Foundation
import Darwin
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

final class ICloudDriveChannel {
  private static let worker = DispatchQueue(label: "io.github.mylxsw.marginmind.icloud")
  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let accountEvents: ICloudAccountEvents
  init(messenger: FlutterBinaryMessenger, store: ICloudDriveStore? = nil) {
    accountEvents = ICloudAccountEvents()
    events = FlutterEventChannel(name: "marginmind/icloud_account", binaryMessenger: messenger)
    events.setStreamHandler(accountEvents)
    channel = FlutterMethodChannel(name: "marginmind/icloud_drive", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      // Capture only serializable arguments, never a live file coordinator.
      Self.worker.async {
        do {
          let value = try Self.handle(call, store: store)
          DispatchQueue.main.async { result(value) }
        } catch {
          let code = Self.errorCode(error)
          DispatchQueue.main.async { result(FlutterError(code: code, message: nil, details: nil)) }
        }
      }
    }
  }

  static func errorCode(_ error: Error) -> String {
    if let failure = error as? ICloudDriveFailure { return failure.rawValue }
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain {
      if [Int(ENOSPC), Int(EDQUOT)].contains(error.code) { return "quota" }
      if [Int(EACCES), Int(EPERM)].contains(error.code) { return "permission" }
    }
    if error.domain == NSCocoaErrorDomain {
      if error.code == NSFileWriteOutOfSpaceError { return "quota" }
      if [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return "permission" }
    }
    return "unavailable"
  }

  static func handle(_ call: FlutterMethodCall, store supplied: ICloudDriveStore? = nil) throws -> Any? {
    guard let container = supplied?.container ?? ICloudDriveStore.configuredContainer() else {
      if call.method == "configuration" { return nil }
      throw ICloudDriveFailure.unavailable
    }
    if call.method == "configuration" { return container }
    guard let args = call.arguments as? [String: Any], args["container"] as? String == container else {
      throw ICloudDriveFailure.invalidResponse
    }
    let store = supplied ?? ICloudDriveStore.production(container: container)
    if call.method == "account" { return try store.accountIdentity() }
    guard let path = args["path"] as? String, let account = args["account"] as? String else {
      throw ICloudDriveFailure.invalidResponse
    }
    switch call.method {
    case "prepare": try store.prepare(path, expected: account); return nil
    case "list": return try store.list(path, expected: account)
    case "read": return try store.read(path, expected: account).map { FlutterStandardTypedData(bytes: $0) }
    case "create", "uploaded":
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else { throw ICloudDriveFailure.invalidResponse }
      if call.method == "uploaded" { return try store.uploaded(path, bytes: bytes.data, expected: account) }
      try store.create(path, bytes: bytes.data, expected: account); return nil
    default: return FlutterMethodNotImplemented
    }
  }
}

/// Main-queue invalidation bypasses the file worker, which may be waiting for
/// iCloud downloads. No token or account identifier is sent to the UI.
final class ICloudAccountEvents: NSObject, FlutterStreamHandler {
  private let center: NotificationCenter
  private var observer: NSObjectProtocol?
  init(center: NotificationCenter = .default) { self.center = center; super.init() }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stop()
    observer = center.addObserver(forName: NSNotification.Name.NSUbiquityIdentityDidChange,
      object: nil, queue: .main) { _ in events(true) }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { stop(); return nil }
  private func stop() { if let observer { center.removeObserver(observer) }; observer = nil }
  deinit { stop() }
}
