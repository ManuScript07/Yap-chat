package com.yapchat.app

import org.junit.Assert.*
import org.junit.Test

class BrandingUpdateQueueTest {
    @Test fun coldStartAndAccountRestoreNeverChangeVisibleLauncher() {
        val applied = mutableListOf<String>()
        val queue = BrandingUpdateQueue { applied.add(it) }
        queue.request("ru")
        queue.request("en")
        queue.onHostStarted()
        assertTrue(applied.isEmpty())
        queue.onHostStopped()
        assertEquals(listOf("en"), applied)
    }

    @Test fun resumeDoesNotReplayCompletedUpdates() {
        val applied = mutableListOf<String>()
        val queue = BrandingUpdateQueue { applied.add(it) }
        queue.request("en")
        queue.onHostStopped()
        repeat(10) { queue.onHostStarted(); queue.onHostStopped() }
        assertEquals(listOf("en"), applied)
    }

    @Test fun lateBackgroundResultAppliesWithoutWaitingForAnotherResume() {
        val applied = mutableListOf<String>()
        val queue = BrandingUpdateQueue { applied.add(it) }
        queue.onHostStopped()
        queue.request("ru")
        assertEquals(listOf("ru"), applied)
    }

    @Test fun failedUpdateRetainsPendingLanguageForTheNextSafeStop() {
        var shouldFail = true
        val applied = mutableListOf<String>()
        val queue = BrandingUpdateQueue {
            if (shouldFail) throw IllegalStateException("PackageManager unavailable")
            applied.add(it)
        }
        queue.request("en")
        try { queue.onHostStopped(); fail("expected failure") } catch (_: IllegalStateException) {}
        shouldFail = false
        queue.onHostStarted()
        assertTrue(applied.isEmpty())
        queue.onHostStopped()
        assertEquals(listOf("en"), applied)
    }
}
