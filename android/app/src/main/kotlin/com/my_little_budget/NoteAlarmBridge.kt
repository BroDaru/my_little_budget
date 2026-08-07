package com.my_little_budget

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object NoteAlarmScheduler {
    const val EXTRA_JOB = "note_alarm_job"
    const val EXTRA_NOTE_ID = "note_id"
    private const val PREFS = "note_alarm_jobs"
    private const val KEY_JOBS = "jobs"

    fun replace(context: Context, jobs: List<Map<String, Any?>>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = JSONArray(prefs.getString(KEY_JOBS, "[]"))
        for (index in 0 until old.length()) cancel(context, old.getJSONObject(index).optInt("id"))
        val array = JSONArray()
        jobs.forEach { array.put(JSONObject(it)) }
        prefs.edit().putString(KEY_JOBS, array.toString()).apply()
        scheduleStored(context, array)
    }

    fun reschedule(context: Context) {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_JOBS, "[]")
        scheduleStored(context, JSONArray(raw))
    }

    fun snooze(context: Context, job: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = JSONArray(prefs.getString(KEY_JOBS, "[]"))
        val array = JSONArray()
        val id = job.getInt("id")
        for (index in 0 until old.length()) {
            val existing = old.getJSONObject(index)
            if (existing.optInt("id") != id) array.put(existing)
        }
        cancel(context, id)
        array.put(job)
        prefs.edit().putString(KEY_JOBS, array.toString()).apply()
        schedule(context, job)
    }

    private fun scheduleStored(context: Context, jobs: JSONArray) {
        val now = System.currentTimeMillis()
        for (index in 0 until jobs.length()) {
            val job = jobs.getJSONObject(index)
            if (job.optLong("triggerAt") > now) schedule(context, job)
        }
    }

    private fun schedule(context: Context, job: JSONObject) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            job.getInt("id"),
            Intent(context, NoteAlarmReceiver::class.java).putExtra(EXTRA_JOB, job.toString()),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, job.getLong("triggerAt"), pending)
    }

    private fun cancel(context: Context, id: Int) {
        val pending = PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, NoteAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }
}

class NoteAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            NoteAlarmScheduler.reschedule(context)
            return
        }
        val job = intent.getStringExtra(NoteAlarmScheduler.EXTRA_JOB) ?: return
        val service = Intent(context, NoteAlarmPlaybackService::class.java)
            .setAction(NoteAlarmPlaybackService.ACTION_PLAY)
            .putExtra(NoteAlarmScheduler.EXTRA_JOB, job)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service)
        else context.startService(service)
    }
}

class NoteAlarmPlaybackService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var startedAt = 0L
    private var clipStart = 0
    private var clipEnd: Int? = null
    private var alarmActive = false

    override fun onCreate() {
        super.onCreate()
        NoteAlarmChannel.ensureCreated(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopPlayback(notifyScreen = true)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_SNOOZE) {
            val raw = intent.getStringExtra(NoteAlarmScheduler.EXTRA_JOB)
            if (raw != null) snooze(JSONObject(raw))
            stopPlayback(notifyScreen = true)
            stopSelf()
            return START_NOT_STICKY
        }
        val raw = intent?.getStringExtra(NoteAlarmScheduler.EXTRA_JOB) ?: return START_NOT_STICKY
        play(JSONObject(raw))
        return START_NOT_STICKY
    }

    private fun play(job: JSONObject) {
        stopPlayback(notifyScreen = false)
        alarmActive = true
        val systemSettings = NoteAlarmChannel.playbackSettings(this)
        val playback = NoteAlarmPlaybackPolicy.resolve(
            systemSoundAllowed = systemSettings.soundAllowed,
            systemVibrationAllowed = systemSettings.vibrationAllowed,
            noteSoundAllowed = job.optBoolean("soundEnabled", true),
            noteVibrationAllowed = job.optBoolean("vibrationEnabled", true),
        )
        startForeground(NOTIFICATION_ID, notification(job))
        startedAt = System.currentTimeMillis()
        clipStart = job.optInt("clipStartMs", 0).coerceAtLeast(0)
        clipEnd = job.optInt("clipEndMs", -1).takeIf { it > clipStart }
        if (playback.playSound) {
            player = createPlayer(this, job)?.also { media ->
                media.setOnPreparedListener {
                    if (clipStart > 0) it.seekTo(clipStart)
                    it.start()
                    handler.post(progress)
                }
                media.prepareAsync()
            }
        }
        if (playback.vibrate) startVibration()
        handler.postDelayed(timeout, 60_000L)
    }

    private fun snooze(job: JSONObject) {
        val minutes = job.optInt("snoozeMinutes", 0)
        if (minutes <= 0) return
        job.put("triggerAt", System.currentTimeMillis() + minutes * 60_000L)
        NoteAlarmScheduler.snooze(this, job)
    }

    private val timeout = Runnable {
        stopPlayback(notifyScreen = true)
        stopSelf()
    }

    private val progress = object : Runnable {
        override fun run() {
            val media = player ?: return
            val end = clipEnd ?: media.duration.takeIf { it > 0 }
            if (end != null && media.isPlaying && media.currentPosition >= end - 60) media.seekTo(clipStart)
            handler.postDelayed(this, 80)
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 500, 350)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION") vibrator?.vibrate(pattern, 0)
        }
    }

    private fun notification(job: JSONObject): android.app.Notification {
        val noteId = job.optInt("noteId")
        val title = job.optString("title", "메모 알람")
        val open = PendingIntent.getActivity(
            this,
            noteId,
            Intent(this, MainActivity::class.java)
                .putExtra(NoteAlarmScheduler.EXTRA_NOTE_ID, noteId)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, NoteAlarmPlaybackService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val snooze = PendingIntent.getService(
            this,
            2,
            Intent(this, NoteAlarmPlaybackService::class.java)
                .setAction(ACTION_SNOOZE)
                .putExtra(NoteAlarmScheduler.EXTRA_JOB, job.toString()),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmScreen = PendingIntent.getActivity(
            this,
            FULL_SCREEN_REQUEST_CODE,
            Intent(this, NoteAlarmActivity::class.java)
                .putExtra(NoteAlarmScheduler.EXTRA_JOB, job.toString())
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, NoteAlarmPlaybackPolicy.CHANNEL_ID)
            .setSmallIcon(com.my_little_budget.R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("메모 알람이 울리고 있습니다.")
            .setContentIntent(open)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSilent(NoteAlarmPlaybackPolicy.NOTIFICATION_MUST_BE_SILENT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(alarmScreen, true)
            .addAction(0, "정지", stop)
        if (job.optInt("snoozeMinutes", 0) > 0) {
            builder.addAction(0, "스누즈", snooze)
        }
        return builder.build()
    }

    private fun stopPlayback(notifyScreen: Boolean) {
        handler.removeCallbacksAndMessages(null)
        player?.runCatching { stop() }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (alarmActive && notifyScreen) {
            sendBroadcast(Intent(ACTION_FINISHED).setPackage(packageName))
        }
        alarmActive = false
    }

    override fun onDestroy() {
        stopPlayback(notifyScreen = true)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_PLAY = "com.my_little_budget.PLAY_NOTE_ALARM"
        const val ACTION_STOP = "com.my_little_budget.STOP_NOTE_ALARM"
        const val ACTION_SNOOZE = "com.my_little_budget.SNOOZE_NOTE_ALARM"
        const val ACTION_FINISHED = "com.my_little_budget.NOTE_ALARM_FINISHED"
        private const val NOTIFICATION_ID = 739999
        private const val FULL_SCREEN_REQUEST_CODE = 739998
    }
}

internal object NoteAlarmChannel {
    private val vibrationPattern = longArrayOf(0, 500, 350)

    fun ensureCreated(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val legacy = manager.getNotificationChannel(NoteAlarmPlaybackPolicy.LEGACY_CHANNEL_ID)
        if (manager.getNotificationChannel(NoteAlarmPlaybackPolicy.CHANNEL_ID) == null) {
            val importance = legacy?.importance ?: NotificationManager.IMPORTANCE_HIGH
            val soundAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                NoteAlarmPlaybackPolicy.CHANNEL_ID,
                "메모 알람",
                importance,
            ).apply {
                description = "메모 알람의 소리와 진동 허용 여부"
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), soundAttributes)
                setVibrationPattern(vibrationPattern)
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
        if (legacy != null) {
            manager.deleteNotificationChannel(NoteAlarmPlaybackPolicy.LEGACY_CHANNEL_ID)
        }
    }

    fun playbackSettings(context: Context): NoteAlarmSystemPlaybackSettings {
        val notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return NoteAlarmPlaybackPolicy.systemSettings(
                notificationsAllowed = notificationsAllowed,
                channelEnabled = true,
                channelSoundAllowed = true,
                channelVibrationAllowed = true,
            )
        }
        val channel = context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(NoteAlarmPlaybackPolicy.CHANNEL_ID)
        return NoteAlarmPlaybackPolicy.systemSettings(
            notificationsAllowed = notificationsAllowed,
            channelEnabled = channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE,
            channelSoundAllowed = channel != null &&
                channel.importance >= NotificationManager.IMPORTANCE_DEFAULT &&
                channel.sound != null,
            channelVibrationAllowed = channel?.shouldVibrate() == true,
        )
    }
}

object NoteAlarmPreview {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var tone: ToneGenerator? = null

    fun play(context: Context, values: Map<String, Any?>): Boolean {
        stop()
        val job = JSONObject(values)
        val start = job.optInt("clipStartMs", 0).coerceAtLeast(0)
        val end = job.optInt("clipEndMs", -1).takeIf { it > start }
        player = createPlayer(context, job)?.also { media ->
            media.setOnPreparedListener {
                if (start > 0) it.seekTo(start)
                it.start()
                if (end != null) handler.post(object : Runnable {
                    override fun run() {
                        if (media.currentPosition >= end - 60) stop() else handler.postDelayed(this, 80)
                    }
                })
            }
            media.setOnCompletionListener { stop() }
            media.prepareAsync()
        }
        if (player != null) return true

        return runCatching {
            tone = ToneGenerator(AudioManager.STREAM_ALARM, 100).also {
                it.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 1500)
            }
            handler.postDelayed({ stop() }, 1600)
            true
        }.getOrDefault(false)
    }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        player?.runCatching { stop() }
        player?.release()
        player = null
        tone?.runCatching { stopTone() }
        tone?.release()
        tone = null
    }
}

private fun createPlayer(context: Context, job: JSONObject): MediaPlayer? {
    val configured = job.optString("soundUri").takeIf { it.isNotBlank() }
    val uri = if (job.optString("soundKind") == "custom") {
        configured?.let { value ->
            val file = File(Uri.parse(value).path ?: value)
            if (file.exists()) Uri.fromFile(file) else null
        }
    } else configured?.let(Uri::parse)
    for (source in alarmSoundCandidates(context, uri)) {
        val player = try {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                setDataSource(context, source)
            }
        } catch (_: Exception) {
            null
        }
        if (player != null) return player
    }
    return null
}

private fun alarmSoundCandidates(context: Context, preferred: Uri?): List<Uri> {
    return listOfNotNull(
        preferred,
        RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM),
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
        RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_NOTIFICATION),
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
        RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE),
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
    ).distinct()
}
