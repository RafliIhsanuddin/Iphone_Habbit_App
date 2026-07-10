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

class SnoozePage extends StatelessWidget {
  final String habitId;
  final String habitTitle;
  const SnoozePage({super.key, required this.habitId, required this.habitTitle});

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
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    _currentTimeLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    habitTitle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // ── Tombol SNOOZE bulat besar di tengah ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ReminderService.instance.rescheduleSingleInMinutes(
                  habitId: habitId,
                  habitTitle: habitTitle,
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
              child: Container(
                width: 200,
                height: 200,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2C),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SNOOZE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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