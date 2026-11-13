package work.shuyo.app

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import android.widget.TextView
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class EarlyClassAlarmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureWindow()
        if (savedInstanceState == null && intent.action == EarlyClassAlarmService.ACTION_STOP) {
            stopAlarm()
            return
        }
        render(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent == null) return
        setIntent(intent)
        if (intent.action == EarlyClassAlarmService.ACTION_STOP) {
            stopAlarm()
        } else {
            render(intent)
        }
    }

    private fun configureWindow() {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.statusBarColor = getColorCompat(R.color.alarm_background_start)
        window.navigationBarColor = getColorCompat(R.color.alarm_background_end)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val isNight = resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            window.decorView.systemUiVisibility = if (isNight) {
                0
            } else {
                View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            }
        }
    }

    private fun render(alarmIntent: Intent) {
        val title = alarmIntent.getStringExtra("title") ?: "早课提醒"
        val courseTime = alarmIntent.getLongExtra("courseTime", 0L)
        val courseEndTime = alarmIntent.getLongExtra("courseEndTime", 0L)
        val campus = alarmIntent.getStringExtra("campus").orEmpty()
        val location = alarmIntent.getStringExtra("location").orEmpty()
        val teacherName = alarmIntent.getStringExtra("teacherName").orEmpty()
        val place = listOf(campus, location)
            .filter { it.isNotBlank() }
            .joinToString(" ")

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            fitsSystemWindows = true
            background = gradientBackground(
                getColorCompat(R.color.alarm_background_start),
                getColorCompat(R.color.alarm_background_end),
            )
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(48), dp(24), dp(48))
        }
        scroll.addView(
            content,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(28), dp(24), dp(28))
            background = roundedBackground(
                getColorCompat(R.color.alarm_surface),
                dp(24).toFloat(),
            )
        }
        content.addView(
            card,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        card.addView(TextView(this).apply {
            text = title
            textSize = 28f
            setTextColor(getColorCompat(R.color.alarm_text_primary))
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 3
        })

        val details = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        card.addView(space(height = 28))
        card.addView(
            details,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        addDetailRow(
            details,
            label = "上课时间",
            value = if (courseTime > 0L) formatCourseTime(courseTime, courseEndTime) else "未提供",
        )
        addDetailRow(
            details,
            label = "地点",
            value = place.ifBlank { "未提供" },
        )
        addDetailRow(details, label = "教师", value = teacherName.ifBlank { "未提供" })

        content.addView(space(height = 36))
        val stopButton = Button(this).apply {
            text = "关闭闹钟"
            textSize = 17f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            minHeight = dp(58)
            stateListAnimator = null
            background = roundedBackground(
                getColorCompat(R.color.alarm_accent),
                dp(18).toFloat(),
            )
            setOnClickListener { stopAlarm() }
        }
        content.addView(
            stopButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(58),
            ),
        )

        setContentView(scroll)
    }

    private fun addDetailRow(
        parent: LinearLayout,
        label: String,
        value: String,
    ) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(10), 0, dp(10))
        }
        row.addView(TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(getColorCompat(R.color.alarm_text_muted))
        }, LinearLayout.LayoutParams(dp(84), LinearLayout.LayoutParams.WRAP_CONTENT))
        row.addView(TextView(this).apply {
            text = value
            textSize = 16f
            setTextColor(getColorCompat(R.color.alarm_text_primary))
            maxLines = 2
            gravity = Gravity.END
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        parent.addView(row)
    }

    private fun stopAlarm() {
        EarlyClassAlarmService.dismiss(this)
        finish()
    }

    private fun formatCourseTime(start: Long, end: Long): String {
        val formatter = SimpleDateFormat("HH:mm", Locale.CHINA)
        return if (end > 0L) {
            "${formatter.format(Date(start))}–${formatter.format(Date(end))}"
        } else {
            formatter.format(Date(start))
        }
    }

    private fun roundedBackground(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }

    private fun gradientBackground(start: Int, end: Int): GradientDrawable =
        GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(start, end),
        ).apply { cornerRadius = 0f }

    private fun space(height: Int = 0, width: Int = 0): Space = Space(this).apply {
        layoutParams = LinearLayout.LayoutParams(width, height)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun getColorCompat(id: Int): Int = ContextCompat.getColor(this, id)
}
