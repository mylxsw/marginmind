import Cocoa
import FlutterMacOS
import XCTest
import Network

@testable import MarginMind

@MainActor
class RunnerTests: XCTestCase {
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
