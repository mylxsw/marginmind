import Foundation
import XCTest
#if os(macOS)
import FlutterMacOS
#if !FOLIARC_STANDALONE_TEST
@testable import MarginMind
#endif
#else
import Flutter
#if !FOLIARC_STANDALONE_TEST
@testable import Runner
#endif
#endif

final class ICloudDriveChannelTests: XCTestCase {
  func testIdentityEventsContainNoTokenAndCancelObserver() {
    let center = NotificationCenter()
    let stream = ICloudAccountEvents(center: center)
    var values: [Bool] = []
    XCTAssertNil(stream.onListen(withArguments: nil) { value in
      XCTAssertTrue(Thread.isMainThread)
      values.append(value as! Bool)
    })
    center.post(name: NSNotification.Name.NSUbiquityIdentityDidChange, object: "private-token")
    XCTAssertEqual(values, [true])
    XCTAssertNil(stream.onListen(withArguments: nil) { value in values.append(value as! Bool) })
    center.post(name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
    XCTAssertEqual(values, [true, true])
    XCTAssertNil(stream.onCancel(withArguments: nil))
    center.post(name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
    XCTAssertEqual(values, [true, true])
  }

  func testWorkerRepliesOnMainThreadAndRedactsNativeErrors() throws {
    let messenger = DriveTestMessenger()
    let store = ICloudDriveStore(container: "iCloud.test", root: {
      throw NSError(domain: "private path and account", code: 42)
    }, account: { "account" }, state: { _ in (true, false, false) }, download: { _ in })
    let channel = ICloudDriveChannel(messenger: messenger, store: store)
    let success = expectation(description: "configuration"), failure = expectation(description: "redacted error")
    let codec = FlutterStandardMethodCodec.sharedInstance()
    messenger.handler?(codec.encode(FlutterMethodCall(methodName: "configuration", arguments: nil))) { reply in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(codec.decodeEnvelope(reply!) as? String, "iCloud.test")
      success.fulfill()
    }
    messenger.handler?(codec.encode(FlutterMethodCall(methodName: "read", arguments: [
      "requestId": String(repeating: "a", count: 32), "container": "iCloud.test", "path": "foliarc-v2/" + String(repeating: "a", count: 64) + "/library.json", "account": "account"
    ]))) { reply in
      XCTAssertTrue(Thread.isMainThread)
      let error = codec.decodeEnvelope(reply!) as? FlutterError
      XCTAssertEqual(error?.code, "unavailable")
      XCTAssertNil(error?.message); XCTAssertNil(error?.details)
      failure.fulfill()
    }
    withExtendedLifetime(channel) { wait(for: [success, failure], timeout: 5) }
  }

  func testCancellationReleasesReplyBeforeWorkerAndSuppressesLateWrite() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let entered = expectation(description: "container lookup entered")
    let gate = DispatchSemaphore(value: 0)
    let store = ICloudDriveStore(container: "iCloud.test", root: {
      entered.fulfill(); gate.wait(); return root
    }, account: { "account" }, state: { _ in (true, true, false) }, download: { _ in })
    let messenger = DriveTestMessenger(), queue = DispatchQueue(label: "cancel-test")
    let channel = ICloudDriveChannel(messenger: messenger, store: store, worker: queue)
    let id = String(repeating: "a", count: 32)
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let cancelled = expectation(description: "cancelled reply")
    var replies = 0
    messenger.handler?(codec.encode(FlutterMethodCall(methodName: "prepare", arguments: [
      "requestId": id, "container": "iCloud.test", "account": "account",
      "path": "foliarc-v2/" + String(repeating: "a", count: 64) + "/commits"
    ]))) { reply in
      replies += 1
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual((codec.decodeEnvelope(reply!) as? FlutterError)?.code, "cancelled")
      cancelled.fulfill()
    }
    wait(for: [entered], timeout: 5)
    for _ in 0..<2 {
      messenger.handler?(codec.encode(FlutterMethodCall(methodName: "cancel", arguments: ["requestId": id]))) { reply in
        XCTAssertNil(codec.decodeEnvelope(reply!))
      }
    }
    // This completes while the physical worker is still blocked in root().
    wait(for: [cancelled], timeout: 1)
    let drained = expectation(description: "worker drained")
    gate.signal()
    queue.async { DispatchQueue.main.async { drained.fulfill() } }
    wait(for: [drained], timeout: 5)
    XCTAssertEqual(replies, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    withExtendedLifetime(channel) {}
  }

  func testTimeoutQueuedCancellationAndBoundedRequests() throws {
    let messenger = DriveTestMessenger(), queue = DispatchQueue(label: "timeout-test")
    let gate = DispatchSemaphore(value: 0)
    queue.async { gate.wait() }
    var calls = 0
    let store = ICloudDriveStore(container: "iCloud.test", root: { URL(fileURLWithPath: "/unused") },
      account: { calls += 1; return "account" }, state: { _ in (true, true, false) }, download: { _ in })
    let channel = ICloudDriveChannel(messenger: messenger, store: store, timeout: 0.02, worker: queue)
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let expired = expectation(description: "queued requests time out")
    expired.expectedFulfillmentCount = 8
    var replies = 0
    for index in 0..<8 {
      messenger.handler?(codec.encode(FlutterMethodCall(methodName: "account", arguments: [
        "container": "iCloud.test", "requestId": String(repeating: String(index), count: 32)
      ]))) { reply in
        replies += 1
        XCTAssertEqual((codec.decodeEnvelope(reply!) as? FlutterError)?.code, "timedOut")
        expired.fulfill()
      }
    }
    wait(for: [expired], timeout: 5)
    // Logical completion does not free the physical queue's payload budget.
    for id in [String(repeating: "a", count: 32), String(repeating: "0", count: 32), "invalid"] {
      messenger.handler?(codec.encode(FlutterMethodCall(methodName: "account", arguments: [
        "container": "iCloud.test", "requestId": id
      ]))) { reply in
        XCTAssertEqual((codec.decodeEnvelope(reply!) as? FlutterError)?.code,
          id == "invalid" ? "invalidResponse" : "unavailable")
      }
    }
    // Configuration and cancellation still work with a saturated file queue.
    messenger.handler?(codec.encode(FlutterMethodCall(methodName: "configuration", arguments: nil))) { reply in
      XCTAssertEqual(codec.decodeEnvelope(reply!) as? String, "iCloud.test")
    }
    let drained = expectation(description: "worker drained")
    gate.signal()
    queue.async { DispatchQueue.main.async { drained.fulfill() } }
    wait(for: [drained], timeout: 5)
    XCTAssertEqual(replies, 8); XCTAssertEqual(calls, 0)
    let success = expectation(description: "retry after drain")
    messenger.handler?(codec.encode(FlutterMethodCall(methodName: "account", arguments: [
      "container": "iCloud.test", "requestId": String(repeating: "b", count: 32)
    ]))) { reply in
      XCTAssertEqual(codec.decodeEnvelope(reply!) as? String, "account"); success.fulfill()
    }
    wait(for: [success], timeout: 5)
    XCTAssertEqual(calls, 1)
    withExtendedLifetime(channel) {}
  }

  func testStoreCancellationChecksPublicationAndCoordinatorAttachment() throws {
    let operation = ICloudOperation()
    let coordinator = TrackingCoordinator(filePresenter: nil)
    try operation.attach(coordinator)
    operation.cancel(.timedOut)
    XCTAssertEqual(coordinator.cancellations, 1)
    XCTAssertThrowsError(try operation.check()) { XCTAssertEqual($0 as? ICloudDriveFailure, .timedOut) }
    operation.detach()
    operation.cancel() // First reason remains stable.
    XCTAssertThrowsError(try operation.attach(coordinator)) { XCTAssertEqual($0 as? ICloudDriveFailure, .timedOut) }
    XCTAssertEqual(coordinator.cancellations, 2)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let base = "foliarc-v2/" + String(repeating: "a", count: 64)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(base), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let publish = ICloudOperation()
    var checks = 0
    let store = ICloudDriveStore(container: "iCloud.test", root: { root }, account: {
      checks += 1
      if checks == 4 { publish.cancel() } // After temporary bytes have been flushed.
      return "account"
    }, state: { _ in (true, true, false) }, download: { _ in XCTFail("No download expected") })
    XCTAssertThrowsError(try store.create(base + "/library.json", bytes: Data("{}".utf8), expected: "account", operation: publish)) {
      XCTAssertEqual($0 as? ICloudDriveFailure, .cancelled)
    }
    XCTAssertEqual(checks, 4)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(base).path), [])
    XCTAssertThrowsError(try store.accountIdentity(operation: publish))
    XCTAssertThrowsError(try store.prepare(base + "/commits", expected: "account", operation: publish))
  }

  func testChannelRoutesImmutableBytesAndUploadState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var confirmed = false
    let store = ICloudDriveStore(container: "iCloud.test", root: { root }, account: { "account" },
      state: { _ in (true, confirmed, false) }, download: { _ in })
    let base = "foliarc-v2/" + String(repeating: "a", count: 64)
    let bytes = Data("{}".utf8)
    func invoke(_ method: String, _ path: String = "", _ account: String = "account") throws -> Any? {
      try ICloudDriveChannel.handle(FlutterMethodCall(methodName: method, arguments: [
        "container": "iCloud.test", "path": path, "account": account,
        "bytes": FlutterStandardTypedData(bytes: bytes)
      ]), store: store)
    }
    XCTAssertEqual(try invoke("configuration") as? String, "iCloud.test")
    XCTAssertEqual(try invoke("account") as? String, "account")
    XCTAssertNil(try invoke("prepare", base + "/commits"))
    XCTAssertEqual(try invoke("list", base + "/commits") as? [String], [])
    XCTAssertNil(try invoke("read", base + "/library.json"))
    XCTAssertNil(try invoke("create", base + "/library.json"))
    XCTAssertEqual((try invoke("read", base + "/library.json") as? FlutterStandardTypedData)?.data, bytes)
    XCTAssertEqual(try invoke("uploaded", base + "/library.json") as? Bool, false)
    confirmed = true
    XCTAssertEqual(try invoke("uploaded", base + "/library.json") as? Bool, true)
    XCTAssertThrowsError(try invoke("read", base + "/library.json", "old")) {
      XCTAssertEqual(ICloudDriveChannel.errorCode($0), "accountChanged")
    }
    XCTAssertThrowsError(try invoke("read", "../outside")) {
      XCTAssertEqual(ICloudDriveChannel.errorCode($0), "invalidResponse")
    }
    XCTAssertTrue((try invoke("unknown") as? NSObject) === FlutterMethodNotImplemented)
    let invalid: [Any] = [[:], ["container": "wrong"], ["container": "iCloud.test"],
                         ["container": "iCloud.test", "path": base + "/library.json", "account": "account"]]
    for args in invalid {
      XCTAssertThrowsError(try ICloudDriveChannel.handle(FlutterMethodCall(methodName: "create", arguments: args), store: store))
    }
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)), "quota")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)), "permission")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSPOSIXErrorDomain, code: 28)), "quota")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSPOSIXErrorDomain, code: 13)), "permission")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSPOSIXErrorDomain, code: 5)), "unavailable")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: "private", code: 1)), "unavailable")
    XCTAssertEqual(ICloudDriveChannel.errorCode(NSError(domain: NSCocoaErrorDomain, code: 1)), "unavailable")
  }
}

private final class DriveTestMessenger: NSObject, FlutterBinaryMessenger {
  var handler: FlutterBinaryMessageHandler?
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    self.handler = handler; return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
}

private final class TrackingCoordinator: NSFileCoordinator {
  var cancellations = 0
  override func cancel() { cancellations += 1; super.cancel() }
}
