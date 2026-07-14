package com.example.robotdrawing

import android.graphics.Color
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import java.io.File

/**
 * Records the DrawingView's own rendered frames to an MP4 by feeding
 * bitmap snapshots into a MediaRecorder Surface via lockCanvas/unlockCanvasAndPost,
 * instead of capturing the whole screen. No camera/mic involved.
 */
class DrawingVideoRecorder(private val drawingView: DrawingView) {

    private var mediaRecorder: MediaRecorder? = null
    private var inputSurface: Surface? = null
    private var handler: Handler? = null
    private var frameRunnable: Runnable? = null

    var outputFile: File? = null
        private set
    var isRecording = false
        private set

    private val frameIntervalMs = 100L // ~10 fps is plenty for a slow-moving drawing

    fun start(targetFile: File): Boolean {
        if (isRecording) return false
        val width = evenDimension(drawingView.width)
        val height = evenDimension(drawingView.height)
        if (width <= 0 || height <= 0) return false

        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(drawingView.context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        return try {
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoSize(width, height)
            recorder.setVideoFrameRate(10)
            recorder.setVideoEncodingBitRate(4_000_000)
            recorder.setOutputFile(targetFile.absolutePath)
            recorder.prepare()
            val surface = recorder.surface
            recorder.start()

            mediaRecorder = recorder
            inputSurface = surface
            outputFile = targetFile
            isRecording = true

            val mainHandler = Handler(Looper.getMainLooper())
            handler = mainHandler
            val runnable = object : Runnable {
                override fun run() {
                    if (!isRecording) return
                    pushFrame(surface)
                    mainHandler.postDelayed(this, frameIntervalMs)
                }
            }
            frameRunnable = runnable
            mainHandler.post(runnable)
            true
        } catch (e: Exception) {
            try {
                recorder.release()
            } catch (_: Exception) {
            }
            mediaRecorder = null
            inputSurface = null
            isRecording = false
            false
        }
    }

    private fun pushFrame(surface: Surface) {
        try {
            val bitmap = drawingView.exportBitmap(includeActiveStroke = true)
            val canvas = surface.lockCanvas(null)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(bitmap, 0f, 0f, null)
            surface.unlockCanvasAndPost(canvas)
        } catch (_: Exception) {
            // Drop a bad frame rather than kill the whole recording over it.
        }
    }

    /** Stops recording and returns the finished file, or null if nothing was recorded/it failed. */
    fun stop(): File? {
        if (!isRecording) return null
        isRecording = false
        frameRunnable?.let { handler?.removeCallbacks(it) }
        frameRunnable = null
        handler = null

        val finished = try {
            mediaRecorder?.stop()
            outputFile
        } catch (e: Exception) {
            null
        } finally {
            try {
                mediaRecorder?.release()
            } catch (_: Exception) {
            }
            mediaRecorder = null
            inputSurface = null
        }
        return finished
    }

    private fun evenDimension(value: Int): Int = if (value % 2 == 0) value else value - 1
}
