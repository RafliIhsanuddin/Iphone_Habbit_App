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
import 'package:flutter/services.dart' show MethodChannel, PlatformException, SystemNavigator;
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

  // Native channel: plays/stops the phone's actual default alarm sound
  // (RingtoneManager.TYPE_ALARM) on the alarm audio stream, looping, via
  // Android's MediaPlayer. See android/app MainActivity for the handler.
  static const MethodChannel _alarmChannel = MethodChannel('habit_app/alarm');
  final Set<String> _activeAlarmHabitIds = {};

  /// Callback set by main.dart to retrieve the current Postpone Interval
  /// (in minutes) from Settings, so snooze scheduling never hardcodes a
  /// duration.
  static int Function()? getSnoozeMinutes;

  /// Kunci navigator global — di-set dari main.dart (MaterialApp.navigatorKey)
  /// supaya ReminderService bisa melakukan Navigator.push() dari luar widget
  /// tree, misalnya saat notifikasi di-tap ketika app sedang di background.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Callback yang di-set oleh HabitHomePage (atau widget pemilik daftar
  /// habit) supaya ReminderService bisa "memberi tahu" aplikasi untuk
  /// menandai satu habit sebagai DONE hari ini, tanpa ReminderService perlu
  /// tahu struktur internal _HabitHomePageState.
  static void Function(String habitId)? onMarkDone;

  /// Optional callback set by main.dart to persist the current habit list
  /// before the app is moved to the background (e.g. from the Snooze
  /// Page's Snooze/Dismiss actions), so in-memory data survives a possible
  /// OS-initiated process kill while backgrounded.
  static Future<void> Function()? onAppBackgrounding;

  /// Callback opsional untuk membangun halaman Habit (home) dan Snooze page,
  /// di-set dari main.dart. Dipisah dari import langsung supaya file ini
  /// tetap tidak circular-import ke main.dart.
  static Widget Function(BuildContext context)? buildHabitHomeRoute;
  static Widget Function(BuildContext context, String habitId, String habitTitle, String habitCategory, String reminderTime)?
      buildSnoozeRoute;

      /// Tracks which Habit's Snooze Page is currently on top of the
      /// navigation stack (if any), so that when a NEWER alarm's Snooze Page
      /// needs to open, the previous Habit's Snooze Page (which belongs only
      /// to that other Habit) can be removed first instead of stacking
      /// multiple independent Snooze Pages on top of each other.
    static String? _activeSnoozeHabitId;

      /// Exact Route object for the currently open Snooze Page (if any).
      /// Storing the Route itself (rather than just the habitId) lets us
      /// remove precisely that page from the navigation stack — regardless
      /// of its position — instead of assuming it is on top, which was
      /// unsafe whenever a Snooze Page was not actually the topmost route.
    static Route<dynamic>? _activeSnoozeRoute;

      /// Per-habit Snooze Page route tracking, so multiple independent
      /// Snooze Page sessions (one per Habit) can each be reopened by
      /// their own notification tap, independent of whichever Snooze
      /// Page happens to be topmost right now.
    static final Map<String, Route<dynamic>> _snoozeRoutesByHabitId = {};

      /// Ordered list of habitIds whose alarm sound is currently active,
      /// oldest-triggered first, newest-triggered last. Used to determine
      /// which alarm should automatically resume after the currently
      /// playing one is dismissed or snoozed.
    static final List<String> _activeAlarmOrder = [];

      /// SharedPreferences key used to persist the unresolved alarm queue
      /// (same order as _activeAlarmOrder, newest-last) so that Rule 1
      /// (resume the next unresolved Snooze Page on launch) still works
      /// even if the app process was fully killed and _activeAlarmOrder
      /// was reset to empty on this fresh instance.
    static const String _unresolvedQueueKey = 'unresolved_alarm_queue_v1';

      /// Per-habit reminderTime cache for currently-unresolved alarms,
      /// used only to persist enough info to rebuild a Snooze Page after
      /// a cold start.
    static final Map<String, String> _alarmReminderTimeCache = {};

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

    // Rule 1/3/4: when the native side starts an alarm's sound directly
    // (e.g. via the AlarmManager-triggered native path, independent of a
    // notification tap), make sure this habit is also registered in the
    // Dart-side unresolved-alarm queue. Without this, an alarm that fires
    // natively while another alarm is already playing would never be
    // added to _activeAlarmOrder/_activeAlarmHabitIds, so dismissing or
    // snoozing the currently playing alarm could fail to resume this one
    // (or fail to actually stop it), even though its own session was
    // never resolved.
    _alarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'nativeAlarmFired') {
        final args = call.arguments;
        final habitId = args is Map ? args['habitId'] as String? : null;
        if (habitId != null && habitId.isNotEmpty) {
          await playAlarmSound(habitId);
        }
      }
    });

    // Start the continuous alarm sound immediately whenever an Alarm-type
    // notification is presented to the user (foreground/background), not
    // only when the user taps or interacts with it. This reuses the exact
    // same playAlarmSound() implementation (same sound, same looping, same
    // audio player, same volume) already used by SnoozePage and the tap
    // handler above.
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

  /// Handles the case where the app process was not running (or its
  /// Activity had been fully removed from the recent tasks) and the user
  /// tapped a specific Habit's Alarm notification to (re)launch the app.
  /// flutter_local_notifications does NOT automatically replay this tap
  /// through onDidReceiveNotificationResponse — it must be queried
  /// explicitly via getNotificationAppLaunchDetails(). Without this, a
  /// cold-start tap on, e.g., the Painting notification would land on the
  /// default Main Page instead of Painting's own Snooze Page, even though
  /// Painting's alarm session is still fully active. Must be called only
  /// after navigatorKey and buildSnoozeRoute are assigned in main().
  Future<void> consumePendingLaunchNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return;
    final response = details.notificationResponse;
    if (response == null) return;
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;
    final actionId = response.actionId;
    if (actionId == null || actionId.isEmpty) {
      // Guard against a stale/replayed launch Intent from an alarm
      // notification that has already been fully resolved (Snoozed or
      // Dismissed). Only route to that Habit's own Snooze Page if it is
      // still actually present in the unresolved alarm queue.
      if (payload.type == 'alarm' && !_activeAlarmOrder.contains(payload.habitId)) {
        return;
      }
      // Requirement 2: even here, don't necessarily open the tapped
      // habit's own page — if a newer alarm is active, that one must be
      // shown instead. Route through the same newest-resolution used by
      // resumeSnoozePageIfUnresolvedAlarmExists()/_switchSnoozePageToNewestIfNeeded()
      // rather than trusting payload.habitId directly.
      if (payload.type == 'alarm' && _activeAlarmOrder.isNotEmpty) {
        final newestHabitId = _activeAlarmOrder.last;
        final newestReminderTime = _alarmReminderTimeCache[newestHabitId] ?? '';
        _handleBodyTap(ReminderPayload(
          habitId: newestHabitId,
          reminderTime: newestReminderTime,
          type: 'alarm',
        ));
      } else {
        _handleBodyTap(payload);
      }
    } else {
      _onNotificationResponse(response);
    }
  }


  /// Determines, BEFORE runApp() is called, whether this cold start of the
  /// app was caused specifically by the user tapping the body of an active
  /// Alarm notification (not an action button, not a Notification-type
  /// reminder). If so, returns the Widget for that exact Habit's own
  /// Snooze Page so it can be used directly as MaterialApp.home — meaning
  /// the Main Page is never built or shown, not even for a single frame.
  /// Returns null for every other launch case, in which case the caller
  /// should fall back to its normal home widget and rely on
  /// consumePendingLaunchNotification()/_onNotificationResponse() instead.
  Future<Widget?> buildInitialSnoozeRouteIfLaunched() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) {
      return _buildInitialSnoozeRouteFromPersistedQueue();
    }
    final response = details.notificationResponse;
    if (response == null) return _buildInitialSnoozeRouteFromPersistedQueue();
    final actionId = response.actionId;
    if (actionId != null && actionId.isNotEmpty) {
      return _buildInitialSnoozeRouteFromPersistedQueue();
    }
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null || payload.type != 'alarm') {
      return _buildInitialSnoozeRouteFromPersistedQueue();
    }
    // Requirement 2: regardless of WHICH habit's alarm notification was
    // actually tapped to launch the app, the page shown first must
    // always be the newest active alarm's own Snooze Page — never the
    // specific habit named in this particular launch Intent. So instead
    // of building a route for payload.habitId directly, always defer to
    // the persisted unresolved queue, which already resolves to the
    // newest entry. This also naturally handles the stale-launch-Intent
    // guard: if the tapped habit is no longer unresolved, the queue
    // check still correctly falls through (e.g. returns null when the
    // queue is empty, or opens whichever habit is actually newest).
    return _buildInitialSnoozeRouteFromPersistedQueue();
  }

  /// Rule 1 & 2: whenever the app is launched (regardless of whether the
  /// launch itself was caused by tapping a specific alarm notification)
  /// and unresolved alarm sessions still remain, immediately open the
  /// newest unresolved one's own Snooze Page instead of the Main Page.
  /// Reads the persisted unresolved-alarm queue so this still works after
  /// the process was fully killed (in which case _activeAlarmOrder, being
  /// in-memory only, would otherwise be empty on this fresh instance).
  Future<Widget?> _buildInitialSnoozeRouteFromPersistedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_unresolvedQueueKey) ?? [];
    if (queue.isEmpty) return null;
    final builder = buildSnoozeRoute;
    if (builder == null) return null;
    // Newest-last, so the last entry is the next one to resolve (Rule 2).
    final entry = queue.last;
    final parts = entry.split('|');
    final habitId = parts[0];
    final reminderTime = parts.length > 1 ? parts[1] : '';
    _alarmReminderTimeCache[habitId] = reminderTime;
    playAlarmSound(habitId);
    final title = _lastKnownHabitTitle(habitId);
    final category = _lastKnownHabitCategory(habitId);
    _activeSnoozeHabitId = habitId;
    return Builder(
      builder: (ctx) => builder(ctx, habitId, title, category, reminderTime),
    );
  }

  /// Persists the current unresolved alarm queue so Rule 1 can be honored
  /// even after the app process is killed.
  Future<void> _persistUnresolvedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _activeAlarmOrder
        .map((id) => '$id|${_alarmReminderTimeCache[id] ?? ''}')
        .toList();
    await prefs.setStringList(_unresolvedQueueKey, list);
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
  Future<void> _onNotificationResponse(NotificationResponse response) async {
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;

    final actionId = response.actionId;

    // ── Body notifikasi/alarm di-tap langsung (bukan lewat tombol expand) ──
    if (actionId == null || actionId.isEmpty) {
      _handleBodyTap(payload);
      return;
    }

    if (payload.type == 'alarm') {
      // Ensure the continuous alarm sound is already playing (idempotent
      // no-op if already started) regardless of which action button was
      // pressed, since the notification itself may have started it.
      _alarmReminderTimeCache[payload.habitId] = payload.reminderTime;
      playAlarmSound(payload.habitId);
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
        if (payload.type == 'alarm') {
          await stopAlarmSound(payload.habitId);
          await _cancelNativeAlarmSound(payload.habitId);
          // This Habit's own alarm session ends here; only its own
          // Snooze Page tracking (if any) is cleared, and only the
          // newest remaining pending alarm (if any) is resumed.
          clearActiveSnoozeHabitIdIfMatches(payload.habitId);
          await resumeNewestRemainingAlarm();
        }
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
        // Jadwalkan ulang alarm sesuai Postpone Interval dari Settings.
        await stopAlarmSound(payload.habitId);
        await _cancelNativeAlarmSound(payload.habitId);
        final snoozeMinutes = getSnoozeMinutes?.call() ?? 10;
        _plugin.cancel(_notifId(payload.habitId, payload.reminderTime));
        await rescheduleSingleInMinutes(
          habitId: payload.habitId,
          habitTitle: _lastKnownHabitTitle(payload.habitId),
          reminderTime: payload.reminderTime,
          type: 'alarm',
          minutesFromNow: snoozeMinutes,
        );
        _showConfirmationToast('Snooze for $snoozeMinutes ${snoozeMinutes == 1 ? "minute" : "minutes"}');
        // This Habit's own alarm session is now snoozed; only its own
        // Snooze Page tracking (if any) is cleared, and only the newest
        // remaining pending alarm (if any) is resumed — this Habit will
        // re-enter the queue on its own once its snooze timer fires again.
        clearActiveSnoozeHabitIdIfMatches(payload.habitId);
        await resumeNewestRemainingAlarm();
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
      // Start the looping alarm sound immediately, the moment the alarm
      // reminder fires / is interacted with — do not wait for SnoozePage
      // to open. playAlarmSound() is idempotent (safe no-op if already
      // playing for this habit), so this never causes double playback
      // when SnoozePage's own initState also calls it.
      _alarmReminderTimeCache[payload.habitId] = payload.reminderTime;
      playAlarmSound(payload.habitId);
      final builder = buildSnoozeRoute;
      if (builder == null) return;

      // Each Habit owns its own completely independent Snooze Page
      // session (Rule 2). A different Habit's currently open Snooze Page
      // must never be removed, replaced, or otherwise touched here —
      // doing so would destroy that Habit's independent session. Simply
      // proceed to open THIS Habit's own Snooze Page below; any other
      // Habit's Snooze Page (if open) is left completely untouched.

      // Snapshot this Habit's own title AND category together, right
      // before opening its Snooze Page, so the page can never end up
      // rendering a mix of this Habit's title with a stale/other Habit's
      // category or vice versa.
      final thisHabitTitleForRoute = _lastKnownHabitTitle(payload.habitId);
      final thisHabitCategoryForRoute = _lastKnownHabitCategory(payload.habitId);

      final thisHabitId = payload.habitId;
      final thisReminderTimeForRoute = payload.reminderTime;
      _activeSnoozeHabitId = thisHabitId;

      // If THIS habit already has its own tracked Snooze Page route
      // (e.g. it was previously pushed then covered by another habit's
      // alarm), reuse/re-surface that same per-habit tracking slot
      // instead of losing track of it — each habit's own Snooze Page
      // session must remain independently trackable so its own
      // notification can always reopen it.
      late final Route<dynamic> thisRoute;
      thisRoute = PageRouteBuilder(
        settings: RouteSettings(name: 'snooze_page_$thisHabitId'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, animation, secondaryAnimation) => builder(
          ctx,
          thisHabitId,
          thisHabitTitleForRoute,
          thisHabitCategoryForRoute,
          thisReminderTimeForRoute,
        ),
      );
      _activeSnoozeRoute = thisRoute;
      _snoozeRoutesByHabitId[thisHabitId] = thisRoute;
      nav.push(thisRoute).then((_) {
  if (_activeSnoozeHabitId == thisHabitId) {
    _activeSnoozeHabitId = null;
  }
  if (_activeSnoozeRoute == thisRoute) {
    _activeSnoozeRoute = null;
  }
  if (_snoozeRoutesByHabitId[thisHabitId] == thisRoute) {
    _snoozeRoutesByHabitId.remove(thisHabitId);
  }
  // Popping this Habit's page may have revealed an older Habit's own
  // Snooze Page that was still open underneath in the stack. Re-sync
  // tracking to it (without pushing anything new) so a still-unresolved
  // newer alarm can correctly displace it later, instead of leaving
  // tracking stuck at null.
  if (_activeSnoozeHabitId == null && _activeAlarmOrder.isNotEmpty) {
    final revealed = _activeAlarmOrder.last;
    if (_snoozeRoutesByHabitId.containsKey(revealed)) {
      _activeSnoozeHabitId = revealed;
    }
      }
    });
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

  // Per-habit category cache, kept fully independent from
  // _habitTitleCache so one Habit's Snooze Page can never end up
  // displaying another Habit's category.
  final Map<String, String> _habitCategoryCache = {};
  void rememberHabitCategory(String habitId, String category) {
    _habitCategoryCache[habitId] = category;
  }

  String _lastKnownHabitTitle(String habitId) =>
      _habitTitleCache[habitId] ?? '';

  String _lastKnownHabitCategory(String habitId) =>
      _habitCategoryCache[habitId] ?? '';

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
  static Future<void> _onBackgroundNotificationResponse(
      NotificationResponse response) async {
    // Isolate terpisah (app state: terminated) — hanya menulis pending
    // action ke SharedPreferences; UI isolate yang memprosesnya lewat
    // consumePendingBackgroundAction() saat app dibuka kembali.
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;
    if (response.actionId == ReminderActionIds.dismiss ||
        response.actionId == ReminderActionIds.snooze) {
      // Notification sound (category alarm, playSound true) is tied to
      // the notification itself; cancelling it here (dismiss already
      // does via cancelNotification:true) stops the OS-played sound
      // immediately even when the app process was killed.
      final plugin = ReminderService.instance._plugin;
      await plugin.cancel(ReminderService.instance
          ._notifId(payload.habitId, payload.reminderTime));
    }
    if (response.actionId != ReminderActionIds.done) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_mark_done_habit_id', payload.habitId);
  }

  FlutterLocalNotificationsPlugin get rawPlugin => _plugin;

  /// Stops any currently playing alarm sound for the given habit, if any.
  /// Safe to call even if no alarm sound is playing.
  Future<void> stopAlarmSound(String habitId) async {
    final bool wasAudible = _activeAlarmHabitIds.remove(habitId);
    _activeAlarmOrder.remove(habitId);
    await _persistUnresolvedQueue();
    if (!wasAudible) return;
    try {
      await _alarmChannel.invokeMethod('stopAlarm', {'habitId': habitId});
    } on PlatformException catch (e) {
      debugPrint('stopAlarmSound failed for $habitId: $e');
    } catch (e) {
      debugPrint('stopAlarmSound failed for $habitId: $e');
    }
  }

  /// Stops the audible alarm sound for [habitId] WITHOUT removing it from
  /// the pending alarm queue (_activeAlarmOrder). Used only when an alarm
  /// is superseded by a newer alarm taking priority — the superseded
  /// habit's own Snooze Page/notification/alarm state remains fully
  /// intact and eligible to automatically resume later once the newer
  /// alarm(s) are dismissed or snoozed.
  Future<void> _stopAlarmSoundKeepQueued(String habitId) async {
    if (!_activeAlarmHabitIds.remove(habitId)) return;
    try {
      await _alarmChannel.invokeMethod('stopAlarm', {'habitId': habitId});
    } on PlatformException catch (e) {
      debugPrint('stopAlarmSound (keepQueued) failed for $habitId: $e');
    } catch (e) {
      debugPrint('stopAlarmSound (keepQueued) failed for $habitId: $e');
    }
  }

  /// After the currently playing alarm has been stopped (via Dismiss or
  /// Snooze on its own Snooze Page), determine the newest remaining active
  /// Alarm reminder (if any) and resume only that one. Older alarms are
  /// never resumed unless they become the newest remaining active reminder.
  Future<void> resumeNewestRemainingAlarm() async {
    if (_activeAlarmOrder.isEmpty) return;
    final nextHabitId = _activeAlarmOrder.last;
    await playAlarmSound(nextHabitId);
  }


  /// Rule 1 (foreground case): if the app is already running (not a cold
  /// start) and is brought back to the foreground — e.g. via the app
  /// switcher or launcher icon, rather than by tapping the alarm
  /// notification itself — the Main Page must still never be left showing
  /// while unresolved Alarm sessions remain. This checks the in-memory
  /// unresolved alarm queue and, if no Snooze Page is already on screen,
  /// opens the newest unresolved one's own Snooze Page using the exact
  /// same routing already used for a live notification tap.
  Future<void> resumeSnoozePageIfUnresolvedAlarmExists() async {
    if (_activeAlarmOrder.isEmpty) return;
    final habitId = _activeAlarmOrder.last;
    if (_activeSnoozeHabitId == habitId) return;
    final reminderTime = _alarmReminderTimeCache[habitId] ?? '';
    final payload = ReminderPayload(
      habitId: habitId,
      reminderTime: reminderTime,
      type: 'alarm',
    );
    _handleBodyTap(payload);
  }

  /// Starts the looping alarm sound for the given habit, using the phone's
  /// actual default alarm sound (RingtoneManager.TYPE_ALARM) played on the
  /// alarm audio stream via native Android code. If already active for this
  /// habit, this is a safe no-op — it never creates a duplicate playback.
  Future<void> playAlarmSound(String habitId) async {
    if (_activeAlarmHabitIds.contains(habitId)) return;
    // Only one alarm sound may be audible at any time (Rule 1 & 2): the
    // newest triggered alarm owns the audio. Stop any other currently
    // sounding alarm's audio WITHOUT resolving or dequeuing it — it
    // remains an active session and will automatically resume (Rule 3)
    // once this newer alarm is snoozed/dismissed.
    for (final otherId in List<String>.from(_activeAlarmHabitIds)) {
      if (otherId != habitId) {
        await _stopAlarmSoundKeepQueued(otherId);
      }
    }
    _activeAlarmHabitIds.add(habitId);
    _activeAlarmOrder.remove(habitId);
    _activeAlarmOrder.add(habitId);
    await _persistUnresolvedQueue();
    try {
      await _alarmChannel.invokeMethod('playAlarm', {'habitId': habitId});
    } on PlatformException catch (e) {
      debugPrint('playAlarmSound failed for $habitId: $e');
      _activeAlarmHabitIds.remove(habitId);
      _activeAlarmOrder.remove(habitId);
    } catch (e) {
      debugPrint('playAlarmSound failed for $habitId: $e');
      _activeAlarmHabitIds.remove(habitId);
      _activeAlarmOrder.remove(habitId);
    }
    _switchSnoozePageToNewestIfNeeded();
  }

  /// If a Snooze Page is currently visible for a habit that is no longer
  /// the newest active alarm, replace it with the newest active alarm's
  /// own Snooze Page. This ensures the visible Snooze Page always tracks
  /// the most recently activated alarm, switching immediately whenever a
  /// newer reminder becomes active while an older one is still on screen.
  void _switchSnoozePageToNewestIfNeeded() {
    if (_activeAlarmOrder.isEmpty) return;
    final newestHabitId = _activeAlarmOrder.last;
    if (_activeSnoozeHabitId == null) return;
    if (_activeSnoozeHabitId == newestHabitId) return;
    final reminderTime = _alarmReminderTimeCache[newestHabitId] ?? '';
    final payload = ReminderPayload(
      habitId: newestHabitId,
      reminderTime: reminderTime,
      type: 'alarm',
    );
    _handleBodyTap(payload);
  }

  /// Schedules the native alarm sound (same MediaPlayer/RingtoneManager
  /// implementation as playAlarmSound) to start on its own, independent of
  /// any notification-tap callback, at the same moment the alarm reminder
  /// notification is scheduled to appear. This makes the alarm sound begin
  /// as soon as the notification is delivered, even in background/killed
  /// app state, before the Snooze Page is opened. Uses the exact same
  /// native player as playAlarmSound — no duplicate playback implementation.
  Future<void> _scheduleNativeAlarmSound(String habitId, DateTime triggerAt) async {
    try {
      await _alarmChannel.invokeMethod('scheduleNativeAlarmSound', {
        'habitId': habitId,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
      });
    } on PlatformException catch (e) {
      debugPrint('scheduleNativeAlarmSound failed for $habitId: $e');
    } catch (e) {
      debugPrint('scheduleNativeAlarmSound failed for $habitId: $e');
    }
  }

  /// Cancels a pending native alarm-sound trigger scheduled by
  /// _scheduleNativeAlarmSound. Safe no-op if none is pending.
  Future<void> _cancelNativeAlarmSound(String habitId) async {
    try {
      await _alarmChannel.invokeMethod('cancelNativeAlarmSound', {'habitId': habitId});
    } on PlatformException catch (e) {
      debugPrint('cancelNativeAlarmSound failed for $habitId: $e');
    } catch (e) {
      debugPrint('cancelNativeAlarmSound failed for $habitId: $e');
    }
  }

  Future<void> cancelNativeAlarmSoundPublic(String habitId) async {
    await _cancelNativeAlarmSound(habitId);
  }

  /// Public wrapper so SnoozePage (outside this file) can cancel a pending
  /// native alarm-sound trigger using the same private implementation.
  /// Public helper so SnoozePage (outside this file) can clear the
  /// "active Snooze Page" tracking for its own Habit only, when the user
  /// presses Snooze/Dismiss — without touching any other Habit's state.
  static void clearActiveSnoozeHabitIdIfMatches(String habitId) {
    if (_activeSnoozeHabitId == habitId) {
      _activeSnoozeHabitId = null;
      _activeSnoozeRoute = null;
    }
  }

  /// Moves the app to the background (returns to the device home screen)
  /// without terminating the process. Used after Snooze/Dismiss actions on
  /// the Snooze Page.
  Future<void> moveAppToBackground() async {
    try {
      await onAppBackgrounding?.call();
    } on PlatformException catch (e) {
      debugPrint('moveAppToBackground failed: $e');
    } catch (e) {
      debugPrint('moveAppToBackground failed: $e');
    }

    // NOTE: Intentionally do NOT invoke a native 'exitApp' method here.
    // That call was forcing a full native process termination instead of
    // simply moving the task to the background, which wiped all in-memory
    // habit data (habits are only held in memory, not persisted to disk).
    // SystemNavigator.pop alone moves the app to the background/Home
    // Screen while keeping the Dart process (and its in-memory state)
    // alive, so previously saved habits are preserved when reopening.
    SystemNavigator.pop(animated: false);
  }

  /// Shows a native, transient, system-level popup (Android Toast / closest
  /// native equivalent) confirming the snooze action. This is NOT an in-app
  /// dialog, NOT a Flutter overlay, and does NOT remain inside the app —
  /// it is shown via the same native MethodChannel already used for the
  /// alarm sound, so it appears even after the app has moved to the
  /// background / device home screen is shown.
  Future<void> showSnoozeConfirmationNotification(int minutes) async {
    final message = 'Snooze for $minutes ${minutes == 1 ? "minute" : "minutes"}';
    try {
      await _alarmChannel.invokeMethod('showSnoozeToast', {'message': message});
    } on PlatformException catch (e) {
      debugPrint('showSnoozeToast failed: $e');
    } catch (e) {
      debugPrint('showSnoozeToast failed: $e');
    }
  }

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
      // Do not use the platform's own (short, non-looping) notification
      // sound for alarms: ReminderService.playAlarmSound() provides a
      // continuous, looping alarm sound instead. Playing both would result
      // in only the short default sound being audible, which is the bug
      // this change fixes.
      playSound: false,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      // Rule 1: an Alarm notification must not be removable by a manual
      // swipe (left, right, or otherwise). ongoing:true already blocks
      // this on Android; explicitly setting onlyAlertOnce false + leaving
      // autoCancel/ongoing as-is is intentional — no swipe-to-dismiss
      // path is enabled for this channel.
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
  

  /// Notification details used ONLY when re-scheduling an Alarm reminder
  /// after a Snooze (Rule 2–4). Unlike _alarmDetails() (used for the very
  /// first alarm trigger, Rule 1, which must keep auto-opening the Snooze
  /// Page via fullScreenIntent), this variant must NOT auto-launch the
  /// Snooze Page when the snooze timer expires. It only shows a regular,
  /// tappable notification; the Snooze Page is opened later, only when the
  /// user taps it, via the existing _handleBodyTap() routing.
  NotificationDetails _alarmSnoozeDetails() {
    const androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      'Habit Alarms',
      channelDescription: 'Alarms for your habits',
      importance: Importance.max,
      priority: Priority.high,
      // No full-screen intent here: this must never automatically open
      // the Snooze Page when the snooze timer expires (Rule 3). It must
      // behave like a normal notification the user taps.
      fullScreenIntent: false,
      category: AndroidNotificationCategory.alarm,
      playSound: false,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
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



  /// misalnya kalau habit dihapus seluruhnya).
  Future<void> cancelReminderSlot(String habitId, String time) async {
    await _plugin.cancel(_notifId(habitId, time));
  }

  /// Batalkan SEMUA slot reminder milik satu habit (dipanggil saat habit
  /// dihapus, atau sebelum reschedule penuh). Only this habitId's own
  /// notification ids are touched — every other habit's scheduled
  /// notifications/alarms remain completely untouched.
  Future<void> cancelAllForHabit(String habitId, List<String> times) async {
    for (final t in times) {
      await cancelReminderSlot(habitId, t);
      // Each reminder slot may also have its own pending native alarm
      // sound trigger (scheduled via AlarmManager, independent of the
      // flutter_local_notifications notification). Cancel that too so a
      // deleted habit's alarm sound can never fire after the habit and
      // its notification are gone. This only cancels the PendingIntent
      // registered under this exact habitId — it cannot affect any
      // other habit's own pending alarm trigger.
      await _cancelNativeAlarmSound(habitId);
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
    required String habitCategory,
    required List<String> previousTimes,
    required List<ReminderInput> currentReminders,
  }) async {
    // Simpan judul terbaru supaya action handler (DONE/POSTPONED/SNOOZE)
    // bisa menampilkan nama habit yang benar meski dipanggil belakangan.
    rememberHabitTitle(habitId, habitTitle);
    rememberHabitCategory(habitId, habitCategory);

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
        _alarmReminderTimeCache[habitId] = r.time;   // ADD THIS LINE
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
        await _scheduleNativeAlarmSound(habitId, scheduledDate);
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
    final target =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutesFromNow));
    // For Alarm reminders, the scheduled trigger time changes on every
    // snooze; the notification id and payload must reflect this new
    // current scheduled time so the notification bar, the Snooze Page,
    // and the next scheduled alarm all stay synchronized (Alarm only —
    // Notification reminders keep using the original reminderTime).
    final effectiveTime = type == 'alarm'
    ? '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}'
    : reminderTime;
    final id = _notifId(habitId, effectiveTime);
    rememberHabitTitle(habitId, habitTitle);
    if (type == 'alarm') {
      _alarmReminderTimeCache[habitId] = effectiveTime;   // ADD THIS LINE
    }
    final payload = ReminderPayload(
      habitId: habitId,
      reminderTime: effectiveTime,
      type: type,
    ).encode();

    await _plugin.zonedSchedule(
      id,
      habitTitle,
      null,
      target,
      type == 'alarm' ? _alarmSnoozeDetails() : _notificationDetails(),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Tidak pakai matchDateTimeComponents di sini karena ini SEKALI jalan
      // (postpone/snooze 10 menit), bukan pengulangan harian.
    );
    if (type == 'alarm') {
      await _scheduleNativeAlarmSound(habitId, target);
    }
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