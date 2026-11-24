package id.kebonagung.rt15.wargakita

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class RondaReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Reminder Ronda Malam RT 15"
        val body = intent.getStringExtra("body") ?: "Pengingat jadwal ronda malam pukul 22:30 - 04:00 WIB."
        val notifId = intent.getIntExtra("notifId", 7001)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("wargakita_channel", "Notifikasi WargaKITA", NotificationManager.IMPORTANCE_HIGH)
            nm.createNotificationChannel(ch)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            context, notifId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, "wargakita_channel")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(notifId, notif)
    }

    companion object {
        const val PREF_NAME = "wk_ronda_prefs"
        const val KEY_RONDA_JSON = "ronda_json"

        fun saveAndSchedule(context: Context, rondaJson: String) {
            try {
                context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_RONDA_JSON, rondaJson)
                    .apply()
                scheduleFromJson(context, rondaJson)
            } catch (_: Exception) {}
        }

        fun rescheduleSaved(context: Context) {
            try {
                val saved = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                    .getString(KEY_RONDA_JSON, null)
                if (!saved.isNullOrBlank()) {
                    scheduleFromJson(context, saved)
                }
            } catch (_: Exception) {}
        }

        fun scheduleFromJson(context: Context, rondaJson: String) {
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val nowMs = System.currentTimeMillis()
                val arr = org.json.JSONArray(rondaJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val triggerMs = obj.optLong("triggerMs", 0L)
                    if (triggerMs <= nowMs) continue
                    val title = obj.optString("title", "Reminder Ronda Malam RT 15")
                    val body = obj.optString("body", "")
                    val reqCode = 7100 + i
                    val intent = Intent(context, RondaReminderReceiver::class.java).apply {
                        putExtra("title", title)
                        putExtra("body", body)
                        putExtra("notifId", reqCode)
                    }
                    val pi = PendingIntent.getBroadcast(
                        context, reqCode, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
                    } else {
                        am.set(AlarmManager.RTC_WAKEUP, triggerMs, pi)
                    }
                }
            } catch (_: Exception) {}
        }
    }
}
