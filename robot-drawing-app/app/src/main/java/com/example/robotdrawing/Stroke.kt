package com.example.robotdrawing

import android.graphics.Path

data class Stroke(
    val path: Path,
    val color: Int,
    val strokeWidth: Float,
    val isEraser: Boolean
)
