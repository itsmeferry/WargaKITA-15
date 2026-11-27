package id.kebonagung.rt15.wargakita

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class UpdateCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val act = intent?.action
        if (act == Intent.ACTION_BOOT_COMPLETED || act == Intent.ACTION_MY_PACKAGE_REPLACED) {
            schedulePeriodicCheck(context)
            RondaReminderReceiver.rescheduleSaved(context)
        }
        val pendingResult = goAsync()
        Thread {
            try {
                val url = URL("https://api.github.com/repos/itsmeferry/WargaKITA-15/releases/latest")
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

                    var bestVc = 0
                    var bestStamp = ""
                    var bestMs = 0L
                    val vcRegex = Regex("version[-_ ]?code[-_ :.]*?(\\d+)|[-_.]vc(\\d+)", RegexOption.IGNORE_CASE)
                    val assets = json.optJSONArray("assets")
                    if (assets != null) {
                        for (i in 0 until assets.length()) {
                            val a = assets.optJSONObject(i) ?: continue
                            val name = a.optString("name", "")
                            if (!name.lowercase(Locale.ROOT).endsWith(".apk")) continue
                            val m = vcRegex.find(name)
                            val vc = (m?.groupValues?.getOrNull(1)?.takeIf { it.isNotEmpty() }
                                ?: m?.groupValues?.getOrNull(2)?.takeIf { it.isNotEmpty() })?.toIntOrNull() ?: 0
                            val stamp = a.optString("updated_at", "").trim()
                            val ms = parseIsoUtcMillis(stamp)
                            if (vc > bestVc || (vc == bestVc && ms > bestMs)) {
                                bestVc = vc
                                bestStamp = stamp
                                bestMs = ms
                            }
                        }
                    }
                    if (bestStamp.isEmpty()) {
                        bestStamp = json.optString("published_at", "").trim()
                        bestMs = parseIsoUtcMillis(bestStamp)
                    }

                    val isVersionNewer = latestTag.isNotEmpty() && isNewer(latestTag, currentVer)
                    val isVersionCodeNewer = latestTag.equals(currentVer, ignoreCase = true) && bestVc > BuildConfig.VERSION_CODE
                    val sameVerRebuilt = latestTag.equals(currentVer, ignoreCase = true) &&
                        bestVc == 0 &&
                        bestMs > 0L &&
                        BuildConfig.BUILD_EPOCH_MS > 0L &&
                        (bestMs - BuildConfig.BUILD_EPOCH_MS) > 15L * 60L * 1000L

                    if (isVersionNewer || isVersionCodeNewer || sameVerRebuilt) {
                        val prefs = context.getSharedPreferences("wk_update_prefs", Context.MODE_PRIVATE)
                        val sig = "$latestTag|$bestVc|$bestStamp"
                        val lastSig = prefs.getString("last_notif_sig", "")
                        val lastAt = prefs.getLong("last_notif_at", 0L)
                        val now = System.currentTimeMillis()
                        if (sig != lastSig || (now - lastAt) >= 6L * 60L * 60L * 1000L) {
                            prefs.edit().putString("last_notif_sig", sig).putLong("last_notif_at", now).apply()
                            showUpdateNotif(context, latestTag, bestVc, !isVersionNewer)
                        }
                    }
                }
                conn.disconnect()
            } catch (_: Exception) {
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun parseIsoUtcMillis(iso: String): Long {
        if (iso.isBlank()) return 0L
        val patterns = listOf("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        for (p in patterns) {
            try {
                val sdf = SimpleDateFormat(p, Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val d = sdf.parse(iso)
                if (d != null) return d.time
            } catch (_: Exception) {}
        }
        return 0L
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

    private fun showUpdateNotif(context: Context, latestTag: String, remoteVc: Int, isSubBuild: Boolean) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("wargakita_channel", "Notifikasi WargaKITA", NotificationManager.IMPORTANCE_HIGH)
            nm.createNotificationChannel(ch)
        }
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_update", true)
        }
        val pi = PendingIntent.getActivity(context, 9101, tapIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val dlIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_update", true)
        }
        val dlPi = PendingIntent.getActivity(context, 9102, dlIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val verLabel = if (remoteVc > 0) "$latestTag (Version Code: $remoteVc)" else latestTag
        val title = if (isSubBuild) "Pembaruan Terbaru WargaKITA $verLabel" else "Wajib Update WargaKITA $verLabel"
        val text = "Versi terpasang ${"v" + BuildConfig.VERSION_NAME} (VC ${BuildConfig.VERSION_CODE}). Ketuk untuk unduh & pasang $verLabel langsung di aplikasi."

        val notif = NotificationCompat.Builder(context, "wargakita_channel")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .addAction(0, "Unduh & Pasang", dlPi)
            .build()
        nm.notify(9100, notif)
    }

    companion object {
        fun schedulePeriodicCheck(context: Context) {
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, UpdateCheckReceiver::class.java)
                val pi = PendingIntent.getBroadcast(context, 9100, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                val intervalMs = 30 * 60 * 1000L
                am.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 20_000L,
                    intervalMs,
                    pi
                )
            } catch (_: Exception) {}
        }
    }
}
