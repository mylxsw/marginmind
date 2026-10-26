import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  private var articleParser: ArticleParserChannel?
  private var secretStore: SecretStoreChannel?
  private var mapClipboard: FlutterMethodChannel?
  private var systemAppearance: SystemAppearanceChannel?
  private var toolbarVisibilityBeforeFullScreen: Bool?
  private var chromeDelegate: WindowChromeDelegate?

  // window_manager owns the delegate. Preserve its optional callbacks while
  // adding AppKit's failure callback (there is no failure notification).
  override var delegate: NSWindowDelegate? {
    get { super.delegate }
    set {
      if let current = chromeDelegate, newValue === current { return }
      if let target = newValue {
        let proxy = WindowChromeDelegate(host: self, target: target)
        chromeDelegate = proxy
        super.delegate = proxy
      } else {
        super.delegate = nil
        chromeDelegate = nil
      }
    }
  }

  func installFlutterToolbar(eventTarget: NSResponder) {
    let nativeToolbar = FlutterWindowToolbar(identifier: "marginmind.flutterToolbar")
    nativeToolbar.eventTarget = eventTarget
    nativeToolbar.delegate = nativeToolbar
    nativeToolbar.showsBaselineSeparator = false
    nativeToolbar.allowsUserCustomization = false
    nativeToolbar.allowsExtensionItems = false
    if #available(macOS 15.0, *) { nativeToolbar.allowsDisplayModeCustomization = false }
    toolbar = nativeToolbar
    nativeToolbar.isVisible = true
    toolbarStyle = .unified
  }

  // The toolbar only enlarges the native button container in windowed mode.
  // AppKit otherwise detaches an opaque toolbar above our full-size Flutter
  // content during the full-screen animation. Hide it before entering; AppKit
  // still reveals its buttons when the pointer reaches the screen's top edge.
  func observeToolbarFullScreenTransitions() {
    for name in [NSWindow.willEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(toolbarFullScreenTransition(_:)),
                                            name: name, object: self)
    }
  }

  @objc private func toolbarFullScreenTransition(_ notification: Notification) {
    if notification.name == NSWindow.willEnterFullScreenNotification {
      toolbarVisibilityBeforeFullScreen = toolbar?.isVisible
      toolbar?.isVisible = false
    } else {
      restoreToolbarAfterFullScreen()
    }
  }

  fileprivate func restoreToolbarAfterFullScreen() {
    guard let visible = toolbarVisibilityBeforeFullScreen else { return }
    toolbar?.isVisible = visible
    toolbarVisibilityBeforeFullScreen = nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func awakeFromNib() {
    observeToolbarFullScreenTransitions()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    installFlutterToolbar(eventTarget: flutterViewController)
    RegisterGeneratedPlugins(registry: flutterViewController)
    articleParser = ArticleParserChannel(messenger: flutterViewController.engine.binaryMessenger)
    secretStore = SecretStoreChannel(messenger: flutterViewController.engine.binaryMessenger)
    systemAppearance = SystemAppearanceChannel(messenger: flutterViewController.engine.binaryMessenger)

    let clipboard = FlutterMethodChannel(name: "marginmind/map_clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    mapClipboard = clipboard
    clipboard.setMethodCallHandler { call, result in
      let pasteboard = NSPasteboard.general
      let type = NSPasteboard.PasteboardType("io.github.mylxsw.marginmind.nodes")
      switch call.method {
      case "write":
        guard let values = call.arguments as? [String: String],
          let text = values["text"], let data = values["internal"] else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(data, forType: type)
        pasteboard.clearContents()
        if pasteboard.writeObjects([item]) { result(nil) }
        else { result(FlutterError(code: "clipboard_write", message: nil, details: nil)) }
      case "read":
        var values = ["text": pasteboard.string(forType: .string) ?? ""]
        if let data = pasteboard.string(forType: type) { values["internal"] = data }
        result(values)
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

/// Adds only full-screen failure recovery; all other delegate behavior stays
/// with the window plugin. Both references are weak, as NSWindow delegates are.
final class WindowChromeDelegate: NSObject, NSWindowDelegate {
  private weak var host: MainFlutterWindow?
  private weak var target: NSWindowDelegate?

  init(host: MainFlutterWindow, target: NSWindowDelegate) {
    self.host = host
    self.target = target
    super.init()
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || target?.responds(to: selector) == true
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    target ?? super.forwardingTarget(for: selector)
  }

  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    host?.restoreToolbarAfterFullScreen()
    target?.windowDidFailToEnterFullScreen?(window)
  }
}

/// A transparent event surface alongside AppKit's own window buttons.
/// Keep this local: the plugin's BlockingToolbar only forwards down/up.
final class FlutterWindowToolbar: NSToolbar, NSToolbarDelegate {
  weak var eventTarget: NSResponder?
  private let eventItem = NSToolbarItem.Identifier("marginmind.flutterEvents")

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace, eventItem]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard itemIdentifier == eventItem else { return nil }
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    let view = FlutterToolbarEventView()
    view.eventTarget = eventTarget
    view.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
    view.widthAnchor.constraint(lessThanOrEqualToConstant: 100000).isActive = true
    item.view = view
    // macOS 26 otherwise adds glass over Flutter's own controls.
    item.isBordered = false
    return item
  }
}

final class FlutterToolbarEventView: NSView {
  weak var eventTarget: NSResponder?

  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    // A transparent title bar can still start an AppKit drag despite
    // mouseDownCanMoveWindow. Flutter decides whether this is text selection,
    // a control click, or an empty-space drag via DesktopWindow.startDragging.
    let host = window
    let wasMovable = host?.isMovable
    host?.isMovable = false
    defer { if let wasMovable = wasMovable { host?.isMovable = wasMovable } }
    eventTarget?.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) { eventTarget?.mouseUp(with: event) }
  override func mouseDragged(with event: NSEvent) { eventTarget?.mouseDragged(with: event) }
  override func mouseMoved(with event: NSEvent) { eventTarget?.mouseMoved(with: event) }
  override func rightMouseDown(with event: NSEvent) { eventTarget?.rightMouseDown(with: event) }
  override func rightMouseUp(with event: NSEvent) { eventTarget?.rightMouseUp(with: event) }
  override func rightMouseDragged(with event: NSEvent) { eventTarget?.rightMouseDragged(with: event) }
  override func otherMouseDown(with event: NSEvent) { eventTarget?.otherMouseDown(with: event) }
  override func otherMouseUp(with event: NSEvent) { eventTarget?.otherMouseUp(with: event) }
  override func otherMouseDragged(with event: NSEvent) { eventTarget?.otherMouseDragged(with: event) }
  override func scrollWheel(with event: NSEvent) { eventTarget?.scrollWheel(with: event) }
}

/// Reports the system accent color and accessibility display options to
/// Dart (`SystemAppearanceSource` in packages/mm_platform) and pushes a
/// fresh snapshot whenever they change.
final class SystemAppearanceChannel: NSObject {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/system_appearance", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { call, result in
      if call.method == "read" {
        result(SystemAppearanceChannel.snapshot())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(changed),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(changed),
      name: NSColor.systemColorsDidChangeNotification, object: nil)
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func changed() {
    channel.invokeMethod("changed", arguments: SystemAppearanceChannel.snapshot())
  }

  static func snapshot() -> [String: Any] {
    let workspace = NSWorkspace.shared
    var values: [String: Any] = [
      "reduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency,
      "reduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
      "increaseContrast": workspace.accessibilityDisplayShouldIncreaseContrast,
    ]
    if let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
      func channel(_ v: CGFloat) -> Int { Int((v * 255).rounded()) & 0xFF }
      values["accent"] =
        (channel(accent.alphaComponent) << 24) | (channel(accent.redComponent) << 16)
        | (channel(accent.greenComponent) << 8) | channel(accent.blueComponent)
    }
    return values
  }
}

/// App-scoped generic passwords; never copies secrets into defaults or logs.
final class SecretStoreChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/secret_store", binaryMessenger: messenger)
    channel.setMethodCallHandler(Self.handle)
  }

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      guard let args = call.arguments as? [String: String],
            let account = args["account"], !account.isEmpty, account.count <= 256 else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
        return
      }
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.mylxsw.marginmind.research",
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: false,
      ]
      var status: OSStatus
      switch call.method {
      case "read":
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        status = SecItemCopyMatching(readQuery as CFDictionary, &value)
        if status == errSecItemNotFound { result(nil); return }
        if status == errSecSuccess, let data = value as? Data,
           let text = String(data: data, encoding: .utf8) { result(text); return }
      case "write":
        guard let value = args["value"] else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
        }
        let values: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
          var insert = query.merging(values) { _, new in new }
          insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
          status = SecItemAdd(insert as CFDictionary, nil)
        }
        if status == errSecSuccess { result(nil); return }
      case "delete":
        status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil); return }
      default: result(FlutterMethodNotImplemented); return
      }
      result(FlutterError(code: "keychain_failure", message: nil, details: nil))
  }
}
