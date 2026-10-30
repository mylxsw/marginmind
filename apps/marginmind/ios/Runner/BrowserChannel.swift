#if os(macOS)
import Cocoa
import ApplicationServices
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
  private var closed = false
#if os(macOS)
  private var pdfPrint: BrowserPdfPrintJob?
#endif
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
      case "printPdf": self.printPdf(result)
      case "dispose": self.close(); self.onClose(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func printPdf(_ result: @escaping FlutterResult) {
    let expected = generation
#if os(macOS)
    guard pdfPrint == nil, let window = web.window, !closed else {
      result(FlutterError(code: "print_unavailable", message: nil, details: nil)); return
    }
    let job = BrowserPdfPrintJob(web: web, isCurrent: { [weak self] in
      guard let self = self else { return false }
      return !self.closed && self.generation == expected
    }, didFinish: { [weak self] in self?.pdfPrint = nil }, completion: result)
    pdfPrint = job
    job.start(in: window)
#else
    let renderer = BrowserPageRenderer()
    renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
    let count = renderer.numberOfPages
    guard count > 0, count <= 2000 else {
      result(FlutterError(code: "print_limit", message: nil, details: nil)); return
    }
    let bytes = NSMutableData()
    UIGraphicsBeginPDFContextToData(bytes, renderer.paperRect, nil)
    renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
    for page in 0..<count {
      UIGraphicsBeginPDFPage()
      renderer.drawPage(at: page, in: renderer.paperRect)
    }
    UIGraphicsEndPDFContext()
    guard expected == generation, bytes.length <= 128 * 1024 * 1024 else {
      result(FlutterError(code: "print_failed", message: nil, details: nil)); return
    }
    result(FlutterStandardTypedData(bytes: bytes as Data))
#endif
  }
  func close() {
    closed = true
#if os(macOS)
    pdfPrint?.cancel()
#endif
    web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil; web.removeFromSuperview(); channel.setMethodCallHandler(nil) }
  static func allowed(_ url: URL?) -> Bool {
    guard let url = url else { return false }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
  }
  private func emit(_ kind: String, error: String = "other") {
    channel.invokeMethod("event", arguments: ["kind": kind, "navigationId": generation,
      "url": web.url?.absoluteString ?? "", "back": web.canGoBack, "forward": web.canGoForward, "error": error])
  }
  private static func errorCategory(_ error: Error) -> String {
    let error = error as NSError
    guard error.domain == NSURLErrorDomain else { return "other" }
    switch error.code {
    case NSURLErrorTimedOut: return "timeout"
    case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "host"
    case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "offline"
    case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
      NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
      NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
      NSURLErrorClientCertificateRequired: return "certificate"
    default: return "other"
    }
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { activeNavigation = navigation; generation += 1; emit("start") }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if let active = activeNavigation, navigation === active { emit("loaded") } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let active = activeNavigation, navigation === active && (error as NSError).code != NSURLErrorCancelled { emit("failed", error: Self.errorCategory(error)) }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let active = activeNavigation, navigation === active && (error as NSError).code != NSURLErrorCancelled { emit("failed", error: Self.errorCategory(error)) }
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard Self.allowed(action.request.url) else { decisionHandler(.cancel); return }
    if action.shouldPerformDownload {
      decisionHandler(.cancel)
      if action.targetFrame?.isMainFrame != false { emit("download") }
      return
    }
    if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
    else { decisionHandler(.allow) }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    let blocked = !response.canShowMIMEType || disposition.lowercased().contains("attachment") || !Self.allowed(response.response.url)
    if blocked && response.isForMainFrame { activeNavigation = nil }
    decisionHandler(blocked ? .cancel : .allow)
    if blocked && response.isForMainFrame { emit("download") }
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
#if os(macOS)
/// Retained through AppKit's completion callback even if the tab closes.
/// WKWebView printing must yield the main run loop while WebKit paginates.
final class BrowserPdfPrintJob: NSObject {
  let target: URL
  private let operation: NSPrintOperation
  private let printSession: PMPrintSession
  private let isCurrent: () -> Bool
  private let didFinish: () -> Void
  private var completion: FlutterResult?
  private var timeout: DispatchWorkItem?

  init(web: WKWebView, isCurrent: @escaping () -> Bool, didFinish: @escaping () -> Void,
    completion: @escaping FlutterResult) {
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    self.target = target
    self.didFinish = didFinish
    self.isCurrent = isCurrent
    self.completion = completion
    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
    info.paperSize = NSSize(width: 595.28, height: 841.89)
    info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
    info.horizontalPagination = .fit; info.verticalPagination = .automatic
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = target
    let operation = web.printOperation(with: info)
    self.operation = operation
    printSession = unsafeBitCast(operation.printInfo.pmPrintSession(), to: PMPrintSession.self)
    super.init()
    operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    // runModal still blocks its caller when thread spawning is disabled.
    operation.canSpawnSeparateThread = true
  }

  func start(in window: NSWindow) {
    let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
    timeout = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: deadline)
    // AppKit does not own our delegate. Balance this retain in didRun, also
    // when cancellation has already completed the Flutter call.
    let context = Unmanaged.passRetained(self).toOpaque()
    operation.runModal(for: window, delegate: self,
      didRun: #selector(didRun(_:success:contextInfo:)), contextInfo: context)
  }

  func cancel() {
    _ = PMSessionSetError(printSession, OSStatus(kPMCancel))
    finish(FlutterError(code: "print_cancelled", message: nil, details: nil))
  }

  @objc private func didRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
    // AppKit can call the delegate on its printing thread. Flutter replies,
    // cancellation state and tab ownership belong to the platform thread.
    DispatchQueue.main.async {
      self.complete(success: success)
      if let contextInfo = contextInfo { Unmanaged<BrowserPdfPrintJob>.fromOpaque(contextInfo).release() }
    }
  }

  private func complete(success: Bool) {
    defer {
      didFinish()
      // A cancelled operation may have produced its file after cancel().
      try? FileManager.default.removeItem(at: target)
    }
    guard completion != nil else { return }
    guard success, isCurrent(),
      let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > 0, size <= 128 * 1024 * 1024,
      let bytes = try? Data(contentsOf: target) else {
      finish(FlutterError(code: "print_failed", message: nil, details: nil)); return
    }
    finish(FlutterStandardTypedData(bytes: bytes))
  }

  private func finish(_ value: Any?) {
    timeout?.cancel(); timeout = nil
    let callback = completion
    completion = nil
    try? FileManager.default.removeItem(at: target)
    callback?(value)
  }
}
#endif
#if !os(macOS)
extension NativeBrowser: FlutterPlatformView { func view() -> UIView { web } }
private final class BrowserPageRenderer: UIPrintPageRenderer {
  override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.28, height: 841.89) }
  override var printableRect: CGRect { paperRect.insetBy(dx: 36, dy: 36) }
}
#endif
