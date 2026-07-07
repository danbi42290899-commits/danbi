package com.example.robotdrawing

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.pdf.PdfDocument
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var drawingView: DrawingView

    private lateinit var btnPen: MaterialButton
    private lateinit var btnEraser: MaterialButton

    private lateinit var sizeButtons: List<MaterialButton>
    private val sizePx = floatArrayOf(4f, 8f, 12f, 20f, 32f)

    private lateinit var colorButtons: List<MaterialButton>
    private val colorValues = intArrayOf(
        Color.parseColor("#F44336"), // red
        Color.parseColor("#2196F3"), // blue
        Color.parseColor("#4CAF50"), // green
        Color.parseColor("#FFEB3B"), // yellow
        Color.parseColor("#000000")  // black
    )

    private var currentPenType = PenType.PENCIL

    private lateinit var btnRecord: MaterialButton
    private lateinit var videoRecorder: DrawingVideoRecorder
    private var lastRecordedVideo: File? = null

    private var pendingSaveFormat: SaveFormat? = null

    private enum class SaveFormat { PNG, PDF, VIDEO }

    private val requestStoragePermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            when (pendingSaveFormat) {
                SaveFormat.PNG -> savePng()
                SaveFormat.PDF -> savePdf()
                SaveFormat.VIDEO -> saveVideo()
                null -> {}
            }
        } else {
            Toast.makeText(this, R.string.permission_needed, Toast.LENGTH_SHORT).show()
        }
        pendingSaveFormat = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        drawingView = findViewById(R.id.drawingView)
        btnPen = findViewById(R.id.btnPen)
        btnEraser = findViewById(R.id.btnEraser)
        val btnClearAll: MaterialButton = findViewById(R.id.btnClearAll)
        val btnUndo: MaterialButton = findViewById(R.id.btnUndo)
        val btnSave: MaterialButton = findViewById(R.id.btnSave)
        btnRecord = findViewById(R.id.btnRecord)
        videoRecorder = DrawingVideoRecorder(drawingView)

        sizeButtons = listOf(
            findViewById(R.id.btnSize1),
            findViewById(R.id.btnSize2),
            findViewById(R.id.btnSize3),
            findViewById(R.id.btnSize4),
            findViewById(R.id.btnSize5)
        )

        colorButtons = listOf(
            findViewById(R.id.colorRed),
            findViewById(R.id.colorBlue),
            findViewById(R.id.colorGreen),
            findViewById(R.id.colorYellow),
            findViewById(R.id.colorBlack)
        )

        btnPen.setOnClickListener {
            // Tapping Pen while already in Pen mode reopens the pen-type picker;
            // switching from Eraser just activates Pen with whatever type was last chosen.
            if (drawingView.currentMode == DrawMode.PEN) {
                showPenTypeDialog()
            } else {
                setMode(DrawMode.PEN)
            }
        }
        btnEraser.setOnClickListener { setMode(DrawMode.ERASER) }
        btnClearAll.setOnClickListener { drawingView.clearAll() }
        btnUndo.setOnClickListener { drawingView.undo() }
        btnSave.setOnClickListener { showSaveDialog() }
        btnRecord.setOnClickListener { toggleRecording() }

        sizeButtons.forEachIndexed { index, button ->
            button.setOnClickListener { selectSize(index) }
        }

        colorButtons.forEachIndexed { index, button ->
            button.setOnClickListener { selectColor(index) }
        }

        // Defaults: pen mode, pencil type, size index 1 (8px), black color
        drawingView.currentPenType = currentPenType
        setMode(DrawMode.PEN)
        selectSize(1)
        selectColor(4)
    }

    private fun setMode(mode: DrawMode) {
        drawingView.currentMode = mode
        val whiteColor = ContextCompat.getColor(this, android.R.color.white)
        val inkColor = ContextCompat.getColor(this, R.color.ink)

        btnPen.setBackgroundResource(if (mode == DrawMode.PEN) R.drawable.bg_metal_selected else R.drawable.bg_metal_normal)
        btnPen.setTextColor(if (mode == DrawMode.PEN) whiteColor else inkColor)

        btnEraser.setBackgroundResource(if (mode == DrawMode.ERASER) R.drawable.bg_metal_selected else R.drawable.bg_metal_normal)
        btnEraser.setTextColor(if (mode == DrawMode.ERASER) whiteColor else inkColor)
    }

    private fun selectSize(index: Int) {
        drawingView.currentStrokeWidth = sizePx[index]
        val whiteColor = ColorStateList.valueOf(ContextCompat.getColor(this, android.R.color.white))
        val inkColor = ColorStateList.valueOf(ContextCompat.getColor(this, R.color.ink))
        sizeButtons.forEachIndexed { i, button ->
            val selected = i == index
            button.setBackgroundResource(if (selected) R.drawable.bg_dot_selected else R.drawable.bg_dot_normal)
            button.iconTint = if (selected) whiteColor else inkColor
        }
    }

    private fun selectColor(index: Int) {
        drawingView.currentColor = colorValues[index]
        colorButtons.forEachIndexed { i, button ->
            button.foreground = if (i == index) ContextCompat.getDrawable(this, R.drawable.bg_swatch_ring) else null
        }
        setMode(DrawMode.PEN)
    }

    private fun showPenTypeDialog() {
        val labels = arrayOf(
            getString(R.string.pen_type_pencil),
            getString(R.string.pen_type_highlighter),
            getString(R.string.pen_type_fountain)
        )
        AlertDialog.Builder(this)
            .setTitle(R.string.pen_type_dialog_title)
            .setItems(labels) { _, which ->
                currentPenType = when (which) {
                    1 -> PenType.HIGHLIGHTER
                    2 -> PenType.FOUNTAIN
                    else -> PenType.PENCIL
                }
                drawingView.currentPenType = currentPenType
            }
            .show()
    }

    private fun toggleRecording() {
        if (videoRecorder.isRecording) {
            val finished = videoRecorder.stop()
            lastRecordedVideo = finished
            btnRecord.setBackgroundResource(R.drawable.bg_metal_normal)
            btnRecord.setTextColor(ContextCompat.getColor(this, R.color.ink))
            btnRecord.text = getString(R.string.record)
            if (finished == null) {
                Toast.makeText(this, R.string.recording_failed, Toast.LENGTH_SHORT).show()
            }
        } else {
            val tempFile = File(cacheDir, "recording_${timestamp()}.mp4")
            val started = videoRecorder.start(tempFile)
            if (started) {
                btnRecord.setBackgroundResource(R.drawable.bg_metal_recording)
                btnRecord.setTextColor(ContextCompat.getColor(this, android.R.color.white))
                btnRecord.text = getString(R.string.stop_recording)
                Toast.makeText(this, R.string.recording_started, Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, R.string.recording_failed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun showSaveDialog() {
        val options = arrayOf(getString(R.string.save_video), getString(R.string.save_image))
        AlertDialog.Builder(this)
            .setTitle(R.string.save_dialog_title)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> saveWithPermissionCheck(SaveFormat.VIDEO)
                    1 -> showImageFormatDialog()
                }
            }
            .show()
    }

    private fun showImageFormatDialog() {
        val options = arrayOf(getString(R.string.save_as_png), getString(R.string.save_as_pdf))
        AlertDialog.Builder(this)
            .setTitle(R.string.save_dialog_title)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> saveWithPermissionCheck(SaveFormat.PNG)
                    1 -> saveWithPermissionCheck(SaveFormat.PDF)
                }
            }
            .show()
    }

    private fun saveWithPermissionCheck(format: SaveFormat) {
        if (format == SaveFormat.VIDEO && (videoRecorder.isRecording || lastRecordedVideo == null)) {
            Toast.makeText(this, R.string.no_recording_yet, Toast.LENGTH_SHORT).show()
            return
        }

        val needsPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED

        if (needsPermission) {
            pendingSaveFormat = format
            requestStoragePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            return
        }

        when (format) {
            SaveFormat.PNG -> savePng()
            SaveFormat.PDF -> savePdf()
            SaveFormat.VIDEO -> saveVideo()
        }
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())

    private fun savePng() {
        val bitmap = drawingView.exportBitmap()
        val filename = "robot_drawing_${timestamp()}.png"
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/RobotDrawing"
                    )
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                contentResolver.openOutputStream(uri)?.use { out ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                }
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "RobotDrawing"
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, filename)
                FileOutputStream(file).use { out ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                }
                MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/png"), null)
            }
            Toast.makeText(this, R.string.saved_png, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, R.string.save_failed, Toast.LENGTH_SHORT).show()
        }
    }

    private fun savePdf() {
        val bitmap = drawingView.exportBitmap()
        val filename = "robot_drawing_${timestamp()}.pdf"
        val document = PdfDocument()
        try {
            val pageInfo = PdfDocument.PageInfo.Builder(bitmap.width, bitmap.height, 1).create()
            val page = document.startPage(pageInfo)
            page.canvas.drawBitmap(bitmap, 0f, 0f, null)
            document.finishPage(page)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Files.FileColumns.DISPLAY_NAME, filename)
                    put(MediaStore.Files.FileColumns.MIME_TYPE, "application/pdf")
                    put(
                        MediaStore.Files.FileColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOCUMENTS + "/RobotDrawing"
                    )
                }
                val uri = contentResolver.insert(MediaStore.Files.getContentUri("external"), values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                contentResolver.openOutputStream(uri)?.use { out -> document.writeTo(out) }
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                    "RobotDrawing"
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, filename)
                FileOutputStream(file).use { out -> document.writeTo(out) }
                MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("application/pdf"), null)
            }
            Toast.makeText(this, R.string.saved_pdf, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, R.string.save_failed, Toast.LENGTH_SHORT).show()
        } finally {
            document.close()
        }
    }

    private fun saveVideo() {
        val source = lastRecordedVideo
        if (source == null || !source.exists()) {
            Toast.makeText(this, R.string.no_recording_yet, Toast.LENGTH_SHORT).show()
            return
        }
        val filename = "robot_drawing_${timestamp()}.mp4"
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, filename)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(
                        MediaStore.Video.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MOVIES + "/RobotDrawing"
                    )
                }
                val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                contentResolver.openOutputStream(uri)?.use { out ->
                    source.inputStream().use { it.copyTo(out) }
                }
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                    "RobotDrawing"
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, filename)
                source.inputStream().use { input ->
                    FileOutputStream(file).use { out -> input.copyTo(out) }
                }
                MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("video/mp4"), null)
            }
            Toast.makeText(this, R.string.saved_video, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(this, R.string.save_failed, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        if (videoRecorder.isRecording) {
            videoRecorder.stop()
        }
        super.onDestroy()
    }
}
