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
    private var terminal = false
    private var committed = false
    private var finished = false
    private var mainUrl: String? = null
    private fun allowed(raw: String): Boolean {
        val uri = Uri.parse(raw)
        return uri.scheme?.lowercase() in listOf("http", "https") && !uri.host.isNullOrEmpty()
    }
    private fun emit(kind: String, error: String = "other") {
        if (!closed) channel.invokeMethod("event", mapOf("kind" to kind, "navigationId" to generation,
            "url" to web.url, "back" to web.canGoBack(), "forward" to web.canGoForward(), "error" to error))
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
            override fun onPageStarted(view: WebView, url: String?, icon: Bitmap?) {
                generation++; terminal = false; committed = false; finished = false; mainUrl = url; emit("start")
            }
            override fun onPageCommitVisible(view: WebView, url: String?) {
                if (url == mainUrl) { committed = true; if (finished && !terminal) emit("loaded") }
            }
            override fun onPageFinished(view: WebView, url: String?) {
                if (url == mainUrl) { finished = true; if (committed && !terminal) emit("loaded") }
                CookieManager.getInstance().flush()
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame && request.url.toString() == mainUrl) {
                    terminal = true
                    emit("failed", when (error.errorCode) {
                        ERROR_TIMEOUT -> "timeout"
                        ERROR_HOST_LOOKUP -> "host"
                        ERROR_FAILED_SSL_HANDSHAKE -> "certificate"
                        ERROR_CONNECT, ERROR_IO -> "offline"
                        else -> "other"
                    })
                }
            }
            // HTTP errors still contain the site's document (including login walls).
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) {
                handler.cancel()
                if (error.url == mainUrl) { terminal = true; emit("failed", "certificate") }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
        }
        web.setDownloadListener { _, _, _, _, _ -> terminal = true; emit("download") }
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
