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
  // Main-queue registry retains cancelled entries until the serial worker exits.
  // This bounds queued payloads even if container resolution cannot be interrupted.
  private var requests: [String: Request] = [:]
  private final class Request {
    let operation = ICloudOperation()
    var reply: FlutterResult?
    var timer: DispatchWorkItem?
    init(_ reply: @escaping FlutterResult) { self.reply = reply }
    func finish(_ value: Any?) {
      timer?.cancel(); timer = nil
      let callback = reply; reply = nil
      callback?(value)
    }
  }

  init(messenger: FlutterBinaryMessenger, store: ICloudDriveStore? = nil,
       timeout: TimeInterval = 30, worker: DispatchQueue = ICloudDriveChannel.worker) {
    accountEvents = ICloudAccountEvents()
    events = FlutterEventChannel(name: "marginmind/icloud_account", binaryMessenger: messenger)
    events.setStreamHandler(accountEvents)
    channel = FlutterMethodChannel(name: "marginmind/icloud_drive", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      // Flutter delivers this handler on the main queue. Cancellation and timers
      // bypass the file worker, including a blocked container lookup.
      if call.method == "configuration" {
        result(store?.container ?? ICloudDriveStore.configuredContainer()); return
      }
      guard let args = call.arguments as? [String: Any],
            let id = args["requestId"] as? String, id.range(of: #"\A[a-f0-9]{32}\z"#, options: .regularExpression) != nil else {
        result(FlutterError(code: "invalidResponse", message: nil, details: nil)); return
      }
      if call.method == "cancel" {
        if let request = self.requests[id] {
          request.operation.cancel()
          request.finish(FlutterError(code: "cancelled", message: nil, details: nil))
        }
        result(nil); return
      }
      guard self.requests[id] == nil, self.requests.count < 8 else {
        result(FlutterError(code: "unavailable", message: nil, details: nil)); return
      }
      let request = Request(result)
      self.requests[id] = request
      let timer = DispatchWorkItem { [weak request] in
        guard let request else { return }
        request.operation.cancel(.timedOut)
        request.finish(FlutterError(code: "timedOut", message: nil, details: nil))
      }
      request.timer = timer
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
      worker.async { [weak self] in
        let value: Any?
        do {
          try request.operation.check()
          value = try Self.handle(call, store: store, operation: request.operation)
        } catch {
          value = FlutterError(code: Self.errorCode(error), message: nil, details: nil)
        }
        DispatchQueue.main.async {
          request.finish(value)
          self?.requests.removeValue(forKey: id)
        }
      }
    }
  }

  deinit {
    for request in requests.values {
      request.operation.cancel()
      request.finish(FlutterError(code: "cancelled", message: nil, details: nil))
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

  static func handle(_ call: FlutterMethodCall, store supplied: ICloudDriveStore? = nil,
                     operation: ICloudOperation = ICloudOperation()) throws -> Any? {
    guard let container = supplied?.container ?? ICloudDriveStore.configuredContainer() else {
      if call.method == "configuration" { return nil }
      throw ICloudDriveFailure.unavailable
    }
    if call.method == "configuration" { return container }
    guard let args = call.arguments as? [String: Any], args["container"] as? String == container else {
      throw ICloudDriveFailure.invalidResponse
    }
    let store = supplied ?? ICloudDriveStore.production(container: container)
    if call.method == "account" { return try store.accountIdentity(operation: operation) }
    guard let path = args["path"] as? String, let account = args["account"] as? String else {
      throw ICloudDriveFailure.invalidResponse
    }
    switch call.method {
    case "prepare": try store.prepare(path, expected: account, operation: operation); return nil
    case "list": return try store.list(path, expected: account, operation: operation)
    case "read": return try store.read(path, expected: account, operation: operation).map { FlutterStandardTypedData(bytes: $0) }
    case "create", "uploaded":
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else { throw ICloudDriveFailure.invalidResponse }
      if call.method == "uploaded" { return try store.uploaded(path, bytes: bytes.data, expected: account, operation: operation) }
      try store.create(path, bytes: bytes.data, expected: account, operation: operation); return nil
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
