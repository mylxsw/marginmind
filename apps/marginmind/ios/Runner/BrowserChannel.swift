#if os(macOS)
import Cocoa
import FlutterMacOS
#else
import UIKit
import Flutter
#endif
import WebKit

/// App-private persistent WKWebsiteDataStore. No script message handler is
/// registered; page JavaScript cannot reach any application method channel.
final class BrowserFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let manager: FlutterMethodChannel
  private var tabs = [Int64: NativeBrowser]()
  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    manager = FlutterMethodChannel(name: "marginmind/browser", binaryMessenger: messenger)
    super.init()
    manager.setMethodCallHandler { [weak self] call, result in
      guard call.method == "clearData" else { result(FlutterMethodNotImplemented); return }
      self?.tabs.values.forEach { $0.close() }
      self?.tabs.removeAll()
      WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast) { result(nil) }
    }
  }
#if os(macOS)
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
#else
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
#endif
  private func make(_ args: Any?) -> NativeBrowser {
    let id = ((args as? [String: Any])?["id"] as? NSNumber)?.int64Value ?? 0
    let tab = NativeBrowser(id: id, messenger: messenger) { [weak self] in self?.tabs.removeValue(forKey: id) }
    tabs[id] = tab
    return tab
  }
#if os(macOS)
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView { make(args).web }
#else
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let tab = make(args)
    tab.web.frame = frame
    return tab
  }
#endif
}

final class NativeBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
  let web: WKWebView
  private let channel: FlutterMethodChannel
  private let onClose: () -> Void
  private var generation = 0
  private var activeNavigation: WKNavigation?
  private let world = WKContentWorld.world(name: "MarginMindBrowser")
  init(id: Int64, messenger: FlutterBinaryMessenger, onClose: @escaping () -> Void) {
    self.onClose = onClose
    channel = FlutterMethodChannel(name: "marginmind/browser/\(id)", binaryMessenger: messenger)
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    web = WKWebView(frame: .zero, configuration: config)
    super.init()
    web.navigationDelegate = self
    web.uiDelegate = self
    web.allowsBackForwardNavigationGestures = true
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "navigate":
        guard let raw = args["url"] as? String, let url = URL(string: raw), Self.allowed(url) else {
          result(FlutterError(code: "invalid_url", message: nil, details: nil)); return
        }
        self.web.load(URLRequest(url: url)); result(nil)
      case "back": self.web.goBack(); result(nil)
      case "forward": self.web.goForward(); result(nil)
      case "reload": self.web.reload(); result(nil)
      case "stop": self.web.stopLoading(); result(nil)
      case "evaluate":
        let script = args["script"] as? String ?? ""
        self.web.evaluateJavaScript(script, in: nil, in: self.world) { value in
          switch value {
          case .success(let output): result(output as? String)
          case .failure: result(FlutterError(code: "script_failed", message: nil, details: nil))
          }
        }
      case "dispose": self.close(); self.onClose(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func close() { web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil; web.removeFromSuperview(); channel.setMethodCallHandler(nil) }
  static func allowed(_ url: URL?) -> Bool {
    guard let url = url else { return false }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
  }
  private func emit(_ kind: String) {
    channel.invokeMethod("event", arguments: ["kind": kind, "navigationId": generation,
      "url": web.url?.absoluteString ?? "", "back": web.canGoBack, "forward": web.canGoForward])
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { activeNavigation = navigation; generation += 1; emit("start") }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if navigation === activeNavigation { emit("loaded") } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === activeNavigation { emit("failed") } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if navigation === activeNavigation && (error as NSError).code != NSURLErrorCancelled { emit("failed") }
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard Self.allowed(action.request.url), !action.shouldPerformDownload else { decisionHandler(.cancel); return }
    if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
    else { decisionHandler(.allow) }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    let status = (response.response as? HTTPURLResponse)?.statusCode ?? 200
    let blocked = status >= 400 || !response.canShowMIMEType || disposition.lowercased().contains("attachment") || !Self.allowed(response.response.url)
    decisionHandler(blocked ? .cancel : .allow)
    if blocked && response.isForMainFrame { emit("failed") }
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
#if !os(macOS)
  @available(iOS 15.0, *)
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
#endif
}
#if !os(macOS)
extension NativeBrowser: FlutterPlatformView { func view() -> UIView { web } }
#endif
