package id.kebonagung.rt15.wargakita

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.view.ViewGroup
import android.view.WindowInsets
import android.provider.CalendarContract
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebResourceRequest
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.util.TimeZone

class MainActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var cameraPhotoUri: Uri? = null
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false

    private val multiPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _ -> }

    private val cameraPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) launchDirectCamera() else {
            filePathCallback?.onReceiveValue(null)
            filePathCallback = null
        }
    }

    private val cameraLauncher = registerForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success ->
        val res = if (success && cameraPhotoUri != null) arrayOf(cameraPhotoUri!!) else null
        filePathCallback?.onReceiveValue(res)
        filePathCallback = null
    }

    private val galleryLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val uris = if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
        } else null
        filePathCallback?.onReceiveValue(uris)
        filePathCallback = null
    }

    private fun launchDirectCamera() {
        val photoFile = File(cacheDir, "bukti_${System.currentTimeMillis()}.jpg")
        val photoUri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", photoFile)
        cameraPhotoUri = photoUri
        cameraLauncher.launch(photoUri)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("wargakita_channel", "Notifikasi WargaKITA", NotificationManager.IMPORTANCE_HIGH)
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(ch)
        }
    }

    private fun requestInitialPermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.READ_CALENDAR)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.WRITE_CALENDAR)
        }
        if (needed.isNotEmpty()) {
            multiPermLauncher.launch(needed.toTypedArray())
        }
    }

    inner class AndroidBridge {
        @JavascriptInterface
        fun speakJavanese(text: String) {
            if (!ttsReady || tts == null || text.isBlank()) return
            runOnUiThread {
                try {
                    tts?.setPitch(1.12f)
                    tts?.setSpeechRate(1.02f)
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "nawak_${System.currentTimeMillis()}")
                } catch (_: Exception) {}
            }
        }

        @JavascriptInterface
        fun stopSpeak() {
            runOnUiThread {
                try { tts?.stop() } catch (_: Exception) {}
            }
        }

        @JavascriptInterface
        fun getDevicePaletteJson(): String {
            return try {
                if (Build.VERSION.SDK_INT >= 31) {
                    val isDark = isDeviceDarkMode()
                    val accent = ContextCompat.getColor(this@MainActivity, if (isDark) android.R.color.system_accent1_300 else android.R.color.system_accent1_600)
                    val accentBg = ContextCompat.getColor(this@MainActivity, if (isDark) android.R.color.system_accent1_700 else android.R.color.system_accent1_600)
                    val accentSoft = ContextCompat.getColor(this@MainActivity, if (isDark) android.R.color.system_accent1_900 else android.R.color.system_accent1_50)
                    val bgApp = ContextCompat.getColor(this@MainActivity, if (isDark) android.R.color.system_neutral1_900 else android.R.color.system_neutral1_50)
                    val bgCard = ContextCompat.getColor(this@MainActivity, if (isDark) android.R.color.system_neutral1_800 else android.R.color.white)
                    fun hex(c: Int) = String.format("#%06X", 0xFFFFFF and c)
                    "{\"supported\":true,\"isDark\":$isDark,\"accent\":\"${hex(accentBg)}\",\"accentText\":\"${hex(accent)}\",\"accentSoft\":\"${hex(accentSoft)}\",\"bgApp\":\"${hex(bgApp)}\",\"bgCard\":\"${hex(bgCard)}\"}"
                } else "{}"
            } catch (_: Exception) { "{}" }
        }

        @JavascriptInterface
        fun setMaxScreenBrightness(enable: Boolean) {
            runOnUiThread {
                try {
                    val lp = window.attributes
                    lp.screenBrightness = if (enable) 1.0f else android.view.WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                } catch (_: Exception) {}
            }
        }

        @JavascriptInterface
        fun isDeviceDarkMode(): Boolean {
            return (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        }

        @JavascriptInterface
        fun showNotification(title: String, body: String) {
            runOnUiThread {
                val intent = Intent(this@MainActivity, MainActivity::class.java)
                val pi = PendingIntent.getActivity(this@MainActivity, 0, intent, PendingIntent.FLAG_IMMUTABLE)
                val notif = NotificationCompat.Builder(this@MainActivity, "wargakita_channel")
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setAutoCancel(true)
                    .setContentIntent(pi)
                    .build()
                val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                nm.notify((System.currentTimeMillis() % 10000).toInt(), notif)
            }
        }

        @JavascriptInterface
        fun addCalendarEvent(title: String, location: String, description: String, startMillis: Long, endMillis: Long): Boolean {
            val hasWrite = ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
            val hasRead = ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
            if (hasWrite && hasRead) {
                try {
                    var calId: Long? = null
                    val proj = arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.IS_PRIMARY)
                    contentResolver.query(
                        CalendarContract.Calendars.CONTENT_URI,
                        proj,
                        "${CalendarContract.Calendars.VISIBLE} = 1",
                        null,
                        null
                    )?.use { cur ->
                        while (cur.moveToNext()) {
                            val id = cur.getLong(0)
                            val isPrimary = if (!cur.isNull(1)) cur.getInt(1) == 1 else false
                            if (calId == null || isPrimary) calId = id
                        }
                    }
                    if (calId != null) {
                        val evValues = ContentValues().apply {
                            put(CalendarContract.Events.DTSTART, startMillis)
                            put(CalendarContract.Events.DTEND, endMillis)
                            put(CalendarContract.Events.TITLE, title)
                            put(CalendarContract.Events.EVENT_LOCATION, location)
                            put(CalendarContract.Events.DESCRIPTION, description)
                            put(CalendarContract.Events.CALENDAR_ID, calId)
                            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                            put(CalendarContract.Events.HAS_ALARM, 1)
                        }
                        val inserted = contentResolver.insert(CalendarContract.Events.CONTENT_URI, evValues)
                        val eventId = inserted?.lastPathSegment?.toLongOrNull()
                        if (eventId != null) {
                            listOf(60, 15).forEach { mins ->
                                val remValues = ContentValues().apply {
                                    put(CalendarContract.Reminders.MINUTES, mins)
                                    put(CalendarContract.Reminders.EVENT_ID, eventId)
                                    put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                                }
                                contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, remValues)
                            }
                            showNotification("Tersimpan ke Kalender HP", "$title ($location) dengan pengingat otomatis.")
                            return true
                        }
                    }
                } catch (_: Exception) {}
            } else {
                runOnUiThread {
                    multiPermLauncher.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR))
                }
            }
            runOnUiThread {
                val calIntent = Intent(Intent.ACTION_INSERT).apply {
                    data = CalendarContract.Events.CONTENT_URI
                    putExtra(CalendarContract.Events.TITLE, title)
                    putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                    putExtra(CalendarContract.Events.DESCRIPTION, description)
                    putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMillis)
                    putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis)
                }
                startActivity(calIntent)
            }
            return true
        }

        @JavascriptInterface
        fun saveAndShareBase64(base64Data: String, fileName: String, mimeType: String) {
            runOnUiThread {
                try {
                    val bytes = Base64.decode(base64Data, Base64.DEFAULT)
                    val outFile = File(cacheDir, fileName)
                    outFile.writeBytes(bytes)
                    val uri = FileProvider.getUriForFile(this@MainActivity, "${packageName}.fileprovider", outFile)
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Bagikan / Simpan $fileName"))
                } catch (_: Exception) {}
            }
        }

        @JavascriptInterface
        fun saveAndShareMultipleBase64(filesJson: String, mimeType: String) {
            runOnUiThread {
                try {
                    val arr = org.json.JSONArray(filesJson)
                    val uris = ArrayList<android.net.Uri>()
                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val name = obj.optString("name", "Laporan_${i + 1}.png")
                        val b64 = obj.optString("base64", "")
                        if (b64.isNotEmpty()) {
                            val outFile = File(cacheDir, name)
                            outFile.writeBytes(Base64.decode(b64, Base64.DEFAULT))
                            uris.add(FileProvider.getUriForFile(this@MainActivity, "${packageName}.fileprovider", outFile))
                        }
                    }
                    if (uris.size == 1) {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uris[0])
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(shareIntent, "Bagikan Laporan WargaKITA"))
                    } else if (uris.size > 1) {
                        val shareIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                            type = mimeType
                            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(shareIntent, "Bagikan ${uris.size} Halaman Laporan"))
                    }
                } catch (_: Exception) {}
            }
        }
    }

    private val notifHandler = Handler(Looper.getMainLooper())
    private val notifRunnable = object : Runnable {
        override fun run() {
            if (::webView.isInitialized) {
                webView.evaluateJavascript("window.wkCheckPeriodicNotifications && window.wkCheckPeriodicNotifications()", null)
            }
            notifHandler.postDelayed(this, 1800000L)
        }
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) {
            webView.evaluateJavascript("window.wkCheckPeriodicNotifications && window.wkCheckPeriodicNotifications()", null)
        }
    }

    override fun onDestroy() {
        notifHandler.removeCallbacks(notifRunnable)
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (::webView.isInitialized) {
            webView.evaluateJavascript("window.wkOnDeviceThemeChange && window.wkOnDeviceThemeChange()", null)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val res = tts?.setLanguage(Locale("id", "ID"))
                ttsReady = res != TextToSpeech.LANG_MISSING_DATA && res != TextToSpeech.LANG_NOT_SUPPORTED
            }
        }
        requestInitialPermissions()
        UpdateCheckReceiver.schedulePeriodicCheck(this)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            settings.databaseEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            addJavascriptInterface(AndroidBridge(), "AndroidBridge")
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val uri = request?.url ?: return false
                    val url = uri.toString()
                    val scheme = uri.scheme?.lowercase() ?: ""
                    if (scheme in listOf("tel", "whatsapp", "mailto", "sms") ||
                        url.startsWith("https://wa.me/") ||
                        url.startsWith("https://api.whatsapp.com/") ||
                        url.startsWith("https://github.com/")) {
                        return try {
                            startActivity(Intent(if (scheme == "tel") Intent.ACTION_DIAL else Intent.ACTION_VIEW, uri))
                            true
                        } catch (_: Exception) {
                            true
                        }
                    }
                    if (scheme == "intent") {
                        return try {
                            val intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
                            startActivity(intent)
                            true
                        } catch (_: Exception) {
                            true
                        }
                    }
                    return false
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView?,
                    filePathCallback: ValueCallback<Array<Uri>>?,
                    fileChooserParams: FileChooserParams?
                ): Boolean {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = filePathCallback
                    if (fileChooserParams?.isCaptureEnabled == true) {
                        if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                            launchDirectCamera()
                        } else {
                            cameraPermLauncher.launch(Manifest.permission.CAMERA)
                        }
                        return true
                    }
                    val intent = fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "image/*"
                    }
                    return try {
                        galleryLauncher.launch(intent)
                        true
                    } catch (e: Exception) {
                        this@MainActivity.filePathCallback = null
                        false
                    }
                }
            }
        }
        val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
        val fallbackTop = if (resId > 0) resources.getDimensionPixelSize(resId) else 0
        setContentView(webView)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            webView.setOnApplyWindowInsetsListener { v, insets ->
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                val ime = insets.getInsets(WindowInsets.Type.ime())
                val topM = if (bars.top > 0) bars.top else fallbackTop
                val bottomM = maxOf(bars.bottom, ime.bottom)
                (v.layoutParams as? ViewGroup.MarginLayoutParams)?.let { lp ->
                    if (lp.topMargin != topM || lp.bottomMargin != bottomM || lp.leftMargin != bars.left || lp.rightMargin != bars.right) {
                        lp.setMargins(bars.left, topM, bars.right, bottomM)
                        v.layoutParams = lp
                    }
                }
                insets
            }
        } else {
            @Suppress("DEPRECATION")
            webView.setOnApplyWindowInsetsListener { v, insets ->
                (v.layoutParams as? ViewGroup.MarginLayoutParams)?.let { lp ->
                    lp.setMargins(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                    v.layoutParams = lp
                }
                insets
            }
        }
        webView.loadUrl("file:///android_asset/wargakita.html")
        notifHandler.postDelayed(notifRunnable, 15000L)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                webView.evaluateJavascript("(window.wkHandleBack ? window.wkHandleBack() : false)") { res ->
                    if (res == "false" || res == "null") {
                        if (webView.canGoBack()) webView.goBack() else finish()
                    }
                }
            }
        })
    }
}
