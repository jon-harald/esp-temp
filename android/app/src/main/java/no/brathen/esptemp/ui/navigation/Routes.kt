package no.brathen.esptemp.ui.navigation

import kotlinx.serialization.Serializable

@Serializable object Dashboard
@Serializable object Settings
@Serializable object Account

@Serializable data class Thresholds(val deviceId: String)
