import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var browserFactory: BrowserFactory?
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarginMindMobile")!
    let messenger = registrar.messenger()
    let browser = BrowserFactory(messenger: messenger)
    browserFactory = browser
    registrar.register(browser, withId: "marginmind/browser")
    FlutterMethodChannel(name: "marginmind/secret_store", binaryMessenger: messenger)
      .setMethodCallHandler(MobileSecrets.handle)
    FlutterMethodChannel(name: "marginmind/external_link", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "open" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let raw = args["url"] as? String,
          let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          url.host?.isEmpty == false else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      }
    FlutterMethodChannel(name: "marginmind/file_share", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "share" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let name = args["name"] as? String,
          !name.isEmpty, name == (name as NSString).lastPathComponent,
          !name.contains("\\"), !name.unicodeScalars.contains(where: { $0.value < 32 }),
          let bytes = args["bytes"] as? FlutterStandardTypedData, !bytes.data.isEmpty,
          var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController
        else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        do {
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent("share-" + UUID().uuidString)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let file = directory.appendingPathComponent(name)
          try bytes.data.write(to: file, options: .atomic)
          let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
          sheet.popoverPresentationController?.sourceView = presenter.view
          sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
          sheet.popoverPresentationController?.permittedArrowDirections = []
          sheet.completionWithItemsHandler = { _, completed, _, error in
            try? FileManager.default.removeItem(at: directory)
            if error != nil { result(FlutterError(code: "share_failed", message: nil, details: nil)) }
            else { result(completed) }
          }
          presenter.present(sheet, animated: true)
        } catch { result(FlutterError(code: "share_failed", message: nil, details: nil)) }
      }
  }
}

/// Device-only Keychain entries; credentials never enter preferences or backups.
enum MobileSecrets {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["read", "write", "delete"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
    guard let args = call.arguments as? [String: Any], let account = args["account"] as? String,
      !account.isEmpty, account.count <= 256 else {
      result(FlutterError(code: "invalid_request", message: nil, details: nil)); return
    }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.mylxsw.marginmind", kSecAttrAccount as String: account]
    var status: OSStatus = errSecSuccess
    if call.method == "read" {
      var request = query
      request[kSecReturnData as String] = true
      request[kSecMatchLimit as String] = kSecMatchLimitOne
      var value: CFTypeRef?
      status = SecItemCopyMatching(request as CFDictionary, &value)
      if status == errSecItemNotFound { result(nil); return }
      if status == errSecSuccess, let data = value as? Data, let text = String(data: data, encoding: .utf8) {
        result(text); return
      }
    } else if call.method == "delete" {
      status = SecItemDelete(query as CFDictionary)
      if status == errSecItemNotFound { status = errSecSuccess }
    } else {
      guard let value = args["value"] as? String else {
        result(FlutterError(code: "invalid_request", message: nil, details: nil)); return
      }
      let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
      status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
      }
    }
    if status == errSecSuccess { result(nil) }
    else { result(FlutterError(code: "unavailable", message: nil, details: nil)) }
  }
}
