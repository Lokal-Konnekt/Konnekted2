package com.mossapps.flick

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.util.Log
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
    private const val TAG = "LokalAtmos"

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

    private fun capabilities(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < 28) {
            Log.i(TAG, "event=capability sdk=${Build.VERSION.SDK_INT} available=false reason=sdk_unsupported")
            return mapOf("available" to false, "jocDecoder" to false,
                "passthrough" to false, "sdk" to Build.VERSION.SDK_INT)
        }

        // Only explicitly supported JOC decoders count. A generic E-AC-3
        // decoder can reproduce 5.1 but not necessarily Atmos objects.
        val codecSupported = try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                !codec.isEncoder && codec.supportedTypes.any { it.equals(JOC, true) }
            }
        } catch (error: Exception) {
            Log.w(TAG, "event=decoder_probe_error type=${error.javaClass.simpleName}")
            false
        }

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
        } catch (error: Exception) {
            Log.w(TAG, "event=passthrough_probe_error type=${error.javaClass.simpleName}")
            false
        } else false
        val available = codecSupported || passthrough
        Log.i(TAG, "event=capability sdk=${Build.VERSION.SDK_INT} jocDecoder=$codecSupported passthrough=$passthrough available=$available")
        return mapOf(
            "available" to available,
            "jocDecoder" to codecSupported,
            "passthrough" to passthrough,
            "sdk" to Build.VERSION.SDK_INT
        )
    }

    private fun isJocFile(path: String): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            val found = (0 until extractor.trackCount).any { index ->
                val format = extractor.getTrackFormat(index)
                format.getString(MediaFormat.KEY_MIME)?.equals(JOC, true) == true
            }
            // No file path, filename, URL, or provider response is logged.
            Log.i(TAG, "event=source_probe tracks=${extractor.trackCount} joc=$found")
            found
        } catch (error: Exception) {
            Log.w(TAG, "event=source_probe_error type=${error.javaClass.simpleName}")
            false
        } finally {
            extractor.release()
        }
    }
}
