import Cocoa
import FlutterMacOS
import XCTest
import CoreText
import WebKit
import PDFKit
import Network
import Security
import PDFKit

@testable import MarginMind

@MainActor
class RunnerTests: XCTestCase {
  func testSpeechChannelValidatesInputAndStopsBeforeSpeaking() {
    var events = [String]()
    var reply: Any?
    let stop = { events.append("stop") }
    let speak: (String, String) -> Bool = { term, language in
      events.append("speak:\(term):\(language)"); return true
    }
    SpeechChannel.handle(FlutterMethodCall(methodName: "speak", arguments: ["text": "meticulous", "language": "en-GB"]),
      result: { reply = $0 }, stop: stop, speak: speak)
    XCTAssertNil(reply)
    XCTAssertEqual(events, ["stop", "speak:meticulous:en-GB"])
    SpeechChannel.handle(FlutterMethodCall(methodName: "stop", arguments: nil), result: { reply = $0 }, stop: stop, speak: speak)
    XCTAssertEqual(events.last, "stop")
    let invalid: [Any?] = [nil, [:], ["text": "", "language": "en"], ["text": String(repeating: "x", count: 65), "language": "en"]]
    for arguments in invalid {
      SpeechChannel.handle(FlutterMethodCall(methodName: "speak", arguments: arguments), result: { reply = $0 }, stop: stop, speak: speak)
      XCTAssertEqual((reply as? FlutterError)?.code, "invalid")
    }
    SpeechChannel.handle(FlutterMethodCall(methodName: "speak", arguments: ["text": "word", "language": "en-US"]),
      result: { reply = $0 }, stop: stop, speak: { _, _ in false })
    XCTAssertEqual((reply as? FlutterError)?.code, "speech")
    SpeechChannel.handle(FlutterMethodCall(methodName: "unknown", arguments: nil), result: { reply = $0 }, stop: stop, speak: speak)
    XCTAssertTrue((reply as? NSObject) === FlutterMethodNotImplemented)
  }

  func testBrowserPdfPrintIsAsyncPaginatedAndCleansUpAfterStaleOrCancelledJobs() async throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let web = WKWebView(frame: window.contentView!.bounds)
    window.contentView!.addSubview(web)
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    let loaded = expectation(description: "browser print fixture loaded")
    let navigation = BrowserPrintNavigationWaiter(loaded)
    web.navigationDelegate = navigation
    let paragraphs = (0..<80).map { "<p>Paragraph \($0), testing a genuinely paginated web document with readable text.</p>" }.joined()
    web.loadHTMLString("<html><body><h1>Browser print</h1>\(paragraphs)</body></html>", baseURL: nil)
    await fulfillment(of: [loaded], timeout: 20)
    for mode in ["current", "stale", "cancelled"] {
      let finished = expectation(description: "\(mode) print finished")
      let responsive = expectation(description: "main queue remains responsive")
      var value: Any?
      let job = BrowserPdfPrintJob(web: web, isCurrent: { mode != "stale" },
        didFinish: { finished.fulfill() }, completion: { value = $0 })
      DispatchQueue.main.async { responsive.fulfill() }
      job.start(in: window)
      if mode == "cancelled" { job.cancel() }
      await fulfillment(of: [responsive, finished], timeout: 45)
      if mode == "current" {
        let bytes = try XCTUnwrap((value as? FlutterStandardTypedData)?.data)
        XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(data: bytes)).pageCount, 1)
      } else {
        XCTAssertNotNil(value as? FlutterError)
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: job.target.path))
    }
    withExtendedLifetime(navigation) {}
  }

  func testMapExportChannelValidationAndAllVectorCommands() async throws {
    func invoke(_ method: String, _ arguments: [String: Any]) async -> Any? {
      await withCheckedContinuation { continuation in
        MapExportChannel.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
          continuation.resume(returning: $0)
        }
      }
    }
    let invalid = await invoke("pdf", [:])
    XCTAssertEqual((invalid as? FlutterError)?.code, "invalid_scene")
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let image = FlutterStandardTypedData(bytes: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
    let commands: [[String: Any]] = [
      ["type": "box", "rect": [0.0, 0.0, 300.0, 200.0], "radius": 12.0, "color": 0xFFFFFFFF],
      ["type": "curve", "points": [0.0, 0.0, 20.0, 20.0, 40.0, 20.0, 50.0, 50.0], "color": 0xFF000000, "dashed": true],
      ["type": "curve", "points": [0.0, 0.0, 20.0, 20.0, 40.0, 20.0, 50.0, 50.0], "color": 0xFF000000, "dashed": false],
      ["type": "text", "text": "全路径 Export", "fontSize": 13.0, "x": 10.0, "y": 10.0, "color": 0xFF000000, "bold": true],
      ["type": "image", "bytes": image, "x": 50.0, "y": 50.0, "width": 20.0, "height": 20.0]
    ]
    let pdf = await invoke("pdf", ["width": 300.0, "height": 200.0, "commands": commands])
    let bytes = try XCTUnwrap((pdf as? FlutterStandardTypedData)?.data)
    XCTAssertTrue(try XCTUnwrap(PDFDocument(data: bytes)?.string).contains("全路径"))
    let png = await invoke("png", ["width": 2, "height": 2, "tiles": [["x": 0, "y": 0, "bytes": image]]])
    XCTAssertNotNil(png as? FlutterStandardTypedData)
    let unsupported = await invoke("unknown", ["width": 1, "height": 1])
    XCTAssertNotNil(unsupported)
    let failed = await invoke("pdf", ["width": 1, "height": 1, "commands": [["type": "unknown"]]])
    XCTAssertEqual((failed as? FlutterError)?.code, "export_failed")
  }

  func testMapExportVectorTextAndPNGTilePositions() throws {
    var commands: [[String: Any]] = []
    for i in 0..<500 {
      let y = Double(i * 22 + 20)
      let command: [String: Any] = ["type": "text", "text": "Node \(i) 中文", "x": 20.0, "y": y,
        "width": 400.0, "fontSize": 13.0, "color": 0xFF000000, "serif": i % 2 == 0, "bold": false]
      commands.append(command)
    }
    let bytes = try MapExportChannel.pdf(["width": 500.0, "height": 11100.0, "commands": commands])
    let pdf = try XCTUnwrap(PDFDocument(data: bytes))
    XCTAssertEqual(pdf.pageCount, 1)
    let text = try XCTUnwrap(pdf.string)
    XCTAssertTrue(text.contains("Node 0"))
    XCTAssertTrue(text.contains("Node 499"))
    XCTAssertTrue(text.contains("中文"))
    XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).height, 11100)
    func tile(_ color: NSColor) throws -> FlutterStandardTypedData {
      let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
      context.cgContext.setFillColor(color.cgColor)
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      return FlutterStandardTypedData(bytes: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
    }
    let png = try MapExportChannel.png(["width": 4, "height": 4, "tiles": [
      ["x": 0, "y": 0, "bytes": try tile(.red)], ["x": 2, "y": 2, "bytes": try tile(.blue)]
    ]])
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
    XCTAssertEqual(bitmap.pixelsWide, 4)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).redComponent, 0.9)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 3, y: 3)).blueComponent, 0.9)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 3, y: 0)).alphaComponent, 0)
    XCTAssertThrowsError(try MapExportChannel.png(["width": 20000, "height": 1, "tiles": []]))
    XCTAssertThrowsError(try MapExportChannel.pdf(["width": 0, "height": 1, "commands": []]))
  }

  func testImageClipboardReadsPNGJPEGFinderAndTIFF() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertNil(MainFlutterWindow.readImage(from: board))
    for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType("public.jpeg")] {
      board.clearContents()
      let bytes = Data([1, 2, 3])
      board.setData(bytes, forType: type)
      XCTAssertEqual((MainFlutterWindow.readImage(from: board)?["bytes"] as? FlutterStandardTypedData)?.data, bytes)
    }
    board.clearContents()
    let url = URL(fileURLWithPath: "/tmp/chart.png")
    board.writeObjects([url as NSURL])
    XCTAssertEqual(MainFlutterWindow.readImage(from: board)?["path"] as? String, url.path)
    board.clearContents()
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0))
    board.setData(bitmap.tiffRepresentation, forType: .tiff)
    let png = try XCTUnwrap((MainFlutterWindow.readImage(from: board)?["bytes"] as? FlutterStandardTypedData)?.data)
    XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    board.clearContents()
    board.setString("text only", forType: .string)
    XCTAssertNil(MainFlutterWindow.readImage(from: board))
  }

  func testResearchKeychainRoundTripAndValidation() throws {
    let account = "test-" + UUID().uuidString
    func invoke(_ method: String, _ arguments: [String: String]) -> Any? {
      var value: Any?
      SecretStoreChannel.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value = $0 }
      return value
    }
    defer { _ = invoke("delete", ["account": account]) }
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertNil(invoke("write", ["account": account, "value": "test-value"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "test-value")
    XCTAssertNil(invoke("write", ["account": account, "value": "updated"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "updated")
    XCTAssertNil(invoke("delete", ["account": account]))
    XCTAssertNil(invoke("delete", ["account": account]))
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertNotNil(invoke("read", ["account": ""]) as? FlutterError)
    XCTAssertNotNil(invoke("write", ["account": account]) as? FlutterError)
    XCTAssertNotNil(invoke("unknown", ["account": account]))
  }

  func testLockedKeychainFailsWithoutPromptAndPreservesSecret() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("isolated.keychain").path
    let password = UUID().uuidString
    var keychain: SecKeychain?
    let created = password.withCString {
      SecKeychainCreate(path, UInt32(password.utf8.count), $0, false, nil, &keychain)
    }
    XCTAssertEqual(created, errSecSuccess)
    let isolated = try XCTUnwrap(keychain)
    defer { SecKeychainDelete(isolated) }
    func invoke(_ method: String, value: String? = nil) -> Any? {
      var arguments = ["account": "locked-test"]
      if let value = value { arguments["value"] = value }
      var answer: Any?
      SecretStoreChannel.handle(FlutterMethodCall(methodName: method, arguments: arguments), keychain: isolated) {
        answer = $0
      }
      return answer
    }
    var before: DarwinBoolean = false
    XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&before), errSecSuccess)
    XCTAssertNil(invoke("write", value: "preserved"))
    XCTAssertEqual(invoke("read") as? String, "preserved")
    XCTAssertEqual(SecKeychainLock(isolated), errSecSuccess)
    let started = Date()
    XCTAssertEqual((invoke("read") as? FlutterError)?.code, "keychain_auth_required")
    XCTAssertEqual((invoke("write", value: "must-not-replace") as? FlutterError)?.code, "keychain_auth_required")
    XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    var after: DarwinBoolean = false
    XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&after), errSecSuccess)
    XCTAssertEqual(after.boolValue, before.boolValue)
    let unlocked = password.withCString {
      SecKeychainUnlock(isolated, UInt32(password.utf8.count), $0, true)
    }
    XCTAssertEqual(unlocked, errSecSuccess)
    XCTAssertEqual(invoke("read") as? String, "preserved")
  }

  func testSuccessfulUpdateOfAnUnreadableItemMigratesToAVerifiedReplacement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let password = UUID().uuidString
    var keychain: SecKeychain?
    let created = password.withCString {
      SecKeychainCreate(directory.appendingPathComponent("isolated.keychain").path,
                        UInt32(password.utf8.count), $0, false, nil, &keychain)
    }
    XCTAssertEqual(created, errSecSuccess)
    let isolated = try XCTUnwrap(keychain)
    defer { SecKeychainDelete(isolated) }
    let account = "unreadable-" + UUID().uuidString
    let suite = "marginmind-verified-write-" + UUID().uuidString
    let references = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { references.removePersistentDomain(forName: suite) }
    // The old ACL permits encryption/updates but only a different application
    // may decrypt. A successful update does not mean the key can be read.
    var trusted: SecTrustedApplication?
    XCTAssertEqual(SecTrustedApplicationCreateFromPath("/usr/bin/true", &trusted), errSecSuccess)
    var access: SecAccess?
    XCTAssertEqual(SecAccessCreate("unreadable test item" as CFString,
                                  [try XCTUnwrap(trusted)] as CFArray, &access), errSecSuccess)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.mylxsw.marginmind.research",
      kSecAttrAccount as String: account,
      kSecUseKeychain as String: isolated,
      kSecAttrAccess as String: try XCTUnwrap(access),
      kSecValueData as String: Data("original-test-key".utf8),
    ]
    XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
    func invoke(_ method: String, value: String? = nil) -> Any? {
      var arguments = ["account": account]
      if let value = value { arguments["value"] = value }
      var result: Any?
      SecretStoreChannel.handle(FlutterMethodCall(methodName: method, arguments: arguments),
                                keychain: isolated, references: references) { result = $0 }
      return result
    }
    XCTAssertEqual((invoke("read") as? FlutterError)?.code, "keychain_auth_required")
    let update: [String: Any] = [kSecValueData as String: Data("updated-test-key".utf8)]
    let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: "io.github.mylxsw.marginmind.research",
                               kSecAttrAccount as String: account,
                               kSecMatchSearchList as String: [isolated]]
    XCTAssertEqual(SecItemUpdate(match as CFDictionary, update as CFDictionary), errSecSuccess)
    XCTAssertEqual((invoke("read") as? FlutterError)?.code, "keychain_auth_required")
    XCTAssertNil(invoke("write", value: "replacement-test-key"))
    XCTAssertNotNil(references.string(forKey: "marginmind.secret-store.reference.v1." + account))
    XCTAssertEqual(invoke("read") as? String, "replacement-test-key")
    let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
    var restored: Any?
    SecretStoreChannel.handle(FlutterMethodCall(methodName: "read", arguments: ["account": account]),
                              keychain: isolated, references: reloaded) { restored = $0 }
    XCTAssertEqual(restored as? String, "replacement-test-key")
  }

  func testReplacingAnInaccessibleKeyNeverRequiresChangingItsPermissions() throws {
    let account = "test-" + UUID().uuidString
    let suite = "marginmind-secret-reference-test-" + UUID().uuidString
    let references = try XCTUnwrap(UserDefaults(suiteName: suite))
    let originalReferences = try XCTUnwrap(UserDefaults(suiteName: suite + "-original"))
    let referenceKey = "marginmind.secret-store.reference.v1." + account
    var created = [account]
    defer {
      for item in created {
        SecretStoreChannel.handle(FlutterMethodCall(methodName: "delete", arguments: ["account": item]),
                                  references: originalReferences) { _ in }
      }
      references.removePersistentDomain(forName: suite)
      originalReferences.removePersistentDomain(forName: suite + "-original")
    }
    func invoke(_ method: String, value: String? = nil,
                update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate) -> Any? {
      var arguments = ["account": account]
      if let value = value { arguments["value"] = value }
      var answer: Any?
      SecretStoreChannel.handle(FlutterMethodCall(methodName: method, arguments: arguments),
                                references: references, update: update) { answer = $0 }
      return answer
    }
    XCTAssertNil(invoke("write", value: "old-test-key"))
    for denied in [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled] {
      XCTAssertNil(invoke("write", value: "replacement-test-key", update: { _, _ in
        var allowed: DarwinBoolean = true
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
        XCTAssertFalse(allowed.boolValue)
        return denied
      }))
      let replacement = try XCTUnwrap(references.string(forKey: referenceKey))
      XCTAssertNotEqual(replacement, account)
      XCTAssertFalse(created.contains(replacement))
      created.append(replacement)
      XCTAssertEqual(invoke("read") as? String, "replacement-test-key")
      // The reference survives recreating the store, and contains no API key.
      let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
      var read: Any?
      SecretStoreChannel.handle(FlutterMethodCall(methodName: "read", arguments: ["account": account]),
                                references: reloaded) { read = $0 }
      XCTAssertEqual(read as? String, "replacement-test-key")
      XCTAssertFalse(String(describing: references.persistentDomain(forName: suite)).contains("test-key"))
    }
    var old: Any?
    SecretStoreChannel.handle(FlutterMethodCall(methodName: "read", arguments: ["account": account]),
                              references: originalReferences) { old = $0 }
    XCTAssertEqual(old as? String, "old-test-key")
    XCTAssertNil(invoke("delete"))
    XCTAssertNil(invoke("read")) // Clearing the new key must not resurrect the old one.
    XCTAssertNotNil(references.string(forKey: referenceKey))
    XCTAssertNil(invoke("write", value: "saved-again"))
    XCTAssertEqual(invoke("read") as? String, "saved-again")
  }

  func testKeychainChannelRepliesAsynchronouslyOnMainThread() {
    let replied = expectation(description: "Keychain callback")
    var returned = false
    SecretStoreChannel.handleAsync(FlutterMethodCall(methodName: "read", arguments: ["account": "test-" + UUID().uuidString])) { value in
      XCTAssertTrue(returned)
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNil(value)
      replied.fulfill()
    }
    returned = true
    wait(for: [replied], timeout: 5)
  }

  func testExternalLinksOpenOnlyWebPages() {
    XCTAssertEqual(ExternalLinkChannel.url(from: ["url": "https://example.com/a?b=1"])?.host, "example.com")
    XCTAssertNotNil(ExternalLinkChannel.url(from: ["url": "HTTP://example.com"]))
    for rejected in ["file:///etc/hosts", "javascript:alert(1)", "marginmind://x", "https://", "not a url"] {
      XCTAssertNil(ExternalLinkChannel.url(from: ["url": rejected]), rejected)
    }
    XCTAssertNil(ExternalLinkChannel.url(from: nil))
    var value: Any?
    ExternalLinkChannel.handle(FlutterMethodCall(methodName: "open", arguments: ["url": "file:///tmp"])) { value = $0 }
    XCTAssertNotNil(value as? FlutterError)
    ExternalLinkChannel.handle(FlutterMethodCall(methodName: "other", arguments: nil)) { value = $0 }
    XCTAssertTrue((value as AnyObject) === FlutterMethodNotImplemented)
  }

  func testReleaseRendererWorkaroundIsPackaged() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "FLTEnableImpeller") as? Bool, false)
  }

  func testForwardingToolbarRemainsInvisibleAndButtonsReceiveMouseHits() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1000, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    let target = ToolbarEventSpy()
    window.installFlutterToolbar(eventTarget: target)
    let toolbar = try XCTUnwrap(window.toolbar as? FlutterWindowToolbar)
    window.orderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(toolbar.items.count, 2)
    XCTAssertFalse(try XCTUnwrap(toolbar.items.last).isBordered)
    XCTAssertTrue((toolbar.items.last?.view as? FlutterToolbarEventView)?.eventTarget === target)
    XCTAssertEqual(toolbar.toolbarAllowedItemIdentifiers(toolbar), toolbar.toolbarDefaultItemIdentifiers(toolbar))
    XCTAssertNil(toolbar.toolbar(toolbar, itemForItemIdentifier: .init("unknown"), willBeInsertedIntoToolbar: false))
    // Keep the actual buttons inside their native hit-test containers,
    // including after resizing. Flutter never substitutes them.
    for size in [NSSize(width: 1000, height: 800), NSSize(width: 1200, height: 900)] {
      window.setContentSize(size)
      window.contentView?.layoutSubtreeIfNeeded()
      let root = try XCTUnwrap(window.contentView?.superview)
      for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        let button = try XCTUnwrap(window.standardWindowButton(type))
        XCTAssertTrue(button.translatesAutoresizingMaskIntoConstraints)
        let center = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        let hit = root.hitTest(button.convert(center, to: root))
        XCTAssertTrue(hit === button, "Native hit testing must reach \(type)")
        XCTAssertNotNil(button.action)
      }
    }
    window.observeToolbarFullScreenTransitions()
    let notifications = NotificationCenter.default
    for _ in 0..<2 {
      notifications.post(name: NSWindow.willEnterFullScreenNotification, object: window)
      XCTAssertFalse(toolbar.isVisible)
      notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
      XCTAssertTrue(toolbar.isVisible)
    }
    toolbar.isVisible = false
    notifications.post(name: NSWindow.willEnterFullScreenNotification, object: window)
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    XCTAssertFalse(toolbar.isVisible)
    // An unmatched exit and a window without a toolbar must be safe as well.
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    window.toolbar = nil
    notifications.post(name: NSWindow.willEnterFullScreenNotification, object: window)
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    XCTAssertNil(window.toolbar)
  }

  func testFullScreenFailureRestoresChromeAndPreservesPluginDelegateCallbacks() throws {
    let window = MainFlutterWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 800),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let target = ToolbarEventSpy()
    window.installFlutterToolbar(eventTarget: target)
    window.orderFront(nil)
    window.observeToolbarFullScreenTransitions()
    let plugin = WindowDelegateSpy()
    window.delegate = plugin
    let proxy = try XCTUnwrap(window.delegate as? WindowChromeDelegate)
    window.delegate = proxy
    XCTAssertTrue(window.delegate === proxy)
    XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
    window.delegate?.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))
    XCTAssertEqual(plugin.resizes, 1)
    XCTAssertTrue(try XCTUnwrap(window.toolbar).isVisible)
    NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
    XCTAssertFalse(try XCTUnwrap(window.toolbar).isVisible)
    window.delegate?.windowDidFailToEnterFullScreen?(window)
    XCTAssertTrue(try XCTUnwrap(window.toolbar).isVisible)
    XCTAssertEqual(plugin.failures, 1)
    window.delegate = nil
    XCTAssertNil(window.delegate)

    weak var released: WindowDelegateSpy?
    do {
      let temporary = WindowDelegateSpy()
      released = temporary
      window.delegate = temporary
    }
    XCTAssertNil(released)
    let orphan = try XCTUnwrap(window.delegate as? WindowChromeDelegate)
    XCTAssertFalse(orphan.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
    XCTAssertNil(orphan.forwardingTarget(for: #selector(NSWindowDelegate.windowShouldClose(_:))))
    orphan.windowDidFailToEnterFullScreen(window)
  }

  func testToolbarForwardsCompletePointerSequencesWithoutStartingANativeDrag() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1000, height: 800),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let target = ToolbarEventSpy()
    let view = FlutterToolbarEventView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
    view.eventTarget = target
    window.contentView?.addSubview(view)
    XCTAssertTrue(view.window === window)
    XCTAssertFalse(view.mouseDownCanMoveWindow)
    XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    target.onDown = { XCTAssertFalse(window.isMovable) }
    let calls: [(NSEvent.EventType, (NSEvent) -> Void)] = [
      (.leftMouseDown, view.mouseDown), (.leftMouseDragged, view.mouseDragged), (.leftMouseUp, view.mouseUp),
      (.mouseMoved, view.mouseMoved),
      (.rightMouseDown, view.rightMouseDown), (.rightMouseDragged, view.rightMouseDragged),
      (.rightMouseUp, view.rightMouseUp),
      (.otherMouseDown, view.otherMouseDown), (.otherMouseDragged, view.otherMouseDragged),
      (.otherMouseUp, view.otherMouseUp),
    ]
    for (type, forward) in calls {
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 300, y: 770),
        modifierFlags: [.shift], timestamp: 1, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 0.5))
      forward(event)
      XCTAssertTrue(target.events.last === event)
      XCTAssertTrue(window.isMovable)
    }
    let wheel = try XCTUnwrap(NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
      wheelCount: 2, wheel1: 12, wheel2: 5, wheel3: 0)!))
    view.scrollWheel(with: wheel)
    XCTAssertTrue(target.events.last === wheel)
    XCTAssertEqual(target.events.map(\.type), calls.map { $0.0 } + [.scrollWheel])
    window.isMovable = false
    view.mouseDown(with: target.events[0])
    XCTAssertFalse(window.isMovable)

    // The event surface must not keep Flutter's controller alive.
    let detached = FlutterToolbarEventView()
    weak var released: ToolbarEventSpy?
    do {
      let temporary = ToolbarEventSpy()
      released = temporary
      detached.eventTarget = temporary
    }
    XCTAssertNil(released)
    detached.mouseDown(with: target.events[0])
    detached.scrollWheel(with: wheel)
  }

}

private final class ToolbarEventSpy: NSResponder {
  var events: [NSEvent] = []
  var onDown: (() -> Void)?

  override func mouseDown(with event: NSEvent) { onDown?(); events.append(event) }
  override func mouseUp(with event: NSEvent) { events.append(event) }
  override func mouseDragged(with event: NSEvent) { events.append(event) }
  override func mouseMoved(with event: NSEvent) { events.append(event) }
  override func rightMouseDown(with event: NSEvent) { events.append(event) }
  override func rightMouseUp(with event: NSEvent) { events.append(event) }
  override func rightMouseDragged(with event: NSEvent) { events.append(event) }
  override func otherMouseDown(with event: NSEvent) { events.append(event) }
  override func otherMouseUp(with event: NSEvent) { events.append(event) }
  override func otherMouseDragged(with event: NSEvent) { events.append(event) }
  override func scrollWheel(with event: NSEvent) { events.append(event) }
}

private final class WindowDelegateSpy: NSObject, NSWindowDelegate {
  var resizes = 0
  var failures = 0
  func windowShouldClose(_ sender: NSWindow) -> Bool { false }
  func windowDidResize(_ notification: Notification) { resizes += 1 }
  func windowDidFailToEnterFullScreen(_ window: NSWindow) { failures += 1 }
}

extension RunnerTests {
  private var repositoryRoot: URL {
    var path = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { path.deleteLastPathComponent() }
    return path
  }
  private func readabilityScript() throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent("packages/mm_platform/assets/readability/Readability.js"), encoding: .utf8)
  }
  private func parseArticle(_ html: String, script: String? = nil) throws -> Any? {
    let done = expectation(description: "Readability completes")
    var result: Any?
    let job = ArticleParseJob(html: html, script: try script ?? readabilityScript()) { value in result = value; done.fulfill() }
    job.start()
    wait(for: [done], timeout: 25)
    withExtendedLifetime(job) {}
    return result
  }
  func testRecordedEnglishAndChineseArticles() throws {
    let directory = repositoryRoot.appendingPathComponent("packages/mm_research/test/fixtures/articles")
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [[String: Any]]
    XCTAssertEqual(manifest.count, 20)
    for item in manifest {
      let name = item["name"] as! String
      let html = try String(contentsOf: directory.appendingPathComponent(name + ".html"), encoding: .utf8)
      let expected = try String(contentsOf: directory.appendingPathComponent(name + ".txt"), encoding: .utf8)
      let result = try XCTUnwrap(try parseArticle(html) as? [String: Any], name)
      let text = try XCTUnwrap(result["text"] as? String, name)
      let normalized = text.components(separatedBy: .whitespacesAndNewlines).joined()
      XCTAssertEqual(normalized, expected, name)
    }
  }
  func testArticleChannelContract() throws {
    let view = FlutterViewController()
    let channel = ArticleParserChannel(messenger: view.engine.binaryMessenger)
    func invoke(_ method: String, _ arguments: [String: String]?) -> Any? {
      var value: Any?
      channel.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value = $0 }
      return value
    }
    XCTAssertNotNil(invoke("parse", nil) as? FlutterError)
    XCTAssertNotNil(invoke("parse", ["id": "1"]) as? FlutterError)
    XCTAssertNotNil(invoke("unknown", ["id": "1"]))
    for url in ["file:///etc/passwd", "http://u:p@example.com"] {
      XCTAssertNotNil(invoke("parse", ["id": "1", "url": url, "html": "x", "script": "x"]) as? FlutterError)
    }
    let args = ["id": "job", "url": "https://example.com", "html": "<p>Article content.</p>", "script": try readabilityScript()]
    let cancelled = expectation(description: "channel cancellation")
    channel.handle(FlutterMethodCall(methodName: "parse", arguments: args)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "cancelled"); cancelled.fulfill()
    }
    XCTAssertNil(invoke("cancel", ["id": "job"]))
    wait(for: [cancelled], timeout: 2)
    let done = expectation(description: "channel result")
    channel.handle(FlutterMethodCall(methodName: "parse", arguments: args)) { value in
      XCTAssertNotNil(value as? [String: Any]); done.fulfill()
    }
    wait(for: [done], timeout: 25)
    view.engine.shutDownEngine()
  }
  func testArticleParserFailureAndCancellation() throws {
    XCTAssertEqual((try parseArticle("<html><body></body></html>") as? FlutterError)?.code, "unparseable")
    XCTAssertEqual((try parseArticle("<form><p>Sign in</p><input type=password></form>") as? FlutterError)?.code, "login_required")
    XCTAssertEqual((try parseArticle("<p>text</p>", script: "invalid javascript @") as? FlutterError)?.code, "unparseable")
    var calls = 0
    let job = ArticleParseJob(html: "<p>text</p>", script: try readabilityScript()) { result in
      calls += 1
      XCTAssertEqual((result as? FlutterError)?.code, "cancelled")
    }
    job.start(); job.cancel(); job.cancel()
    XCTAssertEqual(calls, 1)
  }
  func testArticleParserBlocksPrivateSubresourcesAndPageScripts() throws {
    let listener = try NWListener(using: .tcp, on: .any)
    let ready = expectation(description: "local trap ready")
    let unwanted = expectation(description: "no private requests")
    unwanted.isInverted = true
    listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
    listener.newConnectionHandler = { connection in unwanted.fulfill(); connection.cancel() }
    listener.start(queue: .main)
    defer { listener.cancel() }
    wait(for: [ready], timeout: 5)
    let port = try XCTUnwrap(listener.port).rawValue
    let url = "http://127.0.0.1:\(port)/private"
    let html = """
      <html><head><meta http-equiv="refresh" content="0;url=\(url)">
      <link rel="stylesheet" href="\(url)"><style>body{background:url('\(url)')}</style></head>
      <body><article><h1>Safe title</h1><p>Original document text preserved for reading.</p>
      <img src="\(url)" onerror="fetch('\(url)')"><iframe src="\(url)"></iframe>
      <object data="\(url)"></object><video poster="\(url)" src="\(url)"></video>
      <script>fetch('\(url)'); document.body.innerHTML='EXECUTED';</script>
      </article></body></html>
      """
    let result = try XCTUnwrap(try parseArticle(html) as? [String: Any])
    XCTAssertTrue((result["text"] as? String)?.contains("Original document") == true)
    XCTAssertFalse((result["text"] as? String)?.contains("EXECUTED") == true)
    wait(for: [unwanted], timeout: 0.3)
  }
}

extension RunnerTests {
  private func ocrFixture(pages: Int = 2, rotated: Bool = false) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sample.pdf")
    var media = CGRect(x: 0, y: 0, width: 600, height: 800)
    let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &media, nil))
    for index in 0..<pages {
      context.beginPDFPage(nil)
      context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(media)
      if index == 1 {
        context.textPosition = CGPoint(x: 60, y: 500)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Existing text", attributes:
          [.font: NSFont.systemFont(ofSize: 24)])), context)
      } else {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 1600, bitsPerComponent: 8,
          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        bitmap.textPosition = CGPoint(x: 120, y: 1200)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "MarginMind local recognition", attributes:
          [.font: NSFont.systemFont(ofSize: 48)])), bitmap)
        bitmap.textPosition = CGPoint(x: 120, y: 1080)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "学习与思考，知识与实践", attributes:
          [.font: NSFont(name: "PingFangSC-Regular", size: 48)!])), bitmap)
        context.draw(try XCTUnwrap(bitmap.makeImage()), in: media)
      }
      context.endPDFPage()
    }
    context.closePDF()
    if rotated {
      let document = try XCTUnwrap(PDFDocument(url: url))
      let page = try XCTUnwrap(document.page(at: 0))
      page.setBounds(CGRect(x: 20, y: 30, width: 540, height: 700), for: .cropBox)
      page.rotation = 90
      XCTAssertTrue(document.write(to: url))
    }
    return url
  }

  private func ocrPixels(_ url: URL) throws -> Data {
    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    let page = try XCTUnwrap(document.page(at: 1))
    let (bounds, transform) = PdfOcrEngine.geometry(page)
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(bounds)
    bitmap.concatenate(transform); bitmap.drawPDFPage(page)
    return Data(bytes: try XCTUnwrap(bitmap.data), count: bitmap.bytesPerRow * bitmap.height)
  }

  func testOcrBilingualVisionAndInvisibleLayer() throws {
    let source = try ocrFixture()
    let original = try Data(contentsOf: source)
    XCTAssertEqual(try PdfOcrEngine.inspect(source)["textPages"] as? [Int], [2])
    var progress = [Int]()
    let result = try PdfOcrEngine.run(source: source, first: 1, last: 2, languages: ["zh-Hans", "en-US"],
      cancelled: { false }, progress: { done, total in progress.append(done); XCTAssertEqual(total, 2) })
    XCTAssertEqual(progress, [1, 2])
    XCTAssertEqual(result["textPages"] as? [Int], [1, 2])
    XCTAssertEqual(try Data(contentsOf: source), original)
    let output = PdfOcrEngine.copyURL(source)
    let document = try XCTUnwrap(PDFDocument(url: output))
    let text = try XCTUnwrap(document.page(at: 0)?.string)
    XCTAssertTrue(text.contains("MarginMind"), text)
    XCTAssertTrue(text.contains("学习"), text)
    XCTAssertEqual(document.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), "Existing text")
    XCTAssertEqual(try ocrPixels(source), try ocrPixels(output), "Hidden text must leave artwork identical")
    // PDFKit selection bounds exercise the actual encoded PDF text positions.
    let match = try XCTUnwrap(document.findString("MarginMind", withOptions: []).first)
    let rect = match.bounds(for: try XCTUnwrap(document.page(at: 0)))
    XCTAssertEqual(rect.minX, 60, accuracy: 8)
    XCTAssertEqual(rect.minY, 600, accuracy: 10)
    XCTAssertGreaterThan(rect.width, 100)
  }

  func testOcrRotatedCropCoordinatesAndResumeAfterCancel() throws {
    let source = try ocrFixture(pages: 3, rotated: true)
    let before = try ocrPixels(source)
    var calls = 0
    let line = PdfOcrEngine.Line(text: "坐标 Coordinates", rect: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.05))
    let result = try PdfOcrEngine.run(source: source, first: 1, last: 3, languages: ["en-US"],
      cancelled: { calls == 1 }, progress: { _, _ in }, recognizer: { _, _ in calls += 1; return [line] })
    XCTAssertEqual(result["cancelled"] as? Bool, true)
    XCTAssertEqual(result["textPages"] as? [Int], [1, 2])
    XCTAssertEqual(try ocrPixels(PdfOcrEngine.copyURL(source)), before)
    let copy = try XCTUnwrap(PDFDocument(url: PdfOcrEngine.copyURL(source)))
    let page = try XCTUnwrap(copy.page(at: 0))
    XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 700, height: 540))
    let selection = try XCTUnwrap(copy.findString("坐标 Coordinates", withOptions: []).first)
    let rect = selection.bounds(for: page)
    XCTAssertEqual(rect.minX, 70, accuracy: 1)
    XCTAssertEqual(rect.minY, 270, accuracy: 8)
    XCTAssertEqual(rect.width, 280, accuracy: 2)
    calls = 0
    _ = try PdfOcrEngine.run(source: source, first: 1, last: 3, languages: ["en-US"],
      cancelled: { false }, progress: { _, _ in }, recognizer: { _, _ in calls += 1; return [line] })
    XCTAssertEqual(calls, 1, "Skip both existing and previously recognized text")
    XCTAssertEqual(try PdfOcrEngine.inspect(source)["textPages"] as? [Int], [1, 2, 3])
  }

  func testOcrFailureDoesNotReplaceCopyAndRejectsRange() throws {
    let source = try ocrFixture()
    let copy = PdfOcrEngine.copyURL(source)
    try FileManager.default.copyItem(at: source, to: copy)
    let original = try Data(contentsOf: copy)
    XCTAssertThrowsError(try PdfOcrEngine.run(source: source, first: 0, last: 2, languages: ["en-US"],
      cancelled: { false }, progress: { _, _ in }))
    XCTAssertThrowsError(try PdfOcrEngine.run(source: source, first: 1, last: 99, languages: ["en-US"],
      cancelled: { false }, progress: { _, _ in }))
    XCTAssertThrowsError(try PdfOcrEngine.run(source: source, first: 1, last: 2, languages: ["en-US"],
      cancelled: { false }, progress: { _, _ in }, recognizer: { _, _ in throw PdfOcrEngine.Failure.render }))
    XCTAssertEqual(try Data(contentsOf: copy), original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path).count, 2)
  }
}

extension RunnerTests {
  func testOcr300PagesKeepsMainRunLoopResponsiveAndMemoryBounded() async throws {
    let source = try ocrFixture(pages: 300)
    @Sendable nonisolated func residentBytes() -> UInt64 {
      var info = mach_task_basic_info()
      var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
      let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
      }
      return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    var heartbeats = 0
    let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in heartbeats += 1 }
    defer { timer.invalidate() }
    let start = Date()
    let metrics: (Int, UInt64, UInt64) = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue(label: "ocr-stress-test", qos: .userInitiated).async {
        do {
          var warm: UInt64 = 0, peak: UInt64 = 0
          let result = try PdfOcrEngine.run(source: source, first: 1, last: 300, languages: ["zh-Hans", "en-US"],
            cancelled: { false }, progress: { done, _ in
              if done == 30 { warm = residentBytes() }
              if done >= 30 && done % 10 == 0 { peak = max(peak, residentBytes()) }
            })
          continuation.resume(returning: ((result["textPages"] as? [Int])?.count ?? 0, warm, peak))
        } catch { continuation.resume(throwing: error) }
      }
    }
    XCTAssertEqual(metrics.0, 300)
    XCTAssertGreaterThan(heartbeats, 10, "Main run loop must run throughout recognition")
    XCTAssertGreaterThan(metrics.1, 0)
    XCTAssertLessThan(metrics.2 - min(metrics.1, metrics.2), 256 * 1024 * 1024,
      "Memory growth after warmup must not scale with page count")
    XCTContext.runActivity(named: "OCR_STRESS pages=300 seconds=\(Date().timeIntervalSince(start)) mainHeartbeats=\(heartbeats) warmRSS=\(metrics.1) peakRSS=\(metrics.2)") { _ in }
  }
}

extension RunnerTests {
  func testOcrChannelValidationBusyProgressCancellationAndErrors() async throws {
    let view = FlutterViewController()
    let worker = DispatchQueue(label: "test.ocr-paused")
    let channel = PdfOcrChannel(messenger: view.engine.binaryMessenger, worker: worker)
    let source = try ocrFixture()
    // Opening another document must not wait behind a long OCR batch.
    worker.suspend()
    let inspectedWhileBusy = expectation(description: "inspection independent of OCR queue")
    channel.handle(FlutterMethodCall(methodName: "inspect", arguments: ["source": source.path])) { value in
      XCTAssertEqual((value as? [String: Any])?["pageCount"] as? Int, 2)
      inspectedWhileBusy.fulfill()
    }
    await fulfillment(of: [inspectedWhileBusy], timeout: 2)
    worker.resume()
    func sync(_ method: String, _ arguments: Any?) -> Any? {
      var value: Any?
      channel.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value = $0 }
      return value
    }
    func invoke(_ method: String, _ arguments: [String: Any]) async -> Any? {
      await withCheckedContinuation { continuation in
        channel.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
          continuation.resume(returning: $0)
        }
      }
    }
    for (method, args) in [("inspect", nil), ("unknown", [:]), ("inspect", ["source": "relative.pdf"]),
                           ("inspect", ["source": "/x.ocr.pdf"]), ("recognize", ["source": source.path]),
                           ("recognize", ["source": source.path, "id": "x", "first": 1, "last": 2, "languages": ["invalid"]])] as [(String, Any?)] {
      XCTAssertEqual((sync(method, args) as? FlutterError)?.code, "invalid_arguments")
    }
    let inspected = await invoke("inspect", ["source": source.path]) as? [String: Any]
    XCTAssertEqual(inspected?["pageCount"] as? Int, 2)
    let readFailure = await invoke("inspect", ["source": "/missing/sample.pdf"]) as? FlutterError
    XCTAssertEqual(readFailure?.code, "read_failed")
    let args: [String: Any] = ["source": source.path, "id": "job", "first": 1, "last": 2, "languages": ["zh-Hans", "en-US"]]
    let complete = expectation(description: "cancelled copy")
    channel.handle(FlutterMethodCall(methodName: "recognize", arguments: args)) { value in
      XCTAssertEqual((value as? [String: Any])?["cancelled"] as? Bool, true)
      complete.fulfill()
    }
    XCTAssertEqual((sync("recognize", args) as? FlutterError)?.code, "busy")
    XCTAssertNil(sync("cancel", ["id": "old-job"]))
    XCTAssertNil(sync("cancel", ["id": "job"]))
    await fulfillment(of: [complete], timeout: 10)
    let resumed = await invoke("recognize", args) as? [String: Any]
    XCTAssertEqual(resumed?["textPages"] as? [Int], [1, 2])
    var bad = args; bad["first"] = 0
    let failure = await invoke("recognize", bad) as? FlutterError
    XCTAssertEqual(failure?.code, "recognition_failed")
    withExtendedLifetime(view) {}
  }
}

private final class BrowserPrintNavigationWaiter: NSObject, WKNavigationDelegate {
  private let loaded: XCTestExpectation
  init(_ loaded: XCTestExpectation) { self.loaded = loaded }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
