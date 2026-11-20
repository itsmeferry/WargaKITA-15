package id.kebonagung.rt15.wargakita

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class UpdateCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            schedulePeriodicCheck(context)
        }
        val pendingResult = goAsync()
        Thread {
            try {
                val url = URL("https://api.github.com/repos/itsmeferry/WargaKITA-17/releases/latest")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Accept", "application/vnd.github+json")
                    setRequestProperty("User-Agent", "WargaKITA-Android")
                    connectTimeout = 8000
                    readTimeout = 8000
                }
                if (conn.responseCode == 200) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    val json = JSONObject(body)
                    val latestTag = json.optString("tag_name", "").trim()
                    val currentVer = "v" + BuildConfig.VERSION_NAME
                    if (latestTag.isNotEmpty() && isNewer(latestTag, currentVer)) {
                        val htmlUrl = json.optString("html_url", "https://github.com/itsmeferry/WargaKITA-17/releases/latest")
                        showUpdateNotif(context, latestTag, htmlUrl)
                    }
                }
                conn.disconnect()
            } catch (_: Exception) {
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun isNewer(a: String, b: String): Boolean {
        val pa = a.removePrefix("v").split(".").map { it.toIntOrNull() ?: 0 }
        val pb = b.removePrefix("v").split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val va = pa.getOrElse(i) { 0 }
            val vb = pb.getOrElse(i) { 0 }
            if (va > vb) return true
            if (va < vb) return false
        }
        return false
    }

    private fun showUpdateNotif(context: Context, latestTag: String, releaseUrl: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("wargakita_channel", "Notifikasi WargaKITA", NotificationManager.IMPORTANCE_HIGH)
            nm.createNotificationChannel(ch)
        }
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(context, 9101, tapIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val dlIntent = Intent(Intent.ACTION_VIEW, Uri.parse(releaseUrl))
        val dlPi = PendingIntent.getActivity(context, 9102, dlIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notif = NotificationCompat.Builder(context, "wargakita_channel")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Wajib Update WargaKITA $latestTag")
            .setContentText("Versi terbaru $latestTag sudah tersedia! Ketuk untuk memperbarui aplikasi.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Versi terbaru $latestTag sudah tersedia di GitHub Releases. Ketuk untuk membuka WargaKITA dan memasang pembaruan."))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .addAction(0, "Unduh APK", dlPi)
            .build()
        nm.notify(9100, notif)
    }

    companion object {
        fun schedulePeriodicCheck(context: Context) {
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, UpdateCheckReceiver::class.java)
                val pi = PendingIntent.getBroadcast(context, 9100, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                val intervalMs = 2 * 60 * 60 * 1000L
                am.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 60_000L,
                    intervalMs,
                    pi
                )
            } catch (_: Exception) {}
        }
    }
}
