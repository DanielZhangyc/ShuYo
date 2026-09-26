package work.shuyo.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class EarlyClassAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, EarlyClassAlarmService::class.java).apply {
            action = EarlyClassAlarmService.ACTION_START
            putExtra("title", intent.getStringExtra("title") ?: "早课提醒")
            putExtra("fireTime", intent.getLongExtra("fireTime", 0L))
            putExtra("courseTime", intent.getLongExtra("courseTime", 0L))
            putExtra("courseEndTime", intent.getLongExtra("courseEndTime", 0L))
            putExtra("sectionText", intent.getStringExtra("sectionText") ?: "")
            putExtra("campus", intent.getStringExtra("campus") ?: "")
            putExtra("location", intent.getStringExtra("location") ?: "")
            putExtra("teacherName", intent.getStringExtra("teacherName") ?: "")
            putExtra("vibrationEnabled", intent.getBooleanExtra("vibrationEnabled", false))
            putExtra("alarmId", intent.getStringExtra("alarmId") ?: "early-class")
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
