import Cocoa
import FlutterMacOS
import XCTest

@testable import MarginMind

@MainActor
class RunnerTests: XCTestCase {
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
