package com.mossapps.flick

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Media3/just_audio can decode or pass through E-AC-3 JOC using Android's
 * licensed codecs/output stack. Do not decode with ffmpeg: that loses the
 * Atmos object metadata. Never infer JOC from an "ec-3" extension alone.
 */
internal object LokalAtmos {
    private const val CHANNEL = "lokal/atmos"
    private const val JOC = "audio/eac3-joc"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "inspect" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) result.error("INVALID_PATH", "Missing audio file", null)
                    else result.success(isJocFile(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun capabilities(): Map<String, Boolean> {
        if (Build.VERSION.SDK_INT < 28) {
            return mapOf("available" to false, "jocDecoder" to false, "passthrough" to false)
        }

        // Only explicitly supported JOC decoders count. A generic E-AC-3
        // decoder can reproduce 5.1 but not necessarily Atmos objects.
        val codecSupported = try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                !codec.isEncoder && codec.supportedTypes.any { it.equals(JOC, true) }
            }
        } catch (_: Exception) { false }

        val passthrough = if (Build.VERSION.SDK_INT >= 29) try {
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_E_AC3_JOC)
                .setSampleRate(48000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
                .build()
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            AudioTrack.isDirectPlaybackSupported(format, attributes)
        } catch (_: Exception) { false } else false
        return mapOf(
            "available" to (codecSupported || passthrough),
            "jocDecoder" to codecSupported,
            "passthrough" to passthrough
        )
    }

    private fun isJocFile(path: String): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            (0 until extractor.trackCount).any { index ->
                val format = extractor.getTrackFormat(index)
                format.getString(MediaFormat.KEY_MIME)?.equals(JOC, true) == true
            }
        } catch (_: Exception) {
            false
        } finally {
            extractor.release()
        }
    }
}
