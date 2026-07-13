// ─────────────────────────────────────────────────────────────
// snooze_page.dart
//
// Halaman yang dibuka saat compact alarm notification di-tap
// LANGSUNG (bukan lewat expand). Bergaya sama dengan halaman lain
// di app (background hitam, font bold uppercase).
//
// Ini HANYA UI + aksi SNOOZE/DISMISS di dalam app — action button
// pada notifikasi expanded (DISMISS/SNOOZE) sudah ditangani lewat
// ReminderService, terpisah dari halaman ini. Halaman ini dibuka
// ketika user tap body alarm sebelum sempat expand.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'reminder_service.dart';

class SnoozePage extends StatefulWidget {
  final String habitId;
  final String habitTitle;
  final String habitCategory;
  const SnoozePage({super.key, required this.habitId, required this.habitTitle, required this.habitCategory});

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
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    super.dispose();
  }

  String get habitId => widget.habitId;
  // NOTE: widget.habitCategory actually carries the HABIT TITLE value
  // (e.g. "ENGLISH") in how this page is currently invoked. This getter
  // is named to reflect what it truly represents on screen.
  String get _displayedHabitTitle => widget.habitCategory;
  // NOTE: widget.habitTitle actually carries the HABIT CATEGORY value
  // (e.g. "STUDY") in how this page is currently invoked. This getter
  // is named to reflect what it truly represents on screen.
  String get _displayedHabitCategory => widget.habitTitle;

  String _currentTimeLabel() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      _currentTimeLabel(),
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
              onTap: () async {
                await ReminderService.instance.rescheduleSingleInMinutes(
                  habitId: habitId,
                  habitTitle: _displayedHabitTitle,
                  reminderTime: _currentTimeLabel(),
                  type: 'alarm',
                  minutesFromNow: 10,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Snoozed for 10 minutes')),
                  );
                  Navigator.of(context).pop();
                }
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
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SNOOZE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '10 minutes',
                            style: TextStyle(
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
              onTap: () => Navigator.of(context).pop(),
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