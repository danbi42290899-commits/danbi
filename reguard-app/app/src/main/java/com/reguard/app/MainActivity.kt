package com.reguard.app

import android.os.Bundle
import android.webkit.WebView
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.OnBackPressedCallback

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

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
}
