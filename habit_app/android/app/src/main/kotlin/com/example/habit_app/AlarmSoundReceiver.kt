// New Code
package com.example.habit_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager

class AlarmSoundReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val habitId = intent.getStringExtra("habitId") ?: return
        MainActivity.startAlarmPlaybackStatic(context, habitId)
    }
}

// Registered against the same action ids flutter_local_notifications uses
// for the Alarm Reminder's DISMISS and SNOOZE buttons. Because this is a
// separate manifest-declared BroadcastReceiver (not routed through the
// Dart isolate), Android can deliver these action Intents to it directly
// even while the app process is fully killed, letting the native alarm
// sound for that exact habit stop immediately — independent of whether
// the Dart-side pending-action bookkeeping in ReminderService has run yet.
class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val habitId = intent.getStringExtra("habitId") ?: return
        MainActivity.stopAlarmPlaybackStatic(habitId)
    }
}