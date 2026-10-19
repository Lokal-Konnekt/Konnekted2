package com.mossapps.flick

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Switches the launcher icon to the alias whose sticker matches the accent.
 *
 * Desktop redraws its Dock/taskbar icon live; Android can only pick one of
 * the pre-built `.LauncherIcon<Accent>` aliases in the manifest. Swapping
 * aliases can make some launchers close the app, so Dart only records the
 * wanted accent and the swap happens in [applyPending], called from
 * `onStop`, when the app is already in the background.
 */
object LauncherIcon {
    private const val CHANNEL = "lokal/launcher_icon"
    private const val PREFS = "lokal_launcher_icon"
    private const val KEY_WANTED = "wanted"
    private const val TAG = "LauncherIcon"

    /** Must match the aliases in AndroidManifest.xml and LokalAccent.presets. */
    val accents = listOf(
        "lime", "purple", "pink", "orange", "blue", "red",
        "teal", "white", "yellow", "cyan", "magenta", "gray",
    )
    private const val DEFAULT = "lime"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAccent" -> {
                    val accent = call.argument<String>("accent")
                    if (accent == null || accent !in accents) {
                        result.error("bad_accent", "Unknown accent: $accent", null)
                    } else {
                        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit().putString(KEY_WANTED, accent).apply()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Enables the wanted alias and disables the others, if anything changed. */
    fun applyPending(context: Context) {
        val wanted = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WANTED, null) ?: return
        val pm = context.packageManager
        try {
            val current = accents.firstOrNull { isEnabled(pm, context, it) } ?: DEFAULT
            if (current == wanted) return
            // Enable first, so there is never a moment with no launcher entry.
            setEnabled(pm, context, wanted, true)
            for (accent in accents) {
                if (accent != wanted) setEnabled(pm, context, accent, false)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not switch the launcher icon: ${e.message}")
        }
    }

    private fun component(context: Context, accent: String) = ComponentName(
        context.packageName,
        "com.mossapps.flick.LauncherIcon${accent.replaceFirstChar { it.uppercase() }}",
    )

    private fun isEnabled(pm: PackageManager, context: Context, accent: String): Boolean =
        when (pm.getComponentEnabledSetting(component(context, accent))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            // Default: whatever the manifest says, which is lime only.
            else -> accent == DEFAULT
        }

    private fun setEnabled(pm: PackageManager, context: Context, accent: String, on: Boolean) {
        pm.setComponentEnabledSetting(
            component(context, accent),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
