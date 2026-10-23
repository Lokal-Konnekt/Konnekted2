package com.mossapps.flick

import java.util.Locale

/**
 * Work around Impeller/Vulkan rendering regressions reported on the Galaxy S25 Ultra.
 *
 * Keep this limited to the S25 Ultra (SM-S938 family) rather than all Samsung
 * phones or all Android 17 devices. Other devices retain their normal renderer,
 * including Xiaomi devices that do not reproduce the reported issue.
 *
 * Flutter engine flags must be supplied before the FlutterEngine is created;
 * a Dart appearance/performance setting cannot switch rendering backends.
 * Remove this compatibility exception once the upstream driver/engine is fixed.
 */
internal object RendererCompatibility {
    private const val GALAXY_S25_ULTRA_MODEL = "SM-S938"

    fun shouldDisableImpeller(manufacturer: String, model: String): Boolean {
        return manufacturer.trim().equals("samsung", ignoreCase = true) &&
            model.trim().uppercase(Locale.ROOT).startsWith(GALAXY_S25_ULTRA_MODEL)
    }

    fun flutterEngineArgs(manufacturer: String, model: String): Array<String>? =
        if (shouldDisableImpeller(manufacturer, model)) {
            arrayOf("--enable-impeller=false")
        } else {
            null
        }
}
