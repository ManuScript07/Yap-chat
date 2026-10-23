package com.yapchat.app

/** One owner-validated restore per return, with bounded hidden-inset fallback. */
internal class ResumeInsetsRecovery(
    private val post: (Long, Runnable) -> Unit,
    private val isReady: () -> Boolean,
    private val restoreFocusedInput: ((Boolean) -> Unit) -> Unit,
    private val syncHiddenInsets: () -> Unit,
) {
    private var pending = false
    private var scheduled = false
    private var inFlight = false
    private var disposed = false
    private var generation = 0

    fun onBackground() {
        if (disposed) return
        generation++
        pending = true
        scheduled = false
        inFlight = false
    }

    fun onForeground() {
        if (disposed || !pending || scheduled || inFlight || !isReady()) return
        scheduled = true
        val current = generation
        post(0, Runnable {
            if (disposed || current != generation) return@Runnable
            scheduled = false
            if (!pending || !isReady()) return@Runnable
            inFlight = true
            post(1000, Runnable { complete(current, false) })
            restoreFocusedInput { restored -> complete(current, restored) }
        })
    }

    private fun complete(current: Int, restored: Boolean) {
        if (disposed || current != generation || !pending || !inFlight) return
        pending = false
        inFlight = false
        if (restored || !isReady()) return
        syncHiddenInsets()
        // A root snapshot can still belong to the outgoing window. Check once
        // more after Android publishes it, never poll permanently or show IME.
        post(300, Runnable {
            if (!disposed && current == generation && !pending && isReady()) {
                syncHiddenInsets()
            }
        })
    }

    fun dispose() {
        disposed = true
        generation++
        pending = false
        scheduled = false
        inFlight = false
    }
}
