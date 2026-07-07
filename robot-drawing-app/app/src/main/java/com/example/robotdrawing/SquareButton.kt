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
