package com.yapchat.app

import org.junit.Assert.assertEquals
import org.junit.Test

class ResumeInsetsRecoveryTest {
    private class Harness {
        data class Job(val at: Long, val action: Runnable)
        val jobs = mutableListOf<Job>()
        val requests = mutableListOf<(Boolean) -> Unit>()
        var ready = true
        var synced = 0
        var now = 0L
        val recovery = ResumeInsetsRecovery(
            post = { delay, action -> jobs.add(Job(now + delay, action)) },
            isReady = { ready },
            restoreFocusedInput = { requests.add(it) },
            syncHiddenInsets = { synced++ },
        )

        fun advance(ms: Long = 0) {
            val until = now + ms
            var remaining = 100
            while (jobs.any { it.at <= until }) {
                check(remaining-- > 0) { "Unbounded recovery loop" }
                val job = jobs.minBy { it.at }
                jobs.remove(job)
                now = job.at
                job.action.run()
            }
            now = until
        }

        fun begin() {
            recovery.onBackground()
            recovery.onForeground()
            advance()
        }
    }

    @Test fun coldStartDoesNotRequestKeyboard() {
        val h = Harness()
        h.recovery.onForeground()
        h.advance(2000)
        assertEquals(0, h.requests.size)
        assertEquals(0, h.synced)
    }

    @Test fun resumeAndFocusCoalesceIntoOneOwnerRequest() {
        val h = Harness()
        h.recovery.onBackground()
        repeat(6) { h.recovery.onForeground() }
        h.advance()
        repeat(6) { h.recovery.onForeground() }
        assertEquals(1, h.requests.size)
    }

    @Test fun requestWaitsForResumedFocusedWindow() {
        val h = Harness()
        h.ready = false
        h.begin()
        assertEquals(0, h.requests.size)
        h.ready = true
        h.recovery.onForeground()
        h.advance()
        assertEquals(1, h.requests.size)
    }

    @Test fun restoredEditorNeverGetsHiddenInsetsForcedOverIt() {
        val h = Harness()
        h.begin()
        h.requests.single()(true)
        h.advance(5000)
        assertEquals(0, h.synced)
        assertEquals(1, h.requests.size)
        assertEquals(0, h.jobs.size)
    }

    @Test fun declinedRestoreRepairsInsetsOnlyTwice() {
        val h = Harness()
        h.begin()
        h.requests.single()(false)
        assertEquals(1, h.synced)
        h.advance(299)
        assertEquals(1, h.synced)
        h.advance(1)
        assertEquals(2, h.synced)
        h.advance(5000)
        assertEquals(2, h.synced)
        assertEquals(1, h.requests.size)
    }

    @Test fun unresponsiveDartHasBoundedFallbackNotEndlessPolling() {
        val h = Harness()
        h.begin()
        h.advance(999)
        assertEquals(0, h.synced)
        h.advance(1)
        assertEquals(1, h.synced)
        h.advance(5000)
        assertEquals(2, h.synced)
        assertEquals(0, h.jobs.size)
    }

    @Test fun lateOrDuplicateReplyCannotRestartRecovery() {
        val h = Harness()
        h.begin()
        h.advance(1000)
        h.requests.single()(true)
        h.requests.single()(false)
        h.advance(1000)
        assertEquals(2, h.synced)
        assertEquals(1, h.requests.size)
    }

    @Test fun firstAcceptedReplyWins() {
        val h = Harness()
        h.begin()
        h.requests.single()(true)
        h.requests.single()(false)
        h.advance(2000)
        assertEquals(0, h.synced)
    }

    @Test fun backgroundInvalidatesQueuedFrame() {
        val h = Harness()
        h.recovery.onBackground()
        h.recovery.onForeground()
        h.recovery.onBackground()
        h.advance()
        assertEquals(0, h.requests.size)
    }

    @Test fun secondAppSwitchInvalidatesReplyFromThePreviousReturn() {
        val h = Harness()
        h.begin()
        val old = h.requests.single()
        h.recovery.onBackground()
        old(false)
        h.recovery.onForeground()
        h.advance()
        assertEquals(2, h.requests.size)
        h.requests.last()(true)
        h.advance(2000)
        assertEquals(0, h.synced)
    }

    @Test fun backgroundCancelsFollowupInsetRepair() {
        val h = Harness()
        h.begin()
        h.requests.single()(false)
        h.recovery.onBackground()
        h.advance(2000)
        assertEquals(1, h.synced)
    }

    @Test fun unfocusedWindowDoesNotReceiveForcedMetrics() {
        val h = Harness()
        h.begin()
        h.ready = false
        h.requests.single()(false)
        h.advance(2000)
        assertEquals(0, h.synced)
    }

    @Test fun disposalCancelsOutstandingCallbacksAndTimeouts() {
        val h = Harness()
        h.begin()
        h.recovery.dispose()
        h.requests.single()(false)
        h.advance(5000)
        h.recovery.onBackground()
        h.recovery.onForeground()
        h.advance()
        assertEquals(0, h.synced)
        assertEquals(1, h.requests.size)
    }

    @Test fun eachReturnCanRestoreExactlyOnce() {
        val h = Harness()
        repeat(5) {
            h.begin()
            h.requests.last()(true)
        }
        h.advance(5000)
        assertEquals(5, h.requests.size)
        assertEquals(0, h.synced)
    }

}
