package com.example.robotdrawing

import android.content.Context
import android.util.AttributeSet
import com.google.android.material.button.MaterialButton

class SquareButton @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : MaterialButton(context, attrs) {

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, widthMeasureSpec)
    }
}
