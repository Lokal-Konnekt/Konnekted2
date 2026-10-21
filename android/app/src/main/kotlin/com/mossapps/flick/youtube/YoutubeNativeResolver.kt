package com.mossapps.flick.youtube

import android.content.Context
import android.webkit.CookieManager
import com.mossapps.flick.youtube.potoken.PoTokenGenerator
import com.mossapps.flick.youtube.potoken.PoTokenWebView
import kotlinx.coroutines.withTimeout
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Android entry point for BitChord's InnerTubeX + BotGuard PoToken stream path.
 * The fast public-client walk remains first; this is the cipher/token-aware
 * fallback for media URLs which direct clients cannot actually stream.
 */
internal object YoutubeNativeResolver {
    @Volatile
    private var initialized = false

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        val app = context.applicationContext
        val preferences = app.getSharedPreferences("innertubex_player_config", Context.MODE_PRIVATE)
        val tokenProvider = PoTokenGenerator(
            createMinter = { PoTokenWebView.getNewPoTokenGenerator(app) },
            available = { runCatching { CookieManager.getInstance() }.isSuccess },
        )
        InnerTubeXResolver.init(
            filesDir = app.filesDir,
            store = object : InnerTubeXResolver.ConfigStore {
                override fun getString(key: String): String? = preferences.getString(key, null)
                override fun getLong(key: String): Long? =
                    if (preferences.contains(key)) preferences.getLong(key, 0L) else null
                override fun putString(key: String, value: String) =
                    preferences.edit().putString(key, value).apply()
                override fun putLong(key: String, value: Long) =
                    preferences.edit().putLong(key, value).apply()
            },
            poTokenProvider = tokenProvider.asTokenProvider(),
        )
        initialized = true
    }

    suspend fun resolveStream(
        videoId: String,
        cookie: String?,
        visitorData: String?,
    ): Map<String, Any?> {
        check(initialized) { "YouTube resolver is not initialized." }
        if (Innertube.updateSession(cookie, visitorData)) {
            InnerTubeXResolver.onSessionChanged()
        }
        val stream = withTimeout(90_000L) {
            InnerTubeXResolver.resolvePlayable(videoId, maxAttempts = 6)
        }
        val length = stream.url.toHttpUrlOrNull()
            ?.queryParameter("clen")
            ?.toLongOrNull()
        return mapOf(
            "url" to stream.url,
            "length" to length,
            "mime" to stream.mimeType,
            "headers" to stream.headers,
        )
    }
}
