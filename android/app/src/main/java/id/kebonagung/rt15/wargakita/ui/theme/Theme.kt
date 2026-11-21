package id.kebonagung.rt15.wargakita.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val RoyalBlue = Color(0xFF1D4ED8)
val SkyBlue = Color(0xFF0EA5E9)
val AirySlate = Color(0xFFF8FAFC)
val SoftBlueSurface = Color(0xFFEFF6FF)

private val LightColors = lightColorScheme(
    primary = RoyalBlue,
    secondary = SkyBlue,
    background = AirySlate,
    surface = Color.White,
    onPrimary = Color.White
)

@Composable
fun WargaKitaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content
    )
}
