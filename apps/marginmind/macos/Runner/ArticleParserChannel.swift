import Cocoa
import FlutterMacOS
import WebKit

/// No remote navigation. Documents arrive over the DNS-pinned Dart transport.
/// Page scripts never execute: DOMParser creates an inert detached document.
final class ArticleParserChannel {
  private let channel: FlutterMethodChannel
  private var jobs: [String: ArticleParseJob] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "marginmind/article_parser", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      guard let args = call.arguments as? [String: String], let id = args["id"] else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
      }
      if call.method == "cancel" { self.jobs.removeValue(forKey: id)?.cancel(); result(nil); return }
      guard call.method == "parse" else { result(FlutterMethodNotImplemented); return }
      guard let url = args["url"], let html = args["html"], let script = args["script"],
            let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme ?? ""),
            parsed.host != nil, parsed.user == nil, html.utf8.count <= 2097152 else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
      }
      self.jobs.removeValue(forKey: id)?.cancel()
      let job = ArticleParseJob(html: html, script: script) { [weak self] value in
        self?.jobs.removeValue(forKey: id)
        result(value)
      }
      self.jobs[id] = job
      job.start()
  }
}

final class ArticleParseJob: NSObject, WKNavigationDelegate {
  static let blockRules = """
  [{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]
  """
  private let html: String
  private let script: String
  private var completion: ((Any?) -> Void)?
  private var webView: WKWebView?
  private var timer: Timer?

  init(html: String, script: String, completion: @escaping (Any?) -> Void) {
    self.html = html; self.script = script; self.completion = completion
  }

  func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.fail("timeout") }
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "marginmind-no-network-v1", encodedContentRuleList: Self.blockRules
    ) { [weak self] rules, _ in
      guard let self = self, self.completion != nil else { return }
      guard let rules = rules else { self.fail("blocked"); return }
      let config = WKWebViewConfiguration()
      config.websiteDataStore = .nonPersistent()
      config.userContentController.add(rules)
      // No page-supplied HTML is loaded into the live document.
      let view = WKWebView(frame: .zero, configuration: config)
      self.webView = view
      view.navigationDelegate = self
      view.loadHTMLString("""
        <!doctype html><html><head><meta http-equiv="Content-Security-Policy"
        content="default-src 'none'; script-src 'none'; connect-src 'none'; frame-src 'none';
        img-src 'none'; style-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        </head><body></body></html>
        """, baseURL: nil)
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // Only the locally loaded blank document is allowed, including child frames.
    decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard completion != nil else { return }
    let input = String(data: try! JSONSerialization.data(withJSONObject: [html]), encoding: .utf8)!
    // JSON serialization, never interpolation of page code. DOMParser's scripts
    // are inert; content rules and CSP additionally deny all network resources.
    let code = script + """
      ;(function() {
        const doc = new DOMParser().parseFromString(\(input)[0], 'text/html');
        const canonical = doc.querySelector('link[rel=canonical]')?.getAttribute('href') || null;
        const login = doc.querySelector('input[type=password]') !== null;
        doc.querySelectorAll('script,iframe,object,embed,link,meta[http-equiv],base,style').forEach(n => n.remove());
        const article = new Readability(doc, {disableJSONLD: true, maxElemsToParse: 50000}).parse();
        if (!article || !article.textContent.trim()) return {error: login ? 'login_required' : 'unparseable'};
        if (login && article.textContent.trim().length < 300) return {error: 'login_required'};
        return {title: article.title || '', html: article.content, text: article.textContent, canonical: canonical};
      })();
      """
    webView.evaluateJavaScript(code) { [weak self] value, error in
      guard let self = self else { return }
      guard error == nil, let result = value as? [String: Any] else { self.fail("unparseable"); return }
      if let reason = result["error"] as? String { self.fail(reason); return }
      self.finish(result)
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("unparseable") }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    fail("blocked")
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("unparseable") }
  func cancel() { fail("cancelled") }
  private func fail(_ code: String) { finish(FlutterError(code: code, message: nil, details: nil)) }
  private func finish(_ value: Any?) {
    guard let callback = completion else { return }
    completion = nil
    timer?.invalidate(); timer = nil
    webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil
    callback(value)
  }
}
