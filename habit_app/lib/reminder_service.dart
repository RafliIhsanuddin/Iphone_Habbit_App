// ─────────────────────────────────────────────────────────────
// reminder_service.dart
//
// Draft langkah 1: skeleton service untuk reminder (Notification
// & Alarm). File ini BELUM dihubungkan ke main.dart / Habit /
// ReminderEntry — itu akan dilakukan di langkah berikutnya.
//
// Tujuan file ini:
//   1. Inisialisasi flutter_local_notifications utk Android & iOS
//   2. Minta izin notifikasi (Android 13+, iOS)
//   3. Definisikan notification "categories" berisi actions:
//        - kategori 'reminder_notification' → DONE, DISMISS, POSTPONED
//        - kategori 'reminder_alarm'        → DISMISS, SNOOZE
//   4. Handler global saat action ditekan / notifikasi di-tap
//      (isinya masih placeholder / TODO, diisi di langkah berikut)
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Action id constants — dipakai di kedua platform supaya konsisten
/// saat menangkap event tombol notifikasi.
class ReminderActionIds {
  static const done = 'action_done';
  static const dismiss = 'action_dismiss';
  static const postponed = 'action_postponed';
  static const snooze = 'action_snooze';
}

/// Notification category ids (dipetakan ke Darwin/iOS categories dan
/// dipakai juga sebagai penanda tipe payload di Android).
class ReminderCategoryIds {
  static const notification = 'reminder_notification'; // DONE / DISMISS / POSTPONED
  static const alarm = 'reminder_alarm';                // DISMISS / SNOOZE
}

/// Payload terstruktur yang disisipkan ke setiap notifikasi supaya saat
/// action ditekan / notifikasi di-tap, kita tahu habit mana & reminder mana.
///
/// Formatnya sederhana: "habitId|reminderTime|type"
/// (dibuat string sederhana dulu; nanti bisa diganti JSON kalau perlu field
/// tambahan seperti reminderIndex).
class ReminderPayload {
  final String habitId;
  final String reminderTime; // format 'HH:mm'
  final String type; // 'notification' | 'alarm'

  ReminderPayload({
    required this.habitId,
    required this.reminderTime,
    required this.type,
  });

  String encode() => '$habitId|$reminderTime|$type';

  static ReminderPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    return ReminderPayload(
      habitId: parts[0],
      reminderTime: parts[1],
      type: parts[2],
    );
  }
}

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Kunci navigator global — di-set dari main.dart (MaterialApp.navigatorKey)
  /// supaya ReminderService bisa melakukan Navigator.push() dari luar widget
  /// tree, misalnya saat notifikasi di-tap ketika app sedang di background.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Callback yang di-set oleh HabitHomePage (atau widget pemilik daftar
  /// habit) supaya ReminderService bisa "memberi tahu" aplikasi untuk
  /// menandai satu habit sebagai DONE hari ini, tanpa ReminderService perlu
  /// tahu struktur internal _HabitHomePageState.
  static void Function(String habitId)? onMarkDone;

  /// Callback opsional untuk membangun halaman Habit (home) dan Snooze page,
  /// di-set dari main.dart. Dipisah dari import langsung supaya file ini
  /// tetap tidak circular-import ke main.dart.
  static Widget Function(BuildContext context)? buildHabitHomeRoute;
  static Widget Function(BuildContext context, String habitId, String habitTitle)?
      buildSnoozeRoute;

  /// Dipanggil sekali di awal, sebelum runApp() — mirip CategoryStore.init().
  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    // NOTE: idealnya timezone lokal device di-set via package `flutter_timezone`
    // agar penjadwalan akurat lintas timezone. Ditambahkan di langkah berikutnya
    // saat wiring scheduling betulan; untuk skeleton ini kita pakai local() dulu.
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // ── iOS: definisikan actions per category ──
    final notifActions = <DarwinNotificationAction>[
      DarwinNotificationAction.plain(
        ReminderActionIds.done,
        'DONE',
        options: {DarwinNotificationActionOption.foreground},
      ),
      DarwinNotificationAction.plain(
        ReminderActionIds.dismiss,
        'DISMISS',
        options: {DarwinNotificationActionOption.destructive},
      ),
      DarwinNotificationAction.plain(
        ReminderActionIds.postponed,
        'POSTPONED',
      ),
    ];

    final alarmActions = <DarwinNotificationAction>[
      DarwinNotificationAction.plain(
        ReminderActionIds.dismiss,
        'DISMISS',
        options: {DarwinNotificationActionOption.destructive},
      ),
      DarwinNotificationAction.plain(
        ReminderActionIds.snooze,
        'SNOOZE',
      ),
    ];

    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // diminta manual lewat requestPermissions()
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          ReminderCategoryIds.notification,
          actions: notifActions,
          options: {
            DarwinNotificationCategoryOption.customDismissAction,
          },
        ),
        DarwinNotificationCategory(
          ReminderCategoryIds.alarm,
          actions: alarmActions,
          options: {
            DarwinNotificationCategoryOption.customDismissAction,
          },
        ),
      ],
    );

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      // Untuk action yg ditekan saat app benar-benar terminated (Android):
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    _initialized = true;
  }

  /// Memproses "pending action" yang ditulis oleh
  /// _onBackgroundNotificationResponse saat app sepenuhnya terminated.
  /// Harus dipanggil sekali dari main.dart, SETELAH onMarkDone di-set,
  /// supaya action DONE yang ditekan saat app killed tetap diterapkan
  /// ketika user membuka app kembali.
  Future<void> consumePendingBackgroundAction() async {
    final prefs = await SharedPreferences.getInstance();
    final habitId = prefs.getString('pending_mark_done_habit_id');
    if (habitId == null) return;
    await prefs.remove('pending_mark_done_habit_id');
    onMarkDone?.call(habitId);
  }

  /// Minta izin notifikasi (Android 13+/POST_NOTIFICATIONS, iOS alert/sound/badge)
  /// dan izin exact alarm (Android 12+/SCHEDULE_EXACT_ALARM).
  /// Dipanggil dari UI (misal saat user pertama kali membuat reminder),
  /// bukan otomatis saat init(), supaya user paham konteks permintaannya.
  Future<bool> requestPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool granted = true;

    if (androidImpl != null) {
      final notifGranted =
          await androidImpl.requestNotificationsPermission() ?? false;
      final exactAlarmGranted =
          await androidImpl.requestExactAlarmsPermission() ?? false;
      granted = granted && notifGranted && exactAlarmGranted;
    }

    if (iosImpl != null) {
      final iosGranted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      granted = granted && iosGranted;
    }

    return granted;
  }

  // ── Handlers (placeholder — diisi lengkap di langkah berikutnya) ──

  /// Dipanggil saat notifikasi/alarm di-tap (baik compact tap maupun
  /// tombol action di versi expanded), selama app masih hidup (foreground/
  /// background, bukan fully killed).
  void _onNotificationResponse(NotificationResponse response) {
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;

    final actionId = response.actionId;

    // ── Body notifikasi/alarm di-tap langsung (bukan lewat tombol expand) ──
    if (actionId == null || actionId.isEmpty) {
      _handleBodyTap(payload);
      return;
    }

    switch (actionId) {
      case ReminderActionIds.done:
        // Tandai habit selesai hari ini — persis seperti menekan DONE di app.
        onMarkDone?.call(payload.habitId);
        cancelReminderSlot(payload.habitId, payload.reminderTime);
        break;

      case ReminderActionIds.dismiss:
        // Tutup saja. Tidak mengubah status habit, tidak menjadwalkan lagi.
        // (Notifikasi sudah otomatis tertutup karena cancelNotification:true
        // pada action DISMISS; panggilan cancel() di sini untuk jaga-jaga.)
        _plugin.cancel(_notifId(payload.habitId, payload.reminderTime));
        break;

      case ReminderActionIds.postponed:
        // Jadwalkan ulang +10 menit, tampilkan konfirmasi platform.
        rescheduleSingleInMinutes(
          habitId: payload.habitId,
          habitTitle: _lastKnownHabitTitle(payload.habitId),
          reminderTime: payload.reminderTime,
          type: 'notification',
          minutesFromNow: 10,
        );
        _showConfirmationToast('Postponed for 10 minutes');
        break;

      case ReminderActionIds.snooze:
        // Jadwalkan ulang alarm +10 menit, tampilkan konfirmasi platform.
        rescheduleSingleInMinutes(
          habitId: payload.habitId,
          habitTitle: _lastKnownHabitTitle(payload.habitId),
          reminderTime: payload.reminderTime,
          type: 'alarm',
          minutesFromNow: 10,
        );
        _showConfirmationToast('Snoozed for 10 minutes');
        break;
    }
  }

  /// Body (compact) notifikasi/alarm di-tap langsung → tentukan halaman
  /// tujuan sesuai tipe reminder, sesuai requirement:
  ///   - notification → Habit page (halaman utama)
  ///   - alarm        → Snooze page
  void _handleBodyTap(ReminderPayload payload) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    if (payload.type == 'alarm') {
      final builder = buildSnoozeRoute;
      if (builder == null) return;
      nav.push(MaterialPageRoute(
        builder: (ctx) => builder(ctx, payload.habitId, _lastKnownHabitTitle(payload.habitId)),
      ));
    } else {
      // Notification → langsung ke Habit page (halaman utama), tanpa
      // menumpuk halaman lain di atasnya.
      nav.popUntil((route) => route.isFirst);
    }
  }

  /// Menyimpan judul habit terakhir yang diketahui per habitId, supaya saat
  /// notifikasi action ditekan (termasuk saat app baru dibuka dari kondisi
  /// background) kita masih bisa menampilkan nama habit yang benar tanpa
  /// harus mengakses state Flutter yang mungkin belum siap.
  final Map<String, String> _habitTitleCache = {};
  void rememberHabitTitle(String habitId, String title) {
    _habitTitleCache[habitId] = title;
  }

  String _lastKnownHabitTitle(String habitId) =>
      _habitTitleCache[habitId] ?? '';

  /// Menampilkan pesan konfirmasi singkat ala platform (mis. "Postponed for
  /// 10 minutes"). Karena ReminderService tidak selalu punya BuildContext
  /// yang valid (misalnya dipanggil dari background isolate), pesan ini
  /// ditampilkan lewat SnackBar HANYA jika ada Scaffold aktif yang bisa
  /// dijangkau lewat navigatorKey; jika tidak tersedia, panggilan diabaikan
  /// dengan aman (tidak melempar error).
  void _showConfirmationToast(String message) {
    final ctx = navigatorKey?.currentState?.overlay?.context;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(
      NotificationResponse response) {
    // Isolate terpisah (app state: terminated) — hanya menulis pending
    // action ke SharedPreferences; UI isolate yang memprosesnya lewat
    // consumePendingBackgroundAction() saat app dibuka kembali.
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;
    if (response.actionId != ReminderActionIds.done) return;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('pending_mark_done_habit_id', payload.habitId);
    });
  }

  FlutterLocalNotificationsPlugin get rawPlugin => _plugin;

  // ── Notification channel ids (Android) ──
  static const _notifChannelId = 'habit_notification_channel';
  static const _alarmChannelId = 'habit_alarm_channel';

  /// Stable numeric id derived from habitId + reminder time, so the same
  /// reminder slot always maps to the same notification id (needed so we
  /// can cancel/replace it precisely).
  int _notifId(String habitId, String time) =>
      ('$habitId|$time').hashCode & 0x7fffffff;

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _notifChannelId,
      'Habit Notifications',
      channelDescription: 'Reminders for your habits',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(ReminderActionIds.done, 'DONE'),
        AndroidNotificationAction(ReminderActionIds.dismiss, 'DISMISS',
            cancelNotification: true),
        AndroidNotificationAction(ReminderActionIds.postponed, 'POSTPONED'),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: ReminderCategoryIds.notification,
    );
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  NotificationDetails _alarmDetails() {
    const androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      'Habit Alarms',
      channelDescription: 'Alarms for your habits',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: [
        AndroidNotificationAction(ReminderActionIds.dismiss, 'DISMISS',
            cancelNotification: true),
        AndroidNotificationAction(ReminderActionIds.snooze, 'SNOOZE'),
      ],
    );
    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: ReminderCategoryIds.alarm,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// Batalkan satu slot reminder (dipakai internal & juga dipanggil langsung
  /// misalnya kalau habit dihapus seluruhnya).
  Future<void> cancelReminderSlot(String habitId, String time) async {
    await _plugin.cancel(_notifId(habitId, time));
  }

  /// Batalkan SEMUA slot reminder milik satu habit (dipanggil saat habit
  /// dihapus, atau sebelum reschedule penuh).
  Future<void> cancelAllForHabit(String habitId, List<String> times) async {
    for (final t in times) {
      await cancelReminderSlot(habitId, t);
    }
  }

  /// ── Fungsi utama untuk penjadwalan REAL-TIME ──
  ///
  /// Dipanggil setiap kali daftar reminder suatu habit berubah (baru
  /// ditambah, diedit waktunya/tipenya, atau dihapus). Cara kerja:
  ///   1. Batalkan dulu SEMUA notifikasi/alarm yang sebelumnya terjadwal
  ///      untuk habit ini (berdasarkan `previousTimes` — daftar waktu
  ///      SEBELUM perubahan disimpan).
  ///   2. Jadwalkan ulang dari nol berdasarkan `currentReminders`
  ///      (daftar reminder SETELAH perubahan disimpan).
  ///
  /// Dengan begitu: reminder yang dihapus otomatis hilang jadwalnya,
  /// reminder yang diedit waktunya otomatis pindah ke waktu barunya,
  /// dan reminder baru otomatis langsung terjadwal — semua di saat itu
  /// juga (real-time), tanpa perlu scan ulang habit lain.
  Future<void> rescheduleHabit({
    required String habitId,
    required String habitTitle,
    required List<String> previousTimes,
    required List<ReminderInput> currentReminders,
  }) async {
    // Simpan judul terbaru supaya action handler (DONE/POSTPONED/SNOOZE)
    // bisa menampilkan nama habit yang benar meski dipanggil belakangan.
    rememberHabitTitle(habitId, habitTitle);

    // 1. Bersihkan jadwal lama
    await cancelAllForHabit(habitId, previousTimes);

    // 2. Jadwalkan ulang dari daftar terbaru
    for (final r in currentReminders) {
      // Don't Remind → tidak dijadwalkan sama sekali, sesuai requirement.
      if (r.type == 'none') continue;

      final parts = r.time.split(':');
      final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
      final minute =
          int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final scheduledDate = _nextInstanceOfTime(hour, minute);
      final id = _notifId(habitId, r.time);
      final payload = ReminderPayload(
        habitId: habitId,
        reminderTime: r.time,
        type: r.type,
      ).encode();

      if (r.type == 'notification') {
        await _plugin.zonedSchedule(
          id,
          habitTitle, // Nama habit — ditampilkan di body compact notification
          null,
          scheduledDate,
          _notificationDetails(),
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // ulang tiap hari
        );
      } else if (r.type == 'alarm') {
        await _plugin.zonedSchedule(
          id,
          habitTitle,
          null,
          scheduledDate,
          _alarmDetails(),
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  /// Jadwalkan ulang HANYA satu slot ke waktu baru (dipakai untuk fitur
  /// POSTPONED / SNOOZE, +10 menit dari sekarang). Diisi lengkap di
  /// langkah berikutnya saat action handler dibuat.
  Future<void> rescheduleSingleInMinutes({
    required String habitId,
    required String habitTitle,
    required String reminderTime,
    required String type, // 'notification' | 'alarm'
    required int minutesFromNow,
  }) async {
    final id = _notifId(habitId, reminderTime);
    final target =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutesFromNow));
    final payload = ReminderPayload(
      habitId: habitId,
      reminderTime: reminderTime,
      type: type,
    ).encode();

    await _plugin.zonedSchedule(
      id,
      habitTitle,
      null,
      target,
      type == 'alarm' ? _alarmDetails() : _notificationDetails(),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Tidak pakai matchDateTimeComponents di sini karena ini SEKALI jalan
      // (postpone/snooze 10 menit), bukan pengulangan harian.
    );
  }
}

/// Input ringan untuk satu reminder — sengaja dibuat terpisah dari
/// `ReminderEntry` (yang didefinisikan di main.dart) supaya file ini tidak
/// perlu import main.dart (menghindari circular import). Saat memanggil
/// ReminderService dari main.dart, cukup mapping ReminderEntry → ReminderInput.
class ReminderInput {
  final String time; // format 'HH:mm'
  final String type; // 'none' | 'notification' | 'alarm'
  ReminderInput({required this.time, required this.type});
}