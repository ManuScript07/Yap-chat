package com.yapchat.app

internal object LauncherBrandingPlan {
    val names = listOf("LauncherDefault", "LauncherRussian", "LauncherEnglish")

    /** The desired launcher is always enabled before another is disabled. */
    fun changes(language: String, enabled: Map<String, Boolean>, systemLanguage: String): List<Pair<String, Boolean>> {
        require(language == "ru" || language == "en")
        // A fresh install already has the right localized icon. Do not replace
        // its component just to confirm the same initial language.
        val target = if (enabled["LauncherDefault"] == true && language == systemLanguage) {
            "LauncherDefault"
        } else if (language == "ru") "LauncherRussian" else "LauncherEnglish"
        return (listOf(target) + names.filter { it != target }).mapNotNull { name ->
            val desired = name == target
            if (enabled[name] == desired) null else name to desired
        }
    }
}
