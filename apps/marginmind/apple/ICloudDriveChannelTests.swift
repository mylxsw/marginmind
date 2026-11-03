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
      "container": "iCloud.test", "path": "foliarc-v2/" + String(repeating: "a", count: 64) + "/library.json", "account": "account"
    ]))) { reply in
      XCTAssertTrue(Thread.isMainThread)
      let error = codec.decodeEnvelope(reply!) as? FlutterError
      XCTAssertEqual(error?.code, "unavailable")
      XCTAssertNil(error?.message); XCTAssertNil(error?.details)
      failure.fulfill()
    }
    withExtendedLifetime(channel) { wait(for: [success, failure], timeout: 5) }
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
