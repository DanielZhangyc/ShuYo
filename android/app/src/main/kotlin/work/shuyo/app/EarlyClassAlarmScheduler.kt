package work.shuyo.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object EarlyClassAlarmScheduler {
    const val PREFS = "early_class_alarms"
    private const val KEY = "alarms"
    private const val ACTION = "work.shuyo.app.EARLY_CLASS_ALARM"
    const val RINGTONE_URI_KEY = "ringtone_uri"
    const val RINGTONE_NAME_KEY = "ringtone_name"

    fun isAvailable(context: Context): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP
    }

    fun getRingtone(context: Context): Map<String, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val uri = prefs.getString(RINGTONE_URI_KEY, null)?.takeIf { it.isNotBlank() }
            ?: return null
        return mapOf(
            "uri" to uri,
            "name" to (prefs.getString(RINGTONE_NAME_KEY, null) ?: "自定义铃声"),
        )
    }

    fun sync(context: Context, raw: List<Map<String, Any?>>): Int {
        return try {
            val manager = context.getSystemService(AlarmManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !manager.canScheduleExactAlarms()
            ) {
                cancelAll(context)
                return -1
            }

            cancelAll(context)
            val now = System.currentTimeMillis()
            val saved = JSONArray()
            raw.forEachIndexed { index, item ->
                val time = (item["fireTime"] as? Number)?.toLong()
                    ?: return@forEachIndexed
                if (time <= now) return@forEachIndexed

                val id = item["id"]?.toString() ?: "alarm-$index-$time"
                val title = item["title"]?.toString() ?: "早课提醒"
                val courseTime = (item["courseTime"] as? Number)?.toLong() ?: time
                val courseEndTime = (item["courseEndTime"] as? Number)?.toLong() ?: 0L
                val sectionText = item["sectionText"]?.toString().orEmpty()
                val campus = item["campus"]?.toString().orEmpty()
                val location = item["location"]?.toString().orEmpty()
                val teacherName = item["teacherName"]?.toString().orEmpty()
                val vibrationEnabled = item["vibrationEnabled"] as? Boolean ?: false
                val requestCode = id.hashCode()
                schedule(
                    context = context,
                    manager = manager,
                    fireTime = time,
                    requestCode = requestCode,
                    id = id,
                    title = title,
                    courseTime = courseTime,
                    courseEndTime = courseEndTime,
                    sectionText = sectionText,
                    campus = campus,
                    location = location,
                    teacherName = teacherName,
                    vibrationEnabled = vibrationEnabled,
                )
                saved.put(JSONObject().apply {
                    put("requestCode", requestCode)
                    put("id", id)
                    put("fireTime", time)
                    put("title", title)
                    put("courseTime", courseTime)
                    put("courseEndTime", courseEndTime)
                    put("sectionText", sectionText)
                    put("campus", campus)
                    put("location", location)
                    put("teacherName", teacherName)
                    put("vibrationEnabled", vibrationEnabled)
                })
            }
            save(context, saved)
            saved.length()
        } catch (_: SecurityException) {
            -1
        }
    }

    fun restore(context: Context): Int {
        return try {
            val saved = load(context)
            if (saved.length() == 0) return 0

            val manager = context.getSystemService(AlarmManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !manager.canScheduleExactAlarms()
            ) {
                return -1
            }

            val now = System.currentTimeMillis()
            val active = JSONArray()
            var restored = 0
            for (index in 0 until saved.length()) {
                val item = saved.optJSONObject(index) ?: continue
                val fireTime = item.optLong("fireTime", 0L)
                if (fireTime <= now) continue

                val id = item.optString("id", "alarm-$index-$fireTime")
                val title = item.optString("title", "早课提醒")
                val courseTime = item.optLong("courseTime", fireTime)
                val courseEndTime = item.optLong("courseEndTime", 0L)
                val sectionText = item.optString("sectionText", "")
                val campus = item.optString("campus", "")
                val location = item.optString("location", "")
                val teacherName = item.optString("teacherName", "")
                val vibrationEnabled = item.optBoolean("vibrationEnabled", false)
                val requestCode = item.optInt("requestCode", id.hashCode())
                schedule(
                    context = context,
                    manager = manager,
                    fireTime = fireTime,
                    requestCode = requestCode,
                    id = id,
                    title = title,
                    courseTime = courseTime,
                    courseEndTime = courseEndTime,
                    sectionText = sectionText,
                    campus = campus,
                    location = location,
                    teacherName = teacherName,
                    vibrationEnabled = vibrationEnabled,
                )
                active.put(item)
                restored++
            }
            save(context, active)
            restored
        } catch (_: SecurityException) {
            -1
        }
    }

    fun cancelAll(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val saved = load(context)
        for (i in 0 until saved.length()) {
            val code = saved.optJSONObject(i)?.optInt("requestCode") ?: continue
            val intent = Intent(context, EarlyClassAlarmReceiver::class.java).apply {
                action = ACTION
            }
            val pending = PendingIntent.getBroadcast(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            manager.cancel(pending)
            pending.cancel()
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY).apply()
    }

    private fun schedule(
        context: Context,
        manager: AlarmManager,
        fireTime: Long,
        requestCode: Int,
        id: String,
        title: String,
        courseTime: Long,
        courseEndTime: Long,
        sectionText: String,
        campus: String,
        location: String,
        teacherName: String,
        vibrationEnabled: Boolean,
    ) {
        val alarmIntent = Intent(context, EarlyClassAlarmReceiver::class.java).apply {
            action = ACTION
            putExtra("title", title)
            putExtra("fireTime", fireTime)
            putExtra("courseTime", courseTime)
            putExtra("courseEndTime", courseEndTime)
            putExtra("sectionText", sectionText)
            putExtra("campus", campus)
            putExtra("location", location)
            putExtra("teacherName", teacherName)
            putExtra("vibrationEnabled", vibrationEnabled)
            putExtra("alarmId", id)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val showIntent = Intent(context, EarlyClassAlarmActivity::class.java).apply {
            putExtra("fireTime", fireTime)
            putExtra("title", title)
            putExtra("courseTime", courseTime)
            putExtra("courseEndTime", courseEndTime)
            putExtra("sectionText", sectionText)
            putExtra("campus", campus)
            putExtra("location", location)
            putExtra("teacherName", teacherName)
            putExtra("vibrationEnabled", vibrationEnabled)
            putExtra("alarmId", id)
        }
        val showPendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            showIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Tell Android that this is a user-visible alarm. This is more suitable
        // for an alarm-clock use case than a normal exact background alarm.
        manager.setAlarmClock(
            AlarmManager.AlarmClockInfo(fireTime, showPendingIntent),
            pending,
        )
    }

    private fun load(context: Context): JSONArray {
        val value = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "[]") ?: "[]"
        return runCatching { JSONArray(value) }.getOrDefault(JSONArray())
    }

    private fun save(context: Context, alarms: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, alarms.toString()).apply()
    }
}
