package io.github.mylxsw.marginmind

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.*
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.*
import org.json.JSONTokener

/** No addJavascriptInterface: untrusted pages have no application bridge. */
class BrowserFactory(private val context: Context, private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val tabs = mutableMapOf<Int, NativeBrowser>()
    init {
        MethodChannel(messenger, "marginmind/browser").setMethodCallHandler { call, result ->
            if (call.method != "clearData") { result.notImplemented(); return@setMethodCallHandler }
            tabs.values.toList().forEach { it.dispose() }; tabs.clear()
            CookieManager.getInstance().removeAllCookies {
                CookieManager.getInstance().flush()
                WebStorage.getInstance().deleteAllData()
                WebView(context).apply { clearCache(true); clearHistory(); clearFormData(); destroy() }
                result.success(null)
            }
        }
    }
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val id = ((args as Map<*, *>)["id"] as Number).toInt()
        return NativeBrowser(context, messenger, id) { tabs.remove(id) }.also { tabs[id] = it }
    }
}
class NativeBrowser(context: Context, messenger: BinaryMessenger, id: Int, private val onClose: () -> Unit) : PlatformView {
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "marginmind/browser/$id")
    private var generation = 0
    private var closed = false
    private fun allowed(raw: String): Boolean {
        val uri = Uri.parse(raw)
        return uri.scheme?.lowercase() in listOf("http", "https") && !uri.host.isNullOrEmpty()
    }
    private fun emit(kind: String) {
        if (!closed) channel.invokeMethod("event", mapOf("kind" to kind, "navigationId" to generation,
            "url" to web.url, "back" to web.canGoBack(), "forward" to web.canGoForward()))
    }
    init {
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false; setSupportMultipleWindows(true)
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        CookieManager.getInstance().setAcceptCookie(true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = !allowed(request.url.toString())
            override fun onPageStarted(view: WebView, url: String?, icon: Bitmap?) { generation++; emit("start") }
            override fun onPageFinished(view: WebView, url: String?) { emit("loaded"); CookieManager.getInstance().flush() }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) { if (request.isForMainFrame) emit("failed") }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) { if (request.isForMainFrame) emit("failed") }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) { handler.cancel(); emit("failed") }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
        }
        web.setDownloadListener { _, _, _, _, _ -> web.stopLoading(); emit("failed") }
        channel.setMethodCallHandler { call, result ->
            if (closed) { result.success(null); return@setMethodCallHandler }
            when (call.method) {
                "navigate" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (!allowed(url)) result.error("invalid_url", null, null)
                    else { web.loadUrl(url); result.success(null) }
                }
                "back" -> { web.goBack(); result.success(null) }
                "forward" -> { web.goForward(); result.success(null) }
                "reload" -> { web.reload(); result.success(null) }
                "stop" -> { web.stopLoading(); result.success(null) }
                "evaluate" -> web.evaluateJavascript(call.argument<String>("script") ?: "") { raw ->
                    try { result.success(JSONTokener(raw).nextValue().let { if (it is String) it else null }) }
                    catch (_: Exception) { result.error("script_failed", null, null) }
                }
                "dispose" -> { dispose(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun getView() = web
    override fun dispose() {
        if (closed) return
        closed = true; channel.setMethodCallHandler(null); web.stopLoading()
        (web.parent as? android.view.ViewGroup)?.removeView(web)
        web.destroy(); onClose()
    }
}
