package com.example.habit_app

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ALARM_CHANNEL = "habit_app/alarm"

    companion object {
        val activePlayers = HashMap<String, MediaPlayer>()

        fun startAlarmPlaybackStatic(context: android.content.Context, habitId: String) {
            startNativeAlarmSound(context, habitId)
        }

        fun startNativeAlarmSound(context: android.content.Context, habitId: String) {
            try {
                if (!activePlayers.containsKey(habitId)) {
                    // Only one alarm may play at a time — stop any other
                    // currently playing alarm before starting this one.
                    val othersToStop = activePlayers.keys.filter { it != habitId }
                    for (otherId in othersToStop) {
                        activePlayers.remove(otherId)?.apply {
                            try { stop(); release() } catch (_: Exception) {}
                        }
                    }
                    val alarmUri = RingtoneManager.getActualDefaultRingtoneUri(
                        context, RingtoneManager.TYPE_ALARM
                    ) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

                    val mediaPlayer = MediaPlayer().apply {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        setDataSource(context, alarmUri)
                        isLooping = true
                        prepare()
                        start()
                    }
                    activePlayers[habitId] = mediaPlayer
                }
            } catch (e: Exception) {
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                val habitId = call.argument<String>("habitId") ?: ""
                when (call.method) {
                    "playAlarm" -> {
                        try {
                            startNativeAlarmSound(applicationContext, habitId)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_ALARM_FAILED", e.message, null)
                        }
                    }
                    "scheduleNativeAlarmSound" -> {
                        try {
                            val triggerAtMillis = call.argument<Long>("triggerAtMillis") ?: 0L
                            val am = applicationContext.getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
                            val intent = Intent(applicationContext, AlarmSoundReceiver::class.java)
                            intent.putExtra("habitId", habitId)
                            val pi = android.app.PendingIntent.getBroadcast(
                                applicationContext,
                                habitId.hashCode(),
                                intent,
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                            )
                            am.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_NATIVE_ALARM_FAILED", e.message, null)
                        }
                    }
                    "cancelNativeAlarmSound" -> {
                        try {
                            val am = applicationContext.getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
                            val intent = Intent(applicationContext, AlarmSoundReceiver::class.java)
                            val pi = android.app.PendingIntent.getBroadcast(
                                applicationContext,
                                habitId.hashCode(),
                                intent,
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                            )
                            am.cancel(pi)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CANCEL_NATIVE_ALARM_FAILED", e.message, null)
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
                    "showSnoozeToast" -> {
                        try {
                            val message = call.argument<String>("message") ?: ""
                            android.widget.Toast.makeText(applicationContext, message, android.widget.Toast.LENGTH_SHORT).show()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHOW_SNOOZE_TOAST_FAILED", e.message, null)
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