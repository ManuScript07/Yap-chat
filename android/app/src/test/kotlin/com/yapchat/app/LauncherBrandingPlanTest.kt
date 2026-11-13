package com.yapchat.app

import org.junit.Assert.*
import org.junit.Test

class LauncherBrandingPlanTest {
    @Test fun initialMatchingLanguageDoesNotReplaceTheLauncher() {
        for (language in listOf("ru", "en")) {
            val initial = mapOf("LauncherDefault" to true, "LauncherRussian" to false, "LauncherEnglish" to false)
            assertTrue(LauncherBrandingPlan.changes(language, initial, language).isEmpty())
        }
    }
    @Test fun allStatesConvergeToOneLauncherAndRemainIdempotent() {
        for (bits in 0..7) for (language in listOf("ru", "en")) for (system in listOf("ru", "en")) {
            val state = LauncherBrandingPlan.names.mapIndexed { index, name -> name to (bits and (1 shl index) != 0) }.toMap().toMutableMap()
            val changes = LauncherBrandingPlan.changes(language, state, system)
            var hadLauncher = state.values.any { it }
            for ((name, enabled) in changes) {
                state[name] = enabled
                if (hadLauncher) assertTrue(state.values.any { it })
                hadLauncher = hadLauncher || enabled
            }
            assertEquals(1, state.values.count { it })
            assertTrue(LauncherBrandingPlan.changes(language, state, system).isEmpty())
            if (state.getValue("LauncherDefault")) assertEquals(language, system)
            else assertTrue(state.getValue(if (language == "ru") "LauncherRussian" else "LauncherEnglish"))
            assertFalse(state.containsKey("MainActivity"))
        }
    }
    @Test fun switchingAwayAndBackEnablesDestinationFirst() {
        val russian = mapOf("LauncherDefault" to false, "LauncherRussian" to true, "LauncherEnglish" to false)
        assertEquals(listOf("LauncherEnglish" to true, "LauncherRussian" to false), LauncherBrandingPlan.changes("en", russian, "ru"))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsUnknownLanguages() {
        LauncherBrandingPlan.changes("other", emptyMap(), "ru")
    }
}
