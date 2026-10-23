package com.mossapps.flick

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RendererCompatibilityTest {
    @Test
    fun s25UltraVariantsUseSkia() {
        for (model in listOf("SM-S938B", "SM-S938U", "SM-S938U1", "SM-S9380", "SM-S938N", "SM-S938W", "SM-S938E")) {
            assertTrue(RendererCompatibility.shouldDisableImpeller("samsung", model))
            assertArrayEquals(
                arrayOf("--enable-impeller=false"),
                RendererCompatibility.flutterEngineArgs("SAMSUNG", model),
            )
        }
    }

    @Test
    fun otherSamsungModelsKeepImpeller() {
        for (model in listOf("SM-S931B", "SM-S936U", "SM-S928B", "SM-F956B")) {
            assertFalse(RendererCompatibility.shouldDisableImpeller("samsung", model))
            assertNull(RendererCompatibility.flutterEngineArgs("samsung", model))
        }
    }

    @Test
    fun unaffectedAndroidDevicesKeepImpeller() {
        assertFalse(RendererCompatibility.shouldDisableImpeller("Xiaomi", "25113PN0EG"))
        assertNull(RendererCompatibility.flutterEngineArgs("Xiaomi", "25113PN0EG"))
        assertNull(RendererCompatibility.flutterEngineArgs("Google", "Pixel 10"))
        assertNull(RendererCompatibility.flutterEngineArgs("other", "SM-S938B"))
    }
}
