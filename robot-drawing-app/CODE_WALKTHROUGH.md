# 로봇 드로잉 암 — 코드 전체 설명

로봇팔이 태블릿을 눌러서 그림을 그릴 때 쓰는 안드로이드 앱(Kotlin, Custom View)의
전체 소스코드입니다. 각 코드 블록 위에 "이게 뭘 하는 코드인지"를 먼저 설명하고,
바로 아래 실제 코드를 붙였습니다. 위에서 아래로 순서대로 읽으면 됩니다.

**전체 그림**: 사용자가 화면을 터치 → `DrawingView`가 선을 그림 → 왼쪽/오른쪽 패널의
버튼을 누르면 `MainActivity`가 펜 색/굵기/모드를 바꿈 → Save 버튼을 누르면 PNG/PDF/영상으로 저장.

---

## 1. `Stroke.kt` — 그림 한 획을 표현하는 데이터

가장 작은 파일입니다. 화면에 손가락(또는 로봇팔)이 한 번 닿았다 떼는 동안 그려지는
"한 획"을 어떤 정보로 저장할지 정의합니다. `PenType`은 연필/형광펜/만년필 세 종류의
펜을 구분하는 값이고, `Stroke`는 그 한 획의 경로(`path`), 색, 굵기, 지우개 여부 등을
담는 그릇입니다. 아래에 나올 모든 파일이 이 `Stroke`를 만들고, 읽고, 그립니다.

```kotlin
package com.example.robotdrawing

import android.graphics.Path
import android.graphics.PointF

enum class PenType { PENCIL, HIGHLIGHTER, FOUNTAIN }

data class Stroke(
    val path: Path,
    val color: Int,
    val strokeWidth: Float,
    val isEraser: Boolean,
    val penType: PenType = PenType.PENCIL,
    // Only populated for FOUNTAIN strokes: per-point smoothed width, used to render
    // a tapered ballpoint-style line instead of one fixed-width path.
    val points: MutableList<PointF> = mutableListOf(),
    val widths: MutableList<Float> = mutableListOf()
)
```

만년필(`FOUNTAIN`) 타입만 `points`/`widths` 리스트를 따로 채우는 이유는, 만년필은
그리는 속도에 따라 선 굵기가 점마다 달라지기 때문입니다(뒤에서 다시 설명합니다).

---

## 2. `DrawingView.kt` — 앱의 심장부, 실제로 그림이 그려지는 곳

터치를 받아서 화면에 선을 그리는 커스텀 View입니다. 안드로이드의 `View`를 상속받아
`onTouchEvent`(터치 입력 처리)와 `onDraw`(화면에 실제로 그리기) 두 함수를 직접 구현했습니다.

```kotlin
package com.example.robotdrawing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.os.SystemClock
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

enum class DrawMode {
    PEN, ERASER
}

class DrawingView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    var currentMode: DrawMode = DrawMode.PEN
    var currentColor: Int = Color.BLACK
    var currentStrokeWidth: Float = 8f
    var currentPenType: PenType = PenType.PENCIL

    private val strokes = mutableListOf<Stroke>()
    private var activePath: Path? = null
    private var activeStroke: Stroke? = null
    private var lastX = 0f
    private var lastY = 0f
    private var lastMoveTime = 0L
    private var smoothWidth = 0f

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Color.WHITE)
        for (stroke in strokes) {
            drawStroke(canvas, stroke)
        }
        activeStroke?.let { drawStroke(canvas, it) }
    }

    private fun drawStroke(canvas: Canvas, stroke: Stroke) {
        if (stroke.isEraser) {
            paint.color = Color.WHITE
            paint.alpha = 255
            paint.strokeWidth = stroke.strokeWidth * 1.4f
            canvas.drawPath(stroke.path, paint)
            return
        }

        when (stroke.penType) {
            PenType.HIGHLIGHTER -> {
                // Whole path stroked in one call: translucency is applied once, so
                // self-overlapping loops within a single stroke never double-blend.
                paint.color = stroke.color
                paint.alpha = 140
                paint.strokeWidth = stroke.strokeWidth * 2.2f
                canvas.drawPath(stroke.path, paint)
            }
            PenType.FOUNTAIN -> {
                paint.color = stroke.color
                paint.alpha = 255
                if (stroke.points.size >= 2) {
                    for (i in 1 until stroke.points.size) {
                        val a = stroke.points[i - 1]
                        val b = stroke.points[i]
                        paint.strokeWidth = (stroke.widths[i - 1] + stroke.widths[i]) / 2f
                        canvas.drawLine(a.x, a.y, b.x, b.y, paint)
                    }
                } else {
                    paint.strokeWidth = stroke.strokeWidth
                    canvas.drawPath(stroke.path, paint)
                }
            }
            PenType.PENCIL -> {
                paint.color = stroke.color
                paint.alpha = 255
                paint.strokeWidth = stroke.strokeWidth * 0.7f
                canvas.drawPath(stroke.path, paint)
            }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y
        val isEraser = currentMode == DrawMode.ERASER

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val path = Path()
                path.moveTo(x, y)
                activePath = path
                activeStroke = Stroke(
                    path = path,
                    color = currentColor,
                    strokeWidth = currentStrokeWidth,
                    isEraser = isEraser,
                    penType = currentPenType
                )
                smoothWidth = currentStrokeWidth
                if (!isEraser && currentPenType == PenType.FOUNTAIN) {
                    activeStroke?.points?.add(PointF(x, y))
                    activeStroke?.widths?.add(smoothWidth)
                }
                lastX = x
                lastY = y
                lastMoveTime = SystemClock.uptimeMillis()
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                activePath?.quadTo(lastX, lastY, (x + lastX) / 2, (y + lastY) / 2)

                if (!isEraser && currentPenType == PenType.FOUNTAIN) {
                    val now = SystemClock.uptimeMillis()
                    val dt = max(now - lastMoveTime, 1L).toFloat()
                    val dist = hypot((x - lastX).toDouble(), (y - lastY).toDouble()).toFloat()
                    val speed = dist / dt
                    val target = currentStrokeWidth * max(0.82f, min(1.25f, 1.1f - speed * 0.7f))
                    smoothWidth += (target - smoothWidth) * 0.18f
                    activeStroke?.points?.add(PointF(x, y))
                    activeStroke?.widths?.add(smoothWidth)
                    lastMoveTime = now
                }

                lastX = x
                lastY = y
                invalidate()
            }
            MotionEvent.ACTION_UP -> {
                activePath?.lineTo(x, y)
                activeStroke?.let { strokes.add(it) }
                activePath = null
                activeStroke = null
                invalidate()
            }
            else -> return false
        }
        return true
    }

    fun undo() {
        if (strokes.isNotEmpty()) {
            strokes.removeAt(strokes.size - 1)
            invalidate()
        }
    }

    fun clearAll() {
        strokes.clear()
        invalidate()
    }

    fun exportBitmap(): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        for (stroke in strokes) {
            drawStroke(canvas, stroke)
        }
        return bitmap
    }
}
```

**읽을 때 이 순서로 보면 이해가 쉽습니다:**
1. `onTouchEvent` — 손가락을 대는 순간(`ACTION_DOWN`) 새 `Stroke`를 하나 만들고, 움직이는 동안(`ACTION_MOVE`) `quadTo()`로 점과 점 사이를 부드러운 곡선으로 잇고, 손을 떼면(`ACTION_UP`) 완성된 `Stroke`를 `strokes` 리스트에 저장합니다.
2. `onDraw` — 화면이 다시 그려질 때마다(안드로이드가 자동으로 호출) `strokes` 리스트에 쌓인 모든 획을 처음부터 다시 그립니다. 그래서 지우기/undo가 리스트만 건드리면 바로 화면에 반영됩니다.
3. `drawStroke` — 펜 종류마다 그리는 방식이 다릅니다. 형광펜은 반투명(alpha 140)으로 두껍게, 연필은 얇고 불투명하게, 만년필만 특별히 점 하나하나마다 다른 굵기로 선분을 이어 그려서 "손 속도가 빠르면 선이 가늘어지는" 효과를 냅니다.
4. `exportBitmap` — 지금까지 그린 그림을 이미지 파일로 뽑아낼 때 쓰는 함수인데, 뒤에 나올 PNG 저장/PDF 저장/영상 녹화가 전부 이 함수 하나를 재사용합니다.

---

## 3. `DrawingVideoRecorder.kt` — 화면 캡처 없이 그림을 영상으로 녹화

"녹화"라고 하면 보통 화면 전체를 캡처하는 `MediaProjection`을 떠올리지만, 이 앱은
그렇게 하지 않습니다. 대신 `DrawingView`가 그린 그림(비트맵)을 직접 비디오 프레임으로
밀어넣는 방식을 씁니다. 그래서 화면 녹화 권한 팝업이나 상태바 같은 게 영상에 섞여
들어가지 않고, 로봇팔이 그리는 그림만 깨끗하게 담깁니다.

```kotlin
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
            val bitmap = drawingView.exportBitmap()
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
```

**핵심만 짚으면:** `start()`가 `MediaRecorder`를 "카메라 대신 화면(Surface) 입력"
모드로 준비시킨 다음, 100ms마다(초당 10프레임) `pushFrame()`을 반복 호출합니다.
`pushFrame()`은 `drawingView.exportBitmap()`으로 지금 그림을 스냅샷 찍어서, 그걸
`surface.lockCanvas()`로 얻은 캔버스에 그려 넣고 `unlockCanvasAndPost()`로 확정합니다.
이 반복이 곧 "영상"이 됩니다.

---

## 4. `SquareButton.kt` — 색상 스와치를 항상 완전한 원으로 만드는 버튼

20줄짜리 아주 작은 파일이지만, 실제로 버그를 냈던 파일이라 따로 뗐습니다.
`MaterialButton`을 상속받아 `onMeasure` 딱 하나만 오버라이드합니다.

```kotlin
package com.example.robotdrawing

import android.content.Context
import android.util.AttributeSet
import com.google.android.material.button.MaterialButton

class SquareButton @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : MaterialButton(context, attrs) {

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        // Stay a perfect circle, but never larger than whatever height was actually
        // allotted (e.g. by a weighted LinearLayout slot) — otherwise a button sized
        // to match a generous width can overflow its container and get clipped.
        val size = minOf(measuredWidth, measuredHeight)
        setMeasuredDimension(size, size)
    }
}
```

**왜 이게 필요한지:** 원형 색상 스와치를 만들려면 버튼의 가로/세로 길이가 항상 같아야
합니다. `onMeasure`는 안드로이드가 "이 View를 얼마나 크게 그릴지" 계산하는 단계인데,
여기서 `min(측정된 너비, 측정된 높이)`를 구해서 가로세로를 강제로 똑같이 맞춥니다.
처음 버전은 높이 제약을 무시하고 너비만 기준으로 삼아서, 세로 공간이 부족한 자리에서
버튼이 패널 밖으로 삐져나가 잘리는 버그가 있었는데, 이 `min()` 한 줄로 고쳤습니다.

---

## 5. `MainActivity.kt` — 화면을 켰을 때 진짜로 실행되는 컨트롤러

가장 긴 파일이지만 하는 일은 단순합니다: **버튼을 누르면 → `DrawingView`의 상태(색/굵기/모드)를
바꾸고 → 버튼 자체의 모양(선택 표시)도 갱신**합니다. 뒷부분은 그림을 PNG/PDF/영상으로
저장하는 로직입니다.

```kotlin
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
```

**따라가기 쉬운 흐름:**
- `onCreate` — 앱이 켜질 때 딱 한 번 실행. 모든 버튼을 `findViewById`로 찾아 변수에 담고, `setOnClickListener`로 각 버튼에 할 일을 연결합니다. 맨 아래 4줄(`setMode`, `selectSize(1)`, `selectColor(4)`)이 앱이 켜졌을 때 기본값(펜 모드, 8px 굵기, 검정색)을 정합니다.
- `setMode` / `selectSize` / `selectColor` — 이름 그대로 모드/굵기/색을 바꾸는 함수인데, 셋 다 "① `drawingView`의 값 바꾸기 → ② 버튼 배경/텍스트색 갱신"이라는 똑같은 패턴을 씁니다.
- `showSaveDialog` → `showImageFormatDialog` — Save 버튼을 누르면 먼저 "영상/이미지" 중 고르고, 이미지를 고르면 다시 "PNG/PDF" 중 고르는 2단계 팝업입니다.
- `savePng` / `savePdf` / `saveVideo` — 안드로이드 10(API 29) 이상이면 `MediaStore`(스코프드 스토리지)로, 그보다 낮으면 예전 방식(`File` + 권한 요청)으로 저장하는 분기가 세 함수 모두 똑같이 반복됩니다.

---

## 6. XML — 화면 배치와 색·문구 정의

Kotlin 코드가 "동작"을 담당한다면, XML은 "생김새"를 담당합니다.

### `AndroidManifest.xml` — 앱의 신분증

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-feature android:name="android.hardware.touchscreen" android:required="true" />

    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:theme="@style/Theme.RobotDrawing"
        android:forceDarkAllowed="false"
        android:supportsRtl="true">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`screenOrientation="landscape"`로 항상 가로 화면 고정(로봇팔 작업대에 맞춤),
`forceDarkAllowed="false"`로 시스템 다크모드가 UI를 억지로 어둡게 칠하지 못하게
막아뒀습니다(안 그러면 검정 스와치가 배경과 섞여 안 보이는 버그가 생겼었습니다).

### `res/layout/activity_main.xml` — 화면을 세 구역으로 나누기

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/screen_bg">

    <androidx.constraintlayout.widget.Guideline
        android:id="@+id/guidelineLeft"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        app:layout_constraintGuide_percent="0.13" />

    <androidx.constraintlayout.widget.Guideline
        android:id="@+id/guidelineRight"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        app:layout_constraintGuide_percent="0.87" />

    <!-- Center canvas: fills the full height between the two guidelines -->
    <com.example.robotdrawing.DrawingView
        android:id="@+id/drawingView"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:background="@color/canvas_white"
        android:foreground="@drawable/bg_canvas_frame"
        app:layout_constraintStart_toStartOf="@id/guidelineLeft"
        app:layout_constraintEnd_toEndOf="@id/guidelineRight"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintBottom_toBottomOf="parent"
        android:layout_marginStart="4dp"
        android:layout_marginEnd="4dp"
        android:layout_marginTop="16dp"
        android:layout_marginBottom="16dp" />

    <!-- Left panel: Pen / Eraser / Clear All / Undo -->
    <com.google.android.material.card.MaterialCardView
        android:id="@+id/leftPanel"
        android:layout_width="0dp"
        android:layout_height="0dp"
        app:cardCornerRadius="24dp"
        app:cardElevation="3dp"
        app:strokeWidth="1dp"
        app:strokeColor="@color/border"
        app:cardBackgroundColor="@color/panel_bg"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toStartOf="@id/guidelineLeft"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintBottom_toBottomOf="parent"
        android:layout_marginStart="16dp"
        android:layout_marginEnd="4dp"
        android:layout_marginTop="16dp"
        android:layout_marginBottom="16dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:orientation="vertical"
            android:padding="8dp">

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnPen"
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:layout_marginBottom="18dp"
                android:text="@string/pen"
                android:textSize="16sp"
                android:textAllCaps="false"
                android:textColor="@android:color/white"
                android:background="@drawable/bg_metal_selected"
                app:backgroundTint="@null" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnEraser"
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:layout_marginBottom="18dp"
                android:text="@string/eraser"
                android:textSize="16sp"
                android:textAllCaps="false"
                android:textColor="@color/ink"
                android:background="@drawable/bg_metal_normal"
                app:backgroundTint="@null" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnClearAll"
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:layout_marginBottom="18dp"
                android:text="@string/clear_all"
                android:textSize="16sp"
                android:textAllCaps="false"
                android:textColor="@color/danger_text"
                android:background="@drawable/bg_metal_danger"
                app:backgroundTint="@null" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnUndo"
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:layout_marginBottom="18dp"
                android:text="@string/undo"
                android:textSize="16sp"
                android:textAllCaps="false"
                android:textColor="@color/ink"
                android:background="@drawable/bg_metal_normal"
                app:backgroundTint="@null" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnRecord"
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:text="@string/record"
                android:textSize="15sp"
                android:textAllCaps="false"
                android:textColor="@color/ink"
                android:background="@drawable/bg_metal_normal"
                app:backgroundTint="@null" />

        </LinearLayout>
    </com.google.android.material.card.MaterialCardView>

    <!-- Right panel: Save + color swatches -->
    <com.google.android.material.card.MaterialCardView
        android:id="@+id/rightPanel"
        android:layout_width="0dp"
        android:layout_height="0dp"
        app:cardCornerRadius="24dp"
        app:cardElevation="3dp"
        app:strokeWidth="1dp"
        app:strokeColor="@color/border"
        app:cardBackgroundColor="@color/panel_bg"
        app:layout_constraintStart_toEndOf="@id/guidelineRight"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintBottom_toBottomOf="parent"
        android:layout_marginStart="4dp"
        android:layout_marginEnd="16dp"
        android:layout_marginTop="16dp"
        android:layout_marginBottom="16dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:orientation="vertical"
            android:padding="8dp">

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSave"
                android:layout_width="match_parent"
                android:layout_height="68dp"
                android:layout_marginBottom="20dp"
                android:text="@string/save"
                android:textSize="16sp"
                android:textAllCaps="false"
                android:textColor="@android:color/white"
                android:background="@drawable/bg_metal_selected"
                app:backgroundTint="@null" />

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:orientation="vertical"
                android:gravity="center_horizontal">

                <com.example.robotdrawing.SquareButton
                    android:id="@+id/colorRed"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1"
                    android:layout_gravity="center"
                    android:layout_marginBottom="8dp"
                    android:maxWidth="88dp"
                    android:insetTop="0dp"
                    android:insetBottom="0dp"
                    android:background="@drawable/swatch_red"
                    app:backgroundTint="@null" />

                <com.example.robotdrawing.SquareButton
                    android:id="@+id/colorBlue"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1"
                    android:layout_gravity="center"
                    android:layout_marginBottom="8dp"
                    android:maxWidth="88dp"
                    android:insetTop="0dp"
                    android:insetBottom="0dp"
                    android:background="@drawable/swatch_blue"
                    app:backgroundTint="@null" />

                <com.example.robotdrawing.SquareButton
                    android:id="@+id/colorGreen"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1"
                    android:layout_gravity="center"
                    android:layout_marginBottom="8dp"
                    android:maxWidth="88dp"
                    android:insetTop="0dp"
                    android:insetBottom="0dp"
                    android:background="@drawable/swatch_green"
                    app:backgroundTint="@null" />

                <com.example.robotdrawing.SquareButton
                    android:id="@+id/colorYellow"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1"
                    android:layout_gravity="center"
                    android:layout_marginBottom="8dp"
                    android:maxWidth="88dp"
                    android:insetTop="0dp"
                    android:insetBottom="0dp"
                    android:background="@drawable/swatch_yellow"
                    app:backgroundTint="@null" />

                <com.example.robotdrawing.SquareButton
                    android:id="@+id/colorBlack"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1"
                    android:layout_gravity="center"
                    android:maxWidth="88dp"
                    android:insetTop="0dp"
                    android:insetBottom="0dp"
                    android:background="@drawable/swatch_black"
                    app:backgroundTint="@null" />

            </LinearLayout>
        </LinearLayout>
    </com.google.android.material.card.MaterialCardView>

    <!-- Floating compact pen-size pill: bottom-left of the canvas -->
    <com.google.android.material.card.MaterialCardView
        android:id="@+id/sizePanel"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        app:cardCornerRadius="34dp"
        app:cardElevation="4dp"
        app:strokeWidth="1dp"
        app:strokeColor="@color/border"
        app:cardBackgroundColor="@color/panel_bg"
        app:layout_constraintStart_toStartOf="@id/guidelineLeft"
        app:layout_constraintBottom_toBottomOf="parent"
        android:layout_marginStart="16dp"
        android:layout_marginBottom="28dp">

        <LinearLayout
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:padding="10dp">

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSize1"
                android:layout_width="64dp"
                android:layout_height="64dp"
                android:layout_marginEnd="14dp"
                android:insetTop="0dp"
                android:insetBottom="0dp"
                android:minWidth="0dp"
                android:minHeight="0dp"
                android:background="@drawable/bg_dot_normal"
                app:backgroundTint="@null"
                app:icon="@drawable/dot_1"
                app:iconGravity="textStart"
                app:iconPadding="0dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSize2"
                android:layout_width="64dp"
                android:layout_height="64dp"
                android:layout_marginEnd="14dp"
                android:insetTop="0dp"
                android:insetBottom="0dp"
                android:minWidth="0dp"
                android:minHeight="0dp"
                android:background="@drawable/bg_dot_selected"
                app:backgroundTint="@null"
                app:icon="@drawable/dot_2"
                app:iconGravity="textStart"
                app:iconPadding="0dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSize3"
                android:layout_width="64dp"
                android:layout_height="64dp"
                android:layout_marginEnd="14dp"
                android:insetTop="0dp"
                android:insetBottom="0dp"
                android:minWidth="0dp"
                android:minHeight="0dp"
                android:background="@drawable/bg_dot_normal"
                app:backgroundTint="@null"
                app:icon="@drawable/dot_3"
                app:iconGravity="textStart"
                app:iconPadding="0dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSize4"
                android:layout_width="64dp"
                android:layout_height="64dp"
                android:layout_marginEnd="14dp"
                android:insetTop="0dp"
                android:insetBottom="0dp"
                android:minWidth="0dp"
                android:minHeight="0dp"
                android:background="@drawable/bg_dot_normal"
                app:backgroundTint="@null"
                app:icon="@drawable/dot_4"
                app:iconGravity="textStart"
                app:iconPadding="0dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnSize5"
                android:layout_width="64dp"
                android:layout_height="64dp"
                android:insetTop="0dp"
                android:insetBottom="0dp"
                android:minWidth="0dp"
                android:minHeight="0dp"
                android:background="@drawable/bg_dot_normal"
                app:backgroundTint="@null"
                app:icon="@drawable/dot_5"
                app:iconGravity="textStart"
                app:iconPadding="0dp" />

        </LinearLayout>
    </com.google.android.material.card.MaterialCardView>

</androidx.constraintlayout.widget.ConstraintLayout>
```

`Guideline` 2개(13%, 87% 지점)로 화면을 왼쪽 패널(13%) / 캔버스(74%) / 오른쪽 패널(13%)
세 구역으로 나눴습니다. `%` 기준이라 태블릿 화면 크기가 달라져도 비율은 그대로 유지됩니다.
왼쪽엔 Pen·Eraser·Clear·Undo·Record, 오른쪽엔 Save + 색상 스와치 5개, 캔버스 좌하단엔
떠 있는 펜 굵기 알약(pill) 모양 패널이 배치됩니다.

### `res/values/colors.xml` — 색상 값 모음

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="pen_red">#F44336</color>
    <color name="pen_blue">#2196F3</color>
    <color name="pen_green">#4CAF50</color>
    <color name="pen_yellow">#FFEB3B</color>
    <color name="pen_black">#000000</color>

    <color name="screen_bg">#FFFFFF</color>
    <color name="canvas_white">#FFFFFF</color>
    <color name="panel_bg">#FFFFFF</color>
    <color name="border">#E7E7EA</color>
    <color name="canvas_border">#E5E5E8</color>

    <color name="ink">#1C1C1E</color>
    <color name="ink_soft">#8A8A8E</color>

    <color name="accent">#3D5AFE</color>
    <color name="accent_tint">#EEF1FF</color>
    <color name="danger_text">#B3261E</color>

    <color name="button_bg_normal">#FFFFFF</color>
</resources>
```

### `res/values/strings.xml` — 화면에 보이는 모든 문구

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Robot Drawing</string>
    <string name="pen">Pen</string>
    <string name="eraser">Eraser</string>
    <string name="undo">Undo</string>
    <string name="clear_all">Clear</string>
    <string name="record">● Record</string>
    <string name="stop_recording">■ Stop</string>
    <string name="save">Save</string>
    <string name="save_dialog_title">Save drawing as…</string>
    <string name="save_video">Video Save</string>
    <string name="save_image">Image Save</string>
    <string name="save_as_png">Save as PNG</string>
    <string name="save_as_pdf">Save as PDF</string>
    <string name="saved_png">Saved as PNG</string>
    <string name="saved_pdf">Saved as PDF</string>
    <string name="saved_video">Saved as MP4</string>
    <string name="save_failed">Save failed</string>
    <string name="no_recording_yet">No recorded video yet</string>
    <string name="recording_started">Recording started</string>
    <string name="recording_failed">Could not start recording</string>
    <string name="permission_needed">Storage permission is needed to save files</string>
    <string name="pen_type_dialog_title">Choose pen type</string>
    <string name="pen_type_pencil">연필 (Pencil)</string>
    <string name="pen_type_highlighter">형광펜 (Highlighter)</string>
    <string name="pen_type_fountain">만년필 (Fountain pen)</string>
</resources>
```

### `res/values/themes.xml` — 앱 전체 테마

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.RobotDrawing" parent="Theme.MaterialComponents.Light.NoActionBar">
        <item name="colorPrimary">@color/accent</item>
        <item name="android:windowBackground">@color/screen_bg</item>
    </style>
</resources>
```

`Theme.MaterialComponents.Light.NoActionBar`를 부모로 삼아서 상단 액션바 없이
항상 밝은 테마로 고정했습니다. `colorPrimary`를 `@color/accent`(#3D5AFE)로 지정한
게 Pen/Save 버튼의 파란색 강조 색상의 근원입니다.

---

## 마무리 — 전체를 한 문장으로

**손가락/펜이 닿으면(`DrawingView.onTouchEvent`) 선이 쌓이고(`Stroke`),
매 프레임 다시 그려지고(`onDraw`), 버튼(`MainActivity`)이 그 선의 색·굵기·종류를
바꾸고, 마지막엔 그림을 이미지·PDF·영상 중 하나로 저장한다.** 나머지는 전부
이 흐름을 위한 디테일(정원형 버튼, 그라디언트 배경, 다크모드 대응 등)입니다.
