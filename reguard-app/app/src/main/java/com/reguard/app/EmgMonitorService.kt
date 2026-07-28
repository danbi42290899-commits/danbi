package com.reguard.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Watches the brace's raw EMG stream directly (its own WebSocket connection,
 * independent of the WebView) and fires a real system notification if any
 * channel's signal stays above its Danger threshold long enough.
 *
 * Why this exists at all: Chromium-based WebView freezes/heavily throttles
 * JS timers and socket callbacks the moment the Activity isn't visible,
 * regardless of whether the hosting process is still alive -- so the
 * in-app alert evaluator (EmgAlertEvaluator in index.html) simply stops
 * running the instant the app is backgrounded. There is no way to fix that
 * from JS; it has to be redone natively. MainActivity starts this service
 * in onStop() and stops it in onStart(), so only one of {WebView JS,
 * this service} is ever talking to the brace at a time.
 *
 * Deliberately NOT full parity with the in-app evaluator (see chat/memory
 * for the scoping decision): single Danger-only threshold per channel, no
 * Warning tier, no hysteresis release edge, no multi-channel-simultaneous
 * rule. It reuses the app's own HP20->Notch60/120/180->LP450 filter chain
 * (index.html's makeEmgChain()) since skipping that would mean alerting on
 * the electrode's raw DC offset instead of real muscle activity -- the
 * exact bug the partner's filter-chain fix corrected in the JS path.
 */
class EmgMonitorService : Service() {

    private var client: OkHttpClient? = null
    private var ws: WebSocket? = null
    private var reconnectHandler: Handler? = null
    private var stopping = false

    private val chains = Array(3) { EmgBiquadChain() }
    private val emaPower = DoubleArray(3)
    private val aboveSinceMs = LongArray(3) { -1L }
    private val alertedThisEpisode = BooleanArray(3)

    private var dangerMv = doubleArrayOf(-1.0, -1.0, -1.0)
    private var dangerDurationMs = 500L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(FOREGROUND_ID, buildForegroundNotification())
        loadConfig()
        if (ws == null) connect()
        return START_STICKY
    }

    override fun onDestroy() {
        stopping = true
        reconnectHandler?.removeCallbacksAndMessages(null)
        ws?.close(1000, null)
        ws = null
        client?.dispatcher?.executorService?.shutdown()
        client = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun loadConfig() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        dangerDurationMs = prefs.getLong(KEY_DURATION, 500L)
        dangerMv[0] = readMv(prefs, KEY_CH1)
        dangerMv[1] = readMv(prefs, KEY_CH2)
        dangerMv[2] = readMv(prefs, KEY_CH3)
    }

    private fun readMv(prefs: android.content.SharedPreferences, key: String): Double =
        java.lang.Double.longBitsToDouble(prefs.getLong(key, DISABLED_BITS))

    private fun connect() {
        if (stopping) return
        val httpClient = client ?: OkHttpClient.Builder().build().also { client = it }
        val request = Request.Builder().url("ws://192.168.4.1:81/").build()
        ws = httpClient.newWebSocket(request, listener)
    }

    private fun scheduleReconnect() {
        if (stopping) return
        val handler = reconnectHandler ?: Handler(mainLooper).also { reconnectHandler = it }
        handler.postDelayed({ connect() }, 1000)
    }

    private val listener = object : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            processFrame(bytes)
        }
        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            scheduleReconnect()
        }
        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            scheduleReconnect()
        }
    }

    // Binary frame layout matches EspEmgSource._onMessage() in index.html:
    // [8B header: seq(uint32 BE) + t_ms(uint32 BE)][N x 9B samples],
    // each sample = 3 channels x 3-byte 24-bit signed big-endian.
    private fun processFrame(bytes: ByteString) {
        if (bytes.size < 8) return
        val n = (bytes.size - 8) / 9
        for (k in 0 until n) {
            val o = 8 + k * 9
            processSample(0, s24be(bytes, o) * ESP_CODE_TO_MV)
            processSample(1, s24be(bytes, o + 3) * ESP_CODE_TO_MV)
            processSample(2, s24be(bytes, o + 6) * ESP_CODE_TO_MV)
        }
    }

    private fun processSample(ch: Int, mv: Double) {
        val y = chains[ch].process(mv)
        // ~250ms time-constant power estimate (matches the "250ms RMS" badge
        // already shown in the app's own Debug Mode waveform view).
        val alpha = SAMPLE_DT_S / (RMS_TAU_S + SAMPLE_DT_S)
        emaPower[ch] += alpha * (y * y - emaPower[ch])
        val rms = sqrt(emaPower[ch])

        val threshold = dangerMv[ch]
        if (threshold <= 0) { aboveSinceMs[ch] = -1; alertedThisEpisode[ch] = false; return }

        val now = System.currentTimeMillis()
        if (rms >= threshold) {
            if (aboveSinceMs[ch] < 0) aboveSinceMs[ch] = now
            if (!alertedThisEpisode[ch] && now - aboveSinceMs[ch] >= dangerDurationMs) {
                alertedThisEpisode[ch] = true
                fireDangerAlert(ch)
            }
        } else {
            aboveSinceMs[ch] = -1
            alertedThisEpisode[ch] = false
        }
    }

    private fun fireDangerAlert(ch: Int) {
        val channelName = CHANNEL_NAMES.getOrElse(ch) { "Channel ${ch + 1}" }
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("Danger Detected")
            .setContentText("$channelName activity exceeded the danger threshold.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent())
            .build()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            == PackageManager.PERMISSION_GRANTED
        ) {
            NotificationManagerCompat.from(this).notify(ALERT_NOTIFICATION_ID_BASE + ch, notification)
        }
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun createNotificationChannels() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL_ID, "Danger Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Fires when a monitored muscle exceeds its danger threshold while the app is in the background"
                enableVibration(true)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(MONITOR_CHANNEL_ID, "Background Monitoring", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Persistent notification shown while Re:Guard watches the brace in the background"
            }
        )
    }

    private fun buildForegroundNotification(): Notification =
        NotificationCompat.Builder(this, MONITOR_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Re:Guard monitoring active")
            .setContentText("Watching for restricted muscle activity in the background")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(openAppPendingIntent())
            .build()

    companion object {
        private const val FOREGROUND_ID = 2001
        private const val ALERT_NOTIFICATION_ID_BASE = 2100
        private const val ALERT_CHANNEL_ID = "reguard_alerts"
        private const val MONITOR_CHANNEL_ID = "reguard_monitor"
        private val CHANNEL_NAMES = listOf("Tibialis Anterior", "Fibularis Longus", "Lateral Gastrocnemius")

        private const val EMG_FS = 1295.0
        private const val SAMPLE_DT_S = 1.0 / EMG_FS
        private const val RMS_TAU_S = 0.25
        private const val ESP_CODE_TO_MV = 1200.0 / 8388608.0

        const val PREFS_NAME = "reguard_alert_config"
        const val KEY_CH1 = "ch1_danger_mv_bits"
        const val KEY_CH2 = "ch2_danger_mv_bits"
        const val KEY_CH3 = "ch3_danger_mv_bits"
        const val KEY_DURATION = "danger_duration_ms"
        // Not `const` -- Double.doubleToLongBits() isn't a compile-time-constant
        // function in Kotlin, so this has to be a regular val.
        private val DISABLED_BITS: Long = java.lang.Double.doubleToLongBits(-1.0)

        private fun s24be(bytes: ByteString, offset: Int): Int {
            val b0 = bytes[offset].toInt() and 0xFF
            val b1 = bytes[offset + 1].toInt() and 0xFF
            val b2 = bytes[offset + 2].toInt() and 0xFF
            var v = (b0 shl 16) or (b1 shl 8) or b2
            if (v and 0x800000 != 0) v = v or -0x1000000
            return v
        }
    }

    /** HP20 -> Notch60/120/180 -> LP450 RBJ-cookbook biquad cascade -- ported 1:1 from makeEmgChain() in index.html. */
    private class EmgBiquadChain {
        private val hp = Biquad(FilterType.HIGHPASS, 20.0, 0.707)
        private val notches = listOf(60.0, 120.0, 180.0).map { Biquad(FilterType.NOTCH, it, 30.0) }
        private val lp = Biquad(FilterType.LOWPASS, 450.0, 0.707)
        fun process(x: Double): Double {
            var y = hp.process(x)
            for (notch in notches) y = notch.process(y)
            return lp.process(y)
        }
    }

    private enum class FilterType { HIGHPASS, LOWPASS, NOTCH }

    private class Biquad(type: FilterType, f0: Double, q: Double) {
        private val b0: Double
        private val b1: Double
        private val b2: Double
        private val a1: Double
        private val a2: Double
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        init {
            val w0 = 2 * PI * f0 / EMG_FS
            val c = cos(w0)
            val s = sin(w0)
            val al = s / (2 * q)
            val rb0: Double
            val rb1: Double
            val rb2: Double
            val a0 = 1 + al
            when (type) {
                FilterType.HIGHPASS -> { rb0 = (1 + c) / 2; rb1 = -(1 + c); rb2 = (1 + c) / 2 }
                FilterType.LOWPASS -> { rb0 = (1 - c) / 2; rb1 = 1 - c; rb2 = (1 - c) / 2 }
                FilterType.NOTCH -> { rb0 = 1.0; rb1 = -2 * c; rb2 = 1.0 }
            }
            b0 = rb0 / a0; b1 = rb1 / a0; b2 = rb2 / a0
            a1 = (-2 * c) / a0; a2 = (1 - al) / a0
        }

        fun process(x: Double): Double {
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}
