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

    fun exportBitmap(includeActiveStroke: Boolean = false): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        for (stroke in strokes) {
            drawStroke(canvas, stroke)
        }
        if (includeActiveStroke) {
            activeStroke?.let { drawStroke(canvas, it) }
        }
        return bitmap
    }
}
