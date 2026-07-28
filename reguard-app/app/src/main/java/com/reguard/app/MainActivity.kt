package com.reguard.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    // Result is ignored either way: the CSV still saves to Downloads
    // without notification permission, it just won't show the banner.
    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    // Whether the WebView's JS last reported an active brace connection
    // (see AlertBridge.setConnected). Read at onStop() to decide whether
    // background monitoring is worth starting at all.
    @Volatile private var espConnected = false
    // True only while EmgMonitorService is running *because this Activity
    // paused the WebView's own connection for it* -- deliberately separate
    // from espConnected, which flips to false the instant we pause the JS
    // side and would otherwise make onStart() unable to tell "was this
    // backgrounded while connected" from "was never connected at all".
    private var backgroundMonitorActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        createDownloadNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        webView = findViewById(R.id.webView)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false
        // The app page loads from file:///android_asset/, a distinct origin
        // from http://192.168.4.1 (the EMG brace's own Wi-Fi AP + web server).
        // Without these, the brace-connection fetch() calls are blocked by
        // the same-origin policy even with usesCleartextTraffic enabled.
        @Suppress("DEPRECATION")
        webView.settings.allowFileAccessFromFileURLs = true
        @Suppress("DEPRECATION")
        webView.settings.allowUniversalAccessFromFileURLs = true
        webView.addJavascriptInterface(DownloadBridge(this), "AndroidDownloader")
        webView.addJavascriptInterface(AlertBridge(this), "AndroidAlerts")
        webView.loadUrl("file:///android_asset/index.html")

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })
    }

    // Hands monitoring off to EmgMonitorService the moment the app stops
    // being visible, if a brace connection was actually active -- WebView
    // JS timers/sockets are throttled once the Activity isn't in the
    // foreground regardless of process lifetime, so leaving it to keep
    // running wouldn't work. Pausing the WebView's own connection avoids
    // two simultaneous WebSocket clients hitting the brace at once (unclear
    // whether its firmware even supports that).
    override fun onStop() {
        super.onStop()
        if (espConnected && !backgroundMonitorActive) {
            backgroundMonitorActive = true
            webView.evaluateJavascript(
                "if(typeof EspEmgSource!=='undefined' && EspEmgSource.active) EspEmgSource.stop();", null
            )
            ContextCompat.startForegroundService(this, Intent(this, EmgMonitorService::class.java))
        }
    }

    override fun onStart() {
        super.onStart()
        if (backgroundMonitorActive) {
            backgroundMonitorActive = false
            stopService(Intent(this, EmgMonitorService::class.java))
            webView.evaluateJavascript(
                "if(typeof toggleEspConnection==='function' && !EspEmgSource.active) toggleEspConnection();", null
            )
        }
    }

    private fun createDownloadNotificationChannel() {
        val channel = NotificationChannel(
            DOWNLOAD_CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply { description = "Notifies when a Re:Guard patient report finishes downloading" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Called on a background (non-UI) thread by the WebView JS bridge. */
    fun onCsvSaved(filename: String, uri: Uri) {
        runOnUiThread {
            val notification = buildDownloadNotification(filename, uri)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED
            ) {
                NotificationManagerCompat.from(this).notify(DOWNLOAD_NOTIFICATION_ID, notification)
            }
            Toast.makeText(this, "$filename saved to Downloads", Toast.LENGTH_SHORT).show()
        }
    }

    fun onCsvSaveFailed(message: String) {
        runOnUiThread { Toast.makeText(this, "Download failed: $message", Toast.LENGTH_LONG).show() }
    }

    private fun buildDownloadNotification(filename: String, uri: Uri) =
        NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Report downloaded")
            .setContentText("$filename saved to Downloads — tap to open")
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .apply {
                // Only content:// URIs (MediaStore, API 29+) can be safely
                // handed to another app via ACTION_VIEW; a plain file:// URI
                // on the legacy (<29) save path would throw
                // FileUriExposedException, so skip the tap action there.
                if (uri.scheme == "content") {
                    val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "text/csv")
                        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }
                    val pendingIntent = PendingIntent.getActivity(
                        this@MainActivity, 0, viewIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    setContentIntent(pendingIntent)
                }
            }
            .build()

    companion object {
        private const val DOWNLOAD_CHANNEL_ID = "reguard_downloads"
        private const val DOWNLOAD_NOTIFICATION_ID = 1001
    }

    // Bridges CSV report downloads from the WebView's JS to a real file in
    // the device's Downloads folder, since neither the Claude Artifact
    // `window.claude.downloads` capability (only injected by claude.ai
    // around the published artifact, never present here) nor a plain
    // Blob+<a download> click triggers an actual file save inside WebView.
    private class DownloadBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun saveCsv(filename: String, base64Data: String) {
            try {
                val bytes = Base64.decode(base64Data, Base64.DEFAULT)
                val uri = writeToDownloads(activity, filename, bytes)
                activity.onCsvSaved(filename, uri)
            } catch (e: Exception) {
                activity.onCsvSaveFailed(e.message ?: e.javaClass.simpleName)
            }
        }

        private fun writeToDownloads(context: Context, filename: String, bytes: ByteArray): Uri {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not open output stream")
                return uri
            } else {
                // Android 8-9 (API 26-28): no scoped storage yet. Writing
                // here requires the legacy WRITE_EXTERNAL_STORAGE permission
                // (declared in the manifest with maxSdkVersion=28) to already
                // be granted; if it isn't, this throws and onCsvSaveFailed
                // reports it rather than crashing the app.
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, filename)
                file.writeBytes(bytes)
                return Uri.fromFile(file)
            }
        }
    }

    // Bridges the in-app alert config (calibrated Danger thresholds + how
    // long to hold above them) from JS into SharedPreferences, and tracks
    // live connection state -- both consumed by EmgMonitorService, which
    // cannot reach into the WebView's JS state directly since it runs
    // independently once the app is backgrounded. See onStop()/onStart().
    private class AlertBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun setConnected(connected: Boolean) {
            activity.espConnected = connected
        }

        @JavascriptInterface
        fun updateConfig(json: String) {
            try {
                val obj = JSONObject(json)
                val prefs = activity.getSharedPreferences(EmgMonitorService.PREFS_NAME, MODE_PRIVATE)
                prefs.edit()
                    .putLong(EmgMonitorService.KEY_DURATION, obj.optLong("dangerDurationMs", 500L))
                    .putLong(EmgMonitorService.KEY_CH1, java.lang.Double.doubleToLongBits(obj.optDouble("ch1DangerMv", -1.0)))
                    .putLong(EmgMonitorService.KEY_CH2, java.lang.Double.doubleToLongBits(obj.optDouble("ch2DangerMv", -1.0)))
                    .putLong(EmgMonitorService.KEY_CH3, java.lang.Double.doubleToLongBits(obj.optDouble("ch3DangerMv", -1.0)))
                    .apply()
            } catch (e: Exception) {
                // Malformed config from JS -- leave whatever was previously
                // stored in place rather than wiping it out.
            }
        }
    }
}
