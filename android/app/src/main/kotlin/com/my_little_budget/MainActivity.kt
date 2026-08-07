package com.my_little_budget

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var soundResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NoteAlarmChannel.ensureCreated(this)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.my_little_budget/note_alarms",
        ).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchNoteId" -> {
                        val id = intent?.getIntExtra(NoteAlarmScheduler.EXTRA_NOTE_ID, -1) ?: -1
                        intent?.removeExtra(NoteAlarmScheduler.EXTRA_NOTE_ID)
                        result.success(id.takeIf { it >= 0 })
                    }
                    "replaceAlarms" -> {
                        @Suppress("UNCHECKED_CAST")
                        val jobs = call.arguments as? List<Map<String, Any?>> ?: emptyList()
                        NoteAlarmScheduler.replace(this, jobs)
                        result.success(null)
                    }
                    "pickSystemSound" -> pickSystemSound(result)
                    "audioDuration" -> result.success(audioDuration(call.arguments as? String))
                    "preview" -> {
                        @Suppress("UNCHECKED_CAST")
                        result.success(NoteAlarmPreview.play(this, call.arguments as? Map<String, Any?> ?: emptyMap()))
                    }
                    "stopPreview" -> {
                        NoteAlarmPreview.stop()
                        result.success(null)
                    }
                    "cleanupAudio" -> {
                        @Suppress("UNCHECKED_CAST")
                        cleanupAudio((call.arguments as? List<String>) ?: emptyList())
                        result.success(null)
                    }
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "requestFullScreenIntentPermission" -> {
                        requestFullScreenIntentPermission()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val id = intent.getIntExtra(NoteAlarmScheduler.EXTRA_NOTE_ID, -1)
        if (id >= 0) channel?.invokeMethod("openNote", id)
    }

    private fun pickSystemSound(result: MethodChannel.Result) {
        if (soundResult != null) {
            result.error("picker_busy", "알람음 선택기가 이미 열려 있습니다.", null)
            return
        }
        soundResult = result
        startActivityForResult(
            Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            },
            REQUEST_RINGTONE,
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_RINGTONE) return
        val result = soundResult ?: return
        soundResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            result.success(null)
            return
        }
        val name = RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "시스템 알람음"
        result.success(mapOf("uri" to uri.toString(), "name" to name, "durationMs" to audioDuration(uri.toString())))
    }

    private fun audioDuration(value: String?): Int? {
        if (value.isNullOrBlank()) return null
        val retriever = MediaMetadataRetriever()
        return try {
            val uri = Uri.parse(value)
            if (uri.scheme == null || uri.scheme == "file") {
                retriever.setDataSource(uri.path ?: value)
            } else {
                retriever.setDataSource(this, uri)
            }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull()
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun cleanupAudio(retainedUris: List<String>) {
        val retained = retainedUris.mapNotNull { Uri.parse(it).path }.toSet()
        File(filesDir.parentFile, "app_flutter/note_alarm_audio")
            .listFiles()
            ?.filter { it.absolutePath !in retained }
            ?.forEach { it.delete() }
    }

    private fun canUseFullScreenIntent(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
        } else {
            true
        }
    }

    private fun requestFullScreenIntentPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || canUseFullScreenIntent()) return
        runCatching {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    companion object {
        private const val REQUEST_RINGTONE = 9301
    }
}
