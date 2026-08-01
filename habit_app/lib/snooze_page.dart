import 'package:flutter/material.dart';
import 'reminder_service.dart';
import 'main.dart' show PostponeIntervalStore;
import 'dart:math' as math;

class SnoozePage extends StatefulWidget {
  final String habitId;
  final String habitTitle;
  final String habitCategory;
  final String reminderTime;
  const SnoozePage({required Key key, required this.habitId, required this.habitTitle, required this.habitCategory, this.reminderTime = ''}) : super(key: key);

  @override
  State<SnoozePage> createState() => _SnoozePageState();
}

class _SnoozePageState extends State<SnoozePage> with SingleTickerProviderStateMixin {
  late final AnimationController _rippleCtrl;
  static const double _timeNumberYOffset = 0.0;
  static const double _habitTitleYOffset = 0.0;
  static const double _habitCategoryYOffset = 0.0;
  static const double _timeNumberFontSize = 48.0;
  static const double _habitTitleFontSize = 20.0;
  static const double _habitCategoryFontSize = 18.0;
  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    ReminderService.instance.playAlarmSound(habitId);
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    super.dispose();
  }

  String get habitId => widget.habitId;
  bool _snoozeTriggered = false;

  Future<void> _performSnooze() async {
    if (_snoozeTriggered) return;
    _snoozeTriggered = true;
    final minutes = PostponeIntervalStore.minutes;
    // Only stop/cancel/reschedule THIS Habit's own alarm session — never
    // another Habit's, even if this page was opened while a different
    // Habit's alarm was mid-flight.
    ReminderService.clearActiveAlarmSession(habitId);
    await ReminderService.instance.stopAlarmSound(habitId);
    await ReminderService.instance.cancelNativeAlarmSoundPublic(habitId);
    await ReminderService.instance.cancelReminderSlot(
      habitId,
      widget.reminderTime.isNotEmpty ? widget.reminderTime : _currentTimeLabel(),
    );
    await ReminderService.instance.rescheduleSingleInMinutes(
      habitId: habitId,
      habitTitle: _displayedHabitTitle,
      reminderTime: widget.reminderTime.isNotEmpty ? widget.reminderTime : _currentTimeLabel(),
      type: 'alarm',
      minutesFromNow: minutes,
    );
    await ReminderService.instance.showSnoozeConfirmationNotification(minutes);
    ReminderService.clearActiveSnoozeHabitIdIfMatches(habitId);
    await ReminderService.instance.resumeNewestRemainingAlarm();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await ReminderService.instance.moveAppToBackground();
  }

  // Displays the Habit Name inside the top rectangular box.
  String get _displayedHabitTitle => widget.habitTitle;
  // Displays the Habit Category outside the top rectangular box.
  String get _displayedHabitCategory => widget.habitCategory;

  String _currentTimeLabel() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _displayedAlarmTime {
    final stored = ReminderService.activeAlarmTriggerTime(habitId);
    if (stored != null && stored.isNotEmpty) return stored;
    return widget.reminderTime.isNotEmpty ? widget.reminderTime : _currentTimeLabel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // ── Jam + label habit (mirip tampilan alarm sistem) ──
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Transform.translate(
                    offset: const Offset(0, _timeNumberYOffset),
                    child: Text(
                      _displayedAlarmTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: _timeNumberFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Transform.translate(
                    offset: const Offset(0, _habitTitleYOffset),
                    child: Text(
                      _displayedHabitTitle.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: _habitTitleFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Transform.translate(
              offset: const Offset(0, _habitCategoryYOffset),
              child: Text(
                _displayedHabitCategory.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: _habitCategoryFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            // ── Tombol SNOOZE bulat besar di tengah ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _performSnooze,
              onLongPress: _performSnooze,
              onPanUpdate: (details) {
                if (_snoozeTriggered) return;
                final dx = details.localPosition.dx - 85;
                final dy = details.localPosition.dy - 85;
                final dist = math.sqrt(dx * dx + dy * dy);
                if (dist > 85) {
                  _performSnooze();
                }
              },
              onPanEnd: (details) {
                if (!_snoozeTriggered) _performSnooze();
              },
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _rippleCtrl,
                        builder: (context, child) {
                          final t = _rippleCtrl.value;
                          return CustomPaint(
                            painter: _RippleCirclePainter(progress: t),
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                width: 170,
                height: 170,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2C),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'SNOOZE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${PostponeIntervalStore.minutes} minutes',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
            const Spacer(),
            // ── Tombol DISMISS di bawah ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ReminderService.instance.stopAlarmSound(habitId);
                await ReminderService.instance.cancelNativeAlarmSoundPublic(habitId);
                if (widget.reminderTime.isNotEmpty) {
                  await ReminderService.instance.cancelReminderSlot(habitId, widget.reminderTime);
                }
                ReminderService.clearActiveAlarmSession(habitId);
                ReminderService.clearActiveSnoozeHabitIdIfMatches(habitId);
                await ReminderService.instance.resumeNewestRemainingAlarm();
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                await ReminderService.instance.moveAppToBackground();
              },

              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'DISMISS',
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
          ],
        ),
      ),
      ),
    );
  }
}

class _RippleCirclePainter extends CustomPainter {
  final double progress;
  const _RippleCirclePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final startRadius = baseRadius * 0.9;
    final endRadius = baseRadius * 1.8;
    final radius = startRadius + (endRadius - startRadius) * progress;
    final opacity = (0.2 * (1.0 - progress)).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RippleCirclePainter oldDelegate) =>
      oldDelegate.progress != progress;
}