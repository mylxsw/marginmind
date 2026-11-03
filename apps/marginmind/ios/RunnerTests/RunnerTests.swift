import Flutter
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testKeychainRoundTripAndValidation() {
    let account = "test-" + UUID().uuidString
    func invoke(_ method: String, _ args: [String: Any]) -> Any? {
      var value: Any?
      MobileSecrets.handle(FlutterMethodCall(methodName: method, arguments: args)) { value = $0 }
      return value
    }
    defer { _ = invoke("delete", ["account": account]) }
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertNil(invoke("write", ["account": account, "value": "secret"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "secret")
    XCTAssertNil(invoke("write", ["account": account, "value": "updated"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "updated")
    XCTAssertNil(invoke("delete", ["account": account]))
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertTrue(invoke("write", ["account": ""]) is FlutterError)
    XCTAssertTrue(invoke("write", ["account": account]) is FlutterError)
  }
  func testIncomingURLProvidersAndAcknowledgement() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try IncomingShareStore(root: directory)
    let title = NSItemProvider(object: "An article" as NSString)
    let url = NSItemProvider(object: URL(string: "https://example.com/article")! as NSURL)
    try await IncomingShareLoader.receive([title, url], title: "Article", store: store)
    let batches = try store.pending()
    XCTAssertEqual(batches.count, 1)
    XCTAssertEqual(batches.first?["url"] as? String, "https://example.com/article")
    XCTAssertEqual(batches.first?["title"] as? String, "Article")
    XCTAssertEqual(try store.pending().count, 1)
    let id = batches[0]["id"] as! String
    try store.complete(id)
    try store.complete(id)
    XCTAssertTrue(try store.pending().isEmpty)
  }

  func testIncomingProviderFilesAreCopiedBeforeProviderURLExpires() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try IncomingShareStore(root: directory.appendingPathComponent("inbox"))
    let original = directory.appendingPathComponent("source.epub")
    try Data("provider fixture".utf8).write(to: original)
    let provider = NSItemProvider()
    provider.suggestedName = "book.epub"
    provider.registerFileRepresentation(forTypeIdentifier: "org.idpf.epub-container", fileOptions: [], visibility: .all) { callback in
      callback(original, false, nil)
      return nil
    }
    try await IncomingShareLoader.receive([provider], title: nil, store: store)
    try FileManager.default.removeItem(at: original)
    let batch = try store.pending()[0]
    let files = batch["files"] as! [[String: String]]
    XCTAssertEqual(files[0]["name"], "book.epub")
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: files[0]["path"]!)), Data("provider fixture".utf8))
    try store.complete(batch["id"] as! String)
    XCTAssertFalse(FileManager.default.fileExists(atPath: files[0]["path"]!))
  }

  func testIncomingUnsupportedAndOversizedBatchesPublishFailureWithoutFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try IncomingShareStore(root: directory)
    do {
      try await IncomingShareLoader.receive([NSItemProvider(object: "not a URL" as NSString)], title: nil, store: store)
      XCTFail("Unsupported content accepted")
    } catch IncomingShareStore.Failure.unsupported {}
    let failed = try store.pending()[0]
    XCTAssertEqual(failed["error"] as? String, "unsupported")
    XCTAssertTrue((failed["files"] as! [[String: String]]).isEmpty)
    try store.complete(failed["id"] as! String)
    do {
      try await IncomingShareLoader.receive(Array(repeating: NSItemProvider(object: "https://example.com" as NSString), count: 21), title: nil, store: store)
      XCTFail("Oversized batch accepted")
    } catch IncomingShareStore.Failure.limit {}
    XCTAssertEqual(try store.pending()[0]["error"] as? String, "limit")
  }

  func testIncomingFileURLRepresentationUsesTheCopiedDocument() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try IncomingShareStore(root: directory.appendingPathComponent("inbox"))
    let original = directory.appendingPathComponent("shared.md")
    try Data("# Shared document".utf8).write(to: original)
    let provider = NSItemProvider(object: original as NSURL)
    try await IncomingShareLoader.receive([provider], title: nil, store: store)
    let files = try store.pending()[0]["files"] as! [[String: String]]
    XCTAssertEqual(files[0]["name"], "shared.md")
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: files[0]["path"]!)), Data("# Shared document".utf8))
  }
}
