package com.yapchat.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultNetworkStatusTest {
    private class Harness : DefaultNetworkStatus.Source<String> {
        var network: String? = "wifi"
        var snapshotFailure = false
        var registerFailure = false
        var unregisterFailure = false
        var duringRegister: ((DefaultNetworkStatus.Listener<String>) -> Unit)? = null
        val listeners = mutableListOf<DefaultNetworkStatus.Listener<String>>()
        val jobs = mutableListOf<() -> Unit>()
        val events = mutableListOf<Map<String, Any?>>()
        val operations = mutableListOf<String>()
        var active = 0
        var unregistered = 0
        val status = DefaultNetworkStatus(this) { jobs.add(it) }

        override fun snapshot(): String? {
            operations.add("snapshot")
            if (snapshotFailure) throw SecurityException("denied")
            return network
        }

        override fun register(listener: DefaultNetworkStatus.Listener<String>): () -> Unit {
            operations.add("register")
            if (registerFailure) throw IllegalStateException("service unavailable")
            listeners.add(listener)
            active++
            duringRegister?.invoke(listener)
            return {
                active--
                unregistered++
                if (unregisterFailure) throw IllegalArgumentException("already removed")
            }
        }

        fun listen() = status.listen { events.add(it) }
        fun drain() {
            while (jobs.isNotEmpty()) jobs.removeAt(0).invoke()
        }
        fun values() = events.map { it["available"] }
        fun generations() = events.map { it["generation"] }
    }

    @Test fun listenImmediatelySendsExactOnlinePayload() {
        val h = Harness()
        h.listen()
        assertEquals(listOf(mapOf("available" to true, "generation" to 1)), h.events)
        assertEquals(listOf("register", "snapshot"), h.operations)
        assertEquals(1, h.active)
    }

    @Test fun listenImmediatelySendsOfflineSnapshot() {
        val h = Harness()
        h.network = null
        h.listen()
        assertEquals(listOf(false), h.values())
        assertEquals(listOf(mapOf("available" to false, "generation" to 0)), h.events)
    }

    @Test fun callbackEventsWaitForMainDispatcher() {
        val h = Harness()
        h.listen()
        val callback = h.listeners.single()
        val worker = Thread { callback.onLost("wifi") }
        worker.start()
        worker.join()
        assertEquals(listOf(true), h.values())
        assertEquals(listOf(1), h.generations())
        h.drain()
        assertEquals(listOf(true, false), h.values())
        assertEquals(listOf(1, 2), h.generations())
    }

    @Test fun handoverIgnoresLateLossOfOldNetwork() {
        val h = Harness()
        h.listen()
        val callback = h.listeners.single()
        callback.onAvailable("mobile")
        callback.onLost("wifi")
        h.drain()
        assertEquals(listOf(true, true), h.values())
        assertEquals(listOf(1, 2), h.generations())
        callback.onLost("mobile")
        h.drain()
        assertEquals(listOf(true, true, false), h.values())
        assertEquals(listOf(1, 2, 3), h.generations())
    }

    @Test fun trueToTrueHandoffEmitsNewGenerationAndStaleOldLossIsSilent() {
        val h = Harness()
        h.listen()
        val callback = h.listeners.single()
        callback.onAvailable("mobile")
        h.drain()
        val expected = listOf(
            mapOf("available" to true, "generation" to 1),
            mapOf("available" to true, "generation" to 2),
        )
        assertEquals(expected, h.events)
        callback.onLost("wifi")
        callback.onAvailable("mobile")
        h.drain()
        assertEquals(expected, h.events)
    }

    @Test fun availableForSnapshotNetworkDoesNotAdvanceGenerationOrEmit() {
        val h = Harness()
        h.listen()
        // Identity uses equality, as Android can supply distinct Network wrappers.
        h.listeners.single().onAvailable(String(charArrayOf('w', 'i', 'f', 'i')))
        h.drain()
        assertEquals(listOf(mapOf("available" to true, "generation" to 1)), h.events)
    }

    @Test fun routeReturningToEarlierIdentityStillAdvancesGeneration() {
        val h = Harness()
        h.listen()
        h.listeners.single().onAvailable("mobile")
        h.listeners.single().onAvailable("wifi")
        h.drain()
        assertEquals(listOf(true, true, true), h.values())
        assertEquals(listOf(1, 2, 3), h.generations())
    }

    @Test fun lossBeforeFirstAvailableUsesSnapshotIdentity() {
        val h = Harness()
        h.listen()
        h.listeners.single().onLost("wifi")
        h.drain()
        assertEquals(listOf(true, false), h.values())
    }

    @Test fun lossOfUnrelatedNetworkDoesNotInvalidateSnapshot() {
        val h = Harness()
        h.listen()
        h.listeners.single().onLost("old")
        h.drain()
        assertEquals(listOf(true), h.values())
        assertEquals(listOf(1), h.generations())
    }

    @Test fun callbackDuringRegistrationIsAppliedAfterSnapshot() {
        val h = Harness()
        h.duringRegister = { it.onLost("wifi") }
        h.listen()
        assertEquals(listOf(true), h.values())
        h.drain()
        assertEquals(listOf(true, false), h.values())
    }

    @Test fun lossThenReplacementReportsBothTransitions() {
        val h = Harness()
        h.listen()
        h.listeners.single().onLost("wifi")
        h.listeners.single().onAvailable("mobile")
        h.drain()
        assertEquals(listOf(true, false, true), h.values())
        assertEquals(listOf(1, 2, 3), h.generations())
    }

    @Test fun duplicateAvailabilityAndLossAreCoalesced() {
        val h = Harness()
        h.listen()
        repeat(3) { h.listeners.single().onAvailable("wifi") }
        repeat(3) { h.listeners.single().onLost("wifi") }
        h.drain()
        assertEquals(listOf(true, false), h.values())
        assertEquals(listOf(1, 2), h.generations())
    }

    @Test fun cancelUnregistersOnceAndDropsQueuedAndLateCallbacks() {
        val h = Harness()
        h.listen()
        h.listeners.single().onLost("wifi")
        h.status.cancel()
        h.status.cancel()
        h.listeners.single().onAvailable("mobile")
        h.drain()
        assertEquals(0, h.active)
        assertEquals(1, h.unregistered)
        assertEquals(listOf(true), h.values())
    }

    @Test fun relistenHasOneCallbackFreshSnapshotAndRejectsOldSession() {
        val h = Harness()
        h.listen()
        val old = h.listeners.single()
        old.onLost("wifi")
        h.network = null
        h.listen()
        old.onAvailable("wifi")
        h.drain()
        assertEquals(1, h.active)
        assertEquals(1, h.unregistered)
        assertEquals(listOf(true, false), h.values())
        h.listeners.last().onAvailable("mobile")
        h.drain()
        assertEquals(listOf(true, false, true), h.values())
        assertEquals(listOf(1, 0, 1), h.generations())
    }

    @Test fun disposeUnregistersAndPermanentlyRejectsEventsAndListen() {
        val h = Harness()
        h.listen()
        h.listeners.single().onLost("wifi")
        h.status.dispose()
        h.status.dispose()
        h.listeners.single().onAvailable("mobile")
        h.listen()
        h.drain()
        assertEquals(0, h.active)
        assertEquals(1, h.unregistered)
        assertEquals(listOf(true), h.values())
    }

    @Test fun disposeBeforeListenNeverRegisters() {
        val h = Harness()
        h.status.dispose()
        h.listen()
        assertTrue(h.listeners.isEmpty())
        assertTrue(h.events.isEmpty())
    }

    @Test fun registrationFailureIsUnknownAndCanRetryOnNewListen() {
        val h = Harness()
        h.registerFailure = true
        h.listen()
        assertEquals(listOf(mapOf("available" to null, "generation" to 0)), h.events)
        assertEquals(0, h.active)
        h.registerFailure = false
        h.listen()
        assertEquals(listOf(null, true), h.values())
        assertEquals(listOf(0, 1), h.generations())
        h.status.dispose()
        assertEquals(1, h.unregistered)
    }

    @Test fun snapshotFailureIsUnknownUntilCallbackAndStillUnregisters() {
        val h = Harness()
        h.snapshotFailure = true
        h.listen()
        assertEquals(listOf<Boolean?>(null), h.values())
        h.listeners.single().onAvailable("mobile")
        h.drain()
        assertEquals(listOf(null, true), h.values())
        assertEquals(listOf(0, 1), h.generations())
        h.status.cancel()
        assertEquals(0, h.active)
    }

    @Test fun lossWithoutAnySnapshotOrAvailableResolvesUnknownToOffline() {
        val h = Harness()
        h.snapshotFailure = true
        h.listen()
        h.listeners.single().onLost("wifi")
        h.drain()
        assertEquals(listOf(null, false), h.values())
        assertEquals(listOf(0, 0), h.generations())
    }

    @Test fun cleanupFailureDoesNotKeepSessionAliveOrBlockRelisten() {
        val h = Harness()
        h.listen()
        h.unregisterFailure = true
        h.status.cancel()
        h.listeners.single().onLost("wifi")
        h.drain()
        h.listen()
        assertEquals(listOf(true, true), h.values())
        assertEquals(1, h.active)
    }
}
