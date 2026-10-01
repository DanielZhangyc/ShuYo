package work.shuyo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale

class ScheduleWidgetSmallProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget_small,
    rowBindings = emptyList(),
    compact = true
)

class ScheduleWidgetProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget,
    rowBindings = listOf(
        CourseRowBinding(R.id.course_row_1, R.id.course_time_1, R.id.course_name_1, R.id.course_meta_1),
        CourseRowBinding(R.id.course_row_2, R.id.course_time_2, R.id.course_name_2, R.id.course_meta_2)
    ),
    compact = false
)

class ScheduleWidgetLargeProvider : ScheduleWidgetBaseProvider(
    layoutId = R.layout.schedule_widget_large,
    rowBindings = listOf(
        CourseRowBinding(R.id.course_row_1, R.id.course_time_1, R.id.course_name_1, R.id.course_meta_1),
        CourseRowBinding(R.id.course_row_2, R.id.course_time_2, R.id.course_name_2, R.id.course_meta_2),
        CourseRowBinding(R.id.course_row_3, R.id.course_time_3, R.id.course_name_3, R.id.course_meta_3)
    ),
    compact = false
)

abstract class ScheduleWidgetBaseProvider(
    private val layoutId: Int,
    private val rowBindings: List<CourseRowBinding>,
    private val compact: Boolean
) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val schedule = WidgetSchedule.parse(widgetData.getString(KEY_SNAPSHOT, null))
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, schedule)
            )
        }
    }

    private fun buildViews(context: Context, schedule: WidgetSchedule?): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId)
        views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context))

        if (schedule == null) {
            bindEmpty(views)
            return views
        }

        val now = LocalDateTime.now()
        val today = now.toLocalDate()
        val activeWeek = schedule.activeWeek(today)
        val isVacation = activeWeek < 1 || activeWeek > schedule.maxWeek
        val todayCourses = if (isVacation) {
            emptyList()
        } else {
            schedule.courses
                .filter { course ->
                    course.weekday == today.dayOfWeek.value &&
                        course.occursInWeek(activeWeek)
                }
                .sortedWith(compareBy<WidgetCourse> { it.startMinute }.thenBy { it.name })
        }
        val nowMinute = now.hour * 60 + now.minute
        val upcoming = todayCourses.firstOrNull { it.endMinute >= nowMinute }

        val tomorrow = today.plusDays(1)
        val tomorrowWeek = schedule.activeWeek(tomorrow)
        val tomorrowCourses = if (
            upcoming == null && tomorrowWeek in 1..schedule.maxWeek
        ) {
            schedule.courses
                .filter { course ->
                    course.weekday == tomorrow.dayOfWeek.value &&
                        course.occursInWeek(tomorrowWeek)
                }
                .sortedWith(compareBy<WidgetCourse> { it.startMinute }.thenBy { it.name })
        } else {
            emptyList()
        }

        if (compact) {
            bindCompact(
                views,
                activeWeek,
                today.dayOfWeek.value,
                todayCourses,
                upcoming,
                tomorrowCourses.firstOrNull(),
                tomorrowWeek,
                tomorrow.dayOfWeek.value,
                nowMinute,
                isVacation
            )
            return views
        }

        val showingTomorrow = tomorrowCourses.isNotEmpty()
        val visibleCourses = if (showingTomorrow) {
            tomorrowCourses.take(rowBindings.size)
        } else {
            todayCourses
                .filter { it.endMinute >= nowMinute }
                .take(rowBindings.size)
        }
        val displayWeek = if (showingTomorrow) tomorrowWeek else activeWeek
        val displayWeekday = if (showingTomorrow) {
            tomorrow.dayOfWeek.value
        } else {
            today.dayOfWeek.value
        }

        views.setTextViewText(
            R.id.widget_title,
            schedule.term.ifBlank { "ShuYo课表" }
        )
        views.setTextViewText(
            R.id.widget_meta,
            if (showingTomorrow) {
                "第${displayWeek}周 · ${weekdayName(displayWeekday)}"
            } else if (isVacation) {
                "假期中 · ${weekdayName(today.dayOfWeek.value)}"
            } else {
                "第${displayWeek}周 · ${weekdayName(displayWeekday)}"
            }
        )
        views.setTextViewText(
            R.id.widget_status,
            if (showingTomorrow) {
                "明天的课程"
            } else if (isVacation) {
                "假期中"
            } else {
                statusText(todayCourses, upcoming, nowMinute)
            }
        )
        rowBindings.forEachIndexed { index, binding ->
            bindCourseRow(
                views,
                binding,
                visibleCourses.getOrNull(index),
                if (showingTomorrow) -1 else nowMinute
            )
        }
        return views
    }

    private fun bindEmpty(views: RemoteViews) {
        views.setTextViewText(R.id.widget_title, "ShuYo课表")
        views.setTextViewText(R.id.widget_meta, "")
        views.setTextViewText(R.id.widget_status, "打开 ShuYo 同步课表")
        if (compact) {
            views.setTextViewText(R.id.compact_course_meta, "本地还没有可显示的课程缓存")
        }
        rowBindings.forEach { binding ->
            bindCourseRow(views, binding, null, 0)
        }
    }

    private fun bindCompact(
        views: RemoteViews,
        activeWeek: Int,
        weekday: Int,
        todayCourses: List<WidgetCourse>,
        upcoming: WidgetCourse?,
        tomorrowCourse: WidgetCourse?,
        tomorrowWeek: Int,
        tomorrowWeekday: Int,
        nowMinute: Int,
        isVacation: Boolean
    ) {
        val showingTomorrow = tomorrowCourse != null
        views.setTextViewText(R.id.widget_title, "课表")
        views.setTextViewText(
            R.id.widget_meta,
            if (showingTomorrow) "第${tomorrowWeek}周 · ${weekdayName(tomorrowWeekday)}"
            else if (isVacation) "假期中 · ${weekdayName(weekday)}"
            else "第${activeWeek}周 · ${weekdayName(weekday)}"
        )
        views.setTextViewText(R.id.compact_course_meta, "")
        if (tomorrowCourse != null) {
            val place = tomorrowCourse.room.ifBlank { tomorrowCourse.sectionText }
            views.setTextViewText(R.id.widget_status, tomorrowCourse.name)
            views.setTextViewText(
                R.id.compact_course_meta,
                if (place.isBlank()) "明天 ${tomorrowCourse.startText}"
                else "明天 ${tomorrowCourse.startText} · $place"
            )
            return
        }
        if (isVacation) {
            views.setTextViewText(R.id.widget_status, "假期中")
            return
        }
        if (todayCourses.isEmpty()) {
            views.setTextViewText(R.id.widget_status, "明日暂无课程")
            return
        }
        if (upcoming == null) {
            views.setTextViewText(R.id.widget_status, "明日暂无课程")
            return
        }
        val prefix = if (upcoming.isActive(nowMinute)) "正在上课" else "下一节 ${upcoming.startText}"
        val place = upcoming.room.ifBlank { upcoming.sectionText }
        views.setTextViewText(R.id.widget_status, upcoming.name)
        views.setTextViewText(
            R.id.compact_course_meta,
            "$prefix · $place"
        )
    }

    private fun bindCourseRow(
        views: RemoteViews,
        binding: CourseRowBinding,
        course: WidgetCourse?,
        nowMinute: Int
    ) {
        if (course == null) {
            views.setTextViewText(binding.timeId, "")
            views.setTextViewText(binding.nameId, "")
            views.setTextViewText(binding.metaId, "")
            views.setViewVisibility(binding.rowId, View.INVISIBLE)
            return
        }
        views.setViewVisibility(binding.rowId, View.VISIBLE)
        views.setInt(
            binding.rowId,
            "setBackgroundResource",
            if (course.isActive(nowMinute)) {
                R.drawable.widget_course_row_active_background
            } else {
                R.drawable.widget_course_row_background
            }
        )
        views.setTextViewText(binding.timeId, "${course.startText}-${course.endText}")
        views.setTextViewText(binding.nameId, course.name)
        views.setTextViewText(
            binding.metaId,
            course.meta.ifBlank { course.sectionText }
        )
    }

    private fun statusText(
        todayCourses: List<WidgetCourse>,
        upcoming: WidgetCourse?,
        nowMinute: Int
    ): String {
        if (todayCourses.isEmpty()) {
            return "明日暂无课程"
        }
        if (upcoming == null) {
            return "明日暂无课程"
        }
        if (upcoming.isActive(nowMinute)) {
            return "正在上课 · ${upcoming.name}"
        }
        return "下一节 ${upcoming.startText} · ${upcoming.name}"
    }

    private fun launchIntent(context: Context): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("shuyo://schedule")
        )
    }

    private fun weekdayName(weekday: Int): String {
        return when (weekday) {
            1 -> "周一"
            2 -> "周二"
            3 -> "周三"
            4 -> "周四"
            5 -> "周五"
            6 -> "周六"
            7 -> "周日"
            else -> ""
        }
    }

    companion object {
        private const val KEY_SNAPSHOT = "academic_schedule_widget_snapshot"
    }
}

data class CourseRowBinding(
    val rowId: Int,
    val timeId: Int,
    val nameId: Int,
    val metaId: Int
)

private data class WidgetSchedule(
    val term: String,
    val maxWeek: Int,
    val currentWeek: Int,
    val anchorMonday: String,
    val courses: List<WidgetCourse>
) {
    fun activeWeek(today: LocalDate): Int {
        val vacationWeek = maxWeek + 1
        val anchor = parseDate(anchorMonday)
            ?: return currentWeek.coerceIn(0, vacationWeek)
        val todayMonday = today.minusDays((today.dayOfWeek.value - 1).toLong())
        val weekOffset = ChronoUnit.WEEKS.between(anchor, todayMonday).toInt()
        return (currentWeek + weekOffset).coerceIn(0, vacationWeek.coerceAtLeast(2))
    }

    companion object {
        fun parse(raw: String?): WidgetSchedule? {
            if (raw.isNullOrBlank()) {
                return null
            }
            return try {
                val json = JSONObject(raw)
                if (!json.optBoolean("hasSchedule", false)) {
                    return null
                }
                val sessions = mutableListOf<WidgetCourse>()
                val sessionJson = json.optJSONArray("sessions")
                if (sessionJson != null) {
                    for (index in 0 until sessionJson.length()) {
                        val course = WidgetCourse.parse(
                            sessionJson.optJSONObject(index) ?: continue
                        )
                        if (course != null) {
                            sessions.add(course)
                        }
                    }
                }
                WidgetSchedule(
                    term = json.optString("term", ""),
                    maxWeek = json.optInt("maxWeek", 1).coerceAtLeast(1),
                    currentWeek = json.optInt("currentWeek", 1).coerceAtLeast(0),
                    anchorMonday = json.optString("anchorMonday", ""),
                    courses = sessions
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}

private data class WidgetCourse(
    val name: String,
    val room: String,
    val meta: String,
    val weekday: Int,
    val weeks: Set<Int>,
    val startMinute: Int,
    val endMinute: Int,
    val startText: String,
    val endText: String,
    val sectionText: String
) {
    fun occursInWeek(week: Int): Boolean = weeks.isEmpty() || weeks.contains(week)

    fun isActive(minute: Int): Boolean = minute in startMinute..endMinute

    companion object {
        fun parse(json: JSONObject): WidgetCourse? {
            val name = json.optString("name", "").trim()
            val weekday = json.optInt("weekday", 0)
            val startMinute = json.optInt("startMinute", -1)
            val endMinute = json.optInt("endMinute", -1)
            if (name.isBlank() ||
                weekday !in 1..7 ||
                startMinute < 0 ||
                endMinute < startMinute
            ) {
                return null
            }

            val weeks = mutableSetOf<Int>()
            val weekJson = json.optJSONArray("weeks")
            if (weekJson != null) {
                for (index in 0 until weekJson.length()) {
                    val week = weekJson.optInt(index, 0)
                    if (week > 0) {
                        weeks.add(week)
                    }
                }
            }

            return WidgetCourse(
                name = name,
                room = json.optString("room", "").trim(),
                meta = json.optString("meta", "").trim(),
                weekday = weekday,
                weeks = weeks,
                startMinute = startMinute,
                endMinute = endMinute,
                startText = json.optString("startText", formatMinute(startMinute)),
                endText = json.optString("endText", formatMinute(endMinute)),
                sectionText = json.optString("sectionText", "").trim()
            )
        }

        private fun formatMinute(minute: Int): String {
            return String.format(
                Locale.US,
                "%02d:%02d",
                minute / 60,
                minute % 60
            )
        }
    }
}

private fun parseDate(value: String): LocalDate? {
    val datePart = value.substringBefore("T").ifBlank { return null }
    return try {
        LocalDate.parse(datePart)
    } catch (_: Exception) {
        null
    }
}
