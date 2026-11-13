package com.yapchat.app

/** Package changes can make OEM launchers remove the current task. Never do
 *  that while the host is visible, including cold start and account restore. */
internal class BrandingUpdateQueue(private val apply: (String) -> Unit) {
    private var hostStarted = true
    private var pending: String? = null

    fun request(language: String) {
        require(language == "ru" || language == "en")
        pending = language
        if (!hostStarted) flush()
    }

    fun onHostStarted() { hostStarted = true }

    fun onHostStopped() {
        hostStarted = false
        flush()
    }

    private fun flush() {
        val language = pending ?: return
        apply(language)
        pending = null
    }
}
