package com.mossapps.flick

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Switches the launcher icon to the alias whose sticker matches the accent.
 *
 * Desktop redraws its Dock/taskbar icon live; Android can only pick one of
 * the pre-built `.LauncherIcon<Accent>` aliases in the manifest. Swapping
 * aliases uses DONT_KILL_APP. Apply immediately when Dart sends the saved
 * accent, and retry on registration/onStop to repair launcher state after
 * an upgrade or an interrupted change.
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
    private var aliases: Map<String, String>? = null

    fun onStop(context: Context) {
        applyPending(context)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        applyPending(context)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAccent" -> {
                    val accent = call.argument<String>("accent")
                    if (accent == null || accent !in accents) {
                        result.error("bad_accent", "Unknown accent: $accent", null)
                    } else {
                        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit().putString(KEY_WANTED, accent).apply()
                        // Xiaomi/HyperOS can retain the foreground task for a long
                        // time. DONT_KILL_APP lets us update the launcher now.
                        applyPending(context)
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
            val current = accents.filter { isEnabled(pm, context, it) }
            if (current == listOf(wanted)) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.setComponentEnabledSettings(accents.map { accent ->
                    PackageManager.ComponentEnabledSetting(
                        component(context, accent),
                        if (accent == wanted) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                })
                return
            }
            // Enable first, so there is never a moment with no launcher entry.
            setEnabled(pm, context, wanted, true)
            for (accent in accents) {
                if (accent != wanted) setEnabled(pm, context, accent, false)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not switch the launcher icon: ${e.message}")
        }
    }

    private fun component(context: Context, accent: String): ComponentName {
        val suffix = "LauncherIcon${accent.replaceFirstChar { it.uppercase() }}"
        val names = aliases ?: context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS,
        ).activities.orEmpty().associate { it.name.substringAfterLast('.') to it.name }
            .also { aliases = it }
        val name = names[suffix] ?: error("Missing launcher alias: $suffix")
        return ComponentName(context.packageName, name)
    }

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
