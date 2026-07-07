package com.example.robotdrawing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

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

    private val strokes = mutableListOf<Stroke>()
    private var activePath: Path? = null
    private var activeStroke: Stroke? = null
    private var lastX = 0f
    private var lastY = 0f

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
        paint.color = if (stroke.isEraser) Color.WHITE else stroke.color
        paint.strokeWidth = stroke.strokeWidth
        canvas.drawPath(stroke.path, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val path = Path()
                path.moveTo(x, y)
                activePath = path
                activeStroke = Stroke(
                    path = path,
                    color = currentColor,
                    strokeWidth = currentStrokeWidth,
                    isEraser = currentMode == DrawMode.ERASER
                )
                lastX = x
                lastY = y
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                activePath?.quadTo(lastX, lastY, (x + lastX) / 2, (y + lastY) / 2)
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
