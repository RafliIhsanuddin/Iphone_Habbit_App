package com.example.habit_app

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ALARM_CHANNEL = "habit_app/alarm"
    private val activePlayers = HashMap<String, MediaPlayer>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                val habitId = call.argument<String>("habitId") ?: ""
                when (call.method) {
                    "playAlarm" -> {
                        try {
                            if (!activePlayers.containsKey(habitId)) {
                                val alarmUri = RingtoneManager.getActualDefaultRingtoneUri(
                                    applicationContext, RingtoneManager.TYPE_ALARM
                                ) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

                                val mediaPlayer = MediaPlayer().apply {
                                    setAudioAttributes(
                                        AudioAttributes.Builder()
                                            .setUsage(AudioAttributes.USAGE_ALARM)
                                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                            .build()
                                    )
                                    setDataSource(applicationContext, alarmUri)
                                    isLooping = true
                                    prepare()
                                    start()
                                }
                                activePlayers[habitId] = mediaPlayer
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_ALARM_FAILED", e.message, null)
                        }
                    }
                    "stopAlarm" -> {
                        try {
                            activePlayers.remove(habitId)?.apply {
                                stop()
                                release()
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("STOP_ALARM_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        activePlayers.values.forEach {
            try { it.stop(); it.release() } catch (_: Exception) {}
        }
        activePlayers.clear()
        super.onDestroy()
    }
}