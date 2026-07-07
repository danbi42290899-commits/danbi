package com.example.robotdrawing

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.pdf.PdfDocument
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import android.widget.Button
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var drawingView: DrawingView

    private lateinit var btnPen: Button
    private lateinit var btnEraser: Button

    private lateinit var sizeButtons: List<Button>
    private val sizePx = floatArrayOf(4f, 8f, 12f, 20f, 32f)

    private lateinit var colorViews: List<View>
    private val colorValues = intArrayOf(
        Color.parseColor("#F44336"), // red
        Color.parseColor("#2196F3"), // blue
        Color.parseColor("#4CAF50"), // green
        Color.parseColor("#FFEB3B"), // yellow
        Color.parseColor("#000000")  // black
    )

    private var pendingSaveFormat: SaveFormat? = null

    private enum class SaveFormat { PNG, PDF }

    private val requestStoragePermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            when (pendingSaveFormat) {
                SaveFormat.PNG -> savePng()
                SaveFormat.PDF -> savePdf()
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
        val btnUndo: Button = findViewById(R.id.btnUndo)
        val btnSave: Button = findViewById(R.id.btnSave)

        sizeButtons = listOf(
            findViewById(R.id.btnSize1),
            findViewById(R.id.btnSize2),
            findViewById(R.id.btnSize3),
            findViewById(R.id.btnSize4),
            findViewById(R.id.btnSize5)
        )

        colorViews = listOf(
            findViewById(R.id.colorRed),
            findViewById(R.id.colorBlue),
            findViewById(R.id.colorGreen),
            findViewById(R.id.colorYellow),
            findViewById(R.id.colorBlack)
        )

        btnPen.setOnClickListener { setMode(DrawMode.PEN) }
        btnEraser.setOnClickListener { setMode(DrawMode.ERASER) }
        btnUndo.setOnClickListener { drawingView.undo() }
        btnSave.setOnClickListener { showSaveDialog() }

        sizeButtons.forEachIndexed { index, button ->
            button.setOnClickListener { selectSize(index) }
        }

        colorViews.forEachIndexed { index, view ->
            view.setOnClickListener { selectColor(index) }
        }

        // Defaults: pen mode, size index 1 (8px), black color
        setMode(DrawMode.PEN)
        selectSize(1)
        selectColor(4)
    }

    private fun setMode(mode: DrawMode) {
        drawingView.currentMode = mode
        val selectedColor = ContextCompat.getColor(this, R.color.button_selected)
        val normalColor = ContextCompat.getColor(this, R.color.button_normal)
        btnPen.setBackgroundColor(if (mode == DrawMode.PEN) selectedColor else normalColor)
        btnEraser.setBackgroundColor(if (mode == DrawMode.ERASER) selectedColor else normalColor)
    }

    private fun selectSize(index: Int) {
        drawingView.currentStrokeWidth = sizePx[index]
        val selectedColor = ContextCompat.getColor(this, R.color.button_selected)
        val normalColor = ContextCompat.getColor(this, R.color.button_normal)
        sizeButtons.forEachIndexed { i, button ->
            button.setBackgroundColor(if (i == index) selectedColor else normalColor)
        }
    }

    private fun selectColor(index: Int) {
        drawingView.currentColor = colorValues[index]
        colorViews.forEachIndexed { i, view ->
            view.background = swatchDrawable(colorValues[i], i == index)
        }
        setMode(DrawMode.PEN)
    }

    private fun swatchDrawable(fillColor: Int, selected: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fillColor)
            setStroke(
                if (selected) 10 else 3,
                if (selected) Color.BLACK else Color.GRAY
            )
        }
    }

    private fun showSaveDialog() {
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
}
