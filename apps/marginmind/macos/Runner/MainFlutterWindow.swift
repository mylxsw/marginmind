import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var mapClipboard: FlutterMethodChannel?
  private var systemAppearance: SystemAppearanceChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
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
