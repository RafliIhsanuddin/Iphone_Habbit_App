import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'reminder_service.dart';
import 'snooze_page.dart';
import 'dart:convert';

// ─────────────────────────────────────────────────────────────
// No-animation route used specifically for opening the Edit screen
// from the Main Page (via long-press sheet / swipe / card menu).
// Ensures that when Back is pressed from the Edit page, the Main
// Page (including its bottom navigation / FAB) reappears instantly
// in its final state, with no slide/fade transition of any kind.
// ─────────────────────────────────────────────────────────────
Route<T> _noAnimationEditRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

class PostponeIntervalStore {
  static const _key = 'postpone_interval_minutes';
  static int _cache = 10;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = prefs.getInt(_key) ?? 10;
  }

  static int get minutes => _cache;

  static Future<void> setMinutes(int value) async {
    _cache = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value);
  }
}

// ─── Category Persistence ─────────────────────────────────────────────────────

class CategoryStore {
  static const _key = 'custom_categories';
  static List<String> _cache = [];

  /// Must be called once before runApp().
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = prefs.getStringList(_key) ?? [];
  }

  /// Synchronous snapshot of stored custom categories.
  static List<String> get custom => List<String>.from(_cache);

  static bool exists(String name) {
    final n = name.trim().toLowerCase();
    return _cache.any((c) => c.trim().toLowerCase() == n);
  }

  /// Adds + persists. No-op on empty or duplicate (case-insensitive).
  static Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || exists(trimmed)) return;
    _cache = [..._cache, trimmed];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _cache);
  }

  static Future<void> rename(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final oldLower = oldName.trim().toLowerCase();
    final idx = _cache.indexWhere((c) => c.trim().toLowerCase() == oldLower);
    if (idx == -1) return;
    final newLower = trimmed.toLowerCase();
    for (int i = 0; i < _cache.length; i++) {
      if (i != idx && _cache[i].trim().toLowerCase() == newLower) return;
    }
    final updated = List<String>.from(_cache);
    updated[idx] = trimmed;
    _cache = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _cache);
  }

  /// Removes + persists (case-insensitive). Same _key, same prefs list.
  static Future<void> remove(String name) async {
    final lower = name.trim().toLowerCase();
    final before = _cache.length;
    _cache = _cache.where((c) => c.trim().toLowerCase() != lower).toList();
    if (_cache.length == before) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _cache);
  }

}
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();


void deleteHabitEverywhere(List<Habit> allHabits, String habitId) {
  final idx = allHabits.indexWhere((h) => h.id == habitId);
  if (idx == -1) return;
  final target = allHabits[idx];
  ReminderService.instance.cancelAllForHabit(
    target.id,
    target.reminders.map((r) => r.time).toList(),
  );
  allHabits.removeWhere((h) => h.id == habitId);
}

final List<Habit> _rootHabits = [];

extension HabitJsonCodec on Habit {
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'description': description,
        'priority': priority,
        'reminders': reminders
            .map((r) => {
                  'time': r.time,
                  'type': r.type,
                  'schedule': r.schedule,
                  'weekDays': r.weekDays.toList(),
                  'daysBefore': r.daysBefore,
                })
            .toList(),
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'isArchived': isArchived,
        'archivedAt': archivedAt?.toIso8601String(),
        'frequency': frequency,
        'dailyState': dailyState.map((k, v) => MapEntry(k, v.index)),
        'dailyNote': dailyNote,
        'freqWeekDays': freqWeekDays,
        'freqMonthDays': freqMonthDays.toList(),
        'freqYearDays': freqYearDays.map((d) => d.toIso8601String()).toList(),
        'freqPeriodDays': freqPeriodDays,
        'freqPeriodUnit': freqPeriodUnit,
        'freqRepeatEvery': freqRepeatEvery,
        'freqFlexible': freqFlexible,
      };

  static Habit fromJson(Map<String, dynamic> j) {
    final h = Habit(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      category: j['category'] as String? ?? '',
      description: j['description'] as String? ?? '',
      priority: j['priority'] as int? ?? 1,
      reminders: ((j['reminders'] as List?) ?? [])
          .map((r) => ReminderEntry(
                time: r['time'] as String? ?? '12:00',
                type: r['type'] as String? ?? 'notification',
                schedule: r['schedule'] as String? ?? 'always',
                weekDays: Set<String>.from(r['weekDays'] ?? const []),
                daysBefore: r['daysBefore'] as int? ?? 1,
              ))
          .toList(),
      startDate: DateTime.tryParse(j['startDate'] as String? ?? '') ?? DateTime.now(),
      endDate: j['endDate'] != null ? DateTime.tryParse(j['endDate'] as String) : null,
      isArchived: j['isArchived'] as bool? ?? false,
      archivedAt: j['archivedAt'] != null ? DateTime.tryParse(j['archivedAt'] as String) : null,
      frequency: j['frequency'] as String? ?? 'EVERY DAY',
      freqWeekDays: (j['freqWeekDays'] as Map?)?.map((k, v) => MapEntry(k as String, v as bool)),
      freqMonthDays: Set<int>.from(j['freqMonthDays'] ?? const []),
      freqYearDays: ((j['freqYearDays'] as List?) ?? [])
          .map((d) => DateTime.tryParse(d as String) ?? DateTime.now())
          .toList(),
      freqPeriodDays: j['freqPeriodDays'] as int? ?? 1,
      freqPeriodUnit: j['freqPeriodUnit'] as String? ?? 'WEEK',
      freqRepeatEvery: j['freqRepeatEvery'] as int? ?? 1,
      freqFlexible: j['freqFlexible'] as bool? ?? false,
    );
    final ds = (j['dailyState'] as Map?) ?? {};
    ds.forEach((k, v) => h.dailyState[k as String] = HabitState.values[v as int]);
    final dn = (j['dailyNote'] as Map?) ?? {};
    dn.forEach((k, v) => h.dailyNote[k as String] = v as String);
    return h;
  }
}

class HabitStore {
  static const _key = 'saved_habits_v1';

  static Future<void> save(List<Habit> habits) async {
    final prefs = await SharedPreferences.getInstance();
    final list = habits.map((h) => h.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<List<Habit>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HabitJsonCodec.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

void main() async {
  List<Habit> _snoozeLookupHabits = [];
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await CategoryStore.init();
  await PostponeIntervalStore.init();

  _rootHabits.addAll(await HabitStore.load());
  ReminderService.onAppBackgrounding = () => HabitStore.save(_rootHabits);

  await ReminderService.instance.init();
  await ReminderService.instance.requestPermissions();
  ReminderService.navigatorKey = appNavigatorKey;
  ReminderService.getSnoozeMinutes = () => PostponeIntervalStore.minutes;
  ReminderService.buildSnoozeRoute = (ctx, habitId, habitTitle) {
    final match = _rootHabits.where((h) => h.id == habitId);
    final category = match.isNotEmpty ? match.first.category : '';
    final title = match.isNotEmpty ? match.first.title : habitTitle;
    return SnoozePage(habitId: habitId, habitTitle: title, habitCategory: category);
  };

  runApp(HabitApp(webPreviewSnooze: kIsWeb));
}

class HabitApp extends StatelessWidget {
  const HabitApp({super.key, this.webPreviewSnooze = false});
  final bool webPreviewSnooze;
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'Habits',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Colors.black),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
         builder: (context, child) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 402.0,
              height: 874.0,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: const Size(402.0, 874.0)),
                child: child!,
              ),
            ),
          );
        },
        home: HabitHomePage(habits: _rootHabits),
      );
}

class ReminderEntry {
  String time, type, schedule;
  Set<String> weekDays;
  int daysBefore;
  ReminderEntry({this.time = '12:00', this.type = 'notification', this.schedule = 'always', Set<String>? weekDays, this.daysBefore = 1}) : weekDays = weekDays ?? {};
}

enum HabitState { empty, done, failed, skipped }

class Habit {
  final String id;
  String title, category, description;
  String frequency;
  int priority;
  List<ReminderEntry> reminders;
  DateTime startDate;
  DateTime? endDate;
  bool isArchived;
  DateTime? archivedAt;
  final Map<String, HabitState> dailyState = {};
  final Map<String, String> dailyNote = {};
  Map<String,bool> freqWeekDays;
  Set<int> freqMonthDays;
  List<DateTime> freqYearDays;
  int freqPeriodDays;
  String freqPeriodUnit;
  int freqRepeatEvery;
  bool freqFlexible;

  Habit({required this.id, required this.title, this.category = '', this.description = '', this.priority = 1, List<ReminderEntry>? reminders, required this.startDate, this.endDate, this.isArchived = false, this.archivedAt, this.frequency = 'EVERY DAY', Map<String,bool>? freqWeekDays, Set<int>? freqMonthDays, List<DateTime>? freqYearDays, this.freqPeriodDays = 1, this.freqPeriodUnit = 'WEEK', this.freqRepeatEvery = 1, this.freqFlexible = false})
      : reminders = reminders ?? [],
        freqWeekDays = freqWeekDays ?? {'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false},
        freqMonthDays = freqMonthDays ?? {},
        freqYearDays = freqYearDays ?? [];

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) return false;
    if (endDate != null && d.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day))) return false;
    // If archived: days strictly after archivedAt are not active.
    // The day of archiving itself remains active (history is preserved).
    if (isArchived && archivedAt != null) {
      final archiveDay = DateTime(archivedAt!.year, archivedAt!.month, archivedAt!.day);
      if (d.isAfter(archiveDay)) return false;
    }
    return true;
  }

  HabitState stateOn(DateTime day) => dailyState[_key(day)] ?? HabitState.empty;
  void setStateOn(DateTime day, HabitState s) => dailyState[_key(day)] = s;
  String noteOn(DateTime day) => dailyNote[_key(day)] ?? '';
  void setNoteOn(DateTime day, String n) => dailyNote[_key(day)] = n;
}

class HabitScheduleResult {
  final String title, description, category, startDate, frequency, endDate;
  final int priority;
  final List<ReminderEntry> reminders;
  final Map<String,bool> freqWeekDays;
  final Set<int> freqMonthDays;
  final List<DateTime> freqYearDays;
  final int freqPeriodDays;
  final String freqPeriodUnit;
  final int freqRepeatEvery;
  final bool freqFlexible;
  HabitScheduleResult({required this.title, required this.description, required this.category, required this.startDate, required this.frequency, required this.endDate, required this.priority, required this.reminders, Map<String,bool>? freqWeekDays, Set<int>? freqMonthDays, List<DateTime>? freqYearDays, this.freqPeriodDays=1, this.freqPeriodUnit='WEEK', this.freqRepeatEvery=1, this.freqFlexible=false})
      : freqWeekDays = freqWeekDays ?? {'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false},
        freqMonthDays = freqMonthDays ?? {},
        freqYearDays = freqYearDays ?? [];
}

// ─── Clock Hands Painter ──────────────────────────────────────────────────────

class _ClockHandsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    final handPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = radius * 0.38
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final minuteAngle = -math.pi / 2;
    final minuteLen = radius * 0.55;
    canvas.drawLine(
      center,
      Offset(center.dx + minuteLen * math.cos(minuteAngle), center.dy + minuteLen * math.sin(minuteAngle)),
      handPaint,
    );
    final hourAngle = math.pi / 6;
    final hourLen = radius * 0.38;
    canvas.drawLine(
      center,
      Offset(center.dx + hourLen * math.cos(hourAngle), center.dy + hourLen * math.sin(hourAngle)),
      handPaint,
    );
  }
  @override
  bool shouldRepaint(_ClockHandsPainter o) => false;
}

// ─── Bold Status Icon Painters ────────────────────────────────────────────────

class _BoldCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.54)
      ..lineTo(size.width * 0.42, size.height * 0.68)
      ..lineTo(size.width * 0.76, size.height * 0.32);
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(_BoldCheckPainter o) => false;
}

class _BoldCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.35),
      Offset(size.width * 0.65, size.height * 0.65),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, size.height * 0.35),
      Offset(size.width * 0.35, size.height * 0.65),
      paint,
    );
  }
  @override bool shouldRepaint(_BoldCrossPainter o) => false;
}

class _WhiteCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.35),
      Offset(size.width * 0.65, size.height * 0.65),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, size.height * 0.35),
      Offset(size.width * 0.35, size.height * 0.65),
      paint,
    );
  }
  @override bool shouldRepaint(_WhiteCrossPainter o) => false;
}

class _CalCheckPainter extends CustomPainter {
  final Color color;
  const _CalCheckPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.52)
      ..lineTo(size.width * 0.38, size.height * 0.80)
      ..lineTo(size.width * 0.90, size.height * 0.18);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(_CalCheckPainter o) => o.color != color;
}

class _CalCrossPainter extends CustomPainter {
  final Color color;
  const _CalCrossPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.15),
      Offset(size.width * 0.85, size.height * 0.85),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.85, size.height * 0.15),
      Offset(size.width * 0.15, size.height * 0.85),
      paint,
    );
  }
  @override
  bool shouldRepaint(_CalCrossPainter o) => o.color != color;
}

class _BoldMinusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.28, size.height * 0.50),
      Offset(size.width * 0.70, size.height * 0.50),
      paint,
    );
  }
  @override bool shouldRepaint(_BoldMinusPainter o) => false;
}


// ─── Mini status indicators (above date number, never overlapping) ────────────

class _MiniCheck extends StatelessWidget {
  final Color color;
  const _MiniCheck({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(10, 8),
      painter: _MiniCheckPainter(color),
    );
  }
}

class _MiniCheckPainter extends CustomPainter {
  final Color color;
  _MiniCheckPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.52)
      ..lineTo(size.width * 0.38, size.height * 0.80)
      ..lineTo(size.width * 0.88, size.height * 0.18);
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(_MiniCheckPainter o) => o.color != color;
}

class _MiniCross extends StatelessWidget {
  final Color color;
  const _MiniCross({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 8),
      painter: _MiniCrossPainter(color),
    );
  }
}


class _MiniCrossPainter extends CustomPainter {
  final Color color;
  _MiniCrossPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.15),
      Offset(size.width * 0.85, size.height * 0.85),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.85, size.height * 0.15),
      Offset(size.width * 0.15, size.height * 0.85),
      paint,
    );
  }
  @override bool shouldRepaint(_MiniCrossPainter o) => o.color != color;
}


// ─── Shared Scheduling Logic (single source of truth) ────────────────────────
bool _habitIsScheduledOn(Habit h, DateTime day) {
  if (!h.isActiveOn(day)) return false;
  final f = h.frequency;
  if (f == 'EVERY DAY' || f.isEmpty) return true;
  if (f == 'SPECIFIC DAYS OF THE WEEK') {
    const names = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY'];
    return h.freqWeekDays[names[day.weekday - 1]] == true;
  }
  if (f == 'SPECIFIC DAYS OF THE MONTH') {
    if (h.freqMonthDays.isNotEmpty && h.freqFlexible) {
      final lastDayOfMonth = DateTime(day.year, day.month + 1, 0).day;
      final boundaries = h.freqMonthDays
          .map((d) => d == 0 ? lastDayOfMonth : d)
          .toList()
        ..sort();
      final currentDay = day.day;
      if (currentDay < boundaries.first) return false;
      int intervalStart = boundaries.first;
      int intervalEnd = lastDayOfMonth + 1;
      for (int i = 0; i < boundaries.length; i++) {
        if (boundaries[i] <= currentDay) {
          intervalStart = boundaries[i];
          intervalEnd = (i + 1 < boundaries.length) ? boundaries[i + 1] : lastDayOfMonth + 1;
        }
      }
      for (int d = intervalStart; d < currentDay; d++) {
        final checkDay = DateTime(day.year, day.month, d);
        if (h.stateOn(checkDay) == HabitState.done) return false;
      }
      return true;
    }
    if (h.freqMonthDays.contains(day.day)) return true;
    if (h.freqMonthDays.contains(0)) {
      final lastDay = DateTime(day.year, day.month + 1, 0).day;
      if (day.day == lastDay) return true;
    }
    return false;
  }
  if (f == 'SPECIFIC DAYS OF THE YEAR') {
    return h.freqYearDays.any((d) => d.month == day.month && d.day == day.day);
  }
  if (f == 'SOME DAYS PER PERIOD') {
    DateTime periodStart, periodEnd;
    if (h.freqPeriodUnit == 'WEEK') {
      periodStart = day.subtract(Duration(days: day.weekday - 1));
      periodEnd = periodStart.add(const Duration(days: 6));
    } else if (h.freqPeriodUnit == 'MONTH') {
      periodStart = DateTime(day.year, day.month, 1);
      periodEnd = DateTime(day.year, day.month + 1, 0);
    } else {
      periodStart = DateTime(day.year, 1, 1);
      periodEnd = DateTime(day.year, 12, 31);
    }
    int completed = 0;
    for (DateTime d = periodStart; !d.isAfter(periodEnd); d = d.add(const Duration(days: 1))) {
      if (h.stateOn(d) == HabitState.done) completed++;
    }
    if (completed >= h.freqPeriodDays) {
      return h.stateOn(day) == HabitState.done;
    }
    return true;
  }
  if (f == 'REPEAT') {
    if (h.freqFlexible) {
      final start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
      final target = DateTime(day.year, day.month, day.day);
      if (target.isBefore(start)) return false;
      DateTime? lastDone;
      for (DateTime d = start; !d.isAfter(target); d = d.add(const Duration(days: 1))) {
        if (h.stateOn(d) == HabitState.done) lastDone = d;
      }
      if (lastDone == null) return true;
      final cooldownEnd = lastDone.add(Duration(days: h.freqRepeatEvery));
      if (target.isBefore(cooldownEnd)) return false;
      return true;
    } else {
      final start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
      final target = DateTime(day.year, day.month, day.day);
      if (target.isBefore(start)) return false;
      final diff = target.difference(start).inDays;
      return diff % h.freqRepeatEvery == 0;
    }
  }
  return true;
}


// ─── Calendar Page ────────────────────────────────────────────────────────────

class HabitCalendarPage extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  const HabitCalendarPage({super.key, required this.habit, required this.allHabits});
  @override State<HabitCalendarPage> createState() => _HabitCalendarPageState();
}

class _HabitCalendarPageState extends State<HabitCalendarPage> {
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month, 1);
  }

  void _prevMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1));
  void _nextMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1));

  // Reuses the exact same scheduling logic as HabitsScreen._isScheduledOn
  // so calendar indicators match the main habit page exactly.
  bool _isScheduledOn(DateTime day) => _habitIsScheduledOn(widget.habit, day);

  static const _monthNames = [
    'JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE',
    'JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'
  ];
  static const _weekLabels = ['SUN','MON','TUE','WED','THU','FRI','SAT'];

  // Days in month
  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  // Weekday of first day (0=Sun,1=Mon,...6=Sat)
  int _firstWeekday(int year, int month) {
    final d = DateTime(year, month, 1);
    return d.weekday % 7; // dart: Mon=1..Sun=7 → Sun=0
  }

  // Streak: consecutive days completed up to today
  int _calcStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(widget.habit.startDate.year, widget.habit.startDate.month, widget.habit.startDate.day);

    final List<DateTime> occurrences = [];
    for (DateTime d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (_isScheduledOn(d)) occurrences.add(d);
    }

    int streak = 0;
    for (int i = occurrences.length - 1; i >= 0; i--) {
      final state = widget.habit.stateOn(occurrences[i]);
      if (state == HabitState.done) {
        streak++;
      } else if (state == HabitState.empty) {
        if (streak == 0) continue;
        break;
      } else {
        break;
      }
    }
    return streak;
  }

  Widget _buildCalendarGrid() {
    final year = _displayMonth.year;
    final month = _displayMonth.month;
    final daysInMonth = _daysInMonth(year, month);
    final firstWd = _firstWeekday(year, month);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build cells: leading blanks + days
    final totalCells = firstWd + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - firstWd + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox(width: 40, height: 64);
              }

              final date = DateTime(year, month, dayNum);
              final state = widget.habit.stateOn(date);
              final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
              final isFuture = date.isAfter(today);
              final isDone = state == HabitState.done;
              final isFail = state == HabitState.failed;
              final isScheduled = _isScheduledOn(date);

              // ─────────────────────────────────────────────────────────────
              // SIX CALENDAR STATES — strictly black & white, date always visible
              //
              // Layout per cell (top → bottom, 58px total):
              //   [16px]  indicator strip  — symbol ABOVE the circle
              //   [38px]  date circle      — number always fully readable
              //   [ 4px]  bottom gap
              // ─────────────────────────────────────────────────────────────

              Color bgFill = Colors.transparent;
              Border? bgBorder;
              Color numberColor = Colors.white;
              FontWeight numberWeight = FontWeight.w400;
              Widget? indicator;

              // ─── SIX STATES — black & white only, date always unobstructed ───
              //
              // Layout per cell (64px total height):
              //   [14px]  icon strip  — check/cross/dot ABOVE the circle, never overlapping
              //   [40px]  date circle — number always fully visible
              //   [10px]  bottom gap
              //
              // State matrix:
              //   Non-scheduled            → dimmed number, no circle, no icon
              //   Pending (past, not today)→ outlined circle (white border), normal number
              //   Done (past, not today)   → solid WHITE filled circle, black number, white check above
              //   Fail (past, not today)   → solid BLACK filled circle, white number, white cross above
              //   Pending Today            → double-ring circle (outer ring gap), white number
              //   Done Today               → solid WHITE filled circle + outer ring, black number, white check above
              //   Fail Today               → solid BLACK filled circle + outer ring, white number, white cross above

              Widget? iconAbove;        // rendered in the 14px strip above the circle
              Color   circleFill   = Colors.transparent;
              Border? circleBorder;     // border ON the main 40px circle
              bool    hasOuterRing = false; // extra ring drawn around the circle (today marker)
              Color   numColor     = Colors.white;
              FontWeight numWeight = FontWeight.w400;

              if (!isScheduled) {
                // ── Non-scheduled: visible but clearly dimmed, zero decoration ──
                numColor  = isFuture ? Colors.white24 : Colors.white30;
                numWeight = FontWeight.w400;

              } else if (!isToday) {
                // ── Scheduled, past or future (not today) ──
                if (isDone) {
                  // DONE — solid white circle, black number, bright white check above
                  circleFill  = Colors.white;
                  numColor    = Colors.black;
                  numWeight   = FontWeight.w800;
                  iconAbove   = CustomPaint(
                    size: const Size(13, 11),
                    painter: _CalCheckPainter(Colors.white),
                  );
                } else if (isFail) {
                  // FAIL — solid black circle, white number, bright white cross above
                  circleFill  = Colors.black;
                  circleBorder = Border.all(color: Colors.white, width: 1.5);
                  numColor    = Colors.white;
                  numWeight   = FontWeight.w800;
                  iconAbove   = CustomPaint(
                    size: const Size(12, 12),
                    painter: _CalCrossPainter(Colors.white),
                  );
                } else {
                  // PENDING — outlined circle only, no icon
                  circleFill   = Colors.transparent;
                  circleBorder = Border.all(color: Colors.white54, width: 1.5);
                  numColor     = Colors.white70;
                  numWeight    = FontWeight.w500;
                }

              } else {
                // ── Today (scheduled) — gray filled circle, black number ──
                hasOuterRing = false;
                if (isDone) {
                  // DONE TODAY — gray fill, black number, white check above
                  circleFill  = const Color(0xFFB8B8B8);
                  circleBorder = null;
                  numColor    = Colors.black;
                  numWeight   = FontWeight.w900;
                  iconAbove   = CustomPaint(
                    size: const Size(12, 10),
                    painter: _CalCheckPainter(Colors.white),
                  );
                } else if (isFail) {
                  // FAIL TODAY — gray fill, black number, white cross above
                  circleFill   = const Color(0xFFB8B8B8);
                  circleBorder = null;
                  numColor     = Colors.black;
                  numWeight    = FontWeight.w900;
                  iconAbove    = CustomPaint(
                    size: const Size(10, 10),
                    painter: _CalCrossPainter(Colors.white),
                  );
                } else {
                  // PENDING TODAY — gray fill, black number, no icon
                  circleFill   = const Color(0xFFB8B8B8);
                  circleBorder = null;
                  numColor     = Colors.black;
                  numWeight    = FontWeight.w900;
                }
              }

              // ── Build the 40×40 date circle ──
              final Widget dateCircle = Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: circleFill,
                  border: circleBorder,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    color: numColor,
                    fontSize: 15,
                    fontWeight: numWeight,
                    height: 1,
                  ),
                ),
              );

              // ── Wrap with outer ring for today states ──
              final Widget dateWidget = hasOuterRing
                  ? Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 2,
                        ),
                      ),
                      child: Center(child: dateCircle),
                    )
                  : dateCircle;

              // ── Assemble the full cell (icon strip + circle + gap) ──
              final cellContent = SizedBox(
                width: hasOuterRing ? 46 : 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 14,
                      child: Center(
                        child: iconAbove ?? const SizedBox.shrink(),
                      ),
                    ),
                    dateWidget,
                    const SizedBox(height: 10),
                  ],
                ),
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  if (date.isAfter(today)) return;
                  if (!isScheduled) return;
                  setState(() {
                    final cur = widget.habit.stateOn(date);
                    if (cur == HabitState.skipped) {
                      widget.habit.setStateOn(date, HabitState.empty);
                    } else {
                      widget.habit.setStateOn(
                        date,
                        cur == HabitState.empty
                            ? HabitState.done
                            : cur == HabitState.done
                                ? HabitState.failed
                                : HabitState.empty,
                      );
                    }
                  });
                },
                child: SizedBox(width: 40, child: Center(child: cellContent)),
              );
            }),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streak = _calcStreak();
    final desc = widget.habit.description;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.habit.title.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ── CALENDAR / EDIT Toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(10)),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // CALENDAR — selected
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: const Center(
                            child: Text('CALENDAR', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ),
                        ),
                      ),
                      // EDIT — navigate to edit screen
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditHabitScreen(
                                  habit: widget.habit,
                                  allHabits: widget.allHabits,
                                  onDelete: () => deleteHabitEverywhere(widget.allHabits, widget.habit.id),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
                            child: const Center(
                              child: Text('EDIT', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Calendar Card ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        children: [
                          // Month/Year + arrows
                          Row(
                            children: [
                              Text(
                                '${_monthNames[_displayMonth.month - 1]} ${_displayMonth.year}',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _prevMonth,
                                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_left, color: Colors.white, size: 22)),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _nextMonth,
                                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_right, color: Colors.white, size: 22)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Weekday labels
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: _weekLabels.map((l) => SizedBox(
                              width: 40,
                              child: Center(
                                child: Text(l, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 4),
                          // Calendar grid
                          _buildCalendarGrid(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // ── Streak ──
                    const Center(
                      child: Text('STREAK', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '$streak ${streak == 1 ? 'DAY' : 'DAYS'}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // ── Description ──
                    const Center(
                      child: Text('DESCRIPTION', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        desc.isNotEmpty ? desc.toUpperCase() : '—',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}


// ─── Priority Modal ───────────────────────────────────────────────────────────

class _PriorityModal extends StatefulWidget {
  final int priority;
  final void Function(int) onChanged;
  const _PriorityModal({required this.priority, required this.onChanged});
  @override State<_PriorityModal> createState() => _PriorityModalState();
}
class _PriorityModalState extends State<_PriorityModal> {
  late int _val;
  @override void initState() { super.initState(); _val = widget.priority; }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('SET A PRIORITY', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
          Container(height: 0.5, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20,20,20,12),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24, width: 1.5)),
              child: IntrinsicHeight(child: Row(children: [
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() { if (_val > 1) _val--; }),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF888888), shape: BoxShape.circle), child: const Icon(Icons.remove, color: Colors.white, size: 20)))))),
                Container(width: 1.5, color: Colors.white24),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('$_val', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800))))),
                Container(width: 1.5, color: Colors.white24),
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _val++),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF888888), shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 20)))))),
              ])),
            ),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF888888), borderRadius: BorderRadius.circular(20)), child: const Text('DEFAULT = 1 🏳', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
          Container(height: 0.5, color: Colors.white24),
          IntrinsicHeight(child:Row(children:[
            Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:(){Navigator.pop(context);},child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:16),child:const Center(child:Text('CLOSE',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
            Container(width:0.5,color:Colors.white24),
            Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:(){widget.onChanged(_val);Navigator.pop(context);},child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:16),child:const Center(child:Text('OK',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
          ])),
        ]),
      ),
    );
  }
}

// ─── Time Picker Dialog ───────────────────────────────────────────────────────

class _TimePickerDialog extends StatefulWidget {
  final int initialHour, initialMinute;
  final void Function(int, int) onConfirm;
  const _TimePickerDialog({required this.initialHour, required this.initialMinute, required this.onConfirm});
  @override State<_TimePickerDialog> createState() => _TimePickerDialogState();
}
class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int _hour, _minute;
  late TextEditingController _hCtrl, _mCtrl;
  @override
  void initState() {
    super.initState();
    _hour = widget.initialHour; _minute = widget.initialMinute;
    _hCtrl = TextEditingController(text: _hour.toString().padLeft(2,'0'));
    _mCtrl = TextEditingController(text: _minute.toString().padLeft(2,'0'));
  }
  @override void dispose() { _hCtrl.dispose(); _mCtrl.dispose(); super.dispose(); }

  void _setHour(int h) { _hour = h.clamp(0,23); _hCtrl.text = _hour.toString().padLeft(2,'0'); _hCtrl.selection = TextSelection.collapsed(offset: _hCtrl.text.length); }
  void _setMinute(int m) { _minute = ((m%60)+60)%60; _mCtrl.text = _minute.toString().padLeft(2,'0'); _mCtrl.selection = TextSelection.collapsed(offset: _mCtrl.text.length); }

  void _onHourChanged(String v) {
    final d = v.replaceAll(RegExp(r'[^0-9]'),'');
    if (d.isEmpty) { _hCtrl.value = const TextEditingValue(text:'',selection:TextSelection.collapsed(offset:0)); return; }
    if (d.length == 1) { setState(()=>_hour=int.parse(d)); _hCtrl.value = TextEditingValue(text:d,selection:TextSelection.collapsed(offset:d.length)); return; }
    if (d.length == 2) {
      final f=int.parse(d[0]),s=int.parse(d[1]);
      final ok=(f==0||f==1)||(f==2&&s<=3);
      if (ok) { setState(()=>_hour=int.parse(d)); _hCtrl.value = TextEditingValue(text:d,selection:TextSelection.collapsed(offset:d.length)); }
      else { final r=_hour<10?'$_hour':_hour.toString().padLeft(2,'0'); _hCtrl.value = TextEditingValue(text:r,selection:TextSelection.collapsed(offset:r.length)); }
      return;
    }
    final p=_hour<10?'$_hour':_hour.toString().padLeft(2,'0'); _hCtrl.value = TextEditingValue(text:p,selection:TextSelection.collapsed(offset:p.length));
  }
  void _onMinChanged(String v) {
    final d = v.replaceAll(RegExp(r'[^0-9]'),'');
    if (d.isEmpty) { _mCtrl.value = const TextEditingValue(text:'',selection:TextSelection.collapsed(offset:0)); return; }
    if (d.length == 1) { setState(()=>_minute=int.parse(d)); _mCtrl.value = TextEditingValue(text:d,selection:TextSelection.collapsed(offset:d.length)); return; }
    if (d.length == 2) {
      final ok=int.parse(d[0])<=5;
      if (ok) { setState(()=>_minute=int.parse(d)); _mCtrl.value = TextEditingValue(text:d,selection:TextSelection.collapsed(offset:d.length)); }
      else { final r=_minute<10?'$_minute':_minute.toString().padLeft(2,'0'); _mCtrl.value = TextEditingValue(text:r,selection:TextSelection.collapsed(offset:r.length)); }
      return;
    }
    final p=_minute<10?'$_minute':_minute.toString().padLeft(2,'0'); _mCtrl.value = TextEditingValue(text:p,selection:TextSelection.collapsed(offset:p.length));
  }
  void _finalH() {
    if (_hCtrl.text.isEmpty) { setState(()=>_hour=0); _hCtrl.text='00'; _hCtrl.selection=const TextSelection.collapsed(offset:2); }
    else { final n=int.tryParse(_hCtrl.text); if(n!=null&&n>=0&&n<=23){setState(()=>_hour=n);_hCtrl.text=n.toString().padLeft(2,'0');_hCtrl.selection=TextSelection.collapsed(offset:_hCtrl.text.length);} }
  }
  void _finalM() {
    if (_mCtrl.text.isEmpty) { setState(()=>_minute=0); _mCtrl.text='00'; _mCtrl.selection=const TextSelection.collapsed(offset:2); }
    else { final n=int.tryParse(_mCtrl.text); if(n!=null&&n>=0&&n<=59){setState(()=>_minute=n);_mCtrl.text=n.toString().padLeft(2,'0');_mCtrl.selection=TextSelection.collapsed(offset:_mCtrl.text.length);} }
  }

  Widget _box(TextEditingController ctrl, String label, VoidCallback onUp, VoidCallback onDown, void Function(String) onChanged, VoidCallback onDone) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(onTap: onUp, child: const Icon(Icons.keyboard_arrow_up, color: Colors.white54, size: 28)),
      const SizedBox(height: 4),
      Container(width: 72, decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(8)),
        child: TextField(controller: ctrl, textAlign: TextAlign.center, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800), decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)), onChanged: onChanged, onEditingComplete: onDone, onTapOutside: (_)=>onDone())),
      const SizedBox(height: 4),
      GestureDetector(onTap: onDown, child: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 28)),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('REMINDER TIME', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
            _box(_hCtrl,'HOUR',()=>setState(()=>_setHour(_hour+1)),()=>setState(()=>_setHour(_hour-1)),_onHourChanged,_finalH),
            const Padding(padding: EdgeInsets.only(bottom: 28), child: Text(' : ', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800))),
            _box(_mCtrl,'MINUTES',()=>setState(()=>_setMinute(_minute+1)),()=>setState(()=>_setMinute(_minute-1)),_onMinChanged,_finalM),
          ])),
        const SizedBox(height: 16),
        Container(height: 1, color: Colors.white38),
        IntrinsicHeight(child: Row(children: [
          Expanded(child: GestureDetector(behavior:HitTestBehavior.opaque,onTap: ()=>Navigator.pop(context), child: Container(width:double.infinity,padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('CANCEL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
          Container(width: 1, color: Colors.white38),
          Expanded(child: GestureDetector(behavior:HitTestBehavior.opaque,onTap: (){_finalH();_finalM();widget.onConfirm(_hour,_minute);Navigator.pop(context);}, child: Container(width:double.infinity,padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('OK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
        ])),
      ]),
    );
  }
}

// ─── Reminders Modal ──────────────────────────────────────────────────────────

class _RemindersModal extends StatefulWidget {
  final List<ReminderEntry> reminders;
  final void Function(List<ReminderEntry>) onChanged;
  const _RemindersModal({required this.reminders, required this.onChanged});
  @override State<_RemindersModal> createState() => _RemindersModalState();
}
class _RemindersModalState extends State<_RemindersModal> {
  late List<ReminderEntry> _list;
  @override void initState() { super.initState(); _list = List.from(widget.reminders); }

  void _add() { showDialog(context: context, barrierColor: Colors.black54, builder: (_) => _NewReminderModal(existingTimes: _list.map((r)=>r.time).toList(), onConfirm: (e){setState(()=>_list.add(e));widget.onChanged(List.from(_list));})); }
  void _edit(int i) {
    final otherTimes = _list.asMap().entries.where((e)=>e.key!=i).map((e)=>e.value.time).toList();
    showDialog(context: context, barrierColor: Colors.black54, builder: (_) => _NewReminderModal(existingTimes: otherTimes, initialEntry: _list[i], title:'EDIT REMINDERS', onConfirm: (e){setState(()=>_list[i]=e);widget.onChanged(List.from(_list));}));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('TIME AND REMINDERS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)))),
        Container(height: 0.5, color: Colors.white24),
        Flexible(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(20,0,20,0), child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_list.isEmpty) ...[const SizedBox(height:20), const Icon(Icons.notifications_off, color: Colors.white, size: 48), const SizedBox(height:8), const Text('NO REMINDERS FOR THIS ACTIVITY', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)), const SizedBox(height:20)]
          else ...[
            ...(() { final sorted = [..._list]..sort((a, b) { final ap = a.time.split(':'); final bp = b.time.split(':'); return ((int.tryParse(ap[0])??0)*60+(int.tryParse(ap.length>1?ap[1]:'0')??0)).compareTo((int.tryParse(bp[0])??0)*60+(int.tryParse(bp.length>1?bp[1]:'0')??0)); }); return sorted.asMap().entries; })().map((e) {
              final i=e.key; final r=e.value;
              final icon = r.type=='none'?Icons.notifications_off:r.type=='alarm'?Icons.alarm:Icons.notifications;
              final sched = r.schedule=='always'?'ALWAYS ENABLED':r.schedule=='before'?'${r.daysBefore} DAYS BEFORE':r.weekDays.join(' . ');
              return Column(children: [
                if (i > 0) Container(height: 0.5, color: Colors.white12),
                SizedBox(height: 60, child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: ()=>_edit(i), child: Row(children: [
                    Container(width:36,height:36,decoration:const BoxDecoration(color:Color(0xFF444444),shape:BoxShape.circle),child:Icon(icon,color:Colors.white70,size:18)),
                    const SizedBox(width:12),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(r.time,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800)),Text(sched,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54,fontSize:11,letterSpacing:0.5))])),
                    const SizedBox(width:48),
                  ]))),
                  Positioned(right:0,top:0,bottom:0,child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: (){setState((){_list.removeAt(i);widget.onChanged(List.from(_list));});}, child: Center(child: Container(width:36,height:36,decoration:const BoxDecoration(color:Color(0xFF444444),shape:BoxShape.circle),child:const Icon(Icons.delete_outline,color:Colors.white70,size:18))))),
                ])),
              ]);
            }),
            const SizedBox(height:4),
          ],
        ])))),
        Container(height: 0.5, color: Colors.white24),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _add,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('NEW REMINDER', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ]),
          ),
        ),
        Container(height: 0.5, color: Colors.white24),
        GestureDetector(behavior:HitTestBehavior.opaque,onTap: (){widget.onChanged(_list);Navigator.pop(context);}, child: Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical: 16),child:Center(child: Text('CLOSE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5))))),
      ])),
    );
  }
}

// ─── New Reminder Modal ───────────────────────────────────────────────────────

class _NewReminderModal extends StatefulWidget {
  final void Function(ReminderEntry) onConfirm;
  final List<String> existingTimes;
  final ReminderEntry? initialEntry;
  final String title;
  const _NewReminderModal({required this.onConfirm, this.existingTimes=const[], this.initialEntry, this.title='NEW REMINDER'});
  @override State<_NewReminderModal> createState() => _NewReminderModalState();
}
class _NewReminderModalState extends State<_NewReminderModal> {
  late TextEditingController _tCtrl, _dbCtrl;
  late String _type, _schedule;
  late Set<String> _weekDays;
  static const _days = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
  @override
  void initState() {
    super.initState();
    final init=widget.initialEntry;
    final rawTime=init?.time??'12:00';
    final tp=rawTime.split(':');
    final th=(int.tryParse(tp.isNotEmpty?tp[0]:'12')??12).clamp(0,23);
    final tm=(int.tryParse(tp.length>1?tp[1]:'00')??0).clamp(0,59);
    final cleanTime='${th.toString().padLeft(2,'0')}:${tm.toString().padLeft(2,'0')}';
    _tCtrl=TextEditingController(text:cleanTime);
    _type=init?.type??'notification';
    _schedule=init?.schedule??'always';
    _weekDays=Set.from(init?.weekDays??{});
    _dbCtrl=TextEditingController(text:'${init?.daysBefore??1}');
  }
  @override void dispose(){_tCtrl.dispose();_dbCtrl.dispose();super.dispose();}

  Widget _typeIcon(String t,IconData icon,String label){
    final sel=_type==t;
    return GestureDetector(onTap:()=>setState(()=>_type=t),child:Column(children:[Icon(icon,color:sel?Colors.white:Colors.white38,size:32),const SizedBox(height:4),Text(label,style:TextStyle(color:sel?Colors.white:Colors.white38,fontSize:10,fontWeight:FontWeight.w600,letterSpacing:0.5))]));
  }
  Widget _radio(String value,String label,{Widget? child}){
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      GestureDetector(onTap:()=>setState(()=>_schedule=value),child:Row(children:[
        Container(width:18,height:18,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white,width:1.5),color:_schedule==value?Colors.white:Colors.transparent),child:_schedule==value?Center(child:Container(width:6,height:6,decoration:const BoxDecoration(shape:BoxShape.circle,color:Colors.black))):null),
        const SizedBox(width:10),
        Text(label,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w700,letterSpacing:0.3)),
      ])),
      if(_schedule==value&&child!=null) Padding(padding:const EdgeInsets.only(left:28,top:8),child:child),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding:const EdgeInsets.fromLTRB(20,20,20,12),child:Center(child:Text(widget.title,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700,letterSpacing:0.5)))),
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          GestureDetector(onTap:()async{
            final p=_tCtrl.text.split(':');
            await showDialog(context:context,builder:(_)=>_TimePickerDialog(initialHour:int.tryParse(p.isNotEmpty?p[0]:'12')??12,initialMinute:int.tryParse(p.length>1?p[1]:'00')??0,onConfirm:(h,m){final hh=h.clamp(0,23);final mm=m.clamp(0,59);setState(()=>_tCtrl.text='${hh.toString().padLeft(2,'0')}:${mm.toString().padLeft(2,'0')}');}));
          },child:Center(child:Text(_tCtrl.text,style:const TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.w700)))),
          const Center(child:Text('REMINDER TIME',style:TextStyle(color:Colors.white54,fontSize:11,letterSpacing:1))),
          const SizedBox(height:12),
        ])),
        Container(height:0.5,color:Colors.white24),
        Padding(padding:const EdgeInsets.fromLTRB(20,12,20,12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('REMINDER TYPE',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700,letterSpacing:0.5)),
          const SizedBox(height:12),
          Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_typeIcon('none',Icons.notifications_off,"DON'T REMIND"),_typeIcon('notification',Icons.notifications,'NOTIFICATION'),_typeIcon('alarm',Icons.alarm,'ALARM')]),
        ])),
        Container(height:0.5,color:Colors.white24),
        Padding(padding:const EdgeInsets.fromLTRB(20,12,20,20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('REMINDER SCHEDULE',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700,letterSpacing:0.5)),
          const SizedBox(height:10),
          _radio('always','ALWAYS ENABLED'),
          const SizedBox(height:10),
          _radio('week','SPECIFIC DAYS OF THE WEEK',child:Wrap(spacing:6,runSpacing:6,children:_days.map((d){final sel=_weekDays.contains(d);return GestureDetector(onTap:()=>setState(()=>sel?_weekDays.remove(d):_weekDays.add(d)),child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:sel?Colors.white38:const Color(0xFF444444),borderRadius:BorderRadius.circular(6)),child:Text(d,style:TextStyle(color:sel?Colors.white:Colors.white54,fontSize:11,fontWeight:FontWeight.w700))));}).toList())),
          const SizedBox(height:10),
          _radio('before','DAYS BEFORE',child:Row(children:[SizedBox(width:60,child:TextField(controller:_dbCtrl,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(border:InputBorder.none,isDense:true))),const SizedBox(width:8),const Text('DAYS BEFORE',style:TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w700))])),
        ])),
        Container(height:0.5,color:Colors.white24),
        IntrinsicHeight(child:Row(children:[
          Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>Navigator.pop(context),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:14),child:const Center(child:Text('CANCEL',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
          Container(width:0.5,color:Colors.white24),
          Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:(){
            final t=_tCtrl.text.trim();
            if(widget.existingTimes.contains(t)){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:const Text('Duplicate Reminder',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),content:const Text('A reminder already exists at that time',style:TextStyle(color:Colors.white70,fontSize:13)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));return;}
            widget.onConfirm(ReminderEntry(time:t,type:_type,schedule:_schedule,weekDays:Set.from(_weekDays),daysBefore:int.tryParse(_dbCtrl.text)??1));
            Navigator.pop(context);
          },child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:14),child:const Center(child:Text('CONFIRM',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
        ])),
      ])),
    );
  }
}

// ─── Marquee Widget ───────────────────────────────────────────────────────────

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});
  @override State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late ScrollController _scrollCtrl;
  dynamic _ticker;
  double _textWidth = 0;
  double _containerWidth = 0;
  bool _needsScroll = false;
  static const double _speed = 0.7;
  double _accumulated = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    _textWidth = tp.width;

    final box = context.findRenderObject() as RenderBox?;
    if (box != null) _containerWidth = box.size.width;

    if (_textWidth > _containerWidth) {
      setState(() => _needsScroll = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
    }
  }

  void _startMarquee() {
    _ticker?.dispose();
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
    _lastElapsed = Duration.zero;
    _accumulated = 0;
    _ticker = createTicker((elapsed) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final delta = elapsed - _lastElapsed;
      _lastElapsed = elapsed;
      _accumulated += _speed * delta.inMilliseconds / 16.0;
      final pixels = _accumulated.floor();
      if (pixels <= 0) return;
      _accumulated -= pixels;
      final max = _scrollCtrl.position.maxScrollExtent;
      final cur = _scrollCtrl.offset;
      if (cur + pixels >= max) {
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.jumpTo(cur + pixels);
      }
    });
    _ticker!.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.clip);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _containerWidth = constraints.maxWidth;
        final gap = _containerWidth * 0.5;
        return SingleChildScrollView(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Text(widget.text, style: widget.style, maxLines: 1),
              SizedBox(width: gap),
              Text(widget.text, style: widget.style, maxLines: 1),
            ],
          ),
        );
      },
    );
  }
}

// ─── Add Note Dialog ──────────────────────────────────────────────────────────

class _AddNoteDialog extends StatefulWidget {
  final String initialNote;
  final void Function(String) onConfirm;
  const _AddNoteDialog({required this.initialNote, required this.onConfirm});
  @override State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  late TextEditingController _ctrl;
  static const int _maxChars = 400;
  int _charCount = 0;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialNote); _charCount = _ctrl.text.length; }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text('ADD NOTE...', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Stack(
              children: [
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) {
                    var u = v.toUpperCase();
                    if (u.length > _maxChars) {
                      u = u.substring(0, _maxChars);
                    }
                    if (v != u) {
                      _ctrl.value = TextEditingValue(text: u, selection: TextSelection.collapsed(offset: u.length));
                    }
                    setState(() => _charCount = u.length);
                  },
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(12, 28, 12, 12),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 8,
                  child: Text(
                    '$_charCount/$_maxChars',
                    style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(height: 0.5, color: Colors.white24),
        IntrinsicHeight(child: Row(children: [
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('CANCEL', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
          )),
          Container(width: 0.5, color: Colors.white24),
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_ctrl.text.length > _maxChars) { return; }
              widget.onConfirm(_ctrl.text.trim());
              Navigator.pop(context);
            },
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('OK', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
          )),
        ])),
      ]),
    );
  }
}

// ─── Habit Name Edit Dialog ───────────────────────────────────────────────────

class _HabitNameEditDialog extends StatefulWidget {
  final String initialName;
  final void Function(String) onConfirm;
  const _HabitNameEditDialog({required this.initialName, required this.onConfirm});
  @override State<_HabitNameEditDialog> createState() => _HabitNameEditDialogState();
}
class _HabitNameEditDialogState extends State<_HabitNameEditDialog> {
  late TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialName); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('HABIT NAME', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          ),
          Container(height: 0.5, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  final u = v.toUpperCase();
                  if (v != u) {
                    _ctrl.value = TextEditingValue(text: u, selection: TextSelection.collapsed(offset: u.length));
                  }
                },
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: Colors.white24),
          IntrinsicHeight(child: Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('CANCEL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
            )),
            Container(width: 0.5, color: Colors.white24),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final name = _ctrl.text.trim();
                if (name.isNotEmpty) widget.onConfirm(name);
                Navigator.pop(context);
              },
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('OK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
            )),
          ])),
        ]),
      ),
    );
  }
}

class _DescriptionEditDialog extends StatefulWidget {
  final String initialDescription;
  final void Function(String) onConfirm;
  const _DescriptionEditDialog({required this.initialDescription, required this.onConfirm});
  @override State<_DescriptionEditDialog> createState() => _DescriptionEditDialogState();
}
class _DescriptionEditDialogState extends State<_DescriptionEditDialog> {
  late TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialDescription); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('DESCRIPTION', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          ),
          Container(height: 0.5, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  final u = v.toUpperCase();
                  if (v != u) {
                    _ctrl.value = TextEditingValue(text: u, selection: TextSelection.collapsed(offset: u.length));
                  }
                },
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: Colors.white24),
          IntrinsicHeight(child: Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('CANCEL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
            )),
            Container(width: 0.5, color: Colors.white24),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onConfirm(_ctrl.text.trim());
                Navigator.pop(context);
              },
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), child: const Center(child: Text('OK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
            )),
          ])),
        ]),
      ),
    );
  }
}

class _CategoryFilterDialog extends StatefulWidget {
  final List<Habit> habits;
  final Set<String> initialSelected;
  final void Function(Set<String>) onChanged;
  const _CategoryFilterDialog({
    required this.habits,
    required this.initialSelected,
    required this.onChanged,
  });
  @override State<_CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<_CategoryFilterDialog> {
  final _scrollCtrl = ScrollController();
  late Set<String> _selected;
  static const double _rowHeight = 56.0;
  static const int _maxVisible = 5;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<String> get _categoriesInUse {
    final seen = <String>{};
    final ordered = <String>[];
    for (final h in widget.habits) {
      final c = h.category.trim();
      if (c.isEmpty) continue;
      final key = c.toLowerCase();
      if (seen.add(key)) ordered.add(c);
    }
    return ordered;
  }

  void _toggle(String category) {
    setState(() {
      if (_selected.contains(category)) {
        _selected.remove(category);
      } else {
        _selected.add(category);
      }
    });
    widget.onChanged(Set.from(_selected));
  }

  Widget _circle(bool selected) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          color: selected ? Colors.white : Colors.transparent,
        ),
      );

  Widget _buildRow(String category) {
    final selected = _selected.contains(category);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(category),
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _circle(selected),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categoriesInUse;
    final bool isEmpty = categories.isEmpty;
    final bool needsScroll = categories.length > _maxVisible;
    final double listHeight = isEmpty
        ? _rowHeight
        : (needsScroll ? _rowHeight * _maxVisible : _rowHeight * categories.length);

    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'SELECT CATEGORY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            SizedBox(
              height: listHeight,
              child: isEmpty
                  ? const Center(
                      child: Text(
                        'NO CATEGORIES AVAILABLE',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                      ),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        physics: needsScroll
                            ? const ClampingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: categories.length,
                        itemExtent: _rowHeight,
                        itemBuilder: (ctx, i) => _buildRow(categories[i]),
                      ),
                    ),
            ),
            Container(height: 0.5, color: Colors.white24),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(
                  child: Text(
                    'CLOSE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelectDialog extends StatefulWidget {
  final void Function(String) onSelected;
  final List<Habit> habits;
  const _CategorySelectDialog({required this.onSelected, required this.habits});
  @override State<_CategorySelectDialog> createState() => _CategorySelectDialogState();
}

const double _kCreateCategoryIconOffsetX = 20.0;
const double _kCreateCategoryIconOffsetY = 0.0;

class _CategorySelectDialogState extends State<_CategorySelectDialog> {
  final _scrollCtrl = ScrollController();
  static const _defaultCategories = [
    'MEDITATION','SPORT','ENTERTAINMENT','ART','STUDY',
    'QUIT A BAD HABIT',
  ];
  List<String> _customCategories = CategoryStore.custom;
  static const _manageCategory = 'MANAGE CATEGORIES';

  List<String> get _categories => [..._customCategories, ..._defaultCategories];
  static const double _rowHeight = 52.0;
  static const int _maxVisible = 5;

  @override void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bool needsScroll = _categories.length > _maxVisible;
    final double listHeight = needsScroll
        ? _rowHeight * _maxVisible
        : _rowHeight * _categories.length;

    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sticky title
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('SELECT A CATEGORY', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
            ),
            Container(height: 0.5, color: Colors.white24),
            // Scrollable category list
            SizedBox(
              height: listHeight,
              child: needsScroll
                  ? ScrollbarTheme(
                      data: ScrollbarThemeData(
                        thumbColor: WidgetStateProperty.all(Colors.white54),
                        trackColor: WidgetStateProperty.all(Colors.white12),
                        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
                        thickness: WidgetStateProperty.all(4),
                        radius: const Radius.circular(2),
                        thumbVisibility: WidgetStateProperty.all(true),
                        trackVisibility: WidgetStateProperty.all(true),
                      ),
                      child: Scrollbar(
                        controller: _scrollCtrl,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: EdgeInsets.zero,
                          itemCount: _categories.length,
                          itemExtent: _rowHeight,
                          itemBuilder: (ctx, i) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () { widget.onSelected(_categories[i]); Navigator.pop(ctx); },
                              child: SizedBox(height: _rowHeight, child: Center(
                                child: Text(_categories[i], textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 15,
                                    fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                              )),
                            );
                          },
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _categories.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (ctx, i) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () { widget.onSelected(_categories[i]); Navigator.pop(ctx); },
                          child: SizedBox(height: _rowHeight, child: Center(
                            child: Text(_categories[i], textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 15,
                                fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          )),
                        );
                      },
                    ),
            ),
            Container(height: 0.5, color: Colors.white24),
            // Sticky: Manage Categories
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => _CategoriesScreen(
                      customCategories: _customCategories,
                      habits: widget.habits,
                      onChanged: (updated) {
                        if (!mounted) return;
                        setState(() => _customCategories = updated);
                      },
                    ),
                  ),
                );
              },
              child: SizedBox(
                height: _rowHeight,
                child: Center(
                  child: Text(_manageCategory, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                ),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            // Sticky: Close
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(child: Text('CLOSE', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}




class _NewCategorySheet extends StatefulWidget {
  final List<String> existingCustom;
  const _NewCategorySheet({required this.existingCustom});
  @override State<_NewCategorySheet> createState() => _NewCategorySheetState();
}

class _NewCategorySheetState extends State<_NewCategorySheet> {
  String _sheetTitle = 'NEW CATEGORY';
  String _enteredName = '';

  final TextEditingController _nameController = TextEditingController();

  Future<void> _openCategoryNameDialog() async {
    _nameController.text = _enteredName;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        // ── Tune these two values to vertically center the text ──
        const double inputTopPadding = 16;     // space ABOVE the text
        const double inputBottomPadding = 16;  // space BELOW the text
        return Dialog(
          backgroundColor: const Color(0xFF2C2C2C),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // TITLE
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'CATEGORY NAME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // TOP DIVIDER
                Container(
                  height: 0.5,
                  color: Colors.white24,
                ),

                // INPUT AREA
                // INPUT AREA
                Padding(
                  padding: EdgeInsets.only(
                    left: MediaQuery.of(context).size.width * 0.03,
                    right: MediaQuery.of(context).size.width * 0.03,
                    top: 26,
                    bottom: 26,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                      ],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '',
                        contentPadding: EdgeInsets.fromLTRB(
                          16,                   // left inset
                          inputTopPadding,      // ← top spacing
                          16,                   // right inset
                          inputBottomPadding,   // ← bottom spacing
                        ),
                      ),
                    ),
                  ),
                ),

                // BOTTOM DIVIDER
                Container(
                  height: 0.5,
                  color: Colors.white24,
                ),

                SizedBox(
                  height: 74,
                  child: Row(
                    children: [

                      // CANCEL
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // CENTER DIVIDER
                      Container(
                        width: 0.5,
                        color: Colors.white24,
                      ),

                      // OK
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pop(
                              context,
                              _nameController.text.trim().toUpperCase(),
                            );
                          },
                          child: const Center(
                            child: Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    setState(() {
      _enteredName = result;
      _sheetTitle = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 0),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(_sheetTitle,
              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 28),

Container(height: 0.5, color: Colors.white12),

// 8. Archive row — opens confirmation dialog
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: _openCategoryNameDialog,
  child: Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 22,
    ),
    child: const Text(
      'CATEGORY NAME',
      style: TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    ),
  ),
),

Container(height: 0.5, color: Colors.white12),

const SizedBox(height: 48),

Container(height: 0.5, color: Colors.white12),

// CREATE CATEGORY BUTTON
GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
  final trimmed = _enteredName.trim();

  // Prevent empty names
  if (trimmed.isEmpty) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Center(
                  child: Text(
                    'ENTER A NAME',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: const Center(
                    child: Text(
                      'OK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return;
  }

  // Case-insensitive duplicate check
  final normalized = trimmed.toLowerCase();

  final isDuplicate = widget.existingCustom.any(
    (c) => c.trim().toLowerCase() == normalized,
  );

  // Duplicate popup
  if (isDuplicate) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Center(
                  child: Text(
                    'NAME ALREADY EXISTS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: const Center(
                    child: Text(
                      'OK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return;
  }

  // Close bottom sheet with existing downward animation
  Navigator.of(context).pop(trimmed);
},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const Center(
                child: Text(
                  'CREATE CATEGORY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}


class _EditCategorySheet extends StatefulWidget {
  final String initialName;
  final void Function(String oldName, String newName) onRename;
  final void Function(String name) onDelete;
  const _EditCategorySheet({
    required this.initialName,
    required this.onRename,
    required this.onDelete,
  });
  @override State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  late String _currentName;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentName = widget.initialName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Same name-input dialog as Create: same uppercase formatter, OK/CANCEL,
  // and the same trim().toUpperCase() commit behavior. (Req 3)
  Future<void> _openCategoryNameDialog() async {
    _nameController.text = _currentName;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        const double inputTopPadding = 16;
        const double inputBottomPadding = 16;
        return Dialog(
          backgroundColor: const Color(0xFF2C2C2C),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('CATEGORY NAME',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ),
                Container(height: 0.5, color: Colors.white24),
                Padding(
                  padding: EdgeInsets.only(
                    left: MediaQuery.of(context).size.width * 0.03,
                    right: MediaQuery.of(context).size.width * 0.03,
                    top: 26,
                    bottom: 26,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      maxLines: 1,
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '',
                        contentPadding: EdgeInsets.fromLTRB(16, inputTopPadding, 16, inputBottomPadding),
                      ),
                    ),
                  ),
                ),
                Container(height: 0.5, color: Colors.white24),
                SizedBox(
                  height: 74,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context),
                          child: const Center(
                            child: Text('CANCEL',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ),
                        ),
                      ),
                      Container(width: 0.5, color: Colors.white24),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context, _nameController.text.trim().toUpperCase()),
                          child: const Center(
                            child: Text('OK',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return; // CANCEL

    final trimmed = result.trim();

    // Same empty validation/popup as Create.
    if (trimmed.isEmpty) {
      _showInfoDialog('ENTER A NAME');
      return;
    }

    // No change → do nothing.
    if (trimmed.toLowerCase() == _currentName.trim().toLowerCase()) return;

    // Same duplicate validation/popup as Create (excluding the current name).
    final normalized = trimmed.toLowerCase();
    final isDuplicate = CategoryStore.custom.any((c) =>
        c.trim().toLowerCase() != _currentName.trim().toLowerCase() &&
        c.trim().toLowerCase() == normalized);
    if (isDuplicate) {
      _showInfoDialog('NAME ALREADY EXISTS');
      return;
    }

    final oldName = _currentName;
    widget.onRename(oldName, trimmed);          // persist + refresh in parent
    setState(() => _currentName = trimmed);     // live-update sheet title
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Center(
                child: Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(child: Text('OK', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // Confirmation before delete. (Req 4)
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Center(
                child: Text('ARE YOU SURE YOU WANT TO DELETE THIS CATEGORY?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            IntrinsicHeight(child: Row(children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context), // NO → close dialog only
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Center(child: Text('NO',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
              Container(width: 0.5, color: Colors.white24),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(context);          // close confirm dialog
                    widget.onDelete(_currentName);   // persist + refresh in parent
                    Navigator.pop(context);          // close edit bottom sheet
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Center(child: Text('YES',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
            ])),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle — same as Create sheet.
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 0),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Top title = category name.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(_currentName,
              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 28),
          Container(height: 0.5, color: Colors.white12),
          // CATEGORY NAME row → rename dialog.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openCategoryNameDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: const Text('CATEGORY NAME',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          ),
          Container(height: 0.5, color: Colors.white12),
          const SizedBox(height: 48),
          Container(height: 0.5, color: Colors.white12),
          // DELETE CATEGORY (where CREATE CATEGORY is on the Create sheet).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _confirmDelete,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const Center(
                child: Text('DELETE CATEGORY',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}



class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}



// ─── Categories Screen ────────────────────────────────────────────────────────

class _CategoriesScreen extends StatefulWidget {
  final List<String> customCategories;
  final void Function(List<String>) onChanged;
  final List<Habit> habits;
  const _CategoriesScreen({required this.customCategories, required this.onChanged, required this.habits});
  @override State<_CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<_CategoriesScreen> {
  late List<String> _custom;
  static const _defaults = [
    'MEDITATION', 'SPORT', 'ENTERTAINMENT', 'ART', 'STUDY', 'QUIT A BAD HABIT',
  ];

  // ── Scroll support for >5 custom categories (Requirement 1) ──
  final ScrollController _customScrollCtrl = ScrollController();
  static const double _customRowHeight = 37.0; // Text(16px) + 18px bottom padding ≈ one row
  static const int _maxVisibleCustom = 5;

  @override
  void dispose() {
    _customScrollCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _custom = List.from(widget.customCategories);
  }

  void _openNewCategorySheet() {
  showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _NewCategorySheet(existingCustom: List.from(_custom)),
    ).then((name) async {
      if (name == null || !mounted) return;
      await CategoryStore.add(name);
      if (!mounted) return;
      setState(() => _custom = CategoryStore.custom);
      try { widget.onChanged(List.from(_custom)); } catch (_) {}
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF2C2C2C),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Center(child: Text('CATEGORY CREATED', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
              ),
              Container(height: 0.5, color: Colors.white24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                  child: const Center(child: Text('OK', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
              ),
            ]),
          ),
        ),
      );
    });
  }

  String _entryCountLabel(String category) {
    final target = category.trim().toLowerCase();
    final count =
        widget.habits.where((h) => h.category.trim().toLowerCase() == target).length;
    return count == 1 ? '1 ENTRY' : '$count ENTRIES';
  }

  // Tappable custom-category row. Styling identical to the original row
  // (Padding bottom:18 + same Text). GestureDetector only adds the tap (Req 2);
  // HitTestBehavior.opaque means no visual change.
  Widget _buildCustomCategoryRow(String c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditCategorySheet(c),
      child: SizedBox(
        height: _customRowHeight,
        child: Container(
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5,
                ),
                child: Text(
                  c,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
              ),
              const Spacer(),
              Text(
                _entryCountLabel(c),
                style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSection() {
    // Empty state — unchanged.
    if (_custom.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(
          'THERE ARE NO CUSTOM CATEGORIES',
          style: TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
      );
    }

    final rows = _custom.map(_buildCustomCategoryRow).toList();

    // 5 or fewer → behave exactly as before (no scroll, no bounded height).
    if (_custom.length <= _maxVisibleCustom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }

    // More than 5 → bounded, scrollable both ways, with a visible scrollbar.
    return SizedBox(
      height: _customRowHeight * _maxVisibleCustom,
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(Colors.white54),
          trackColor: WidgetStateProperty.all(Colors.white12),
          trackBorderColor: WidgetStateProperty.all(Colors.transparent),
          thickness: WidgetStateProperty.all(4),
          radius: const Radius.circular(2),
          thumbVisibility: WidgetStateProperty.all(true),
          trackVisibility: WidgetStateProperty.all(true),
        ),
        child: Scrollbar(
          controller: _customScrollCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _customScrollCtrl,
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  void _openEditCategorySheet(String name) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _EditCategorySheet(
        initialName: name,
        onRename: (oldName, newName) async {
          await CategoryStore.rename(oldName, newName); // persist (Req 5)
          if (!mounted) return;
          setState(() => _custom = CategoryStore.custom); // refresh CUSTOM list (Req 3)
          widget.onChanged(List.from(_custom));           // propagate, same as create
        },
        onDelete: (delName) async {
          await CategoryStore.remove(delName);            // persist (Req 5)
          if (!mounted) return;
          setState(() => _custom = CategoryStore.custom); // refresh CUSTOM list (Req 4)
          widget.onChanged(List.from(_custom));
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  const Text(
                    'CATEGORIES',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'CUSTOM CATEGORIES',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 24),   // ← NEW: increased gap
                      _buildCustomSection(),
                    const SizedBox(height: 8),
                    // ── REPLACE WITH ──
                    const Text(
                      'DEFAULT CATEGORIES',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 24),   // ← NEW: increased gap
                    ..._defaults.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        children: [
                          Text(
                            c,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                          ),
                          const Spacer(),
                          Text(
                            _entryCountLabel(c),
                            style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openNewCategorySheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: Colors.black,
                child: const Center(
                  child: Text(
                    'NEW CATEGORY',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}



class _FrequencyEditResult {
  final String frequency;
  final Map<String,bool> weekDays;
  final Set<int> monthDays;
  final List<DateTime> yearDays;
  final int periodDays;
  final String periodUnit;
  final int repeatEvery;
  final bool flexible;
  _FrequencyEditResult({required this.frequency,required this.weekDays,required this.monthDays,required this.yearDays,required this.periodDays,required this.periodUnit,required this.repeatEvery,this.flexible=false});
}


// ─── Edit Habit Screen ────────────────────────────────────────────────────────

class EditHabitScreen extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  final VoidCallback onDelete;
  // Optional callback invoked immediately after any reminder change is
  // committed to the shared Habit object, so an already-alive Main Page
  // can rebuild in real time without waiting for this screen to be popped.
  final VoidCallback? onHabitChanged;
  const EditHabitScreen({super.key, required this.habit, required this.allHabits, required this.onDelete, this.onHabitChanged});
  @override State<EditHabitScreen> createState() => _EditHabitScreenState();
}

class _EditHabitScreenState extends State<EditHabitScreen> {
  // Toggle state: false = CALENDAR view, true = EDIT view
  // On this screen EDIT is always selected by default
  bool _editSelected = true;
  String _habitTitle = '';
  String _category = '';
  String _description = '';
  late String _frequency;
  late List<ReminderEntry> _reminders;
  Map<String,bool> _savedWeekDays = {'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false};
  Set<int> _savedMonthDays = {};
  List<DateTime> _savedYearDays = [];
  int _savedPeriodDays = 1;
  String _savedPeriodUnit = 'WEEK';
  int _savedRepeatEvery = 1;
  bool _savedFlexible = false;

  @override
  void initState() {
    super.initState();
    _habitTitle = widget.habit.title;
    _category = widget.habit.category;
    _description = widget.habit.description;
    _frequency = widget.habit.frequency;
    _reminders = List.from(widget.habit.reminders);
    _savedWeekDays = Map.from(widget.habit.freqWeekDays);
    _savedMonthDays = Set.from(widget.habit.freqMonthDays);
    _savedYearDays = List.from(widget.habit.freqYearDays);
    _savedPeriodDays = widget.habit.freqPeriodDays;
    _savedPeriodUnit = widget.habit.freqPeriodUnit;
    _savedRepeatEvery = widget.habit.freqRepeatEvery;
    _savedFlexible = widget.habit.freqFlexible;
  }

  static const _weekDayAbbr = {
  'MONDAY': 'MON',
  'TUESDAY': 'TUE',
  'WEDNESDAY': 'WED',
  'THURSDAY': 'THU',
  'FRIDAY': 'FRI',
  'SATURDAY': 'SAT',
  'SUNDAY': 'SUN',
  };

  static const _monthNames = [
    'JAN','FEB','MAR','APR','MAY','JUN',
    'JUL','AUG','SEP','OCT','NOV','DEC'
  ];
  static const _monthNamesFull = [
    'JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE',
    'JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'
  ];

  String _fmtDate(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

  String _fmtDateShort(DateTime d) =>
      '${d.month}/${d.day}/${d.year % 100}';


  String _formatFrequency(String freq) {
  if (freq == 'EVERY DAY' || freq.isEmpty) return 'EVERY DAY';
  if (freq == 'REPEAT') return 'every $_savedRepeatEvery days';
  if (freq == 'SOME DAYS PER PERIOD') {
    final unit = _savedPeriodUnit.toLowerCase();
    return '$_savedPeriodDays days per $unit';
  }
  if (freq == 'SPECIFIC DAYS OF THE WEEK') {
    // Collect selected days in week order
    final ordered = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY'];
    final selected = ordered.where((d) => _savedWeekDays[d] == true).toList();
    if (selected.length == 7) return 'EVERY DAY';
    if (selected.isEmpty) return 'SPECIFIC DAYS OF THE WEEK';
    return selected.map((d) => _weekDayAbbr[d]!).join(' - ');
  }
  if (freq == 'SPECIFIC DAYS OF THE MONTH') {
  if (_savedMonthDays.isEmpty) return 'SPECIFIC DAYS OF THE MONTH';
  final sorted = _savedMonthDays.toList()..sort((a, b) {
    if (a == 0) return 1;
    if (b == 0) return -1;
    return a.compareTo(b);
  });
  final parts = sorted.map((d) => d == 0 ? 'LAST DAY' : '$d').join(', ');
  return 'DAYS OF MONTH : $parts';
}
  if (freq == 'SPECIFIC DAYS OF THE YEAR') return 'SPECIFIC DAYS OF THE YEAR';
  return freq.toUpperCase();
}

 String _formatMonthDaysValues() {
    if (_savedMonthDays.isEmpty) return '';
    final sorted = _savedMonthDays.toList()..sort((a, b) {
      if (a == 0) return 1;
      if (b == 0) return -1;
      return a.compareTo(b);
    });
    final parts = sorted.map((d) => d == 0 ? 'LAST DAY' : '$d').toList();
    if (parts.length <= 4) {
      return parts.join(', ');
    } else {
      return '${parts.take(4).join(', ')}...';
    }
  }

  String _formatYearDaysValues() {
    if (_savedYearDays.isEmpty) return '';
    const abbr = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    final sorted = List<DateTime>.from(_savedYearDays)
      ..sort((a, b) => a.month != b.month
          ? a.month.compareTo(b.month)
          : a.day.compareTo(b.day));
    final parts = sorted
        .map((d) => '${abbr[d.month - 1]} ${d.day}')
        .toList();
    if (parts.length <= 4) {
      return parts.join(', ');
    } else {
      return '${parts.take(4).join(', ')}...';
    }
  }

  Widget _buildDivider() => Container(height: 0.5, color: Colors.white12);

  Widget _buildRow({
    required String label,
    required Widget right,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: right,
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }

  Widget _buildValueText(String value) => Text(
        value.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      );

  Widget _buildPill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );

  String _priorityLabel() {
    final p = widget.habit.priority;
    if (p == 1) return 'DEFAULT';
    return '$p 🏳';
  }

  void _confirmDeleteEndDate() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'DO YOU WANT TO DELETE THE END DATE?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => widget.habit.endDate = null);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CONFIRM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: widget.habit.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (c, ch) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Color(0xFF2C2C2C),
            onSurface: Colors.white,
          ),
        ),
        child: ch!,
      ),
    );
    if (p != null && mounted) {
      setState(() => widget.habit.startDate = p);  // NOTE: see Section 2 below
    }
  }

  Future<void> _pickEndDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: widget.habit.endDate ?? widget.habit.startDate.add(const Duration(days: 1)),
      firstDate: widget.habit.startDate,
      lastDate: DateTime(2100),
      builder: (c, ch) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Color(0xFF2C2C2C),
            onSurface: Colors.white,
          ),
        ),
        child: ch!,
      ),
    );
    if (p != null && mounted) {
      setState(() => widget.habit.endDate = p);
    }
  }

  void _editHabitName() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _HabitNameEditDialog(
        initialName: _habitTitle,
        onConfirm: (newName) {
          setState(() {
            _habitTitle = newName;
            widget.habit.title = newName;
          });
        },
      ),
    );
  }

  void _confirmDeleteHabit() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'DO YOU WANT TO DELETE THIS HABIT?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.pop(context); // close dialog
                          widget.onDelete();
                          Navigator.pop(context); // close edit screen
                          Navigator.pop(context); // close bottom sheet
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CONFIRM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectCategory() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _CategorySelectDialog(
        habits: widget.allHabits,
          onSelected: (cat) => setState(() {
          _category = cat;
          widget.habit.category = cat;
        }),
      ),
    );
  }

  void _editDescription() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _DescriptionEditDialog(
        initialDescription: _description,
        onConfirm: (newDesc) {
          setState(() {
            _description = newDesc;
            widget.habit.description = newDesc; // ← write back to the shared Habit object
          });
        },
      ),
    );
  }

  void _showReminders() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _RemindersModal(
        reminders: _reminders,
        onChanged: (updated) {
          final previousTimes = _reminders.map((r) => r.time).toList();
          setState(() {
            _reminders = updated;
            widget.habit.reminders
              ..clear()
              ..addAll(updated);
          });
          ReminderService.instance.rescheduleHabit(
            habitId: widget.habit.id,
            habitTitle: widget.habit.title,
            previousTimes: previousTimes,
            currentReminders: updated
                .map((r) => ReminderInput(time: r.time, type: r.type))
                .toList(),
          );
          // Real-time Main Page refresh: the Habit object is already
          // updated above; just notify the still-open Main Page to rebuild
          // now, instead of waiting for this screen to be popped.
          widget.onHabitChanged?.call();
        },
      ),
    );
  }

  void _showPriorityModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _PriorityModal(
        priority: widget.habit.priority,
        onChanged: (v) => setState(() => widget.habit.priority = v),
      ),
    );
  }


  void _editFrequency() async {
    final result = await Navigator.push<_FrequencyEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => HabitFrequencyScreen(
          category: widget.habit.category,
          startDate: widget.habit.startDate.toIso8601String(),
          title: widget.habit.title,
          description: widget.habit.description,
          initialFrequency: _frequency,
          editMode: true,
          initialWeekDays: _savedWeekDays,
          initialMonthDays: _savedMonthDays,
          initialYearDays: _savedYearDays,
          initialPeriodDays: _savedPeriodDays,
          initialPeriodUnit: _savedPeriodUnit,
          initialRepeatEvery: _savedRepeatEvery,
          initialFlexible: _savedFlexible,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _frequency = result.frequency;
        _savedWeekDays = result.weekDays;
        _savedMonthDays = result.monthDays;
        _savedYearDays = result.yearDays;
        _savedPeriodDays = result.periodDays;
        _savedPeriodUnit = result.periodUnit;
        _savedRepeatEvery = result.repeatEvery;
        // Write back to the habit model so it persists across navigation
        widget.habit.frequency = result.frequency;
        widget.habit.freqWeekDays = Map.from(result.weekDays);
        widget.habit.freqMonthDays = Set.from(result.monthDays);
        widget.habit.freqYearDays = List.from(result.yearDays);
        widget.habit.freqPeriodDays = result.periodDays;
        widget.habit.freqPeriodUnit = result.periodUnit;
        widget.habit.freqRepeatEvery = result.repeatEvery;
        widget.habit.freqFlexible = result.flexible;
        _savedFlexible = result.flexible;
      });
    }
  }

  Future<void> _restartHabitProgress() async {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'RESTART PROGRESS FOR THIS HABIT?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final now = DateTime.now();
                          // Normalize to midnight so date-key lookups
                          // (_key) and isActiveOn comparisons are exact.
                          final today = DateTime(now.year, now.month, now.day);

                          setState(() {
                            // 1. Wipe ALL previous occurrence statuses and notes.
                            widget.habit.dailyState.clear();
                            widget.habit.dailyNote.clear();

                            // 2. Move the habit's start date to today (midnight).
                            widget.habit.startDate = today;

                            // 3. Explicitly create today's occurrence as PENDING
                            //    (HabitState.empty is the PENDING state throughout
                            //    the app). This ensures streak = 0, progress = 0,
                            //    and the calendar shows exactly one active day.
                            widget.habit.setStateOn(today, HabitState.empty);

                            // 4. Mirror the new start date into the local state
                            //    field so the START DATE pill in the Edit rows
                            //    re-renders immediately without a hot-reload.
                            //    (widget.habit.startDate is read directly by
                            //    _buildRow for START DATE, so setState alone
                            //    is sufficient — no extra field needed.)
                          });

                          Navigator.pop(context); // close confirm dialog
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'RESTART',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. TOP HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      habit.title.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. CALENDAR / EDIT TOGGLE ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // CALENDAR option
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HabitCalendarPage(
                                  habit: widget.habit,
                                  allHabits: widget.allHabits,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_editSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'CALENDAR',
                                style: TextStyle(
                                  color: !_editSelected ? Colors.black : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // EDIT option
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _editSelected = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _editSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'EDIT',
                                style: TextStyle(
                                  color: _editSelected ? Colors.black : Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── ROWS ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildDivider(),

                    // 3. HABIT NAME
                    _buildRow(
                      label: 'HABIT NAME',
                      right: _buildValueText(_habitTitle),
                      onTap: _editHabitName,
                    ),
                    _buildDivider(),

                    // 4. CATEGORY
                    _buildRow(
                      label: 'CATEGORY',
                      right: _buildValueText(_category.isEmpty ? (habit.category.isEmpty ? '—' : habit.category) : _category),
                      onTap: _selectCategory,
                    ),
                    _buildDivider(),

                    // 5. DESCRIPTION
                    // 5. DESCRIPTION
                    _buildRow(
                      label: 'DESCRIPTION',
                      right: _buildValueText(_description.isEmpty ? '—' : _description),
                      onTap: _editDescription,
                    ),
                    _buildDivider(),

                    // 6. TIME AND REMINDERS
                    _buildRow(
                      label: 'TIME AND REMINDERS',
                      right: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2C2C2C),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${_reminders.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      onTap: _showReminders,
                    ),
                    _buildDivider(),

                    // 7. PRIORITY
                    _buildRow(
                      label: 'PRIORITY',
                      right: habit.priority == 1
                          ? _buildValueText('DEFAULT')
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2C2C2C),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${habit.priority}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.flag, color: Colors.white, size: 14),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                      onTap: _showPriorityModal,
                    ),
                    _buildDivider(),
                    // 8. FREQUENCY
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _editFrequency,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            const Text(
                              'FREQUENCY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _frequency == 'SPECIFIC DAYS OF THE MONTH'
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          const Text(
                                            'DAYS OF MONTH : ',
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              _formatMonthDaysValues().toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : _frequency == 'SPECIFIC DAYS OF THE YEAR'
                                      ? Text(
                                          _formatYearDaysValues().toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                          ),
                                        )
                                      : SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          reverse: true,
                                          child: Text(
                                            _formatFrequency(_frequency).toUpperCase(),
                                            maxLines: 1,
                                            softWrap: false,
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildDivider(),

                    // 9. START DATE
                    _buildRow(
                      label: 'START DATE',
                      right: _buildPill(_fmtDateShort(habit.startDate)),
                      onTap: _pickStartDate,
                    ),
                    _buildDivider(),

                    // 10. END DATE
                    // 10. END DATE
                    // 10. END DATE
                    // 10. END DATE
                    _buildRow(
                      label: 'END DATE',
                      right: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.habit.endDate != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _confirmDeleteEndDate,
                              child: const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: Icon(Icons.delete_outline, color: Colors.white, size: 20),
                              ),
                            ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 80),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                widget.habit.endDate != null
                                    ? _fmtDateShort(widget.habit.endDate!).toUpperCase()
                                    : '—',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: _pickEndDate,
                    ),
                    _buildDivider(),

                    // 11. ARCHIVE / UNARCHIVE
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          if (widget.habit.isArchived) {
                            widget.habit.isArchived = false;
                            widget.habit.archivedAt = null;
                          } else {
                            final now = DateTime.now();
                            widget.habit.archivedAt = DateTime(now.year, now.month, now.day);
                            widget.habit.isArchived = true;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            widget.habit.isArchived ? 'UNARCHIVE HABIT' : 'ARCHIVE HABIT',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildDivider(),

                    // 12. RESTART HABIT PROGRESS
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _restartHabitProgress, 
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            'RESTART HABIT PROGRESS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildDivider(),

                    // 13. DELETE HABIT
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _confirmDeleteHabit,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            'DELETE HABIT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildDivider(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Habit Bottom Sheet ───────────────────────────────────────────────────────

class _HabitBottomSheet extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  final DateTime selectedDay;
  final void Function(HabitState) onStateChanged;
  final void Function(String) onNoteChanged;
  final VoidCallback onDelete;
  // Optional: forwarded into EditHabitScreen so the Main Page (the widget
  // that opened this sheet) can rebuild live while Edit is still open.
  final VoidCallback? onHabitChanged;
  const _HabitBottomSheet({
    required this.habit,
    required this.allHabits,
    required this.selectedDay,
    required this.onStateChanged,
    required this.onNoteChanged,
    required this.onDelete,
    this.onHabitChanged,
  });
  @override State<_HabitBottomSheet> createState() => _HabitBottomSheetState();
}

class _HabitBottomSheetState extends State<_HabitBottomSheet> {
  late HabitState _state;
  late String _note;

  @override
  void initState() {
    super.initState();
    _state = widget.habit.stateOn(widget.selectedDay);
    _note = widget.habit.noteOn(widget.selectedDay);
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day}/${d.year % 100}';

  void _setState(HabitState s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(widget.selectedDay.year, widget.selectedDay.month, widget.selectedDay.day);
    if (target.isAfter(today)) return; // Future dates are read-only
    setState(() => _state = s);
    widget.onStateChanged(s);
  }

  Widget _statusBtn(HabitState s, Widget icon, String label) {
    final selected = _state == s;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setState(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(opacity: selected ? 1.0 : 0.35, child: icon),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _pendingIcon() {
    if (widget.habit.reminders.isNotEmpty) {
      return SizedBox(
        width: 26, height: 26,
        child: CustomPaint(painter: _ClockHandsPainter()),
      );
    }
    return Container(
      width: 26, height: 26,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
    );
  }

  Widget _doneIcon() => Container(
    width: 26, height: 26,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
    child: CustomPaint(painter: _BoldCheckPainter()),
  );

  Widget _failIcon() => Container(
    width: 26, height: 26,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
    child: CustomPaint(painter: _BoldCrossPainter()),
  );

  void _openNote() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _AddNoteDialog(
        initialNote: _note,
        onConfirm: (n) {
          setState(() => _note = n);
          widget.onNoteChanged(n);
        },
      ),
    );
  }

  void _skip() {
    _setState(HabitState.skipped);
    Navigator.pop(context);
  }

  void _openEdit() {
    // Capture the root navigator BEFORE closing this bottom sheet, since
    // this widget's context will be unmounted immediately after pop().
    final rootNav = Navigator.of(context, rootNavigator: true);
    // Close the Habit bottom sheet first so it is no longer part of the
    // navigation stack underneath the Edit page. This ensures that when
    // Back is pressed on the Edit page, it returns straight to the
    // already-alive Main Page instead of momentarily revealing the Habit
    // bottom sheet/navigation bar.
    Navigator.pop(context);
    rootNav.push(
      _noAnimationEditRoute(
        builder: (_) => EditHabitScreen(
          habit: widget.habit,
          allHabits: widget.allHabits,
          onDelete: widget.onDelete,
          onHabitChanged: widget.onHabitChanged,
        ),
      ),
    ).then((_) {
      widget.onHabitChanged?.call();
    });
  }

  String get _reminderText {
    if (widget.habit.reminders.isEmpty) return '';
    final times = widget.habit.reminders
        .where((r) => r.type != 'none')
        .map((r) => r.time)
        .toList();
    times.sort((a, b) {
      final ap = a.split(':'); final bp = b.split(':');
      final am = (int.tryParse(ap[0])??0)*60+(int.tryParse(ap.length>1?ap[1]:'0')??0);
      final bm = (int.tryParse(bp[0])??0)*60+(int.tryParse(bp.length>1?bp[1]:'0')??0);
      return am.compareTo(bm);
    });
    return times.join(' • ');
  }

  

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final dateStr = _fmtDate(widget.selectedDay);
    final reminderStr = _reminderText;
    final hasNote = _note.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(habit.title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              if (habit.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  habit.description.toUpperCase(),
                  style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final target = DateTime(widget.selectedDay.year, widget.selectedDay.month, widget.selectedDay.day);
            final isFuture = target.isAfter(today);
            return Opacity(
              opacity: isFuture ? 0.35 : 1.0,
              child: IgnorePointer(
                ignoring: isFuture,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IntrinsicHeight(child: Row(children: [
                    _statusBtn(HabitState.empty, _pendingIcon(), 'PENDING'),
                    Container(width: 0.5, color: Colors.white12),
                    _statusBtn(HabitState.done, _doneIcon(), 'DONE'),
                    Container(width: 0.5, color: Colors.white12),
                    _statusBtn(HabitState.failed, _failIcon(), 'FAIL'),
                  ])),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (reminderStr.isNotEmpty)
            Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'REMINDERS',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 18,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MarqueeText(
                        text: reminderStr,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openNote,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: hasNote
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('NOTE', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                          const SizedBox(height: 4),
                          Text(_note.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                        ],
                      )
                    : const Text('ADD NOTE...', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: const Text('SKIP', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
          ),
          Container(height: 0.5, color: Colors.white12),
          IntrinsicHeight(child: Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => HabitCalendarPage(
                        habit: widget.habit,
                        allHabits: widget.allHabits,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: const Center(child: Text('CALENDAR', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
              ),
            )),
            Container(width: 0.5, color: Colors.white12),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: const Center(child: Text('EDIT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
              ),
            )),
          ])),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─── Frequency Screen ─────────────────────────────────────────────────────────

class HabitFrequencyScreen extends StatefulWidget {
  final String category,startDate,title,description;
  final String? initialFrequency;
  final bool editMode;
  final Map<String,bool>? initialWeekDays;
  final Set<int>? initialMonthDays;
  final List<DateTime>? initialYearDays;
  final int? initialPeriodDays;
  final String? initialPeriodUnit;
  final int? initialRepeatEvery;
  final bool? initialFlexible;
  const HabitFrequencyScreen({super.key,required this.category,required this.startDate,required this.title,required this.description,this.initialFrequency,this.editMode=false,this.initialWeekDays,this.initialMonthDays,this.initialYearDays,this.initialPeriodDays,this.initialPeriodUnit,this.initialRepeatEvery,this.initialFlexible});
  @override State<HabitFrequencyScreen> createState() => _HabitFrequencyScreenState();
}

class _HabitFrequencyScreenState extends State<HabitFrequencyScreen> {
  String _sel='EVERY DAY';
  Map<String,bool> _wDays={'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false};
  Set<int> _mDays={};
  List<DateTime> _yDays=[];
  bool _showYPicker=false;
  bool _monthPicked=false, _dayPicked=false;
  int _pMonth=DateTime.now().month,_pDay=DateTime.now().day,_periodDays=1,_repeatEvery=1;
  String _periodUnit='WEEK';
  bool _showPDrop=false;
  bool _freqFlexible=false;
  static const _mNames=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];

  @override
  void initState() {
    super.initState();
    if (widget.initialFrequency != null && widget.initialFrequency!.isNotEmpty) {
      _sel = widget.initialFrequency!;
    }
    if (widget.initialWeekDays != null) {
      _wDays = Map.from(widget.initialWeekDays!);
    }
    if (widget.initialMonthDays != null) {
      _mDays = Set.from(widget.initialMonthDays!);
    }
    if (widget.initialYearDays != null) {
      _yDays = List.from(widget.initialYearDays!);
    }
    if (widget.initialPeriodDays != null) {
      _periodDays = widget.initialPeriodDays!;
    }
    if (widget.initialPeriodUnit != null) {
      _periodUnit = widget.initialPeriodUnit!;
    }
    if (widget.initialRepeatEvery != null) {
      _repeatEvery = widget.initialRepeatEvery!;
    }
    if (widget.initialFlexible != null) {
      _freqFlexible = widget.initialFlexible!;
    }
  }

  void _selectOption(String opt) {
  setState(() {
    _sel = opt;
    _showYPicker = false;
    _showPDrop = false;
    _monthPicked = false;
    _dayPicked = false;
    if (!widget.editMode) {
      _wDays = {'MONDAY': false, 'TUESDAY': false, 'WEDNESDAY': false, 'THURSDAY': false, 'FRIDAY': false, 'SATURDAY': false, 'SUNDAY': false};
      _mDays = {};
      _yDays = [];
      _periodDays = 1;
      _periodUnit = 'WEEK';
      _repeatEvery = 1;
      _freqFlexible = false;
    }
  });
}

  Widget _radio(String opt){
    final sel=_sel==opt;
    return GestureDetector(onTap:()=>_selectOption(opt),child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
      Container(width:22,height:22,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white,width:2),color:sel?Colors.white:Colors.transparent),child:sel?Center(child:Container(width:8,height:8,decoration:const BoxDecoration(shape:BoxShape.circle,color:Colors.black))):null),
      const SizedBox(width:12),
      Text(opt,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.3,decoration:TextDecoration.none)),
    ])));
  }

  Widget _wDaysUI(){
    final days=_wDays.keys.toList();final rows=<Widget>[];
    for(int i=0;i<days.length;i+=3){
      final rDays=days.sublist(i,i+3>days.length?days.length:i+3);
      while(rDays.length<3)rDays.add('');
      rows.add(Padding(padding:const EdgeInsets.only(bottom:12,left:32),child:Row(children:rDays.map((d){
        if(d.isEmpty)return const Expanded(child:SizedBox());
        final chk=_wDays[d]!;
        return Expanded(child:GestureDetector(onTap:()=>setState(()=>_wDays[d]=!chk),child:Row(mainAxisSize:MainAxisSize.min,children:[Container(width:20,height:20,decoration:BoxDecoration(border:Border.all(color:Colors.white,width:1.5),color:chk?Colors.white:Colors.transparent),child:chk?const Icon(Icons.check,size:14,color:Colors.black):null),const SizedBox(width:8),Text(d,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w700,letterSpacing:0.3))])));
      }).toList())));
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:rows);
  }

  Widget _mDaysUI(){
    final all=[...List.generate(31,(i)=>i+1),0];final rows=<Widget>[];
    for(int i=0;i<all.length;i+=7){
      final ri=all.sublist(i,i+7>all.length?all.length:i+7);while(ri.length<7)ri.add(-1);
      rows.add(Padding(padding:const EdgeInsets.only(bottom:8),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:ri.map((d){
        if(d==-1)return const SizedBox(width:36,height:36);
        final isL=d==0;final sel=_mDays.contains(d);
        return GestureDetector(onTap:()=>setState(()=>sel?_mDays.remove(d):_mDays.add(d)),child:Container(width:isL?52:36,height:36,decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),color:sel?Colors.white:Colors.transparent,border:Border.all(color:sel?Colors.white:Colors.transparent,width:2)),child:Center(child:Text(isL?'Last':'$d',style:TextStyle(color:sel?Colors.black:Colors.white,fontSize:isL?13:15,fontWeight:sel?FontWeight.w800:FontWeight.w400)))));
      }).toList())));
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:rows);
  }


  Widget _mDaysFlexibleUI() {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 12, bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _freqFlexible = !_freqFlexible),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: _freqFlexible ? Colors.white : Colors.transparent,
              ),
              child: _freqFlexible
                  ? const Center(child: Icon(Icons.check, color: Colors.black, size: 14))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('FLEXIBLE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3, decoration: TextDecoration.none)),
                  SizedBox(height: 2),
                  Text('It will be shown each day until completed', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500, decoration: TextDecoration.none)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yDaysUI(){
    const double rowH = 44.0;
    const int maxVisible = 4;

    Widget plusBtn = GestureDetector(
      onTap: () => setState(() {
        _pMonth = DateTime.now().month;
        _pDay = DateTime.now().day;
        _monthPicked = false;
        _dayPicked = false;
        _showYPicker = true;
      }),
      child: Container(
        width: 36, height: 36,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Icon(Icons.add, color: Colors.black, size: 20),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_yDays.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 8),
          child: Row(children: [
            const Text('SELECT AT LEAST ONE DAY', style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(width: 8),
            plusBtn,
          ]),
        )
      else
        SizedBox(
          height: _yDays.length > maxVisible ? rowH * maxVisible : rowH * _yDays.length,
          child: Row(children: [
            Expanded(
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(Colors.white70),
                  trackColor: WidgetStateProperty.all(Colors.white24),
                  trackBorderColor: WidgetStateProperty.all(Colors.transparent),
                  thickness: WidgetStateProperty.all(4),
                  radius: const Radius.circular(2),
                  thumbVisibility: WidgetStateProperty.all(true),
                  trackVisibility: WidgetStateProperty.all(true),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(left: 32, right: 12),
                    itemCount: _yDays.length,
                    itemExtent: rowH,
                    itemBuilder: (ctx, i) {
                      final d = _yDays[i];
                      return SizedBox(
                        height: rowH,
                        child: Row(children: [
                          Text('${_mNames[d.month-1]} ${d.day}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _yDays.removeAt(i)),
                            child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Center(child: plusBtn),
          ]),
        ),

      if (_showYPicker)
        Container(
          margin: const EdgeInsets.only(left: 32, top: 8, bottom: 8),
          decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: Text('SELECT A DATE', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1))),
                const SizedBox(height: 12),
                SizedBox(height: 100, child: Row(children: [
                  Expanded(flex: 2, child: ListWheelScrollView.useDelegate(
                    itemExtent: 32,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => setState(() {
                      _pMonth = i + 1;
                      _monthPicked = true;
                    }),
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (c, i) => Center(child: Text(
                        _mNames[i],
                        style: TextStyle(
                          color: (_monthPicked && _pMonth == i + 1) ? Colors.white : Colors.white38,
                          fontSize: 14,
                          fontWeight: (_monthPicked && _pMonth == i + 1) ? FontWeight.w700 : FontWeight.w400,
                        ),
                      )),
                      childCount: 12,
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: ListWheelScrollView.useDelegate(
                    itemExtent: 32,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => setState(() {
                      _pDay = i + 1;
                      _dayPicked = true;
                    }),
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (c, i) => Center(child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: (_dayPicked && _pDay == i + 1) ? Colors.white : Colors.white38,
                          fontSize: 14,
                          fontWeight: (_dayPicked && _pDay == i + 1) ? FontWeight.w700 : FontWeight.w400,
                        ),
                      )),
                      childCount: 31,
                    ),
                  )),
                ])),
                const SizedBox(height: 12),
              ]),
            ),
            Container(height: 1, color: Colors.white24),
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _showYPicker = false;
                  _monthPicked = false;
                  _dayPicked = false;
                }),
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('CANCEL', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
              )),
              Container(width: 1, color: Colors.white24),
              Expanded(child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!_monthPicked || !_dayPicked) {
                    showDialog(context: context, builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF2C2C2C),
                      title: const Text('Select at least one day', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.white)))],
                    ));
                    return;
                  }
                  final newDate = DateTime(2000, _pMonth, _pDay);
                  final isDuplicate = _yDays.any((d) => d.month == newDate.month && d.day == newDate.day);
                  if (isDuplicate) {
                    showDialog(context: context, builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF2C2C2C),
                      title: const Text('Duplicate Date', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      content: Text('${_mNames[_pMonth - 1]} $_pDay already exists and cannot be added again.', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.white)))],
                    ));
                  } else {
                    setState(() {
                      _yDays.add(newDate);
                      _showYPicker = false;
                      _monthPicked = false;
                      _dayPicked = false;
                    });
                  }
                },
                child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('OK', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
              )),
            ])),
          ]),
        ),
    ]);
  }

  Widget _periodUI() {
    int _maxForUnit() {
      if (_periodUnit == 'WEEK') return 7;
      if (_periodUnit == 'MONTH') return 28;
      return 365;
    }

    void _validateAndSet(String v) {
    final n = int.tryParse(v);
    if (n != null && n > 0) setState(() => _periodDays = n);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Number input ──
          SizedBox(
            width: 44,
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.only(bottom: 2),
                border: InputBorder.none,
              ),
              controller: TextEditingController(text: '$_periodDays')
                ..selection =
                    TextSelection.collapsed(offset: '$_periodDays'.length),
              onChanged: _validateAndSet,
            ),
          ),
          const SizedBox(width: 12),
          // ── "DAYS PER" label ──
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'DAYS PER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Unit selector + dropdown stacked in its own Column ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The trigger row: WEEK ▼
              GestureDetector(
                onTap: () => setState(() => _showPDrop = !_showPDrop),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _periodUnit,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 22,
                    ),
                  ],
                ),
              ),
              // The dropdown options — appear directly below the trigger
              if (_showPDrop)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: ['WEEK', 'MONTH', 'YEAR']
                        .where((u) => u != _periodUnit)
                        .map((u) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          _periodUnit = u;
                          _showPDrop = false;
                          final max =
                              u == 'WEEK' ? 7 : u == 'MONTH' ? 28 : 365;
                          if (_periodDays > max) _periodDays = max;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            u,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repeatUI(){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Interval row: EVERY [n] DAYS
        Padding(
          padding: const EdgeInsets.only(left: 48, top: 8, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('EVERY', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: Colors.white),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.only(bottom: 2), border: InputBorder.none),
                  controller: TextEditingController(text: '$_repeatEvery')..selection = TextSelection.collapsed(offset: '$_repeatEvery'.length),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) setState(() => _repeatEvery = n);
                  },
                ),
              ),
              const SizedBox(width: 12),
              const Text('DAYS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ],
          ),
        ),
        // Flexible option row
        Padding(
          padding: const EdgeInsets.only(left: 32, top: 12, bottom: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _freqFlexible = !_freqFlexible),
            child: Row(
              children: [
                // Selection circle
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    color: _freqFlexible ? Colors.white : Colors.transparent,
                  ),
                  child: _freqFlexible
                      ? const Center(child: Icon(Icons.check, color: Colors.black, size: 14))
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('FLEXIBLE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3, decoration: TextDecoration.none)),
                    SizedBox(height: 2),
                    Text('It will be shown each day until completed', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500, decoration: TextDecoration.none)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _alert(String msg){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:Text(msg,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));}

  @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── All padded content ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PREFERRED FREQUENCY?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _radio('EVERY DAY'),
                              _radio('SPECIFIC DAYS OF THE WEEK'),
                              if (_sel == 'SPECIFIC DAYS OF THE WEEK') _wDaysUI(),
                              _radio('SPECIFIC DAYS OF THE MONTH'),
                              if (_sel == 'SPECIFIC DAYS OF THE MONTH') _mDaysUI(),
                              if (_sel == 'SPECIFIC DAYS OF THE MONTH') _mDaysFlexibleUI(),
                              _radio('SPECIFIC DAYS OF THE YEAR'),
                              if (_sel == 'SPECIFIC DAYS OF THE YEAR') _yDaysUI(),
                              _radio('SOME DAYS PER PERIOD'),
                              if (_sel == 'SOME DAYS PER PERIOD') _periodUI(),
                              _radio('REPEAT'),
                              if (_sel == 'REPEAT') _repeatUI(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Non-editMode: BACK / dots / NEXT ──
                      if (!widget.editMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context, null),
                                child: const Text(
                                  'BACK',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Row(children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38, width: 1),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38, width: 1),
                                  ),
                                ),
                              ]),
                              GestureDetector(
                                onTap: () async {
                                  if (_sel == 'SPECIFIC DAYS OF THE WEEK' && !_wDays.values.any((v) => v)) {
                                    _alert('Select at least one day');
                                    return;
                                  }
                                  if (_sel == 'SPECIFIC DAYS OF THE MONTH' && _mDays.isEmpty) {
                                    _alert('Select at least one day');
                                    return;
                                  }
                                  if (_sel == 'SPECIFIC DAYS OF THE YEAR' && _yDays.isEmpty) {
                                    _alert('Select at least one day');
                                    return;
                                  }
                                  if (_sel == 'SOME DAYS PER PERIOD') {
                                    final max = _periodUnit == 'WEEK' ? 7 : _periodUnit == 'MONTH' ? 28 : 365;
                                    if (_periodDays > max) {
                                      _alert('enter a frequency less than or equal to $max');
                                      return;
                                    }
                                  }
                                  if (_sel == 'REPEAT') {
                                    if (_repeatEvery <= 1) {
                                      _alert('ENTER A FREQUENCY GREATER THAN 1');
                                      return;
                                    }
                                    if (_repeatEvery > 365) {
                                      _alert('enter a frequency less than or equal to 365');
                                      return;
                                    }
                                  }
                                  final res = await Navigator.push<HabitScheduleResult>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _ScheduleScreen(
                                        category: widget.category,
                                        title: widget.title,
                                        description: widget.description,
                                        frequency: _sel,
                                        initialStartDate: widget.startDate,
                                      ),
                                    ),
                                  );
                                  if (res != null && context.mounted) {
                                    final enriched = HabitScheduleResult(
                                      title: res.title,
                                      description: res.description,
                                      category: res.category,
                                      startDate: res.startDate,
                                      frequency: res.frequency,
                                      endDate: res.endDate,
                                      priority: res.priority,
                                      reminders: res.reminders,
                                      freqWeekDays: Map.from(_wDays),
                                      freqMonthDays: Set.from(_mDays),
                                      freqYearDays: List.from(_yDays),
                                      freqPeriodDays: _periodDays,
                                      freqPeriodUnit: _periodUnit,
                                      freqRepeatEvery: _repeatEvery,
                                      freqFlexible: _freqFlexible,
                                    );
                                    Navigator.pop(context, enriched);
                                  }
                                },
                                child: const Text(
                                  'NEXT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── EditMode bottom row: outside all padding for true edge-to-edge ──
              if (widget.editMode) ...[
                // Full-width top divider — no padding on either side
                Container(height: 0.5, color: Colors.white24),
                // Full-width Close | Confirm row
                IntrinsicHeight(
                  child: Row(
                    children: [
                      // ── LEFT: CLOSE ──
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context, null),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: const Center(
                              child: Text(
                                'CLOSE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── Vertical divider ──
                      Container(width: 0.5, color: Colors.white24),
                      // ── RIGHT: CONFIRM ──
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
  if (_sel == 'SPECIFIC DAYS OF THE WEEK' && !_wDays.values.any((v) => v)) {
    _alert('Select at least one day');
    return;
  }
  if (_sel == 'SPECIFIC DAYS OF THE MONTH' && _mDays.isEmpty) {
    _alert('Select at least one day');
    return;
  }
  if (_sel == 'SPECIFIC DAYS OF THE YEAR' && _yDays.isEmpty) {
    _alert('Select at least one day');
    return;
  }
  if (_sel == 'SOME DAYS PER PERIOD') {
    final max = _periodUnit == 'WEEK' ? 7 : _periodUnit == 'MONTH' ? 28 : 365;
    if (_periodDays > max) {
      _alert('enter a frequency less than or equal to $max');
      return;
    }
  }
  if (_sel == 'REPEAT') {
    if (_repeatEvery <= 1) {
      _alert('ENTER A FREQUENCY GREATER THAN 1');
      return;
    }
    if (_repeatEvery > 365) {
      _alert('enter a frequency less than or equal to 365');
      return;
    }
  }
  Navigator.pop(
    context,
    _FrequencyEditResult(
      frequency: _sel,
      weekDays: Map.from(_wDays),
      monthDays: Set.from(_mDays),
      yearDays: List.from(_yDays),
      periodDays: _periodDays,
      periodUnit: _periodUnit,
      repeatEvery: _repeatEvery,
      flexible: _freqFlexible,
    ),
  );
},
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: const Center(
                              child: Text(
                                'CONFIRM',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
}

// ─── Schedule Screen ──────────────────────────────────────────────────────────

class _ScheduleScreen extends StatefulWidget {
  final String category,title,description,frequency,initialStartDate;
  const _ScheduleScreen({required this.category,required this.title,required this.description,required this.frequency,required this.initialStartDate});
  @override State<_ScheduleScreen> createState() => _ScheduleScreenState();
}
class _ScheduleScreenState extends State<_ScheduleScreen> {
  late DateTime _start;bool _startIsToday=true,_endEnabled=false;DateTime? _end;
  final TextEditingController _dCtrl=TextEditingController(text:'60');
  final List<ReminderEntry> _reminders=[];int _priority=1;
  @override void initState(){super.initState();final p=DateTime.tryParse(widget.initialStartDate)??DateTime.now();_start=p;final n=DateTime.now();_startIsToday=p.year==n.year&&p.month==n.month&&p.day==n.day;_end=_start.add(const Duration(days:59));}
  @override void dispose(){_dCtrl.dispose();super.dispose();}
  String _fmt(DateTime d)=>'${d.month}/${d.day}/${d.year%100}';
  String _lbl()=>_fmt(_start);
  DateTime _compEnd(){final parsed=int.tryParse(_dCtrl.text);final n=(parsed==null||parsed<=0)?1:parsed;return _start.add(Duration(days:n-1));}
  Widget _pill(String l)=>Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:6),decoration:BoxDecoration(color:const Color(0xFF2C2C2C),borderRadius:BorderRadius.circular(20)),child:Text(l,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700,letterSpacing:0.3)));
  Widget _row(String l, Widget r, {VoidCallback? onRowTap}) {
  final inner = Column(children:[Container(height:0.5,color:Colors.white12),Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(l,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800,letterSpacing:0.3)),r]))]);
  if (onRowTap != null) {
    return GestureDetector(behavior:HitTestBehavior.opaque,onTap:onRowTap,child:inner);
  }
  return inner;
}
  Future<void> _pickS()async{final p=await showDatePicker(context:context,initialDate:_start,firstDate:DateTime(2000),lastDate:DateTime(2100),builder:(c,ch)=>Theme(data:ThemeData.dark().copyWith(colorScheme:const ColorScheme.dark(primary:Colors.white,onPrimary:Colors.black,surface:Color(0xFF2C2C2C),onSurface:Colors.white)),child:ch!));if(p!=null){setState((){_start=p;final n=DateTime.now();_startIsToday=p.year==n.year&&p.month==n.month&&p.day==n.day;_end=_compEnd();});}}
  Future<void> _pickE()async{final p=await showDatePicker(context:context,initialDate:_end??_start.add(const Duration(days:60)),firstDate:_start,lastDate:DateTime(2100),builder:(c,ch)=>Theme(data:ThemeData.dark().copyWith(colorScheme:const ColorScheme.dark(primary:Colors.white,onPrimary:Colors.black,surface:Color(0xFF2C2C2C),onSurface:Colors.white)),child:ch!));if(p!=null){setState((){_end=p;_dCtrl.text='${p.difference(_start).inDays}';});}}
  void _showR(){showDialog(context:context,barrierColor:Colors.black54,builder:(_)=>_RemindersModal(reminders:_reminders,onChanged:(u)=>setState((){_reminders.clear();_reminders.addAll(u);})));}
  void _showP(){showDialog(context:context,barrierColor:Colors.black54,builder:(_)=>_PriorityModal(priority:_priority,onChanged:(v)=>setState(()=>_priority=v)));}

  @override
  Widget build(BuildContext context){
    final ed=_end!=null?_fmt(_end!):_fmt(_compEnd());
    return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,32,24,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('WHEN DO YOU WANT\nTO DO IT?',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:0.5,height:1.2)),
      const SizedBox(height:28),
      _row('START DATE',GestureDetector(onTap:_pickS,child:_pill(_lbl())),onRowTap:_pickS),
      _row('END DATE',Switch(value:_endEnabled,onChanged:(v)=>setState((){_endEnabled=v;if(v)_end=_compEnd();}),activeColor:Colors.white,activeTrackColor:const Color(0xFF555555),inactiveThumbColor:Colors.white38,inactiveTrackColor:const Color(0xFF333333)),onRowTap:()=>setState((){_endEnabled=!_endEnabled;if(_endEnabled)_end=_compEnd();})),
      if(_endEnabled)...[Container(height:0.5,color:Colors.white12),Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[GestureDetector(onTap:_pickE,child:_pill(ed)),const SizedBox(width:16),SizedBox(width:80,child:TextField(controller:_dCtrl,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.symmetric(vertical:2),border:InputBorder.none),onChanged:(v){final parsed=int.tryParse(v);final n=(parsed==null||parsed<=0)?1:parsed;setState(()=>_end=_start.add(Duration(days:n-1)));})),const SizedBox(width:16),const Text('DAYS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5))]))],
      _row('TIME AND REMINDERS',GestureDetector(onTap:_showR,child:Container(width:32,height:32,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:Center(child:Text('${_reminders.length}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700))))),onRowTap:_showR),
      _row('PRIORITY',GestureDetector(onTap:_showP,child:_pill(_priority==1?'DEFAULT':'${_priority}🏳')),onRowTap:_showP),
      const Spacer(),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        GestureDetector(onTap:()=>Navigator.pop(context,null),child:const Text('BACK',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
        Row(children:[Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1)))]),
        GestureDetector(onTap:(){
  if(_endEnabled){
    final sd=DateTime(_start.year,_start.month,_start.day);
    final ee=_end??DateTime.now();
    final ed2=DateTime(ee.year,ee.month,ee.day);
    final minValidEnd=sd;
    if(!ed2.isAfter(minValidEnd)){
      showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:const Text('END DATE MUST BE AFTER START DATE',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));
      return;
    }
  }
  Navigator.pop(context,HabitScheduleResult(title:widget.title,description:widget.description,category:widget.category,startDate:_start.toIso8601String(),frequency:widget.frequency,endDate:_endEnabled&&_end!=null?_end!.toIso8601String():'',priority:_priority,reminders:List.from(_reminders)));
},child:const Text('SAVE',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5)))
      ]),
    ]))));
  }
}

// ─── Habit Detail Screen ──────────────────────────────────────────────────────

class HabitDetailScreen extends StatefulWidget {
  final String category,startDate;
  const HabitDetailScreen({super.key,required this.category,required this.startDate});
  @override State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}
class _HabitDetailScreenState extends State<HabitDetailScreen> {
  final _n=TextEditingController(),_d=TextEditingController();
  @override void dispose(){_n.dispose();_d.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,32,24,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('DEFINE YOUR HABIT',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:1)),
      const SizedBox(height:40),
      const Text('HABIT NAME', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller:_n,autofocus:true,textCapitalization:TextCapitalization.characters,onChanged:(v){final u=v.toUpperCase();if(v!=u){_n.value=TextEditingValue(text:u,selection:TextSelection.collapsed(offset:u.length));}},style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),decoration:const InputDecoration(hintText:'HABIT',hintStyle:TextStyle(color:Colors.white38,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white24,width:1)),focusedBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white,width:1)))),
      const SizedBox(height:28),
      const Text('HABIT DESCRIPTION (OPTIONAL)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller:_d,textCapitalization:TextCapitalization.characters,maxLines:null,maxLength:550,maxLengthEnforcement:MaxLengthEnforcement.enforced,onChanged:(v){final u=v.toUpperCase();if(v!=u){_d.value=TextEditingValue(text:u,selection:TextSelection.collapsed(offset:u.length));}},style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),decoration:const InputDecoration(hintText:'DESCRIPTION (OPTIONAL)',hintStyle:TextStyle(color:Colors.white38,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white24,width:1)),focusedBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white,width:1)),counterStyle:TextStyle(color:Colors.white38,fontSize:11,fontWeight:FontWeight.w600))),
      const Spacer(),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        GestureDetector(onTap:()=>Navigator.pop(context,null),child:const Text('BACK',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
        Row(children:[Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.transparent,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1))),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.transparent,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1)))]),
        GestureDetector(onTap:()async{
          final name=_n.text.trim();
          if(name.isEmpty){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:const Text('Enter a name',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));return;}
          final res=await Navigator.push<HabitScheduleResult>(context,MaterialPageRoute(builder:(_)=>HabitFrequencyScreen(category:widget.category,startDate:widget.startDate,title:name,description:_d.text.trim())));
          if(res!=null&&context.mounted)Navigator.pop(context,res);
        },child:const Text('NEXT',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
      ]),
    ]))));
  }
}

// ─── Category Selection Screen ────────────────────────────────────────────────

// ─── Category Selection Screen ────────────────────────────────────────────────

class CategorySelectionScreen extends StatefulWidget {
  final String habitTitle, startDate;
  const CategorySelectionScreen({super.key, required this.habitTitle, this.startDate = ''});
  @override
  State<CategorySelectionScreen> createState() => _CategorySelectionScreenState();
}

class _BoldPlusPainter extends CustomPainter {
  final Color color;
  const _BoldPlusPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      paint,
    );
  }
  @override
  bool shouldRepaint(_BoldPlusPainter o) => o.color != color;
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final _scrollCtrl = ScrollController();
  List<String> _customSnapshot = CategoryStore.custom;
  static const _defaultCats = ['MEDITATION', 'SPORT', 'ENTERTAINMENT', 'ART', 'STUDY', 'QUIT A BAD HABIT'];
  static const int _maxVisibleCategories = 10;
  static const double _rowHeight = 54.0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _row(BuildContext context, String c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (c == 'CREATE CATEGORY') {
          showModalBottomSheet<String>(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            useRootNavigator: true,
            builder: (_) => _NewCategorySheet(existingCustom: List.from(CategoryStore.custom)),
          ).then((name) async {
            if (name == null || !context.mounted) return;
            await CategoryStore.add(name);
            if (!context.mounted) return;
            setState(() => _customSnapshot = CategoryStore.custom);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: const Color(0xFF2C2C2C),
                  insetPadding: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Center(child: Text('CATEGORY CREATED', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
                      ),
                      Container(height: 0.5, color: Colors.white24),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Center(child: Text('OK', textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
                      ),
                    ]),
                  ),
                ),
              );
            });
            final res = await Navigator.push<HabitScheduleResult>(
              context,
              MaterialPageRoute(builder: (_) => HabitDetailScreen(category: name, startDate: widget.startDate)),
            );
            if (!context.mounted) return;
            if (false)
            await showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: const Color(0xFF2C2C2C),
                insetPadding: const EdgeInsets.symmetric(horizontal: 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Center(child: Text('CATEGORY CREATED', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
                    ),
                    Container(height: 0.5, color: Colors.white24),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                        child: const Center(child: Text('OK', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))),
                    ),
                  ]),
                ),
              ),
            );
            if (res != null && context.mounted) Navigator.pop(context, res);
          });
          return;
        }
        final res = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(builder: (_) => HabitDetailScreen(category: c, startDate: widget.startDate)),
        );
        if (res != null && context.mounted) Navigator.pop(context, res);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: c == 'CREATE CATEGORY'
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  const SizedBox(width: 12),
                  Transform.translate(
                    offset: const Offset(_kCreateCategoryIconOffsetX, _kCreateCategoryIconOffsetY),
                    child: Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 3.0),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CustomPaint(painter: _BoldPlusPainter(Colors.white54)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Text(c, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      ..._customSnapshot,
      ..._defaultCats,
      'CREATE CATEGORY',
    ];

    final bool needsScroll = categories.length > _maxVisibleCategories;
    final double listHeight = needsScroll
        ? _rowHeight * _maxVisibleCategories
        : _rowHeight * categories.length;

    final Widget categoryList = needsScroll
        ? SizedBox(
            height: listHeight,
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(Colors.white54),
                trackColor: WidgetStateProperty.all(Colors.white12),
                trackBorderColor: WidgetStateProperty.all(Colors.transparent),
                thickness: WidgetStateProperty.all(4),
                radius: const Radius.circular(2),
                thumbVisibility: WidgetStateProperty.all(true),
                trackVisibility: WidgetStateProperty.all(true),
              ),
              child: Scrollbar(
                controller: _scrollCtrl,
                thumbVisibility: true,
                trackVisibility: true,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: categories.length,
                  itemExtent: _rowHeight,
                  itemBuilder: (ctx, i) => _row(ctx, categories[i]),
                ),
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: categories.map((c) => _row(context, c)).toList(),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SELECT A CATEGORY FOR YOUR HABIT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  const SizedBox(height: 32),
                  categoryList,
                  if (needsScroll) const Spacer(),
                ],
              ),
            ),
            Positioned(
              left: 24,
              bottom: 24,
              child: GestureDetector(
                onTap: () => Navigator.pop(context, null),
                child: const Text('BACK', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Start Date Modal ─────────────────────────────────────────────────────────

class StartDateModal extends StatelessWidget {
  final DateTime selectedDate;
  const StartDateModal({super.key,required this.selectedDate});
  String _fmt(DateTime d){const m=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];return '${m[d.month-1]} ${d.day}, ${d.year}';}
  // REPLACE WITH
  Future<void> _nav(BuildContext ctx,DateTime sd)async{
    final res=await Navigator.push<dynamic>(ctx,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:sd.toIso8601String())));
    if(!ctx.mounted)return;
    if(res is HabitScheduleResult)Navigator.pop(ctx,res);
    else if(res is String)Navigator.pop(ctx,HabitScheduleResult(title:res,description:'',category:res,startDate:sd.toIso8601String(),frequency:'',endDate:'',priority:1,reminders:[]));
    else Navigator.pop(ctx,null);
  }
  @override
  Widget build(BuildContext context){
    return Dialog(backgroundColor:Colors.transparent,insetPadding:const EdgeInsets.symmetric(horizontal:32),child:Container(decoration:BoxDecoration(color:const Color(0xFF2C2C2C),borderRadius:BorderRadius.circular(16)),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:const Center(child:Text('START DATE',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w700,letterSpacing:0.5)))),
      GestureDetector(onTap:()=>_nav(context,selectedDate),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:Center(child:Text(_fmt(selectedDate),style:const TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
      GestureDetector(onTap:()=>_nav(context,DateTime.now()),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:const Center(child:Text('TODAY',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
      GestureDetector(onTap:()=>Navigator.pop(context,null),behavior:HitTestBehavior.opaque,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),child:const Center(child:Text('CLOSE',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
    ])));
  }
}


// ─── Start Date Picker Modal (returns DateTime, no internal navigation) ────────

class _StartDatePickerModal extends StatelessWidget {
  final DateTime selectedDate;
  const _StartDatePickerModal({required this.selectedDate});
  String _fmt(DateTime d){const m=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];return '${m[d.month-1]} ${d.day}, ${d.year}';}
  @override
  Widget build(BuildContext context){
    return Dialog(backgroundColor:Colors.transparent,insetPadding:const EdgeInsets.symmetric(horizontal:32),child:Container(decoration:BoxDecoration(color:const Color(0xFF2C2C2C),borderRadius:BorderRadius.circular(16)),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:const Center(child:Text('START DATE',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w700,letterSpacing:0.5)))),
      GestureDetector(onTap:()=>Navigator.pop(context,selectedDate),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:Center(child:Text(_fmt(selectedDate),style:const TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
      GestureDetector(onTap:()=>Navigator.pop(context,DateTime.now()),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.black,width:1))),child:const Center(child:Text('TODAY',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
      GestureDetector(onTap:()=>Navigator.pop(context,null),behavior:HitTestBehavior.opaque,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),child:const Center(child:Text('CLOSE',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w600,letterSpacing:0.3))))),
    ])));
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);
  @override
  void paint(Canvas c, Size s) {
    final center=Offset(s.width/2,s.height/2);
    final r=(s.width/2)-1.5;
    c.drawCircle(center,r,Paint()..color=Colors.white.withValues(alpha:0.14)..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
    if(progress<=0)return;
    c.drawArc(Rect.fromCircle(center:center,radius:r),-math.pi/2,2*math.pi*progress.clamp(0.0,1.0),false,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
  }
  @override bool shouldRepaint(_RingPainter o)=>o.progress!=progress;
}

// ─── Habit Animated List ──────────────────────────────────────────────────────

class _HabitAnimatedList extends StatefulWidget {
  final List<Habit> habits;
  final DateTime selectedDay;
  final Widget? Function(Habit) buildReminderIcon;
  final String? Function(Habit) earliestReminderTime;
  final Widget Function(HabitState, bool hasReminders) buildStatusIcon;
  final void Function(String) onTap;
  final void Function(String) onDismiss;
  final void Function(String) onLongPress;
  final VoidCallback? onNeedsRefresh;
  const _HabitAnimatedList({
    required this.habits,
    required this.selectedDay,
    required this.buildReminderIcon,
    required this.earliestReminderTime,
    required this.buildStatusIcon,
    required this.onTap,
    required this.onDismiss,
    required this.onLongPress,
    this.onNeedsRefresh,
  });
  @override State<_HabitAnimatedList> createState() => _HabitAnimatedListState();
}

class _HabitAnimatedListState extends State<_HabitAnimatedList> {
  static const double _editRevealWidth = 90.0;
  final _key=GlobalKey<AnimatedListState>();
  late List<Habit> _cur;
  static const _dur=Duration(milliseconds:400);

  @override void initState(){super.initState();_cur=List.from(widget.habits);}

  @override
  void didUpdateWidget(_HabitAnimatedList old){
    super.didUpdateWidget(old);
    for(int i=0;i<_cur.length;i++){
      final idx=widget.habits.indexWhere((h)=>h.id==_cur[i].id);
      if(idx!=-1)_cur[i]=widget.habits[idx];
    }
    if(_sameOrder(_cur,widget.habits))return;
    _sync(widget.habits);
  }

  bool _sameOrder(List<Habit> a,List<Habit> b){
    if(a.length!=b.length)return false;
    for(int i=0;i<a.length;i++)if(a[i].id!=b[i].id)return false;
    return true;
  }

  void _sync(List<Habit> next){
    final newIds=next.map((h)=>h.id).toList();
    for(int i=_cur.length-1;i>=0;i--){
      if(!newIds.contains(_cur[i].id)){
        final h=_cur.removeAt(i);
        _key.currentState?.removeItem(i,(ctx,anim)=>_animated(h,anim,leaving:true),duration:_dur);
      }
    }
    for(int ni=0;ni<next.length;ni++){
      if(!_cur.any((h)=>h.id==next[ni].id)){
        final insertAt=ni.clamp(0,_cur.length);
        _cur.insert(insertAt,next[ni]);
        _key.currentState?.insertItem(insertAt,duration:_dur);
      }
    }
    for(int ni=0;ni<newIds.length;ni++){
      final ci=_cur.indexWhere((h)=>h.id==newIds[ni]);
      if(ci==-1||ci==ni)continue;
      final movingDown=ci<ni;
      final h=_cur.removeAt(ci);
      _key.currentState?.removeItem(ci,(ctx,anim)=>_animated(h,anim,leaving:true,movingDown:movingDown),duration:_dur);
      final insertAt=ni.clamp(0,_cur.length);
      _cur.insert(insertAt,h);
      _key.currentState?.insertItem(insertAt,duration:_dur);
    }
  }

  Widget _row(Habit habit){
    final icon=widget.buildReminderIcon(habit);
    final time=widget.earliestReminderTime(habit);
    final state=habit.stateOn(widget.selectedDay);
    final hasReminders = habit.reminders.isNotEmpty;
    return Container(
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _editRevealWidth,
            child: Container(
              alignment: Alignment.centerRight,
              color: const Color(0xFF3A3A3A),
              padding: const EdgeInsets.only(right: 28),
              child: const Align(
                alignment: Alignment.centerRight,
                child: Text('EDIT', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          _SwipeEditRow(
            habit: habit,
            allHabits: widget.onLongPress == null ? const [] : [],
            maxReveal: _editRevealWidth,
            onNeedsRefresh: widget.onNeedsRefresh,
            child: GestureDetector(
              onTap: () => widget.onTap(habit.id),
              onLongPress: () => widget.onLongPress(habit.id),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: const BoxDecoration(color: Colors.black, border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5))), child: Row(children: [
          Text(habit.title.toUpperCase(),style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,letterSpacing:0.3)),
          if(habit.priority>1)...[const SizedBox(width:6),Text('${habit.priority}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),const SizedBox(width:2),const Icon(Icons.flag,color:Colors.white,size:14)],
          if(icon!=null)...[const SizedBox(width:6),icon,if(time!=null)...[const SizedBox(width:4),Text(time,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w600))]],
          if(icon==null&&time!=null)...[const SizedBox(width:6),Text(time,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w600))],
          const Spacer(),
          const SizedBox(width: 16),
          widget.buildStatusIcon(state, hasReminders),
          const SizedBox(width: 18),
        ])),
      ),
      )],
      ),
    );
  }

  Widget _animated(Habit h,Animation<double> anim,{bool leaving=false,bool movingDown=false}){
    final double beginY=leaving?(movingDown?-0.5:0.5):(movingDown?0.5:-0.5);
    final double endY=leaving?(movingDown?-0.5:0.5):0.0;
    final slide=Tween<Offset>(begin:Offset(0,beginY),end:Offset(0,endY)).animate(CurvedAnimation(parent:anim,curve:leaving?Curves.easeIn:Curves.easeOut));
    return SizeTransition(sizeFactor:anim,axisAlignment:-1,child:FadeTransition(opacity:anim,child:SlideTransition(position:slide,child:_row(h))));
  }

  @override
  Widget build(BuildContext context){
    return AnimatedList(
      key:_key,
      padding:const EdgeInsets.symmetric(horizontal:20,vertical:8),
      initialItemCount:_cur.length,
      itemBuilder:(ctx,i,anim)=>_animated(_cur[i],anim),
    );
  }
}

class _SwipeEditRow extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  final Widget child;
  final double maxReveal;
  final VoidCallback? onNeedsRefresh;
  const _SwipeEditRow({required this.habit, required this.allHabits, required this.child, this.maxReveal = 90.0, this.onNeedsRefresh});
  @override State<_SwipeEditRow> createState() => _SwipeEditRowState();
}

class _SwipeEditRowState extends State<_SwipeEditRow> with SingleTickerProviderStateMixin {
  double get _maxReveal => widget.maxReveal;
  double _dragX = 0;
  bool _navigated = false;
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _dragX, end: target).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut))
      ..addListener(() => setState(() => _dragX = _anim.value));
    _animCtrl.forward(from: 0).whenComplete(() {
      if (target <= -_maxReveal && _dragX <= -_maxReveal) {
        _triggerAutoNavigate();
      }
    });
  }

  void _triggerAutoNavigate() {
    if (_navigated) return;
    _navigated = true;
    _openEdit();
  }

  void _openEdit() {
    Navigator.of(context, rootNavigator: true).push(
      _noAnimationEditRoute(
        builder: (_) => EditHabitScreen(
          habit: widget.habit,
          allHabits: widget.allHabits,
          onDelete: () {},
          // Same callback already used post-pop; reused here so the Main
          // Page also rebuilds live, while the Edit page is still open.
          onHabitChanged: widget.onNeedsRefresh,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _navigated = false;
        _animateTo(0);
      }
      widget.onNeedsRefresh?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      
      onHorizontalDragEnd: (details) {
        if (_dragX <= -_maxReveal / 2) {
          _animateTo(-_maxReveal);
        } else {
          _animateTo(0);
        }
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragX = (_dragX + details.delta.dx).clamp(-_maxReveal, 0.0);
        });
        if (_dragX <= -_maxReveal) {
          _triggerAutoNavigate();
        }
      },
      onTap: _dragX != 0 ? () => _animateTo(0) : null,
      child: Transform.translate(
        offset: Offset(_dragX, 0),
        child: widget.child,
      ),
    );
  }
}

// ─── Habits Card Bottom Sheet ─────────────────────────────────────────────────

class _HabitsCardBottomSheet extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  final String Function(Habit) formatFrequency;
  final VoidCallback onDeleted;
  final VoidCallback onEdited;

  const _HabitsCardBottomSheet({
    required this.habit,
    required this.allHabits,
    required this.formatFrequency,
    required this.onDeleted,
    required this.onEdited,
  });

  @override
  State<_HabitsCardBottomSheet> createState() => _HabitsCardBottomSheetState();
}

class _HabitsCardBottomSheetState extends State<_HabitsCardBottomSheet> {
  void _navigateToCalendar(BuildContext context) {
    Navigator.pop(context);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => HabitCalendarPage(
          habit: widget.habit,
          allHabits: widget.allHabits,
        ),
      ),
    );
  }

  void _navigateToEdit(BuildContext context) {
    Navigator.pop(context);
    Navigator.of(context, rootNavigator: true).push(
      _noAnimationEditRoute(
        builder: (_) => EditHabitScreen(
          habit: widget.habit,
          allHabits: widget.allHabits,
          onDelete: () {
            deleteHabitEverywhere(widget.allHabits, widget.habit.id);
            widget.onDeleted();
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
      widget.onEdited();
    });
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'DO YOU WANT TO DELETE THIS HABIT?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          deleteHabitEverywhere(widget.allHabits, widget.habit.id);
                          Navigator.pop(context); // close confirm dialog
                          Navigator.pop(context); // close bottom sheet
                          widget.onDeleted();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text(
                              'CONFIRM',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final freq = widget.formatFrequency(widget.habit).toUpperCase();
    final desc = widget.habit.description.trim();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 1. Habit name
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
            child: Text(
              widget.habit.title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // 2. Frequency text
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
            child: Text(
              freq,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // 3. Description (only if non-empty)
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text(
                desc.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          const SizedBox(height: 12),
          // 4. Full-width divider
          Container(height: 0.5, color: Colors.white24),
          // 5. Calendar row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _navigateToCalendar(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'CALENDAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // 6. Edit row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _navigateToEdit(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'EDIT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // 7. Full-width divider
          Container(height: 0.5, color: Colors.white24),
          // 8. Archive row — confirmation dialog
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              showDialog(
                context: context,
                barrierColor: Colors.black54,
                builder: (dialogContext) => Dialog(
                  backgroundColor: const Color(0xFF2C2C2C),
                  insetPadding: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Text(
                            'Archive habit?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Container(height: 0.5, color: Colors.white24),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => Navigator.pop(dialogContext),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    child: const Center(
                                      child: Text(
                                        'CANCEL',
                                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(width: 0.5, color: Colors.white24),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    final now = DateTime.now();
                                    widget.habit.archivedAt = DateTime(now.year, now.month, now.day);
                                    widget.habit.isArchived = true;
                                    Navigator.pop(dialogContext); // close dialog
                                    Navigator.pop(context);       // close bottom sheet
                                    widget.onEdited();
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    child: const Center(
                                      child: Text(
                                        'ARCHIVE',
                                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'ARCHIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // 9. Delete row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmDelete(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'DELETE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─── Archived Card Bottom Sheet ──────────────────────────────────────────────

class _ArchivedCardBottomSheet extends StatefulWidget {
  final Habit habit;
  final List<Habit> allHabits;
  final String Function(Habit) formatFrequency;
  final VoidCallback onUnarchive;
  final VoidCallback onDeleted;
  final VoidCallback onEdited;

  const _ArchivedCardBottomSheet({
    required this.habit,
    required this.allHabits,
    required this.formatFrequency,
    required this.onUnarchive,
    required this.onDeleted,
    required this.onEdited,
  });

  @override
  State<_ArchivedCardBottomSheet> createState() => _ArchivedCardBottomSheetState();
}

class _ArchivedCardBottomSheetState extends State<_ArchivedCardBottomSheet> {
  void _navigateToEdit(BuildContext context) {
    Navigator.pop(context);
    Navigator.of(context, rootNavigator: true).push(
      _noAnimationEditRoute(
        builder: (_) => EditHabitScreen(
          habit: widget.habit,
          allHabits: widget.allHabits,
          onDelete: () {
            deleteHabitEverywhere(widget.allHabits, widget.habit.id);
            widget.onDeleted();
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
      widget.onEdited();
    });
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'DO YOU WANT TO DELETE THIS HABIT?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text('CANCEL', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          deleteHabitEverywhere(widget.allHabits, widget.habit.id);
                          Navigator.pop(context);
                          Navigator.pop(context);
                          widget.onDeleted();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text('CONFIRM', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final freq = widget.formatFrequency(widget.habit).toUpperCase();
    final desc = widget.habit.description.trim();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
            child: Text(
              widget.habit.title.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
            child: Text(
              freq,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
            ),
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text(
                desc.toUpperCase(),
                style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
              ),
            ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: Colors.white24),
          // Calendar row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => HabitCalendarPage(
                    habit: widget.habit,
                    allHabits: widget.allHabits,
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'CALENDAR',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ),
          // Edit row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _navigateToEdit(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'EDIT',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ),
          Container(height: 0.5, color: Colors.white24),
          // Unarchive row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.pop(context);
              widget.onUnarchive();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'UNARCHIVE',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ),
          // Delete row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmDelete(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: const Text(
                'DELETE',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─── Archived Habits Screen ───────────────────────────────────────────────────

class _ArchivedHabitsScreen extends StatefulWidget {
  final List<Habit> habits;
  final VoidCallback onUnarchive;
  const _ArchivedHabitsScreen({required this.habits, required this.onUnarchive});
  @override State<_ArchivedHabitsScreen> createState() => _ArchivedHabitsScreenState();
}

class _ArchivedHabitsScreenState extends State<_ArchivedHabitsScreen> {
  List<Habit> get _archived => widget.habits.where((h) => h.isArchived).toList();

  static const _weekDayAbbr = {
    'MONDAY': 'MON', 'TUESDAY': 'TUE', 'WEDNESDAY': 'WED', 'THURSDAY': 'THU',
    'FRIDAY': 'FRI', 'SATURDAY': 'SAT', 'SUNDAY': 'SUN',
  };

  String _formatFrequency(Habit h) {
    final freq = h.frequency;
    if (freq == 'EVERY DAY' || freq.isEmpty) return 'EVERY DAY';
    if (freq == 'REPEAT') return 'every ${h.freqRepeatEvery} days';
    if (freq == 'SOME DAYS PER PERIOD') return '${h.freqPeriodDays} days per ${h.freqPeriodUnit.toLowerCase()}';
    if (freq == 'SPECIFIC DAYS OF THE WEEK') {
      const ordered = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY'];
      final selected = ordered.where((d) => h.freqWeekDays[d] == true).toList();
      if (selected.length == 7) return 'EVERY DAY';
      if (selected.isEmpty) return 'SPECIFIC DAYS OF THE WEEK';
      return selected.map((d) => _weekDayAbbr[d]!).join(' - ');
    }
    if (freq == 'SPECIFIC DAYS OF THE MONTH') {
      if (h.freqMonthDays.isEmpty) return 'SPECIFIC DAYS OF THE MONTH';
      final sorted = h.freqMonthDays.toList()..sort((a, b) { if (a==0) return 1; if (b==0) return -1; return a.compareTo(b); });
      return 'DAYS OF MONTH : ${sorted.map((d) => d == 0 ? 'LAST DAY' : '$d').join(', ')}';
    }
    if (freq == 'SPECIFIC DAYS OF THE YEAR') return 'SPECIFIC DAYS OF THE YEAR';
    return freq.toUpperCase();
  }

  bool _isScheduledOn(Habit h, DateTime day) => _habitIsScheduledOn(h, day);

  List<DateTime> get _week {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  List<String> get _dayLabels {
    const abbr = {1:'MON',2:'TUE',3:'WED',4:'THU',5:'FRI',6:'SAT',7:'SUN'};
    return _week.map((d) => abbr[d.weekday]!).toList();
  }

  int _progressPercent(Habit h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
    // For archived habits use archivedAt as the end of the measurement window
    DateTime end = h.archivedAt != null
        ? DateTime(h.archivedAt!.year, h.archivedAt!.month, h.archivedAt!.day)
        : today;
    if (h.endDate != null) {
      final e = DateTime(h.endDate!.year, h.endDate!.month, h.endDate!.day);
      if (e.isBefore(end)) end = e;
    }
    if (start.isAfter(end)) return 0;
    final List<DateTime> occurrences = [];
    for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (_isScheduledOn(h, d)) occurrences.add(d);
    }
    if (occurrences.isEmpty) return 0;
    int done = 0;
    for (final d in occurrences) { if (h.stateOn(d) == HabitState.done) done++; }
    return (done / occurrences.length * 100).round();
  }

  int _calcStreak(Habit h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
    final List<DateTime> occurrences = [];
    for (DateTime d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (_isScheduledOn(h, d)) occurrences.add(d);
    }
    int streak = 0;
    for (int i = occurrences.length - 1; i >= 0; i--) {
      final state = h.stateOn(occurrences[i]);
      if (state == HabitState.done) { streak++; }
      else if (state == HabitState.empty) { if (streak == 0) continue; break; }
      else { break; }
    }
    return streak;
  }

  void _confirmUnarchive(BuildContext context, Habit h) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF2C2C2C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Text(
                  'Do you want to select a new end date?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
              ),
              Container(height: 0.5, color: Colors.white24),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _doUnarchive(h, null);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text('NO', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: Colors.white24),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                            builder: (c, ch) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Colors.white,
                                  onPrimary: Colors.black,
                                  surface: Color(0xFF2C2C2C),
                                  onSurface: Colors.white,
                                ),
                              ),
                              child: ch!,
                            ),
                          );
                          _doUnarchive(h, picked);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Center(
                            child: Text('YES', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _doUnarchive(Habit h, DateTime? newEndDate) {
    setState(() {
      h.isArchived = false;
      h.archivedAt = null;
      if (newEndDate != null) {
        h.endDate = newEndDate;
      }
    });
    widget.onUnarchive();
  }

  void _openArchivedCardSheet(BuildContext context, Habit h) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ArchivedCardBottomSheet(
        habit: h,
        allHabits: widget.habits,
        formatFrequency: _formatFrequency,
        onUnarchive: () {
          _confirmUnarchive(context, h);
        },
        onDeleted: () {
          setState(() {
            widget.habits.removeWhere((x) => x.id == h.id);
          });
          widget.onUnarchive();
        },
        onEdited: () {
          if (mounted) setState(() {});
        },
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _historyCell(Habit h, DateTime day, DateTime today, String label) {
    final scheduled = _isScheduledOn(h, day);
    final state = h.stateOn(day);
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    final isFuture = day.isAfter(today);
    final isDone = state == HabitState.done;
    final isFail = state == HabitState.failed;

    Widget? iconAbove;
    Color circleFill = Colors.transparent;
    Border? circleBorder;
    Color numColor = Colors.white;
    FontWeight numWeight = FontWeight.w400;

    if (!scheduled) {
      numColor = isFuture ? Colors.white24 : Colors.white30;
    } else if (!isToday) {
      if (isDone) {
        circleFill = Colors.white; numColor = Colors.black; numWeight = FontWeight.w800;
        iconAbove = CustomPaint(size: const Size(13, 11), painter: _CalCheckPainter(Colors.white));
      } else if (isFail) {
        circleFill = Colors.black; circleBorder = Border.all(color: Colors.white, width: 1.5);
        numColor = Colors.white; numWeight = FontWeight.w800;
        iconAbove = CustomPaint(size: const Size(12, 12), painter: _CalCrossPainter(Colors.white));
      } else {
        circleFill = Colors.transparent; circleBorder = Border.all(color: Colors.white54, width: 1.5);
        numColor = Colors.white70; numWeight = FontWeight.w500;
      }
    } else {
      circleFill = const Color(0xFFB8B8B8); numColor = Colors.black; numWeight = FontWeight.w900;
      if (isDone) iconAbove = CustomPaint(size: const Size(12, 10), painter: _CalCheckPainter(Colors.white));
      else if (isFail) iconAbove = CustomPaint(size: const Size(10, 10), painter: _CalCrossPainter(Colors.white));
    }

    final Widget dateCircle = Container(
      width: 32, height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: circleFill, border: circleBorder),
      alignment: Alignment.center,
      child: Text('${day.day}', style: TextStyle(color: numColor, fontSize: 13, fontWeight: numWeight, height: 1)),
    );

    return SizedBox(
      width: 38,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: scheduled ? Colors.white54 : Colors.white24, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        SizedBox(height: 14, child: Center(child: iconAbove ?? const SizedBox.shrink())),
        const SizedBox(height: 2),
        dateCircle,
      ]),
    );
  }

  Widget _card(Habit h) {
    final pct = _progressPercent(h);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        h.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      h.category.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _formatFrequency(h).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ),
                    if (h.priority > 1) ...[
                      const SizedBox(width: 8),
                      Text('${h.priority}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 2),
                      const Icon(Icons.flag, color: Colors.white, size: 13),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: Colors.white24, margin: const EdgeInsets.only(top: 12, bottom: 12)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text('${_calcStreak(h)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 16),
                const Icon(Icons.check, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HabitCalendarPage(habit: h, allHabits: widget.habits),
                    ));
                  },
                  child: const Icon(Icons.calendar_today, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openArchivedCardSheet(context, h),
                  child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archived = _archived;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER: [☰] ARCHIVED  [filled archive icon]
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  const Text('ARCHIVED', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.archive, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: archived.isEmpty
                  ? const Center(
                      child: Text(
                        'There are no archived habits',
                        style: TextStyle(color: Colors.white30, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: archived.length,
                    itemBuilder: (ctx, i) => _card(archived[i]),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Habits Overview Screen ───────────────────────────────────────────────────

class HabitsScreen extends StatefulWidget {
  final List<Habit> habits;
  const HabitsScreen({super.key, required this.habits});
  @override State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Day labels for the week row (Sunday-first, matching the design).
  // Day labels derived from the actual days shown (always ends with today).
  static const _allDayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  List<String> get _dayLabels {
    // weekday: Mon=1 … Sun=7; map to abbreviation.
    const abbr = {1:'MON',2:'TUE',3:'WED',4:'THU',5:'FRI',6:'SAT',7:'SUN'};
    return _week.map((d) => abbr[d.weekday]!).toList();
  }

  // Identical wording/logic to EditHabitScreen._formatFrequency (reused, not re-invented).
  static const _weekDayAbbr = {
    'MONDAY': 'MON', 'TUESDAY': 'TUE', 'WEDNESDAY': 'WED', 'THURSDAY': 'THU',
    'FRIDAY': 'FRI', 'SATURDAY': 'SAT', 'SUNDAY': 'SUN',
  };

  String _formatFrequency(Habit h) {
    final freq = h.frequency;
    if (freq == 'EVERY DAY' || freq.isEmpty) return 'EVERY DAY';
    if (freq == 'REPEAT') return 'every ${h.freqRepeatEvery} days';
    if (freq == 'SOME DAYS PER PERIOD') {
      final unit = h.freqPeriodUnit.toLowerCase();
      return '${h.freqPeriodDays} days per $unit';
    }
    if (freq == 'SPECIFIC DAYS OF THE WEEK') {
      const ordered = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
      final selected = ordered.where((d) => h.freqWeekDays[d] == true).toList();
      if (selected.length == 7) return 'EVERY DAY';
      if (selected.isEmpty) return 'SPECIFIC DAYS OF THE WEEK';
      return selected.map((d) => _weekDayAbbr[d]!).join(' - ');
    }
    if (freq == 'SPECIFIC DAYS OF THE MONTH') {
      if (h.freqMonthDays.isEmpty) return 'SPECIFIC DAYS OF THE MONTH';
      final sorted = h.freqMonthDays.toList()..sort((a, b) {
        if (a == 0) return 1;
        if (b == 0) return -1;
        return a.compareTo(b);
      });
      final parts = sorted.map((d) => d == 0 ? 'LAST DAY' : '$d').join(', ');
      return 'DAYS OF MONTH : $parts';
    }
    if (freq == 'SPECIFIC DAYS OF THE YEAR') return 'SPECIFIC DAYS OF THE YEAR';
    return freq.toUpperCase();
  }

  // Whether the habit is scheduled on a given day (start/end window + frequency).
  bool _isScheduledOn(Habit h, DateTime day) => _habitIsScheduledOn(h, day);

  // Current week, Sunday-first.
  List<DateTime> get _week {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Today is always the rightmost (index 6); each earlier box is the previous day.
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  int _progressPercent(Habit h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
    DateTime end = today;
    if (h.endDate != null) {
      final e = DateTime(h.endDate!.year, h.endDate!.month, h.endDate!.day);
      if (e.isBefore(end)) end = e;
    }
    if (start.isAfter(end)) return 0;

    // Collect only valid scheduled occurrences up to and including today,
    // using the exact same occurrence engine as streak and calendar rendering.
    final List<DateTime> occurrences = [];
    for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (_isScheduledOn(h, d)) occurrences.add(d);
    }
    if (occurrences.isEmpty) return 0;

    // Determine whether today itself is a scheduled occurrence and is still pending.
    // Only today's occurrence is "active" — past occurrences are always finalized,
    // regardless of whether the user marked them or not.
    final DateTime latestOccurrence = occurrences.last;
    final bool latestIsToday = latestOccurrence.year == today.year &&
        latestOccurrence.month == today.month &&
        latestOccurrence.day == today.day;
    final bool latestIsPending = latestIsToday &&
        h.stateOn(latestOccurrence) == HabitState.empty;

    int scheduled = occurrences.length;
    int done = 0;
    for (final d in occurrences) {
      if (h.stateOn(d) == HabitState.done) done++;
    }

    // Only exclude today's occurrence from the denominator when it is still
    // pending (empty). A FAIL on today counts normally (reduces progress).
    // Past occurrences that are empty count as incomplete and stay in the
    // denominator — they are finalized missed days, not active occurrences.
    if (latestIsPending) {
      scheduled -= 1;
    }

    if (scheduled == 0) return 0;
    return (done / scheduled * 100).round();
  }

  

  int _calcStreak(Habit h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(h.startDate.year, h.startDate.month, h.startDate.day);

    // Collect all scheduled occurrences up to today, descending
    final List<DateTime> occurrences = [];
    for (DateTime d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (_isScheduledOn(h, d)) occurrences.add(d);
    }

    // Walk backwards; skip the latest if it's pending
    int streak = 0;
    for (int i = occurrences.length - 1; i >= 0; i--) {
      final state = h.stateOn(occurrences[i]);
      if (state == HabitState.done) {
        streak++;
      } else if (state == HabitState.empty) {
        // Pending: skip only the very first (most recent) occurrence
        if (streak == 0) continue;
        break;
      } else {
        // failed or skipped: break immediately
        break;
      }
    }
    return streak;
  }


  void _openHabitsCardSheet(Habit h) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _HabitsCardBottomSheet(
        habit: h,
        allHabits: widget.habits,
        formatFrequency: _formatFrequency,
        onDeleted: () {
          if (mounted) setState(() {});
        },
        onEdited: () {          // ← ADD
          if (mounted) setState(() {});
        },
      ),
    ).then((_) { if (mounted) setState(() {}); });
  }



  // Reuses the existing habit bottom sheet (same one long-press uses on the Today list).
  void _openSheet(Habit h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _HabitBottomSheet(
        habit: h,
        allHabits: widget.habits,
        selectedDay: today,
        onStateChanged: (s) => h.setStateOn(today, s),
        onNoteChanged: (n) => h.setNoteOn(today, n),
        onDelete: () => deleteHabitEverywhere(widget.habits, h.id),
      ),
    ).then((_) { if (mounted) setState(() {}); });
  }

  

  // SECTION 3: one circular date indicator — exact same 6-state system as Calendar page.
  Widget _historyCell(Habit h, DateTime day, DateTime today, String label) {
    final scheduled = _isScheduledOn(h, day);
    final state = h.stateOn(day);
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    final isFuture = day.isAfter(today);
    final isDone = state == HabitState.done;
    final isFail = state == HabitState.failed;

    // ── Exact same variables as _buildCalendarGrid in HabitCalendarPage ──
    Widget? iconAbove;
    Color   circleFill   = Colors.transparent;
    Border? circleBorder;
    bool    hasOuterRing = false;
    Color   numColor     = Colors.white;
    FontWeight numWeight = FontWeight.w400;

    if (!scheduled) {
      numColor  = isFuture ? Colors.white24 : Colors.white30;
      numWeight = FontWeight.w400;
    } else if (!isToday) {
      if (isDone) {
        circleFill  = Colors.white;
        numColor    = Colors.black;
        numWeight   = FontWeight.w800;
        iconAbove   = CustomPaint(
          size: const Size(13, 11),
          painter: _CalCheckPainter(Colors.white),
        );
      } else if (isFail) {
        circleFill   = Colors.black;
        circleBorder = Border.all(color: Colors.white, width: 1.5);
        numColor     = Colors.white;
        numWeight    = FontWeight.w800;
        iconAbove    = CustomPaint(
          size: const Size(12, 12),
          painter: _CalCrossPainter(Colors.white),
        );
      } else {
        circleFill   = Colors.transparent;
        circleBorder = Border.all(color: Colors.white54, width: 1.5);
        numColor     = Colors.white70;
        numWeight    = FontWeight.w500;
      }
    } else {
      // ── Today (scheduled) — gray filled circle, black number ──
      hasOuterRing = false;
      if (isDone) {
        // DONE TODAY — gray fill, black number, white check above
        circleFill  = const Color(0xFFB8B8B8);
        circleBorder = null;
        numColor    = Colors.black;
        numWeight   = FontWeight.w900;
        iconAbove   = CustomPaint(
          size: const Size(12, 10),
          painter: _CalCheckPainter(Colors.white),
        );
      } else if (isFail) {
        // FAIL TODAY — gray fill, black number, white cross above
        circleFill   = const Color(0xFFB8B8B8);
        circleBorder = null;
        numColor     = Colors.black;
        numWeight    = FontWeight.w900;
        iconAbove    = CustomPaint(
          size: const Size(10, 10),
          painter: _CalCrossPainter(Colors.white),
        );
      } else {
        // PENDING TODAY — gray fill, black number, no icon
        circleFill   = const Color(0xFFB8B8B8);
        circleBorder = null;
        numColor     = Colors.black;
        numWeight    = FontWeight.w900;
      }
    }

    // ── Build the 32×32 date circle (slightly smaller than calendar's 40×40
    //    to fit the card's compact row) ──
    final Widget dateCircle = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: circleFill,
        border: circleBorder,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: numColor,
          fontSize: 13,
          fontWeight: numWeight,
          height: 1,
        ),
      ),
    );

    // ── Wrap with outer ring for today states ──
    final Widget dateWidget = hasOuterRing
        ? Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            child: Center(child: dateCircle),
          )
        : dateCircle;

    // ── Assemble: day-label + icon strip + circle ──
    final cell = SizedBox(
      width: 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheduled ? Colors.white54 : Colors.white24,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 14,
            child: Center(
              child: iconAbove ?? const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 2),
          dateWidget,
        ],
      ),
    );

    final now2 = DateTime.now();
    final today2 = DateTime(now2.year, now2.month, now2.day);
    if (!scheduled || day.isAfter(today2)) return cell;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          final cur = h.stateOn(day);
          if (cur == HabitState.skipped) {
            h.setStateOn(day, HabitState.empty);
          } else {
            h.setStateOn(
              day,
              cur == HabitState.empty
                  ? HabitState.done
                  : cur == HabitState.done
                      ? HabitState.failed
                      : HabitState.empty,
            );
          }
        });
      },
      child: cell,
    );
  }

  Widget _card(Habit h) {
    final week = _week;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pct = _progressPercent(h);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           // SECTION 1: TOP ROW — name (left) + category + archive icon (right)
          // SECTION 1: TOP ROW — name (left) + category (right)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  h.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                h.category.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // SECTION 2: FREQUENCY (+ priority flag to match the screenshot)
          Row(
            children: [
              Flexible(
                child: Text(
                  _formatFrequency(h).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
              ),
              if (h.priority > 1) ...[
                const SizedBox(width: 8),
                Text('${h.priority}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const Icon(Icons.flag, color: Colors.white, size: 13),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // SECTION 3: DATE HISTORY ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) => _historyCell(h, week[i], today, _dayLabels[i])),
          ),
          const SizedBox(height: 12),
          // SECTION 4: BOTTOM ROW — % (far left) · calendar · three dots (far right)
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text('${_calcStreak(h)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              const Icon(Icons.check, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => HabitCalendarPage(
                        habit: h,
                        allHabits: widget.habits,
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.calendar_today, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openHabitsCardSheet(h),
                child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const swdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    const smons = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.72,
        backgroundColor: const Color(0xFF1C1C1C),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(swdays[now.weekday - 1], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('${smons[now.month - 1]} ${now.day}, ${now.year}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 32),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { Navigator.pop(context); Navigator.pop(context); }, // close drawer, return to Today
                  child: const SizedBox(width: double.infinity, child: Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context), // already on HABITS, just close drawer
                  child: const SizedBox(width: double.infinity, child: Text('HABITS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _CategoriesScreen(
                          customCategories: CategoryStore.custom,
                          habits: widget.habits,
                          onChanged: (_) {},
                        ),
                      ),
                    );
                  },
                  child: const SizedBox(width: double.infinity, child: Text('CATEGORIES', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(),
                      ),
                    );
                  },
                  child: const SizedBox(width: double.infinity, child: Text('SETTINGS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SCREEN HEADER: [☰] HABITS  [archive icon]
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.menu, color: Colors.white, size: 24),
                    ),
                  ),
                  const Text('HABITS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _ArchivedHabitsScreen(
                            habits: widget.habits,
                            onUnarchive: () {
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                    child: const Icon(Icons.archive_outlined, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // HABIT LIST — cards keep a consistent size; ~4 fit, more scroll vertically.
            Expanded(
              child: widget.habits.where((h) => !h.isArchived).isEmpty
                  ? const Center(
                      child: Text(
                        'There are no habits',
                        style: TextStyle(color: Colors.white30, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: widget.habits.where((h) => !h.isArchived).length,
                      itemBuilder: (ctx, i) {
                        final active = widget.habits.where((h) => !h.isArchived).toList();
                        return _card(active[i]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}




// ─── Help / Tutorial Dialog ───────────────────────────────────────────────────

class _HelpDialog extends StatefulWidget {
  const _HelpDialog();
  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

const double tutorialHabitVerticalOffset = 8.0;
const double tutorialInstructionVerticalOffset = 10.0;
const double tutorialBlackBackgroundHeightOffset = -4.0;
const double tutorialHabitOuterTopPadding = 6.0;
const double tutorialHabitOuterBottomPadding = 6.0;
const double tutorialDescriptionTopPadding = 10.0;
const double tutorialDescriptionBottomPadding = 10.0;

class _HelpDialogState extends State<_HelpDialog>
    with TickerProviderStateMixin {
      
  bool _isDone = false;
  int _page = 0;

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  late AnimationController _cursorCtrl;
  late Animation<double> _cursorAnim;

  late AnimationController _circleCtrl;
  late Animation<double> _circleAnim;

  late AnimationController _holdPressCtrl;
  late Animation<double> _holdPressAnim;

  late AnimationController _holdCircleCtrl;
  late Animation<double> _holdCircleAnim;

  late AnimationController _swipeCursorCtrl;
  late Animation<double> _swipeCursorAnim;

  late AnimationController _swipeRowCtrl;
  late Animation<double> _swipeRowAnim;

  bool _page0CircleChecked = false;
bool _page1CircleChecked = true;
bool _page2CircleChecked = true;

void _resetPage0State() {
  _page0CircleChecked = false;
  _isDone = false;
}

void _resetAllStates() {
  _page0CircleChecked = false;
  _page1CircleChecked = true;
  _page2CircleChecked = true;
  _isDone = false;
}

  @override
  void initState() {
    super.initState();

    _resetPage0State();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cursorAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cursorCtrl, curve: Curves.easeInOut),
    );


    _circleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _circleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _circleCtrl, curve: Curves.easeOut),
    );
    _circleCtrl.value = 1.0;

    _holdPressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _holdPressAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _holdPressCtrl, curve: Curves.easeInOut),
    );

    _holdCircleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _holdCircleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _holdCircleCtrl, curve: Curves.easeInOut),
    );

    _swipeCursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _swipeCursorAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _swipeCursorCtrl, curve: Curves.easeInOut),
    );

    _swipeRowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _swipeRowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _swipeRowCtrl, curve: Curves.easeOut),
    );

    _runCycle();
    _runHoldCycle();
    _runSwipeCycle();
  }

  Future<void> _runCycle() async {
    while (mounted) {
      if (_page != 0) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      // Step 1: pause at rest position
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (_page != 0) continue;

      // Step 2: finger moves toward checkbox
      await _cursorCtrl.forward(from: 0).orCancel.catchError((_) {});
      if (!mounted) return;
      if (_page != 0) continue;

      // Step 3: tap — ripple + toggle state + scale pop
      _circleCtrl.forward(from: 0);
      setState(() {
        _page0CircleChecked = true;
        _isDone = true;
      });
      _animCtrl.forward(from: 0);

      // Step 4: pause briefly while "tapped"
      await Future.delayed(const Duration(milliseconds: 750));
      if (!mounted) return;
      if (_page != 0) continue;

      // Step 5: finger retreats
      await _cursorCtrl.reverse().orCancel.catchError((_) {});
      if (!mounted) return;

      // Step 6: reset state and pause before next tap
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (_page != 0) continue;
      setState(() => _resetPage0State());
    }
  }

  Future<void> _runHoldCycle() async {
    while (mounted) {
      if (_page != 1) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      // Step 1: pause at rest position
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (_page != 1) continue;

      // Step 2: finger presses down and holds — circle grows and lingers
      await Future.wait([
        _holdPressCtrl.forward(from: 0).orCancel.catchError((_) {}),
        _holdCircleCtrl.forward(from: 0).orCancel.catchError((_) {}),
      ]);
      if (!mounted) return;
      if (_page != 1) continue;

      // Step 3: hold sustained
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      if (_page != 1) continue;

      // Step 4: finger releases
      await Future.wait([
        _holdPressCtrl.reverse().orCancel.catchError((_) {}),
        _holdCircleCtrl.reverse().orCancel.catchError((_) {}),
      ]);
      if (!mounted) return;
      if (_page != 1) continue;

      // Step 5: pause before next hold
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _runSwipeCycle() async {
    while (mounted) {
      if (_page != 2) {
        _swipeCursorCtrl.value = 0.0;
        _swipeRowCtrl.value = 0.0;
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      // Step 1: habit fully closed, no cursor — pause at rest position
      _swipeCursorCtrl.value = 0.0;
      _swipeRowCtrl.value = 0.0;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (_page != 2) continue;

      // Step 2: cursor fades in smoothly at fixed position (opacity only)
      await _swipeCursorCtrl.forward(from: 0).orCancel.catchError((_) {});
      if (!mounted) return;
      if (_page != 2) continue;

      // Step 3 & 4: cursor stays fixed; the entire habit card slides left,
      // gradually revealing the EDIT background, until max swipe position.
      await _swipeRowCtrl.forward(from: 0).orCancel.catchError((_) {});
      if (!mounted) return;
      if (_page != 2) continue;

      // Step 5: pause briefly at the final swipe position
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      if (_page != 2) continue;

      // Step 6: cursor fades out completely (opacity only, no movement)
      await _swipeCursorCtrl.reverse(from: 1.0).orCancel.catchError((_) {});
      if (!mounted) return;
      _swipeCursorCtrl.value = 0.0;
      if (_page != 2) continue;

      // Step 7: only after the cursor has fully disappeared does the
      // entire habit card smoothly slide back to its original position.
      _swipeRowCtrl.duration = const Duration(milliseconds: 100);
      await _swipeRowCtrl.reverse(from: 1.0).orCancel.catchError((_) {});
      _swipeRowCtrl.duration = const Duration(milliseconds: 250);
      if (!mounted) return;
      _swipeRowCtrl.value = 0.0;
      if (_page != 2) continue;

      // Step 8 & 9: habit is fully closed again; pause briefly before
      // restarting the loop from the beginning (step 10).
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }



  @override
  void dispose() {
    _animCtrl.dispose();
    _cursorCtrl.dispose();
    _circleCtrl.dispose();
    _holdPressCtrl.dispose();
    _holdCircleCtrl.dispose();
    _swipeCursorCtrl.dispose();
    _swipeRowCtrl.dispose();
    super.dispose();
  }

  double get _editRevealWidth {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'EDIT',
        style: TextStyle(
          fontSize: 13,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 60.0;
  }

  Widget _buildSwipeEditDemo() {
    final double editWidth = _editRevealWidth;
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(_swipeRowAnim.value * -editWidth, 0),
            child: Container(
              width: double.infinity,
              height: 40,
              decoration: const BoxDecoration(color: Colors.black),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_swipeRowAnim.value > 0)
                    Positioned(
                      right: -editWidth,
                      top: 0,
                      bottom: 0,
                      width: editWidth,
                      child: Container(
                        color: Colors.black,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: const Text(
                              'EDIT',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      const Text(
                        'EXAMPLE HABIT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: CustomPaint(painter: _BoldCheckPainter()),
                      ),
                      const SizedBox(width: 18),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_swipeCursorAnim.value > 0)
            FadeTransition(
              opacity: _swipeCursorAnim,
              child: Transform.rotate(
                angle: -0.87,
                child: const _MouseCursor(),
              ),
            ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'TO-DO LIST GESTURES',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Container(height: 0.5, color: Colors.white24),
            SizedBox(height: tutorialHabitOuterTopPadding),
            Transform.translate(
              offset: const Offset(0, tutorialHabitVerticalOffset),
              child: Container(
              width: double.infinity,
              height: 80 + tutorialBlackBackgroundHeightOffset,
              color: Colors.transparent,
              child: Stack(
              alignment: Alignment.centerRight,
              children: [
                if (_page == 2)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _editRevealWidth,
                  child: Container(
                    color: const Color(0xFFB8B8B8),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: const Text(
                        'EDIT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _swipeRowAnim,
                  builder: (_, child) {
                    final double dx = _page == 2 ? -_swipeRowAnim.value * _editRevealWidth : 0.0;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 80 + tutorialBlackBackgroundHeightOffset,
                    color: Colors.black,
                    child: Center(
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      autofocus: false,
                      showCursor: false,
                      readOnly: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'EXAMPLE HABIT',
                        hintStyle: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Expanded(
                    child: Container(
                        color: Colors.black,
                        height: 40,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // Status indicator — fixed on the right
                            Positioned(
                              right: 18,
                              child: _page == 0
                                  ? AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        transitionBuilder: (child, anim) => ScaleTransition(
                                          scale: anim,
                                          child: FadeTransition(opacity: anim, child: child),
                                        ),
                                        child: Container(
                                          key: ValueKey('page0_${_page0CircleChecked ? 'done' : 'empty'}'),
                                          width: 26,
                                          height: 26,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                          ),
                                          child: _page0CircleChecked
                                              ? CustomPaint(painter: _BoldCheckPainter())
                                              : null,
                                        ),
                                      )
                                  : Container(
                                      width: 26,
                                      height: 26,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                      child: CustomPaint(
                                        painter: _BoldCheckPainter(),
                                      ),
                                    ),
                            ),
                            if (_page == 0)
                            // Click-flash circle — positioned behind the cursor
                            Positioned(
                              right: 120,
                              top: 2.8,
                              child: AnimatedBuilder(
                                animation: _circleAnim,
                                builder: (_, __) {
                                  final v = _circleAnim.value;
                                  final flashOpacity = (1.0 - v).clamp(0.0, 1.0) * (v > 0 ? 1.0 : 0.0);
                                  final baseOpacity = 1.0;
                                  return Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white24.withValues(
                                        alpha: (0.15 * baseOpacity) + (0.45 * flashOpacity),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_page == 1)
                            // Hold circle — grows and lingers behind the cursor while pressed.
                            // Outer box is fixed at the maximum size and centered, so the
                            // circle's center point never moves as it scales.
                            Positioned(
                              right: 120 - 5,
                              top: 2.8 - 5,
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: Center(
                                  child: AnimatedBuilder(
                                    animation: _holdPressAnim,
                                    builder: (_, __) {
                                      final v = _holdPressAnim.value;
                                      return Container(
                                        width: 36 + (10 * v),
                                        height: 36 + (10 * v),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white24.withValues(
                                            alpha: 0.15 + (0.35 * v),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            // Cursor — centered in gap between title and status
                            if (_page != 2)
                            Positioned( 
                              right: 135,
                              top: 20,
                              child: AnimatedBuilder(
                                animation: _page == 1 ? _holdPressAnim : _animCtrl,
                                builder: (_, child) {
                                  final scale = _page == 1
                                      ? 1.0 - (0.12 * _holdPressAnim.value)
                                      : (_animCtrl.isAnimating ? (0.92 + 0.08 * (1.0 - _animCtrl.value)) : 1.0);
                                  return Transform.scale(
                                    scale: scale,
                                    alignment: const Alignment(1.0, 0.0),
                                    child: child,
                                  );
                                },
                                child: Transform.rotate(
                                  angle: -0.87,
                                  child: const _MouseCursor(),
                                ),
                              ),
                            ),
                            // Cursor for Popup 3 — fade-in only, no scale, no movement
                            if (_page == 2)
                            Positioned(
                              right: 135,
                              top: 20,
                              child: FadeTransition(
                                opacity: _swipeCursorAnim,
                                child: Transform.rotate(
                                  angle: -0.87,
                                  child: const _MouseCursor(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ),
                ],
              ),
              ),
                ),
              ))],
            ),
            ),
            ),
            SizedBox(height: tutorialHabitOuterBottomPadding),
            SizedBox(height: tutorialDescriptionTopPadding),
            Transform.translate(
              offset: const Offset(0, tutorialInstructionVerticalOffset),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(
                  _page == 0
                      ? 'Click on any item in the to-do list to mark it as complete or to update its state.'
                      : _page == 1
                      ? 'Long click on any item in the list to access reminders, notes, statistics and more options.'
                      : 'Swipe left to edit the activity',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ),
            ),
            SizedBox(height: tutorialDescriptionBottomPadding),
            Container(height: 0.5, color: Colors.white24),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        overlayColor: Colors.transparent,
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                      ),
                      onPressed: () {
                    if (_page == 0) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _page = _page - 1;
                        if (_page == 0) {
                          _resetPage0State();
                        } else if (_page == 1) {
                          _page1CircleChecked = true;
                        }
                      });
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'BACK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 0.5, color: Colors.white24),
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    overlayColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    splashFactory: NoSplash.splashFactory,
                  ).copyWith(
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  ),
                  onPressed: () {
                    if (_page < 2) {
                      setState(() {
                        _page = _page + 1;
                        if (_page == 1) {
                          _page1CircleChecked = true;
                        } else if (_page == 2) {
                          _page2CircleChecked = true;
                        }
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      _page < 2 ? 'NEXT' : 'Got It',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}






/// Standard desktop arrow cursor — black arrow with white outline.
class _MouseCursor extends StatelessWidget {
  const _MouseCursor();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 18),
      painter: _MouseCursorPainter(),
    );
  }
}

class _MouseCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Right-pointing filled arrow (send/tap icon style)
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, h * 0.5)
      ..lineTo(0, h)
      ..lineTo(w * 0.28, h * 0.5)
      ..close();

    // White outline
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // White fill
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_MouseCursorPainter o) => false;
}

// ─── Calendar Picker Bottom Sheet ──────────────────────────────────────────────

class _CalendarPickerSheet extends StatefulWidget {
  final DateTime initialMonth;
  final DateTime selectedDate;
  const _CalendarPickerSheet({required this.initialMonth, required this.selectedDate});
  @override State<_CalendarPickerSheet> createState() => _CalendarPickerSheetState();
}

class _CalendarPickerSheetState extends State<_CalendarPickerSheet> {
  late DateTime _displayMonth;
  late DateTime _selected;

  static const _monthNames = [
    'JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE',
    'JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'
  ];
  static const _weekLabels = ['SUN','MON','TUE','WED','THU','FRI','SAT'];

  @override
  void initState() {
    super.initState();
    _displayMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _selected = widget.selectedDate;
  }

  void _prevMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1));
  void _nextMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1));

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
  int _firstWeekday(int year, int month) {
    final d = DateTime(year, month, 1);
    return d.weekday % 7; // Sun=0..Sat=6
  }

  void _selectDate(DateTime date) {
    Navigator.pop(context, date);
  }

  void _close() {
    Navigator.pop(context, null);
  }

  void _today() {
    final now = DateTime.now();
    Navigator.pop(context, DateTime(now.year, now.month, now.day));
  }

  Widget _buildGrid() {
    final year = _displayMonth.year;
    final month = _displayMonth.month;
    final daysInMonth = _daysInMonth(year, month);
    final firstWd = _firstWeekday(year, month);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final totalCells = firstWd + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final prevMonthDays = _daysInMonth(
      month == 1 ? year - 1 : year,
      month == 1 ? 12 : month - 1,
    );

    return Column(
      children: List.generate(rows, (row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNum = cellIndex - firstWd + 1;

              final bool isOutsideMonth = dayNum < 1 || dayNum > daysInMonth;

              late final DateTime date;
              late final int displayNum;
              if (dayNum < 1) {
                displayNum = prevMonthDays + dayNum;
                final prevMonth = month == 1 ? 12 : month - 1;
                final prevYear = month == 1 ? year - 1 : year;
                date = DateTime(prevYear, prevMonth, displayNum);
              } else if (dayNum > daysInMonth) {
                displayNum = dayNum - daysInMonth;
                final nextMonth = month == 12 ? 1 : month + 1;
                final nextYear = month == 12 ? year + 1 : year;
                date = DateTime(nextYear, nextMonth, displayNum);
              } else {
                displayNum = dayNum;
                date = DateTime(year, month, dayNum);
              }

              final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
              final isSelected = date.year == _selected.year && date.month == _selected.month && date.day == _selected.day;

              Color bg;
              Color fg;
              bool ringBorder = false;
              if (isOutsideMonth) {
                if (isSelected && isToday) {
                  bg = Colors.white24;
                  fg = Colors.white38;
                } else if (isSelected) {
                  bg = Colors.white24;
                  fg = Colors.white38;
                } else if (isToday) {
                  bg = const Color(0xFF3A3A3A);
                  fg = Colors.white30;
                } else {
                  bg = Colors.transparent;
                  fg = Colors.white24;
                }
              } else {
                if (isSelected && isToday) {
                  bg = Colors.white;
                  fg = const Color(0xFF6B6B6B);
                } else if (isSelected) {
                  bg = Colors.white;
                  fg = Colors.black;
                } else if (isToday) {
                  bg = const Color(0xFF3A3A3A);
                  fg = Colors.white;
                } else {
                  bg = Colors.transparent;
                  fg = Colors.white;
                }
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectDate(date),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bg,
                        border: ringBorder
                            ? Border.all(color: Colors.black, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$displayNum',
                        style: TextStyle(
                          color: fg,
                          fontSize: 14,
                          fontWeight: (isSelected || isToday) ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _nextMonth();
        } else if (v > 200) {
          _prevMonth();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '${_monthNames[_displayMonth.month - 1]} ${_displayMonth.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _prevMonth,
                    child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.chevron_left, color: Colors.white, size: 24)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _nextMonth,
                    child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.chevron_right, color: Colors.white, size: 24)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _weekLabels.map((l) => SizedBox(
                  width: 42,
                  child: Center(
                    child: Text(l, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildGrid(),
            ),
            const SizedBox(height: 12),
            Container(height: 0.5, color: Colors.white24),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: const Center(
                          child: Text('Close', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 0.5, color: Colors.white24),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _today,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: const Center(
                          child: Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Screen ──────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  const Text(
                    'SETTINGS',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsAndAlarmsScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: const Text(
                  'NOTIFICATIONS AND ALARMS',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Habit Home Page ──────────────────────────────────────────────────────────

class NotificationsAndAlarmsScreen extends StatefulWidget {
  const NotificationsAndAlarmsScreen({super.key});
  @override State<NotificationsAndAlarmsScreen> createState() => _NotificationsAndAlarmsScreenState();
}

class _NotificationsAndAlarmsScreenState extends State<NotificationsAndAlarmsScreen> {
  void _openPicker() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _PostponeIntervalPickerDialog(
        initialMinutes: PostponeIntervalStore.minutes,
        onConfirm: (v) async {
          await PostponeIntervalStore.setMinutes(v);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                  const Text(
                    'NOTIFICATIONS AND ALARMS',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openPicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Text(
                      'POSTPONE INTERVAL',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                    const Spacer(),
                    Text(
                      '${PostponeIntervalStore.minutes} MINUTES',
                      style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostponeIntervalPickerDialog extends StatefulWidget {
  final int initialMinutes;
  final void Function(int) onConfirm;
  const _PostponeIntervalPickerDialog({required this.initialMinutes, required this.onConfirm});
  @override State<_PostponeIntervalPickerDialog> createState() => _PostponeIntervalPickerDialogState();
}

class _PostponeIntervalPickerDialogState extends State<_PostponeIntervalPickerDialog> {
  static final List<int> _values = List<int>.generate(60, (i) => i + 1);
  late int _index;
  late int _selected;
  late final FixedExtentScrollController _wheelController;

  @override
  void initState() {
    super.initState();
    _index = _values.indexOf(widget.initialMinutes);
    if (_index == -1) _index = _values.indexOf(10);
    _selected = _values[_index];
    _wheelController = FixedExtentScrollController(initialItem: _values.length * 1000 + _index);
  }

  @override
  void dispose() {
    _wheelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('POSTPONE INTERVAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          ),
          Container(height: 0.5, color: Colors.white24),
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ListWheelScrollView.useDelegate(
                  itemExtent: 44,
                  physics: const FixedExtentScrollPhysics(),
                  controller: _wheelController,
                  onSelectedItemChanged: (i) => setState(() {
                    final realIndex = i % _values.length;
                    _index = realIndex;
                    _selected = _values[realIndex];
                  }),
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (c, i) {
                      final realIndex = i % _values.length;
                      final isSel = realIndex == _index;
                      return Center(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${_values[realIndex]} ',
                                style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white38,
                                  fontSize: isSel ? 17 : 14,
                                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                                ),
                              ),
                              TextSpan(
                                text: _values[realIndex] == 1 ? 'MINUTE' : 'MINUTES',
                                style: TextStyle(
                                  color: (isSel ? Colors.white : Colors.white38).withValues(alpha: isSel ? 0.6 : 0.4),
                                  fontSize: isSel ? 17 : 14,
                                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: null,
                  ),
                ),
                IgnorePointer(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Container(height: 0.5, width: double.infinity, color: Colors.white38),
                      ),
                      const SizedBox(height: 44),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Container(height: 0.5, width: double.infinity, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white38),
          IntrinsicHeight(child: Row(children: [
            Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.pop(context), child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('CANCEL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
            Container(width: 1, color: Colors.white38),
            Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { widget.onConfirm(_selected); Navigator.pop(context); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), child: const Center(child: Text('OK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
          ])),
        ]),
      ),
    );
  }
}

class HabitHomePage extends StatefulWidget {
  final List<Habit>? habits;
  const HabitHomePage({super.key, this.habits});
  @override State<HabitHomePage> createState() => _HabitHomePageState();
}

class _HabitHomePageState extends State<HabitHomePage> {
  bool _searchOpen=false;
  DateTime _sel=DateTime.now();
  late DateTime _weekStart;
  late final List<Habit> _all = widget.habits ?? [];
  final _ctrl=TextEditingController();
  final _scaffoldKey=GlobalKey<ScaffoldState>();
  Timer? _midnightTimer;
  DateTime _lastKnownToday=DateTime.now();

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(_sel);
    final now = DateTime.now();
    _lastKnownToday = DateTime(now.year, now.month, now.day);
    _midnightTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkDateRollover());
    ReminderService.onMarkDone = _handleReminderMarkDone;
    // Terapkan action DONE yang ditekan saat app sepenuhnya terminated
    // (lihat ReminderService._onBackgroundNotificationResponse).
    ReminderService.instance.consumePendingBackgroundAction();
  }

  void _handleReminderMarkDone(String habitId) {
    final idx = _all.indexWhere((h) => h.id == habitId);
    if (idx == -1) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() => _all[idx].setStateOn(today, HabitState.done));
  }

  void _checkDateRollover() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today != _lastKnownToday) {
      final wasOnOldToday = _sel.year == _lastKnownToday.year &&
          _sel.month == _lastKnownToday.month &&
          _sel.day == _lastKnownToday.day;
      setState(() {
        _lastKnownToday = today;
        if (wasOnOldToday) {
          _sel = today;
          _weekStart = _monday(today);
        }
      });
    }
  }

  DateTime _monday(DateTime d)=>d.subtract(Duration(days:d.weekday-1));
  List<DateTime> get _week=>List.generate(7,(i)=>_weekStart.add(Duration(days:i)));

  String get _dateLabel{
    const wd=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const m=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wd[_sel.weekday-1]}, ${_sel.day} ${m[_sel.month-1]} ${_sel.year}';
  }
  String get _dateLabelFull{
    const wd=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const m=['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${wd[_sel.weekday-1]}, ${_sel.day} ${m[_sel.month-1]} ${_sel.year}';
  }

  String get _monthName{const m=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];return m[_sel.month-1];}

  void _prevMonth()=>setState((){_sel=DateTime(_sel.year,_sel.month-1,1);_weekStart=_monday(_sel);});
  void _nextMonth()=>setState((){_sel=DateTime(_sel.year,_sel.month+1,1);_weekStart=_monday(_sel);});
  void _back()=>setState(()=>_weekStart=_weekStart.subtract(const Duration(days:7)));
  void _fwd()=>setState(()=>_weekStart=_weekStart.add(const Duration(days:7)));
  void _pick(DateTime d)=>setState((){_sel=d;_weekStart=_monday(d);});

  bool _isScheduledOn(Habit h, DateTime day) => _habitIsScheduledOn(h, day);

  List<Habit> _forDay(DateTime d) => _all.where((h) => _isScheduledOn(h, d)).toList();

  List<Habit> _applySearchFilter(List<Habit> source) {
    Iterable<Habit> result = source;
    if (_selectedCategories.isNotEmpty) {
      final sel = _selectedCategories.map((c) => c.trim().toLowerCase()).toSet();
      result = result.where((h) => sel.contains(h.category.trim().toLowerCase()));
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((h) => h.title.toLowerCase().startsWith(q));
    }
    return result.toList();
  }

  double _progress(DateTime day){
    final h=_forDay(day);
    if(h.isEmpty)return 0;
    return h.where((x)=>x.stateOn(day)==HabitState.done).length/h.length;
  }

  List<Habit> get _sorted{
  final h=_applySearchFilter(_forDay(_sel));
    final empty=h.where((x)=>x.stateOn(_sel)==HabitState.empty||x.stateOn(_sel)==HabitState.skipped).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    final done=h.where((x)=>x.stateOn(_sel)!=HabitState.empty&&x.stateOn(_sel)!=HabitState.skipped).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    return [...empty,...done];
  }

  void _cycle(String id){
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(_sel.year, _sel.month, _sel.day);
    if (target.isAfter(today)) return; // Future dates are read-only
    setState((){
      final h=_all.firstWhere((x)=>x.id==id);
      final cur=h.stateOn(_sel);
      if(cur==HabitState.skipped){
        h.setStateOn(_sel,HabitState.empty);
        return;
      }
      h.setStateOn(_sel,cur==HabitState.empty?HabitState.done:cur==HabitState.done?HabitState.failed:HabitState.empty);
    });
  }

  int _toMins(String t){final p=t.split(':');return(int.tryParse(p[0])??0)*60+(p.length>1?(int.tryParse(p[1])??0):0);}
  ReminderEntry? _earliestAll(Habit h){
    if(h.reminders.isEmpty)return null;
    final sorted=List<ReminderEntry>.from(h.reminders)..sort((x,y)=>_toMins(x.time).compareTo(_toMins(y.time)));
    return sorted.first;
  }
  String? _earliestTime(Habit h)=>_earliestAll(h)?.time;
  Widget? _reminderIcon(Habit h){
    if(h.reminders.isEmpty)return null;
    final earliest=_earliestAll(h)!;
    if(earliest.type=='none')return null;
    final icon=earliest.type=='alarm'?Icons.alarm:Icons.notifications;
    if(h.reminders.length==1)return Icon(icon,color:Colors.white,size:16);
    return SizedBox(width:26,height:18,child:Stack(clipBehavior:Clip.none,children:[
      Positioned(left:-6,top:3,child:Icon(icon,color:Colors.white.withValues(alpha:0.75),size:14)),
      Positioned(left:0,top:0,child:Icon(icon,color:Colors.white,size:18)),
    ]));
  }

  Widget _statusIcon(HabitState s, bool hasReminders){
    switch(s){
      case HabitState.skipped:
        return Container(
          width:26, height:26,
          decoration:const BoxDecoration(shape:BoxShape.circle, color:Colors.white),
          child: CustomPaint(painter: _BoldMinusPainter()),
        );
      case HabitState.empty:
        if(hasReminders){
          return SizedBox(
            width:26, height:26,
            child: CustomPaint(painter: _ClockHandsPainter()),
          );
        }
        return Container(
          width:26, height:26,
          decoration:const BoxDecoration(shape:BoxShape.circle, color:Colors.white),
        );
      case HabitState.done:
        return Container(
          width:26, height:26,
          decoration:const BoxDecoration(shape:BoxShape.circle, color:Colors.white),
          child: CustomPaint(painter: _BoldCheckPainter()),
        );
      case HabitState.failed:
        return Container(
          width:26, height:26,
          decoration:const BoxDecoration(shape:BoxShape.circle, color:Colors.white),
          child: CustomPaint(painter: _BoldCrossPainter()),
        );
    }
  }

  void _longPress(String id) {
    final habit = _all.firstWhere((x) => x.id == id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _HabitBottomSheet(
        habit: habit,
        allHabits: _all,
        selectedDay: _sel,
        onStateChanged: (s) {
          setState(() => habit.setStateOn(_sel, s));
        },
        onNoteChanged: (n) {
          setState(() => habit.setNoteOn(_sel, n));
        },
        onDelete: () {
          setState(() => deleteHabitEverywhere(_all, id));
        },
        onHabitChanged: () {
          if (mounted) setState(() {});
        },
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _add()async{
    final now=DateTime.now();
    final today=DateTime(now.year,now.month,now.day);
    final isToday=_sel.year==today.year&&_sel.month==today.month&&_sel.day==today.day;
    if(isToday){
      if(mounted)setState((){_searchOpen=false;_searchQuery='';_selectedCategories={};_searchCtrl.clear();});
      final res=await Navigator.push<dynamic>(context,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:today.toIso8601String())));
      if(res!=null&&mounted){
        _addFromResult(res);
      }
    }else{
      final pickedDate=await showDialog<DateTime>(context:context,barrierColor:Colors.black.withValues(alpha:0.75),barrierDismissible:true,builder:(_)=>_StartDatePickerModal(selectedDate:_sel));
      if(pickedDate==null||!mounted)return;
      if(mounted)setState((){_searchOpen=false;_searchQuery='';_selectedCategories={};_searchCtrl.clear();});
      final res=await Navigator.push<dynamic>(context,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:pickedDate.toIso8601String())));
      if(res!=null&&mounted){
        _addFromResult(res);
      }
    }
  }

  void _addFromResult(dynamic r){
    Habit? newHabit;
    if(r is HabitScheduleResult){
      final sd=DateTime.tryParse(r.startDate)??DateTime.now();
      final ed=r.endDate.isNotEmpty?DateTime.tryParse(r.endDate):null;
      newHabit = Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r.title.isNotEmpty?r.title:r.category,category:r.category,description:r.description,priority:r.priority,reminders:r.reminders,startDate:sd,endDate:ed,frequency:r.frequency,freqWeekDays:Map.from(r.freqWeekDays),freqMonthDays:Set.from(r.freqMonthDays),freqYearDays:List.from(r.freqYearDays),freqPeriodDays:r.freqPeriodDays,freqPeriodUnit:r.freqPeriodUnit,freqRepeatEvery:r.freqRepeatEvery,freqFlexible:r.freqFlexible);
      _all.add(newHabit);
    }else if(r is String){
      newHabit = Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r,category:r,description:'',startDate:DateTime.now());
      _all.add(newHabit);
    }else if(r is Map){
      final sd=r['startDate']!=null?DateTime.tryParse(r['startDate'] as String)??DateTime.now():DateTime.now();
      newHabit = Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:((r['title']??r['category'])as String?)??' ',category:(r['category']as String?)??' ',description:(r['description']as String?)??' ',startDate:sd);
      _all.add(newHabit);
    }
    if (newHabit != null && newHabit.reminders.isNotEmpty) {
      ReminderService.instance.rescheduleHabit(
        habitId: newHabit.id,
        habitTitle: newHabit.title,
        previousTimes: const [],
        currentReminders: newHabit.reminders
            .map((r) => ReminderInput(time: r.time, type: r.type))
            .toList(),
      );
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context){
    const dlabels=['M','T','W','T','F','S','S'];
    final week=_week;final now=DateTime.now();final sorted=_sorted;
    const swdays=['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY'];
    const smons=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];

    return Scaffold(
      key:_scaffoldKey,
      backgroundColor:Colors.black,
      drawer:Drawer(width:MediaQuery.of(context).size.width*0.72,backgroundColor:const Color(0xFF1C1C1C),child:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(28,32,28,28),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(swdays[now.weekday-1],style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:1)),
        const SizedBox(height:4),
        Text('${smons[now.month-1]} ${now.day}, ${now.year}',style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
        const SizedBox(height:32),
        GestureDetector(onTap:()=>Navigator.pop(context),child:const Text('TODAY',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:0.5))),
        const SizedBox(height:20),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.pop(context); // close the drawer first
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HabitsScreen(habits: _all),
              ),
            );
          },
          child: const SizedBox(
            width: double.infinity,
            child: Text('HABITS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height:20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(context); // close the drawer first
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _CategoriesScreen(
                          customCategories: CategoryStore.custom,
                          habits: _all,
                          onChanged: (_) {},
                        ),
                      ),
                    );
                  },
                  child: const SizedBox(
                    width: double.infinity,
                    child: Text('CATEGORIES', style: TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:0.5)),
                  ),
                ),
                const SizedBox(height:20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(),
                      ),
                    );
                  },
                  child: const SizedBox(
                    width: double.infinity,
                    child: Text('SETTINGS', style: TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:0.5)),
                  ),
                ),
              ])))),
      body:SafeArea(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(!_searchOpen)Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Expanded(child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
            GestureDetector(onTap:()=>_scaffoldKey.currentState?.openDrawer(),child:const Padding(padding:EdgeInsets.only(right:10),child:Icon(Icons.menu,color:Colors.white,size:22))),
            Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
              Opacity(opacity:(_sel.year==now.year&&_sel.month==now.month&&_sel.day==now.day)?1.0:0.0,child:const Text('TODAY',style:TextStyle(color:Colors.white38,fontSize:11,fontWeight:FontWeight.w600,letterSpacing:2))),
              const SizedBox(height:2),
              Text(_dateLabel,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w600,letterSpacing:0.3)),
            ]),
          ])),
          Row(children:[GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>setState(()=>_searchOpen=true),child:const Icon(Icons.search,color:Colors.white,size:22)),const SizedBox(width:18),GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () {
    showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _CalendarPickerSheet(initialMonth: _sel, selectedDate: _sel),
    ).then((picked) {
      if (picked != null && mounted) _pick(picked);
    });
  },
  child: const Icon(Icons.calendar_month,color:Colors.white,size:22),
),const SizedBox(width:18),GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const _HelpDialog(),
    );
  },
  child: const Text('?', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300)),
)]),
        ])),
        if(_searchOpen)Container(
          margin:const EdgeInsets.fromLTRB(0,0,0,12),
          decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.black,width:1)),
          child:Column(children:[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.black54,
                  builder: (_) => _CategoryFilterDialog(
                    habits: _all,
                    initialSelected: _selectedCategories,
                    onChanged: (sel) => setState(() => _selectedCategories = sel),
                  ),
                );
              },
              child: Container(width: double.infinity, padding:const EdgeInsets.symmetric(vertical:14),child:Center(child:Text(_categoryPanelLabel(),style:TextStyle(color:Colors.black,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:0.5)))),
            ),
            Container(height:1,color:Colors.black),
            Row(children:[
  const Padding(padding:EdgeInsets.symmetric(horizontal:14,vertical:14),child:Icon(Icons.search,color:Colors.black,size:20)),
  Expanded(child:TextField(
    controller:_searchCtrl,
    cursorColor:Colors.black,
    style:const TextStyle(color:Colors.black,fontSize:20,fontWeight:FontWeight.w700,letterSpacing:0.5),
    decoration:const InputDecoration(
      border:InputBorder.none,
      isDense:true,
      hintText:'ACTIVITY NAME',
      hintStyle:TextStyle(color:Color(0xFF9E9E9E),fontSize:20,fontWeight:FontWeight.w700,letterSpacing:0.5),
    ),
    onChanged:(v)=>setState(()=>_searchQuery=v),
  )),
  Container(width:1,height:48,color:Colors.black),
  GestureDetector(
    behavior:HitTestBehavior.opaque,
    onTap:_clearSearch,
    child:Container(height:48,padding:const EdgeInsets.symmetric(horizontal:14),alignment:Alignment.center,child:const Icon(Icons.delete,color:Colors.black,size:22)),
  ),
  Container(width:1,height:48,color:Colors.black),
  GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>setState(()=>_searchOpen=false),child:Container(height:48,padding:const EdgeInsets.symmetric(horizontal:14),alignment:Alignment.center,child:const Icon(Icons.keyboard_arrow_up,color:Colors.black,size:22))),
]),
          ]),
        ),
        const Center(child:Text('HABITS',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:3))),
        const SizedBox(height:20),
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          GestureDetector(onTap:_prevMonth,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_left,color:Colors.white,size:28))),
          Text(_monthName,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:2)),
          GestureDetector(onTap:_nextMonth,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_right,color:Colors.white,size:28))),
        ])),
        const SizedBox(height:16),
        Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Row(children:[
          GestureDetector(onTap:_back,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_left,color:Colors.white54,size:22))),
          Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:List.generate(7,(i){
            final day=week[i];
            final isSel=day.year==_sel.year&&day.month==_sel.month&&day.day==_sel.day;
            final prog=_progress(day);
            return GestureDetector(onTap:()=>_pick(day),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Text(dlabels[i],style:TextStyle(color:isSel?Colors.white:Colors.white38,fontSize:12,fontWeight:FontWeight.w500,letterSpacing:0.5)),
              const SizedBox(height:6),
              SizedBox(width:40,height:40,child:CustomPaint(
                painter:_RingPainter(prog),
                child:Center(child:Container(width:34,height:34,decoration:BoxDecoration(color:isSel?Colors.white:Colors.transparent,shape:BoxShape.circle),child:Center(child:Text('${day.day}',style:TextStyle(color:isSel?Colors.black:Colors.white,fontSize:14,fontWeight:isSel?FontWeight.w700:FontWeight.w400))))),
              )),
              const SizedBox(height:4),
              Container(width:4,height:4,decoration:BoxDecoration(color:(day.year==now.year&&day.month==now.month&&day.day==now.day)?Colors.white:Colors.transparent,shape:BoxShape.circle)),
            ]));
          }))),
          GestureDetector(onTap:_fwd,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_right,color:Colors.white54,size:22))),
        ])),
        const SizedBox(height:24),
        Container(height:0.5,color:Colors.white12),
        Expanded(child:sorted.isEmpty&&_searchQuery.trim().isNotEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text((_searchOpen?_dateLabelFull:_dateLabel).toUpperCase(),style:TextStyle(color:Colors.white,fontSize:_searchOpen?14:10,fontWeight:FontWeight.w600,letterSpacing:0.3)),
              const SizedBox(height:16),
              Text('No matches for the current filter',style:TextStyle(color:Colors.white38,fontSize:_searchOpen?13:9,fontWeight:FontWeight.w500)),
              const SizedBox(height:16),
              GestureDetector(
                behavior:HitTestBehavior.opaque,
                onTap:_clearSearch,
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
                  decoration:BoxDecoration(color:const Color(0xFF111111),borderRadius:BorderRadius.circular(20)),
                  child:Text('remove filters',style:TextStyle(color:Colors.white38,fontSize:_searchOpen?13:9,fontWeight:FontWeight.w600)),
                ),
              ),
            ]))
          :sorted.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Container(width:56,height:56,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white12)),child:const Icon(Icons.add,color:Colors.white24,size:28)),const SizedBox(height:16),const Text('NO HABITS YET',style:TextStyle(color:Colors.white24,fontSize:12,letterSpacing:3,fontWeight:FontWeight.w600)),const SizedBox(height:6),const Text('Tap + to add your first habit',style:TextStyle(color:Colors.white24,fontSize:12))]))
          :_HabitAnimatedList(
              habits:sorted,
              selectedDay:_sel,
              buildReminderIcon:_reminderIcon,
              earliestReminderTime:_earliestTime,
              buildStatusIcon:_statusIcon,
              onTap:_cycle,
              onDismiss:(id)=>setState(()=>deleteHabitEverywhere(_all, id)),
              onLongPress:_longPress,
              onNeedsRefresh: () { if (mounted) setState(() {}); },
            )),
      ])),
      floatingActionButton:GestureDetector(onTap:_add,child:Container(width:54,height:54,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:const Icon(Icons.add,color:Colors.white,size:26))),
    );
  }

  String _searchQuery = '';
  String _categoryPanelLabel() {
    final count = _selectedCategories.length;
    if (count == 0) return 'SELECT A CATEGORY';
    if (count == 1) return '1 CATEGORY SELECTED';
    return '$count CATEGORIES SELECTED';
  }
  final TextEditingController _searchCtrl = TextEditingController();
  Set<String> _selectedCategories = {};






  void _clearSearch() {
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
      _selectedCategories = {};
    });
  }


  
  

  @override
  void dispose() {
  ReminderService.onMarkDone = null;
  _midnightTimer?.cancel();
  _ctrl.dispose();
  _searchCtrl.dispose();   // added
  super.dispose();
  }

  





}