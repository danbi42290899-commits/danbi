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
