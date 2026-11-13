package com.yapchat.app

import android.content.ComponentName
import android.content.Context
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** Launcher aliases only. MainActivity stays enabled for links and push intents. */
internal class AppBrandingBridge(private val activity: Activity) : FlutterPlugin {
    private var channel: MethodChannel? = null
    private val updates = BrandingUpdateQueue { applyLanguage(activity.applicationContext, it) }
    private var splashLanguage: String? = null

    fun onHostStarted() = updates.onHostStarted()

    fun onHostStopped() {
        try {
            updates.onHostStopped()
        } catch (error: Exception) {
            // Pending language remains queued for the next safe stop.
            Log.w("AppBranding", "Launcher update deferred", error)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.yapchat.app/branding").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "setLanguage") {
                    result.notImplemented()
                } else if (call.arguments != "ru" && call.arguments != "en") {
                    result.error("invalid_language", "Expected ru or en", null)
                } else {
                    try {
                        val language = call.arguments as String
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && splashLanguage != language) {
                            // Persist the next system splash theme without recreating Activity.
                            activity.splashScreen.setSplashScreenTheme(
                                if (language == "ru") R.style.LaunchThemeRussian else R.style.LaunchThemeEnglish
                            )
                            splashLanguage = language
                        }
                        updates.request(language)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("branding_update_failed", error.message, null)
                    }
                }
            }
        }
    }

    private fun applyLanguage(context: Context, language: String) {
        val manager = context.packageManager
        val components = LauncherBrandingPlan.names.associateWith { name ->
            ComponentName(context.packageName, "${context.packageName}.$name")
        }
        val enabled = components.mapValues { (name, component) ->
            when (manager.getComponentEnabledSetting(component)) {
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> name == "LauncherDefault"
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                else -> false
            }
        }
        val systemLanguage = if (java.util.Locale.getDefault().language == "ru") "ru" else "en"
        val changes = LauncherBrandingPlan.changes(language, enabled, systemLanguage).map { (name, enabled) ->
            components.getValue(name) to if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
        }
        if (changes.isEmpty()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            manager.setComponentEnabledSettings(changes.map { (component, state) ->
                PackageManager.ComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            })
        } else {
            // The plan enables the destination first, leaving a launcher entry
            // available even if a later PackageManager call fails.
            changes.forEach { (component, state) ->
                manager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
