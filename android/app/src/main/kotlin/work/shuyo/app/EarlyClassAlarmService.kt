package work.shuyo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class EarlyClassAlarmService : Service() {
    private data class ActiveAlarm(
        val title: String,
        val courseTime: Long,
        val courseEndTime: Long,
        val campus: String,
        val location: String,
        val teacherName: String,
        val fireTime: Long,
        val alarmId: String,
    )

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarm()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra("title") ?: "早课提醒"
        val courseTime = intent?.getLongExtra("courseTime", 0L) ?: 0L
        val courseEndTime = intent?.getLongExtra("courseEndTime", 0L) ?: 0L
        val sectionText = intent?.getStringExtra("sectionText") ?: ""
        val campus = intent?.getStringExtra("campus") ?: ""
        val location = intent?.getStringExtra("location") ?: ""
        val teacherName = intent?.getStringExtra("teacherName") ?: ""
        val fireTime = intent?.getLongExtra("fireTime", 0L) ?: 0L
        val alarmId = intent?.getStringExtra("alarmId") ?: "early-class"
        val vibrationEnabled =
            intent?.getBooleanExtra("vibrationEnabled", false) ?: false
        activeAlarm = ActiveAlarm(
            title = title,
            courseTime = courseTime,
            courseEndTime = courseEndTime,
            campus = campus,
            location = location,
            teacherName = teacherName,
            fireTime = fireTime,
            alarmId = alarmId,
        )
        startForeground(
            NOTIFICATION_ID,
            buildNotification(
                title = title,
                courseTime = courseTime,
                courseEndTime = courseEndTime,
                sectionText = sectionText,
                campus = campus,
                location = location,
                teacherName = teacherName,
                fireTime = fireTime,
                alarmId = alarmId,
            ),
        )
        startAlarmSound(vibrationEnabled)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        activeAlarm = null
        stopAlarmPlayback()
        super.onDestroy()
    }

    private fun startAlarmSound(vibrationEnabled: Boolean) {
        stopAlarmPlayback()

        if (vibrationEnabled) {
            vibrator = getSystemService(Vibrator::class.java)
            vibrator?.let { deviceVibrator ->
                if (!deviceVibrator.hasVibrator()) return@let
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val effect = VibrationEffect.createWaveform(
                        longArrayOf(0L, 700L, 500L),
                        0,
                    )
                    deviceVibrator.vibrate(
                        effect,
                        android.os.VibrationAttributes.Builder()
                            .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                            .build(),
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    deviceVibrator.vibrate(
                        VibrationEffect.createWaveform(longArrayOf(0L, 700L, 500L), 0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    deviceVibrator.vibrate(longArrayOf(0L, 700L, 500L), 0)
                }
            }
        }

        val customUri = getSharedPreferences(
            EarlyClassAlarmScheduler.PREFS,
            MODE_PRIVATE,
        ).getString(EarlyClassAlarmScheduler.RINGTONE_URI_KEY, null)
            ?.takeIf { it.isNotBlank() }
            ?.let { runCatching { Uri.parse(it) }.getOrNull() }
        player = (customUri?.let(::createAlarmPlayer)
            ?: createAlarmPlayer(Settings.System.DEFAULT_ALARM_ALERT_URI))
    }

    private fun createAlarmPlayer(uri: Uri): MediaPlayer? {
        val mediaPlayer = MediaPlayer()
        return try {
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            mediaPlayer.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
            mediaPlayer.setDataSource(this, uri)
            mediaPlayer.isLooping = true
            mediaPlayer.prepare()
            mediaPlayer.start()
            mediaPlayer
        } catch (_: Exception) {
            mediaPlayer.release()
            null
        }
    }

    private fun stopAlarm() {
        activeAlarm = null
        stopAlarmPlayback()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopAlarmPlayback() {
        player?.let { mediaPlayer ->
            runCatching { mediaPlayer.stop() }
            mediaPlayer.release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun buildNotification(
        title: String,
        courseTime: Long,
        courseEndTime: Long,
        sectionText: String,
        campus: String,
        location: String,
        teacherName: String,
        fireTime: Long,
        alarmId: String,
    ) = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("早课提醒")
            .setContentText(title)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    notificationDetails(
                        title = title,
                        courseTime = courseTime,
                        courseEndTime = courseEndTime,
                        sectionText = sectionText,
                        campus = campus,
                        location = location,
                        teacherName = teacherName,
                        fireTime = fireTime,
                    ),
                ),
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSilent(true)
            .setContentIntent(
                alarmPendingIntent(
                    title,
                    courseTime,
                    courseEndTime,
                    sectionText,
                    campus,
                    location,
                    teacherName,
                    fireTime,
                    alarmId,
                    false,
                ),
            )
            .setFullScreenIntent(
                alarmPendingIntent(
                    title,
                    courseTime,
                    courseEndTime,
                    sectionText,
                    campus,
                    location,
                    teacherName,
                    fireTime,
                    alarmId,
                    false,
                ),
                true,
            )
            .addAction(
                R.mipmap.ic_launcher,
                "停止",
                alarmPendingIntent(
                    title,
                    courseTime,
                    courseEndTime,
                    sectionText,
                    campus,
                    location,
                    teacherName,
                    fireTime,
                    alarmId,
                    true,
                ),
            )
            .build()

    private fun notificationDetails(
        title: String,
        courseTime: Long,
        courseEndTime: Long,
        sectionText: String,
        campus: String,
        location: String,
        teacherName: String,
        fireTime: Long,
    ): String {
        val place = listOf(campus, location)
            .filter { it.isNotBlank() }
            .joinToString(" ")
        return listOfNotNull(
            title,
            if (courseTime > 0L) {
                "上课 ${formatTime(courseTime, courseEndTime)}"
            } else {
                null
            },
            sectionText.takeIf { it.isNotBlank() },
            place.takeIf { it.isNotBlank() },
            teacherName.takeIf { it.isNotBlank() },
            if (fireTime > 0L) "闹钟 ${formatDateTime(fireTime)}" else null,
        ).joinToString(" · ")
    }

    private fun alarmPendingIntent(
        title: String,
        courseTime: Long,
        courseEndTime: Long,
        sectionText: String,
        campus: String,
        location: String,
        teacherName: String,
        fireTime: Long,
        alarmId: String,
        stop: Boolean,
    ): PendingIntent {
        val intent = Intent(this, EarlyClassAlarmActivity::class.java).apply {
            action = if (stop) ACTION_STOP else ACTION_SHOW
            putExtra("title", title)
            putExtra("courseTime", courseTime)
            putExtra("courseEndTime", courseEndTime)
            putExtra("sectionText", sectionText)
            putExtra("campus", campus)
            putExtra("location", location)
            putExtra("teacherName", teacherName)
            putExtra("fireTime", fireTime)
            putExtra("alarmId", alarmId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            this,
            if (stop) STOP_PENDING_INTENT_REQUEST_CODE else alarmId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun formatTime(start: Long, end: Long): String {
        val formatter = SimpleDateFormat("HH:mm", Locale.CHINA)
        val startText = formatter.format(Date(start))
        return if (end > 0L) "$startText–${formatter.format(Date(end))}" else startText
    }

    private fun formatDateTime(value: Long): String =
        SimpleDateFormat("M月d日 HH:mm", Locale.CHINA).format(Date(value))

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                "早课闹钟",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                // Playback is handled by this service with USAGE_ALARM. Keeping
                // the channel silent prevents a second, short notification sound.
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    companion object {
        const val ACTION_START = "work.shuyo.app.EarlyClassAlarmService.START"
        const val ACTION_STOP = "work.shuyo.app.EarlyClassAlarmService.STOP"
        const val ACTION_SHOW = "work.shuyo.app.EarlyClassAlarmService.SHOW"

        private const val CHANNEL = "early_class_alarms"
        private const val NOTIFICATION_ID = 730001
        private const val STOP_PENDING_INTENT_REQUEST_CODE = 730002

        @Volatile
        private var activeAlarm: ActiveAlarm? = null

        fun activeAlarmIntent(context: Context): Intent? {
            val alarm = activeAlarm ?: return null
            return Intent(context, EarlyClassAlarmActivity::class.java).apply {
                action = ACTION_SHOW
                putExtra("title", alarm.title)
                putExtra("courseTime", alarm.courseTime)
                putExtra("courseEndTime", alarm.courseEndTime)
                putExtra("campus", alarm.campus)
                putExtra("location", alarm.location)
                putExtra("teacherName", alarm.teacherName)
                putExtra("fireTime", alarm.fireTime)
                putExtra("alarmId", alarm.alarmId)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        }

        fun dismiss(context: Context) {
            activeAlarm = null
            context.stopService(Intent(context, EarlyClassAlarmService::class.java))
        }
    }
}
