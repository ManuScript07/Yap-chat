package com.yapchat.app

import android.os.Build
import android.view.WindowInsets
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var resumed = false
    private var keyboardChannel: MethodChannel? = null
    private val insetsRecovery = ResumeInsetsRecovery(
        post = { delay, callback ->
            if (delay == 0L) window.decorView.postOnAnimation(callback)
            else window.decorView.postDelayed(callback, delay)
        },
        isReady = {
            resumed && hasWindowFocus() && !isFinishing && !isDestroyed &&
                findViewById<FlutterView>(FLUTTER_VIEW_ID)?.isAttachedToWindow == true
        },
        restoreFocusedInput = ::restoreFocusedInput,
        syncHiddenInsets = ::syncHiddenImeInsets,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(NetworkStatusBridge())
        keyboardChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yapchat.app/keyboard_resume",
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        flutterEngine.plugins.remove(NetworkStatusBridge::class.java)
        keyboardChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        insetsRecovery.onForeground()
    }

    override fun onPause() {
        resumed = false
        insetsRecovery.onBackground()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) insetsRecovery.onForeground() else insetsRecovery.onBackground()
    }

    override fun onDestroy() {
        insetsRecovery.dispose()
        super.onDestroy()
    }

    private fun restoreFocusedInput(complete: (Boolean) -> Unit) {
        val channel = keyboardChannel ?: return complete(false)
        // Let the focused EditableText make the SAME request as a normal tap.
        // Native isAcceptingText can be false precisely because that client
        // needs to be re-established after the app switch.
        channel.invokeMethod(
            "restoreFocusedInput",
            mapOf("deadlineMs" to System.currentTimeMillis() + 900L),
            object : MethodChannel.Result {
                override fun success(result: Any?) = complete(result == true)
                override fun error(code: String, message: String?, details: Any?) = complete(false)
                override fun notImplemented() = complete(false)
            },
        )
    }

    private fun syncHiddenImeInsets() {
        val view = findViewById<FlutterView>(FLUTTER_VIEW_ID) ?: return
        if (!view.isAttachedToWindow || flutterEngine == null) return
        val insets = window.decorView.rootWindowInsets ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            !insets.isVisible(WindowInsets.Type.ime())) {
            // An interrupted Flutter IME animation can consume normal dispatch.
            // Only repair a hidden IME when no live editor requested restoration.
            view.onApplyWindowInsets(insets)
        } else {
            view.requestApplyInsets()
        }
    }
}
