package com.example.habit_app

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
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
                    // Only one alarm sound may be audible at any given moment
                    // (Rule 1 & 2): stop any other habit's currently playing
                    // native alarm sound before starting this one. This does
                    // NOT resolve/cancel the other habit's alarm session — it
                    // only silences its audio; the Dart-side queue
                    // (_activeAlarmOrder) still tracks it as active/unresolved
                    // and will resume it automatically once this newer alarm
                    // is dismissed/snoozed.
                    for ((otherId, otherPlayer) in activePlayers) {
                        if (otherId != habitId) {
                            try {
                                otherPlayer.stop()
                                otherPlayer.release()
                            } catch (e: Exception) {
                            }
                        }
                    }
                    activePlayers.keys.filter { it != habitId }.forEach { activePlayers.remove(it) }
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

    // ─────────────────────────────────────────────────────────────
    // THE FIX:
    // By default, Flutter's SystemNavigator.pop() calls Activity.finish(),
    // which destroys this Activity and fires onDestroy() below.
    // onDestroy() stops/releases ALL entries in activePlayers — not just
    // the one habit that was just dismissed/snoozed.
    //
    // With two simultaneous habit alarms this caused exactly the bug
    // reported: dismiss/snooze Habit A → resumeNewestRemainingAlarm()
    // starts Habit B's alarm sound → moveAppToBackground() calls
    // SystemNavigator.pop() → Activity.finish() → onDestroy() clears
    // activePlayers → Habit B's just-started alarm is killed too, even
    // though B was never dismissed/snoozed.
    //
    // Overriding popSystemNavigator() to call moveTaskToBack() instead
    // means SystemNavigator.pop() only backgrounds the app (like the
    // Home button) — the Activity, its MediaPlayer instances, and the
    // Dart process's in-memory state all stay alive. Any habit whose
    // alarm hasn't been dismissed/snoozed keeps ringing exactly as
    // intended, and onDestroy() only fires on a real app close/kill.
    // ─────────────────────────────────────────────────────────────
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
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
        // Only fires now on a genuine app close/kill (task swiped away,
        // OS reclaiming memory, etc.) — no longer on every dismiss/snooze,
        // since popSystemNavigator() above no longer calls finish().
        activePlayers.values.forEach {
            try { it.stop(); it.release() } catch (_: Exception) {}
        }
        activePlayers.clear()
        super.onDestroy()
    }
}


