package com.yapchat.app

import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/** Presence of the app's default network, not a probe of internet/server reachability. */
internal class NetworkStatusBridge : FlutterPlugin, EventChannel.StreamHandler {
    private var channel: EventChannel? = null
    private var status: DefaultNetworkStatus<Network>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val manager = binding.applicationContext.getSystemService(ConnectivityManager::class.java)
        val main = Handler(Looper.getMainLooper())
        status = DefaultNetworkStatus(
            source = object : DefaultNetworkStatus.Source<Network> {
                override fun snapshot(): Network? = checkNotNull(manager).activeNetwork

                override fun register(listener: DefaultNetworkStatus.Listener<Network>): () -> Unit {
                    val connectivity = checkNotNull(manager)
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) = listener.onAvailable(network)
                        override fun onLost(network: Network) = listener.onLost(network)
                    }
                    // API 24 is the project's minimum. No NetworkRequest, IP or SSID reads.
                    connectivity.registerDefaultNetworkCallback(callback)
                    return { connectivity.unregisterNetworkCallback(callback) }
                }
            },
            // API 24 callbacks arrive on a connectivity thread; always queue on main.
            dispatch = { action -> main.post { action() }; Unit },
        )
        channel = EventChannel(binding.binaryMessenger, CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        status?.listen { events.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        status?.cancel()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        status?.dispose()
        status = null
        channel?.setStreamHandler(null)
        channel = null
    }

    companion object {
        const val CHANNEL = "com.yapchat.app/network_status"
    }
}
