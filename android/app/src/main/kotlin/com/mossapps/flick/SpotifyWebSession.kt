package com.mossapps.flick

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageButton
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * BitChord-style Spotify web session support.
 *
 * The login is deliberately shown in one in-app WebView. The cookie stays in
 * Dart's encrypted store; this class only receives it when it needs to mint a
 * short-lived web-player bearer token for a Spotify API request.
 */
internal class SpotifyWebSession(private val activity: Activity) {

    data class MintedTokens(
        val accessToken: String,
        val clientToken: String?,
        val expiresAtMs: Long,
    ) {
        fun asMap(): Map<String, Any?> = mapOf(
            "accessToken" to accessToken,
            "clientToken" to clientToken,
            "expiresAtMs" to expiresAtMs,
        )
    }

    private data class LoginState(
        val dialog: Dialog,
        val webView: WebView,
        val callback: (String?) -> Unit,
    )

    private data class HarvestedToken(
        val accessToken: String,
        val expiresAtMs: Long,
        val clientId: String?,
    )

    private data class SessionInfo(
        val clientVersion: String,
        val deviceId: String,
    )

    private var loginState: LoginState? = null

    @SuppressLint("SetJavaScriptEnabled")
    fun authenticate(onResult: (String?) -> Unit) {
        if (loginState != null) {
            onResult(null)
            return
        }

        val dialog = Dialog(activity)
        val webView = WebView(activity)
        val container = FrameLayout(activity)
        val close = ImageButton(activity).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.TRANSPARENT)
            contentDescription = "Close Spotify sign-in"
            setOnClickListener { finishLogin(null) }
        }

        container.setBackgroundColor(Color.rgb(18, 18, 18))
        container.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        container.addView(
            close,
            FrameLayout.LayoutParams(56, 56, Gravity.TOP or Gravity.END),
        )

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.userAgentString = browserUserAgent(webView.settings.userAgentString)
        webView.setBackgroundColor(Color.rgb(18, 18, 18))
        val cookies = CookieManager.getInstance()
        cookies.setAcceptCookie(true)
        cookies.setAcceptThirdPartyCookies(webView, true)

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean = !isLoginHost(request.url)

            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                !isLoginHost(Uri.parse(url))

            override fun onPageFinished(view: WebView, url: String?) {
                if (!isSpotifyOpenUrl(url)) return
                val cookie = extractSessionCookie(cookies.getCookie(SPOTIFY_OPEN_URL))
                if (cookie != null) {
                    view.visibility = View.GONE
                    finishLogin(cookie)
                }
            }
        }

        loginState = LoginState(dialog, webView, onResult)
        dialog.setContentView(container)
        dialog.setOnCancelListener { finishLogin(null) }
        dialog.setOnKeyListener { _, keyCode, event ->
            if (keyCode != KeyEvent.KEYCODE_BACK || event.action != KeyEvent.ACTION_UP) {
                return@setOnKeyListener false
            }
            if (webView.canGoBack()) {
                webView.goBack()
            } else {
                finishLogin(null)
            }
            true
        }
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        dialog.show()
        dialog.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        webView.loadUrl(LOGIN_URL)
    }

    fun cancelLogin() {
        finishLogin(null)
    }

    fun clearSpotifyCookies() {
        val cookies = CookieManager.getInstance()
        for (url in COOKIE_URLS) {
            val names = cookies.getCookie(url)
                ?.split(";")
                ?.map { it.substringBefore("=").trim() }
                ?.filter { it.isNotEmpty() }
                .orEmpty()
            for (name in names) {
                val expired = "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/"
                cookies.setCookie(url, expired)
                cookies.setCookie(url, "$expired; Domain=.spotify.com")
            }
        }
        cookies.flush()
    }

    suspend fun mintTokens(spDc: String): MintedTokens? {
        val cookie = spDc.trim()
        if (cookie.isEmpty()) return null

        val harvested = withContext(Dispatchers.Main.immediate) {
            harvestAccessToken(cookie)
        } ?: return null
        val clientToken = withContext(Dispatchers.IO) {
            fetchClientToken(harvested.clientId)
        }
        return MintedTokens(
            accessToken = harvested.accessToken,
            clientToken = clientToken,
            expiresAtMs = harvested.expiresAtMs,
        )
    }

    private fun finishLogin(cookie: String?) {
        val active = loginState ?: return
        loginState = null
        active.webView.stopLoading()
        active.webView.destroy()
        active.dialog.dismiss()
        active.callback(cookie)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun harvestAccessToken(spDc: String): HarvestedToken? {
        val cookies = CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setCookie(SPOTIFY_OPEN_URL, "sp_dc=$spDc; Domain=.spotify.com; Path=/; Secure")
            setCookie(SPOTIFY_ACCOUNTS_URL, "sp_dc=$spDc; Domain=.spotify.com; Path=/; Secure")
            flush()
        }
        runCatching { WebStorage.getInstance().deleteAllData() }

        val deferred = CompletableDeferred<HarvestedToken?>()
        var webView: WebView? = null
        return try {
            webView = WebView(activity).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString = CANVAS_USER_AGENT
                cookies.setAcceptThirdPartyCookies(this, true)
                addJavascriptInterface(TokenBridge(deferred), BRIDGE_NAME)
                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                        view.evaluateJavascript(HOOK_SCRIPT, null)
                    }

                    override fun onPageFinished(view: WebView, url: String?) {
                        view.evaluateJavascript(HOOK_SCRIPT, null)
                    }
                }
                loadUrl(SPOTIFY_OPEN_URL)
            }
            withTimeoutOrNull(HARVEST_TIMEOUT_MS) { deferred.await() }
        } finally {
            runCatching {
                webView?.removeJavascriptInterface(BRIDGE_NAME)
                webView?.stopLoading()
                webView?.destroy()
            }
        }
    }

    private class TokenBridge(
        private val deferred: CompletableDeferred<HarvestedToken?>,
    ) {
        @JavascriptInterface
        fun onTokenPayload(payload: String?) {
            if (payload.isNullOrBlank() || deferred.isCompleted) return
            runCatching {
                val root = JSONObject(payload)
                val token = root.optString("accessToken").takeIf { it.isNotBlank() }
                if (token == null || root.optBoolean("isAnonymous", false)) return
                val expiresAt = root.optLong(
                    "accessTokenExpirationTimestampMs",
                    System.currentTimeMillis() + DEFAULT_TOKEN_LIFETIME_MS,
                ).takeIf { it > System.currentTimeMillis() }
                    ?: (System.currentTimeMillis() + DEFAULT_TOKEN_LIFETIME_MS)
                val clientId = root.optString("clientId").takeIf { it.isNotBlank() }
                deferred.complete(HarvestedToken(token, expiresAt, clientId))
            }
        }
    }

    private fun fetchClientToken(clientId: String?): String? {
        if (clientId.isNullOrBlank()) return null
        val session = loadSessionInfo() ?: return null
        val payload = JSONObject()
            .put(
                "client_data",
                JSONObject()
                    .put("client_version", session.clientVersion)
                    .put("client_id", clientId)
                    .put(
                        "js_sdk_data",
                        JSONObject()
                            .put("device_brand", "unknown")
                            .put("device_model", "unknown")
                            .put("os", "android")
                            .put("os_version", Build.VERSION.RELEASE.orEmpty())
                            .put("device_id", session.deviceId)
                            .put("device_type", "smartphone"),
                    ),
            )
        val connection = openConnection("https://clienttoken.spotify.com/v1/clienttoken")
            ?: return null
        return runCatching {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", CANVAS_USER_AGENT)
            connection.outputStream.use { output ->
                output.write(payload.toString().toByteArray(StandardCharsets.UTF_8))
            }
            if (connection.responseCode !in 200..299) return@runCatching null
            val root = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            if (root.optString("response_type") != "RESPONSE_GRANTED_TOKEN_RESPONSE") {
                return@runCatching null
            }
            root.optJSONObject("granted_token")
                ?.optString("token")
                ?.takeIf { it.isNotBlank() }
        }.getOrNull().also { connection.disconnect() }
    }

    private fun loadSessionInfo(): SessionInfo? {
        val connection = openConnection("https://open.spotify.com") ?: return null
        return runCatching {
            val html = connection.inputStream.bufferedReader().use { it.readText() }
            val deviceId = connection.headerFields.values
                .asSequence()
                .filterNotNull()
                .flatten()
                .mapNotNull { header -> Regex("sp_t=([^;]+)").find(header)?.groupValues?.get(1) }
                .firstOrNull()
                ?: UUID.randomUUID().toString()
            val encoded = Regex("<script id=\"appServerConfig\" type=\"text/plain\">([^<]+)</script>")
                .find(html)
                ?.groupValues
                ?.get(1)
                ?: return@runCatching null
            val config = JSONObject(
                String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8),
            )
            config.optString("clientVersion")
                .takeIf { it.isNotBlank() }
                ?.let { SessionInfo(it, deviceId) }
        }.getOrNull().also { connection.disconnect() }
    }

    private fun openConnection(rawUrl: String): HttpURLConnection? = runCatching {
        (URL(rawUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = NETWORK_TIMEOUT_MS
            readTimeout = NETWORK_TIMEOUT_MS
            instanceFollowRedirects = false
        }
    }.getOrNull()

    private fun extractSessionCookie(raw: String?): String? = raw
        ?.split(";")
        ?.map { it.trim() }
        ?.firstOrNull { it.startsWith("sp_dc=") }
        ?.substringAfter('=')
        ?.takeIf { it.isNotBlank() }

    private fun isSpotifyOpenUrl(rawUrl: String?): Boolean {
        val uri = rawUrl?.let(Uri::parse) ?: return false
        return uri.scheme == "https" && uri.host?.lowercase() == "open.spotify.com"
    }

    private fun isLoginHost(uri: Uri?): Boolean {
        if (uri?.scheme != "https") return false
        val host = uri.host?.lowercase() ?: return false
        return LOGIN_HOST_SUFFIXES.any { suffix -> host == suffix || host.endsWith(".$suffix") }
    }

    private fun browserUserAgent(platformUserAgent: String?): String {
        val stripped = platformUserAgent
            ?.replace("; wv", "")
            ?.replace(Regex("Version\\d+(\\.\\d+)*\\s*"), "")
            ?.replace("  ", " ")
            ?.trim()
        return stripped?.takeIf { it.contains("Chrome/") } ?: FALLBACK_USER_AGENT
    }

    private companion object {
        const val LOGIN_URL =
            "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F"
        const val SPOTIFY_OPEN_URL = "https://open.spotify.com/"
        const val SPOTIFY_ACCOUNTS_URL = "https://accounts.spotify.com/"
        const val BRIDGE_NAME = "KonnektedSpotifyTokenBridge"
        const val HARVEST_TIMEOUT_MS = 20_000L
        const val DEFAULT_TOKEN_LIFETIME_MS = 3_600_000L
        const val NETWORK_TIMEOUT_MS = 15_000
        const val CANVAS_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        const val FALLBACK_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Mobile) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"
        val COOKIE_URLS = listOf(
            "https://open.spotify.com",
            "https://accounts.spotify.com",
            "https://www.spotify.com",
            "https://spotify.com",
        )
        val LOGIN_HOST_SUFFIXES = listOf(
            "spotify.com",
            "scdn.co",
            "google.com",
            "gstatic.com",
            "facebook.com",
            "apple.com",
        )
        val HOOK_SCRIPT = """
            (function () {
              if (window.__konnektedSpotifyTokenHook) return;
              window.__konnektedSpotifyTokenHook = true;
              var report = function (body) {
                try { $BRIDGE_NAME.onTokenPayload(body); } catch (e) {}
              };
              var isToken = function (u) {
                try { return String(u).indexOf('/api/token') !== -1; } catch (e) { return false; }
              };
              var origFetch = window.fetch;
              if (origFetch) {
                window.fetch = function (input, init) {
                  var url = (input && input.url) ? input.url : input;
                  var result = origFetch.apply(this, arguments);
                  if (isToken(url)) {
                    try {
                      result.then(function (res) {
                        res.clone().text().then(report).catch(function () {});
                      }).catch(function () {});
                    } catch (e) {}
                  }
                  return result;
                };
              }
              var origOpen = XMLHttpRequest.prototype.open;
              XMLHttpRequest.prototype.open = function (method, url) {
                this.__konnektedSpotifyUrl = url;
                return origOpen.apply(this, arguments);
              };
              var origSend = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.send = function () {
                var xhr = this;
                try {
                  xhr.addEventListener('load', function () {
                    if (isToken(xhr.__konnektedSpotifyUrl)) {
                      try { report(xhr.responseText); } catch (e) {}
                    }
                  });
                } catch (e) {}
                return origSend.apply(this, arguments);
              };
            })();
        """.trimIndent()
    }
}
