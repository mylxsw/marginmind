import Cocoa
import FlutterMacOS
import XCTest

@testable import MarginMind

@MainActor
class RunnerTests: XCTestCase {
  func testForwardingToolbarRemainsInvisibleAndButtonsReceiveMouseHits() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1000, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    let toolbar = TestToolbar(identifier: "test-forwarding")
    toolbar.delegate = toolbar
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.orderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertEqual(toolbar.items.count, 1)
    XCTAssertFalse(try XCTUnwrap(toolbar.items.first).isBordered)
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
      notifications.post(name: NSWindow.didEnterFullScreenNotification, object: window)
      XCTAssertFalse(toolbar.isVisible)
      notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
      XCTAssertTrue(toolbar.isVisible)
    }
    toolbar.isVisible = false
    notifications.post(name: NSWindow.didEnterFullScreenNotification, object: window)
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    XCTAssertFalse(toolbar.isVisible)
    // An unmatched exit and a window without a toolbar must be safe as well.
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    window.toolbar = nil
    notifications.post(name: NSWindow.didEnterFullScreenNotification, object: window)
    notifications.post(name: NSWindow.didExitFullScreenNotification, object: window)
    XCTAssertNil(window.toolbar)
  }
}

private final class TestToolbar: NSToolbar, NSToolbarDelegate {
  private let itemID = NSToolbarItem.Identifier("forwarding")

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [itemID]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [itemID]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
    item.isBordered = true
    return item
  }
}
