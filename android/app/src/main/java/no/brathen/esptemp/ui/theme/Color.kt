package no.brathen.esptemp.ui.theme

import androidx.compose.ui.graphics.Color

val TempOrange = Color(0xFFE8562A)
val HumidityBlue = Color(0xFF2A7DE8)

private val BandRed = Color(0xFFD32F2F)
private val BandOrange = Color(0xFFF57C00)
private val BandGreen = Color(0xFF388E3C)

/** Temperature color bands — same cutoffs as the iOS complication. */
fun tempColor(celsius: Double): Color = when {
    celsius < 8 -> BandRed
    celsius < 12 -> BandOrange
    celsius < 20 -> BandGreen
    celsius <= 27 -> BandOrange
    else -> BandRed
}

/** Battery tint by charge fraction (0..1), mirroring the iOS dashboard. */
fun batteryColor(fraction: Double): Color = when {
    fraction < 0.2 -> BandRed
    fraction < 0.4 -> BandOrange
    else -> BandGreen
}
