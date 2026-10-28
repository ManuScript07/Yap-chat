package com.yapchat.app

/** Passive default-network observation. All methods and dispatched work run on the main thread. */
internal class DefaultNetworkStatus<N : Any>(
    private val source: Source<N>,
    private val dispatch: (() -> Unit) -> Unit,
) {
    interface Source<N : Any> {
        fun snapshot(): N?
        fun register(listener: Listener<N>): () -> Unit
    }

    interface Listener<N : Any> {
        fun onAvailable(network: N)
        fun onLost(network: N)
    }

    private class Session<N : Any>(val emit: (Map<String, Any?>) -> Unit) {
        var network: N? = null
        // Starts at zero (offline/unknown); assigning the first known network makes it one.
        // Opaque and local to this listen: no Android network identifiers cross the channel.
        var generation = 0
        var emittedGeneration = -1
        var unregister: (() -> Unit)? = null
        var emitted = false
        var available: Boolean? = null
    }

    private var session: Session<N>? = null
    private var disposed = false

    fun listen(emit: (Map<String, Any?>) -> Unit) {
        if (disposed) return
        cancel()
        val current = Session<N>(emit)
        session = current
        val listener = object : Listener<N> {
            override fun onAvailable(network: N) = dispatch {
                if (session === current) {
                    assignNetwork(current, network)
                    publish(current, true)
                }
            }

            override fun onLost(network: N) = dispatch {
                if (session === current &&
                    (current.network == null || current.network == network)) {
                    // A snapshot may see a network whose onAvailable has not arrived yet.
                    // Unknown state must also accept a loss, rather than stay stuck online.
                    assignNetwork(current, null)
                    publish(current, false)
                }
            }
        }
        try {
            // Register first to avoid a gap between the snapshot and observation. Callback
            // work is queued on main, so it cannot run in the middle of this snapshot.
            current.unregister = source.register(listener)
        } catch (_: RuntimeException) {
            publish(current, null)
            return
        }
        try {
            assignNetwork(current, source.snapshot())
            publish(current, current.network != null)
        } catch (_: RuntimeException) {
            // Permission/service failures are unknown, never evidence of being offline.
            publish(current, null)
        }
    }

    private fun assignNetwork(current: Session<N>, network: N?) {
        if (current.network == network) return
        current.network = network
        current.generation++
    }

    private fun publish(current: Session<N>, available: Boolean?) {
        if (session !== current) return
        if (current.emitted && current.available == available &&
            current.emittedGeneration == current.generation) return
        current.emitted = true
        current.available = available
        current.emittedGeneration = current.generation
        current.emit(mapOf("available" to available, "generation" to current.generation))
    }

    fun cancel() {
        val previous = session ?: return
        session = null // Invalidate queued callbacks before unregistering.
        val unregister = previous.unregister
        previous.unregister = null
        try {
            unregister?.invoke()
        } catch (_: RuntimeException) {
            // Cleanup stays idempotent even if the system has already removed a callback.
        }
    }

    fun dispose() {
        disposed = true
        cancel()
    }
}
