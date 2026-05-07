import 'package:flutter/material.dart';

void main() {
  runApp(const HabitApp());
}

class HabitApp extends StatelessWidget {
  const HabitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habits',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const HabitHomePage(),
    );
  }
}

class Habit {
  final String id;
  final String title;
  final String category;
  bool isDone;
  Habit({required this.id, required this.title, this.category = '', this.isDone = false});
}

// ── HABIT SCHEDULE SCREEN ──
// Step 4 of habit creation flow — "When do you want to do it?"
// Reached after HabitFrequencyScreen
// Collects: start date, end date, reminders, priority
// On SAVE → returns all data back through the nav stack

// ── Reminder data model ──
class ReminderEntry {
  String time;         // HH:mm
  String type;         // 'none' | 'notification' | 'alarm'
  String schedule;     // 'always' | 'week' | 'before'
  Set<String> weekDays;
  int daysBefore;

  ReminderEntry({
    this.time = '12:00',
    this.type = 'notification',
    this.schedule = 'always',
    Set<String>? weekDays,
    this.daysBefore = 1,
  }) : weekDays = weekDays ?? {};
}

class HabitScheduleScreen extends StatefulWidget {
  final String category;
  final String title;
  final String description;
  final String frequency;
  final String initialStartDate; // ISO8601 from previous screen

  const HabitScheduleScreen({
    super.key,
    required this.category,
    required this.title,
    required this.description,
    required this.frequency,
    required this.initialStartDate,
  });

  @override
  State<HabitScheduleScreen> createState() => _HabitScheduleScreenState();
}

class _HabitScheduleScreenState extends State<HabitScheduleScreen> {
  // ── START DATE ──
  late DateTime _startDate;
  bool _startIsToday = true;

  // ── END DATE ──
  bool _endDateEnabled = false;
  DateTime? _endDate;
  final TextEditingController _daysCtrl = TextEditingController(text: '60');

  // ── REMINDERS ──
  final List<ReminderEntry> _reminders = [];

  // ── PRIORITY ──
  int _priority = 1; // 1 = DEFAULT

  @override
  void initState() {
    super.initState();
    final parsed = DateTime.tryParse(widget.initialStartDate) ?? DateTime.now();
    _startDate = parsed;
    final now = DateTime.now();
    _startIsToday = parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
    // Default end date = startDate + 60 days
    _endDate = _startDate.add(const Duration(days: 60));
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──
  String _formatShort(DateTime d) {
    return '${d.month}/${d.day}/${d.year % 100}';
  }

  String _startLabel() {
    if (_startIsToday) return 'TODAY';
    return _formatShort(_startDate);
  }

  DateTime _computedEndDate() {
    final days = int.tryParse(_daysCtrl.text) ?? 60;
    return _startDate.add(Duration(days: days));
  }

  // ── Pill widget (dark rounded badge) ──
  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Pick start date ──
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Color(0xFF2C2C2C),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        final now = DateTime.now();
        _startIsToday = picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day;
        _endDate = _computedEndDate();
      });
    }
  }

  // ── Pick end date from calendar ──
  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 60)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Color(0xFF2C2C2C),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        final diff = picked.difference(_startDate).inDays;
        _daysCtrl.text = '$diff';
      });
    }
  }

  // ── Open reminders modal ──
  void _showRemindersModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _RemindersModal(
        reminders: _reminders,
        onChanged: (updated) => setState(() {
          _reminders.clear();
          _reminders.addAll(updated);
        }),
      ),
    );
  }

  // ── Open priority modal ──
  void _showPriorityModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _PriorityModal(
        priority: _priority,
        onChanged: (v) => setState(() => _priority = v),
      ),
    );
  }

  // ── Row: divider + label left, value right ──
  Widget _row(String label, Widget right) {
    return Column(
      children: [
        Container(height: 0.5, color: Colors.white12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              right,
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final endDisplay = _endDate != null ? _formatShort(_endDate!) : _formatShort(_computedEndDate());

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Title ──
              const Text(
                'WHEN DO YOU WANT\nTO DO IT?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 28),

              // ── START DATE ──
              _row(
                'START DATE',
                GestureDetector(
                  onTap: _pickStartDate,
                  child: _pill(_startLabel()),
                ),
              ),

              // ── END DATE ──
              _row(
                'END DATE',
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _endDateEnabled = !_endDateEnabled;
                      if (_endDateEnabled) {
                        _endDate = _computedEndDate();
                      }
                    });
                  },
                  child: Switch(
                    value: _endDateEnabled,
                    onChanged: (v) => setState(() {
                      _endDateEnabled = v;
                      if (v) _endDate = _computedEndDate();
                    }),
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFF555555),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: const Color(0xFF333333),
                  ),
                ),
              ),

              // ── END DATE sub-row (when enabled) ──
              if (_endDateEnabled) ...[
                Container(height: 0.5, color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    // Evenly space: pill | number | DAYS across full width
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Date pill — tap to pick from calendar
                      GestureDetector(
                        onTap: _pickEndDate,
                        child: _pill(endDisplay),
                      ),
                      // Days input — underlined number, centered in remaining space
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _daysCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n > 0) {
                                setState(() => _endDate = _startDate.add(Duration(days: n)));
                              }
                            },
                          ),
                        ),
                      ),
                      const Text(
                        'DAYS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── TIME AND REMINDERS ──
              _row(
                'TIME AND REMINDERS',
                GestureDetector(
                  onTap: _showRemindersModal,
                  child: Container(
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
                ),
              ),

              // ── PRIORITY ──
              _row(
                'PRIORITY',
                GestureDetector(
                  onTap: _showPriorityModal,
                  child: _pill(_priority == 1 ? 'DEFAULT' : '${_priority}🏳'),
                ),
              ),

              const Spacer(),

              // ── Bottom nav: BACK • dots • SAVE ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: const Text('BACK',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1))),
                  ]),
                  GestureDetector(
                    onTap: () {
                      // Return all habit data including schedule
                      Navigator.pop(context, {
                        'title': widget.title,
                        'description': widget.description,
                        'category': widget.category,
                        'startDate': _startDate.toIso8601String(),
                        'frequency': widget.frequency,
                        'endDate': _endDateEnabled && _endDate != null ? _endDate!.toIso8601String() : '',
                        'priority': '${_priority}',
                        'reminderCount': '${_reminders.length}',
                      });
                    },
                    child: const Text('SAVE',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── REMINDERS MODAL ──
class _RemindersModal extends StatefulWidget {
  final List<ReminderEntry> reminders;
  final void Function(List<ReminderEntry>) onChanged;

  const _RemindersModal({required this.reminders, required this.onChanged});

  @override
  State<_RemindersModal> createState() => _RemindersModalState();
}

class _RemindersModalState extends State<_RemindersModal> {
  late List<ReminderEntry> _list;

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.reminders);
  }

  void _addReminder() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _NewReminderModal(
        existingTimes: _list.map((r) => r.time).toList(),
        onConfirm: (entry) {
          setState(() => _list.add(entry));
          widget.onChanged(List.from(_list));
        },
      ),
    );
  }

  void _editReminder(int index) {
    final r = _list[index];
    // Exclude the current reminder's time from dupe check
    final otherTimes = _list.asMap().entries
        .where((e) => e.key != index)
        .map((e) => e.value.time)
        .toList();
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _NewReminderModal(
        existingTimes: otherTimes,
        initialEntry: r,
        title: 'EDIT REMINDERS',
        onConfirm: (entry) {
          setState(() => _list[index] = entry);
          widget.onChanged(List.from(_list));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      // Symmetric inset ensures dialog is perfectly centered horizontally
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ── centered, padded evenly
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: const Text(
                  'TIME AND REMINDERS',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
            ),
            // Full-width divider — edge to edge inside ClipRRect
            Container(height: 0.5, color: Colors.white24),
            // ── Reminder list — scrollable if many items ──
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_list.isEmpty) ...[
                        const SizedBox(height: 20),
                        const Icon(Icons.notifications_off, color: Colors.white, size: 48),
                        const SizedBox(height: 8),
                        const Text(
                          'NO REMINDERS FOR THIS ACTIVITY',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 20),
                      ] else ...[
                        ..._list.asMap().entries.map((e) {
                          final i = e.key;
                          final r = e.value;
                          IconData icon;
                          if (r.type == 'none') icon = Icons.notifications_off;
                          else if (r.type == 'alarm') icon = Icons.alarm;
                          else icon = Icons.notifications;
                          final schedLabel = r.schedule == 'always' ? 'ALWAYS ENABLED'
                              : r.schedule == 'before' ? '${r.daysBefore} DAYS BEFORE'
                              : r.weekDays.join(' . ');
                          return Column(
                            children: [
                              SizedBox(
                                height: 60,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // ── Edit tap: covers entire row ──
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _editReminder(i),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF444444),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(icon, color: Colors.white70, size: 18),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    r.time,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                                  ),
                                                  Text(
                                                    schedLabel,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Spacer so text doesn't go under delete badge
                                            const SizedBox(width: 48),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // ── Delete badge: on top, right-aligned, intercepts its own tap ──
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            _list.removeAt(i);
                                            widget.onChanged(List.from(_list));
                                          });
                                        },
                                        child: Center(
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF444444),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.delete_outline, color: Colors.white70, size: 18),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(height: 0.5, color: Colors.white12),
                            ],
                          );
                        }),
                        const SizedBox(height: 4),
                      ],
                      // ── NEW REMINDER button ──
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: GestureDetector(
                          onTap: _addReminder,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'NEW REMINDER',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Full-width divider above CLOSE
            Container(height: 0.5, color: Colors.white24),
            // ── CLOSE button ──
            GestureDetector(
              onTap: () {
                widget.onChanged(_list);
                Navigator.pop(context);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'CLOSE',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
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

// ── TIME PICKER DIALOG ──
// Arrow controls + manual text input for HOUR and MINUTES
// Full-width dividers, centered text, CANCEL | OK with vertical divider
class _TimePickerDialog extends StatefulWidget {
  final int initialHour;
  final int initialMinute;
  final void Function(int hour, int minute) onConfirm;

  const _TimePickerDialog({
    required this.initialHour,
    required this.initialMinute,
    required this.onConfirm,
  });

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int _hour;
  late int _minute;
  late TextEditingController _hourCtrl;
  late TextEditingController _minCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialHour;
    _minute = widget.initialMinute;
    _hourCtrl = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minCtrl = TextEditingController(text: _minute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  void _setHour(int h) {
    _hour = h.clamp(0, 23);
    _hourCtrl.text = _hour.toString().padLeft(2, '0');
    _hourCtrl.selection = TextSelection.collapsed(offset: _hourCtrl.text.length);
  }

  void _setMinute(int m) {
    _minute = ((m % 60) + 60) % 60;
    _minCtrl.text = _minute.toString().padLeft(2, '0');
    _minCtrl.selection = TextSelection.collapsed(offset: _minCtrl.text.length);
  }

  // Each box: up arrow, editable text field, down arrow, label
  Widget _numBox({
    required TextEditingController ctrl,
    required String label,
    required VoidCallback onUp,
    required VoidCallback onDown,
    required void Function(String) onChanged,
    required int maxVal,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Up arrow
        GestureDetector(
          onTap: onUp,
          child: const Icon(Icons.keyboard_arrow_up, color: Colors.white54, size: 28),
        ),
        const SizedBox(height: 4),
        // Editable box — manual typing supported
        Container(
          width: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 4),
        // Down arrow
        GestureDetector(
          onTap: onDown,
          child: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 28),
        ),
        const SizedBox(height: 4),
        // Label centered
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      // No horizontal inset — dialog fills edge to edge for full-width dividers
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title — centered
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'REMINDER TIME',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // Hour : Minute boxes — centered row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _numBox(
                  ctrl: _hourCtrl,
                  label: 'HOUR',
                  onUp: () => setState(() => _setHour(_hour + 1)),
                  onDown: () => setState(() => _setHour(_hour - 1)),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null) setState(() => _hour = n.clamp(0, 23));
                  },
                  maxVal: 23,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Text(
                    ' : ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _numBox(
                  ctrl: _minCtrl,
                  label: 'MINUTES',
                  onUp: () => setState(() => _setMinute(_minute + 1)),
                  onDown: () => setState(() => _setMinute(_minute - 1)),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null) setState(() => _minute = n.clamp(0, 59));
                  },
                  maxVal: 59,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Full-width divider — no padding, edge to edge
          Container(height: 0.5, color: Colors.white24),

          // CANCEL | OK row with vertical divider
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'CANCEL',
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
                ),
                Container(width: 0.5, color: Colors.white24),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      widget.onConfirm(_hour, _minute);
                      Navigator.pop(context);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── NEW / EDIT REMINDER MODAL ──
class _NewReminderModal extends StatefulWidget {
  final void Function(ReminderEntry) onConfirm;
  final List<String> existingTimes; // times to check duplicates against
  final ReminderEntry? initialEntry; // non-null = edit mode
  final String title;

  const _NewReminderModal({
    required this.onConfirm,
    this.existingTimes = const [],
    this.initialEntry,
    this.title = 'NEW REMINDERS',
  });

  @override
  State<_NewReminderModal> createState() => _NewReminderModalState();
}

class _NewReminderModalState extends State<_NewReminderModal> {
  late TextEditingController _timeCtrl;
  late String _type;
  late String _schedule;
  late Set<String> _weekDays;
  late TextEditingController _daysBeforeCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initialEntry;
    _timeCtrl = TextEditingController(text: init?.time ?? '12:00');
    _type = init?.type ?? 'notification';
    _schedule = init?.schedule ?? 'always';
    _weekDays = Set.from(init?.weekDays ?? {});
    _daysBeforeCtrl = TextEditingController(text: '${init?.daysBefore ?? 1}');
  }

  static const List<String> _days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  @override
  void dispose() {
    _timeCtrl.dispose();
    _daysBeforeCtrl.dispose();
    super.dispose();
  }

  Widget _typeIcon(String t, IconData icon, String label) {
    final selected = _type == t;
    return GestureDetector(
      onTap: () => setState(() => _type = t),
      child: Column(
        children: [
          Icon(icon, color: selected ? Colors.white : Colors.white38, size: 32),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            color: selected ? Colors.white : Colors.white38,
            fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _radioRow(String value, String label, {Widget? child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _schedule = value),
          child: Row(
            children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  color: _schedule == value ? Colors.white : Colors.transparent,
                ),
                child: _schedule == value
                    ? Center(child: Container(width: 6, height: 6,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)))
                    : null,
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ],
          ),
        ),
        if (_schedule == value && child != null) Padding(padding: const EdgeInsets.only(left: 28, top: 8), child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Center(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
            ),
            // ── Time display — tap to open picker ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final parts = _timeCtrl.text.split(':');
                      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '12') ?? 12;
                      final m = int.tryParse(parts.length > 1 ? parts[1] : '00') ?? 0;
                      await showDialog(
                        context: context,
                        builder: (_) => _TimePickerDialog(
                          initialHour: h,
                          initialMinute: m,
                          onConfirm: (hour, minute) {
                            setState(() {
                              _timeCtrl.text =
                                  '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                            });
                          },
                        ),
                      );
                    },
                    child: Center(
                      child: Text(
                        _timeCtrl.text,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      'REMINDER TIME',
                      style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Full-width divider below REMINDER TIME
            Container(height: 0.5, color: Colors.white24),
            // ── Reminder Type ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REMINDER TYPE',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _typeIcon('none', Icons.notifications_off, "DON'T REMIND"),
                      _typeIcon('notification', Icons.notifications, 'NOTIFICATION'),
                      _typeIcon('alarm', Icons.alarm, 'ALARM'),
                    ],
                  ),
                ],
              ),
            ),
            // Full-width divider below REMINDER TYPE
            Container(height: 0.5, color: Colors.white24),
            // ── Reminder Schedule ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REMINDER SCHEDULE',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 10),
                  _radioRow('always', 'ALWAYS ENABLED'),
                  const SizedBox(height: 10),
                  _radioRow('week', 'SPECIFIC DAYS OF THE WEEK', child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _days.map((d) {
                      final sel = _weekDays.contains(d);
                      return GestureDetector(
                        onTap: () => setState(() => sel ? _weekDays.remove(d) : _weekDays.add(d)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel ? Colors.white38 : const Color(0xFF444444),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d,
                            style: TextStyle(
                              color: sel ? Colors.white : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  )),
                  const SizedBox(height: 10),
                  _radioRow('before', 'DAYS BEFORE', child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: _daysBeforeCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white,
                          ),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DAYS BEFORE',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  )),
                ],
              ),
            ),
            // Full-width divider above CANCEL/CONFIRM
            Container(height: 0.5, color: Colors.white24),
            // ── CANCEL | CONFIRM with vertical divider ──
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            'CANCEL',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 0.5, color: Colors.white24),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final newTime = _timeCtrl.text.trim();
                        // Check for duplicate time
                        if (widget.existingTimes.contains(newTime)) {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF2C2C2C),
                              title: const Text('Duplicate Reminder',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                              content: const Text('A reminder already exists at that time',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        final entry = ReminderEntry(
                          time: newTime,
                          type: _type,
                          schedule: _schedule,
                          weekDays: Set.from(_weekDays),
                          daysBefore: int.tryParse(_daysBeforeCtrl.text) ?? 1,
                        );
                        widget.onConfirm(entry);
                        Navigator.pop(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            'CONFIRM',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
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

// ── PRIORITY MODAL ──
class _PriorityModal extends StatefulWidget {
  final int priority;
  final void Function(int) onChanged;
  const _PriorityModal({required this.priority, required this.onChanged});

  @override
  State<_PriorityModal> createState() => _PriorityModalState();
}

class _PriorityModalState extends State<_PriorityModal> {
  late int _val;

  @override
  void initState() {
    super.initState();
    _val = widget.priority;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'SET A PRIORITY',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
            ),
            // Full-width divider
            Container(height: 0.5, color: Colors.white24),
            // ── Counter row: [-] [value] [+] in a rounded container ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // Minus
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() { if (_val > 1) _val--; }),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Icon(Icons.remove, color: Colors.white54, size: 24),
                            ),
                          ),
                        ),
                      ),
                      // Vertical divider
                      Container(width: 0.5, color: Colors.white12),
                      // Value
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              '${_val}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      // Vertical divider
                      Container(width: 0.5, color: Colors.white12),
                      // Plus
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _val++),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Icon(Icons.add, color: Colors.white54, size: 24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // DEFAULT label
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF444444),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'DEFAULT = 1 🏳',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // Full-width divider
            Container(height: 0.5, color: Colors.white24),
            // CLOSE
            GestureDetector(
              onTap: () {
                widget.onChanged(_val);
                Navigator.pop(context);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'CLOSE',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
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

// ── HABIT FREQUENCY SCREEN ──
// Step 3 of habit creation flow
// Reached after HabitDetailScreen (name + description)
// User selects how often the habit repeats
class HabitFrequencyScreen extends StatefulWidget {
  final String category;
  final String startDate;
  final String title;
  final String description;

  const HabitFrequencyScreen({
    super.key,
    required this.category,
    required this.startDate,
    required this.title,
    required this.description,
  });

  @override
  State<HabitFrequencyScreen> createState() => _HabitFrequencyScreenState();
}

class _HabitFrequencyScreenState extends State<HabitFrequencyScreen> {
  // Which frequency option is selected
  String _selected = 'EVERY DAY';

  // ── Specific Days of the Week ──
  final Map<String, bool> _weekDays = {
    'MONDAY': false, 'TUESDAY': false, 'WEDNESDAY': false,
    'THURSDAY': false, 'FRIDAY': false, 'SATURDAY': false, 'SUNDAY': false,
  };

  // ── Specific Days of the Month ──
  final Set<int> _monthDays = {};

  // ── Specific Days of the Year ──
  final List<DateTime> _yearDays = [];
  bool _showYearDatePicker = false;
  int _pickerMonth = DateTime.now().month;
  int _pickerDay = DateTime.now().day;

  // ── Specific Days per Period ──
  int _periodDays = 1;
  String _periodUnit = 'WEEK';
  bool _showPeriodDropdown = false;

  // ── Repeat ──
  int _repeatEvery = 1;

  static const List<String> _monthNames = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  String _formatYearDay(DateTime d) {
    return '${_monthNames[d.month - 1]} ${d.day}';
  }

  Widget _buildRadio(String option) {
    final bool selected = _selected == option;
    return GestureDetector(
      onTap: () => setState(() {
        _selected = option;
        _showYearDatePicker = false;
        _showPeriodDropdown = false;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Fix 1: Radio circle — white border always, white fill + black inner dot when selected
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: selected ? Colors.white : Colors.transparent,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Fix 2: No underline on selected — TextDecoration.none always
            Text(
              option,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Specific Days of the Week sub-UI ──
  // Fix 3: symmetric, evenly spaced, properly aligned
  // Layout: 3 cols per row (MON TUE WED / THU FRI SAT / SUN)
  // Each cell is fixed width so all columns align perfectly
  Widget _buildWeekDays() {
    final days = _weekDays.keys.toList();
    // 3 items per row, each in a fixed-width Expanded cell
    final rows = <Widget>[];
    for (int i = 0; i < days.length; i += 3) {
      final rowDays = days.sublist(i, i + 3 > days.length ? days.length : i + 3);
      // Pad to 3 items so last row aligns with others
      while (rowDays.length < 3) rowDays.add('');
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 32),
        child: Row(
          children: rowDays.map((day) {
            if (day.isEmpty) return const Expanded(child: SizedBox());
            final checked = _weekDays[day]!;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _weekDays[day] = !checked),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Square checkbox
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.5),
                        color: checked ? Colors.white : Colors.transparent,
                      ),
                      child: checked
                          ? const Icon(Icons.check, size: 14, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      day,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  // ── Specific Days of the Month sub-UI ──
  // Fix 4: clean 7-column grid, uniform item size, Last in same grid row
  // All items (1-31 + Last) are in one flat list rendered as a 7-col grid
  // Each cell is fixed 36x36 so the grid is perfectly aligned
  Widget _buildMonthDays() {
    // Build flat list: 1-31 then 0=Last
    final allItems = [...List.generate(31, (i) => i + 1), 0];
    final List<Widget> rows = [];

    for (int i = 0; i < allItems.length; i += 7) {
      final rowItems = allItems.sublist(
          i, i + 7 > allItems.length ? allItems.length : i + 7);
      // Pad to 7 so last row aligns
      while (rowItems.length < 7) rowItems.add(-1); // -1 = empty cell

      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: rowItems.map((d) {
            if (d == -1) {
              // Empty cell — same fixed size, invisible
              return const SizedBox(width: 36, height: 36);
            }
            final isLast = d == 0;
            final label = isLast ? 'Last' : '$d';
            final selected = _monthDays.contains(d);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) _monthDays.remove(d); else _monthDays.add(d);
              }),
              child: Container(
                // Last gets a wider pill shape, others are fixed circle
                width: isLast ? 52 : 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  // Fix 1: selected = white fill; unselected = transparent
                  color: selected ? Colors.white : Colors.transparent,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      // Fix 1: selected = black text; unselected = white text
                      color: selected ? Colors.black : Colors.white,
                      fontSize: isLast ? 13 : 15,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  // ── Specific Days of the Year sub-UI ──
  Widget _buildYearDays() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._yearDays.asMap().entries.map((entry) {
          final i = entry.key;
          final d = entry.value;
          return Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 8),
            child: Row(
              children: [
                Text(
                  _formatYearDay(d),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _yearDays.removeAt(i)),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() {
                    _pickerMonth = DateTime.now().month;
                    _pickerDay = DateTime.now().day;
                    _showYearDatePicker = true;
                  }),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ),
          );
        }),
        if (_yearDays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _pickerMonth = DateTime.now().month;
                _pickerDay = DateTime.now().day;
                _showYearDatePicker = true;
              }),
              child: const Row(
                children: [
                  Text(
                    'SELECT AT LEAST ONE DAY',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.add, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        if (_showYearDatePicker) _buildYearDatePickerDialog(),
      ],
    );
  }

  Widget _buildYearDatePickerDialog() {
    final months = _monthNames;
    return Container(
      margin: const EdgeInsets.only(left: 32, right: 0, top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'SELECT A DATE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: Row(
              children: [
                // Month picker
                Expanded(
                  flex: 2,
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 32,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => setState(() => _pickerMonth = i + 1),
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (ctx, i) => Center(
                        child: Text(
                          months[i],
                          style: TextStyle(
                            color: _pickerMonth == i + 1 ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: _pickerMonth == i + 1 ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                      childCount: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Day picker
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 32,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => setState(() => _pickerDay = i + 1),
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (ctx, i) => Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: _pickerDay == i + 1 ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: _pickerDay == i + 1 ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                      childCount: 31,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => _showYearDatePicker = false),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _yearDays.add(DateTime(2000, _pickerMonth, _pickerDay));
                    _showYearDatePicker = false;
                  });
                },
                child: const Text(
                  'OK',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Specific Days per Period sub-UI ──
  // Fix 2: clean aligned layout — underlined number, even spacing
  // matches: "  ___1___  DAYS PER   WEEK  ∨"
  Widget _buildPeriodDays() {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Underlined number input — fixed width so it doesn't shift
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
                    ..selection = TextSelection.collapsed(offset: '$_periodDays'.length),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) setState(() => _periodDays = n);
                  },
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'DAYS PER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 12),
              // Period unit + dropdown arrow
              GestureDetector(
                onTap: () => setState(() => _showPeriodDropdown = !_showPeriodDropdown),
                child: Row(
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
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ],
          ),
          if (_showPeriodDropdown)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ['WEEK', 'MONTH', 'YEAR'].map((unit) {
                  return GestureDetector(
                    onTap: () => setState(() {
                      _periodUnit = unit;
                      _showPeriodDropdown = false;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        unit,
                        style: TextStyle(
                          color: _periodUnit == unit ? Colors.white : Colors.white54,
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
    );
  }

  // ── Repeat sub-UI ──
  // Fix 3: balanced layout — EVERY [underlined number] DAYS, evenly spaced
  Widget _buildRepeat() {
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 8, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'EVERY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          // Underlined number input — centered text, fixed width
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
              controller: TextEditingController(text: '$_repeatEvery')
                ..selection = TextSelection.collapsed(offset: '$_repeatEvery'.length),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) setState(() => _repeatEvery = n);
              },
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'DAYS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Title
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

              // Scrollable frequency options
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. EVERY DAY
                      _buildRadio('EVERY DAY'),

                      // 2. SPECIFIC DAYS OF THE WEEK
                      _buildRadio('SPECIFIC DAYS OF THE WEEK'),
                      if (_selected == 'SPECIFIC DAYS OF THE WEEK') _buildWeekDays(),

                      // 3. SPECIFIC DAYS OF THE MONTH
                      _buildRadio('SPECIFIC DAYS OF THE MONTH'),
                      if (_selected == 'SPECIFIC DAYS OF THE MONTH') _buildMonthDays(),

                      // 4. SPECIFIC DAYS OF THE YEAR
                      _buildRadio('SPECIFIC DAYS OF THE YEAR'),
                      if (_selected == 'SPECIFIC DAYS OF THE YEAR') _buildYearDays(),

                      // 5. SPECIFIC DAYS PER PERIOD
                      _buildRadio('SPECIFIC DAYS PER PERIOD'),
                      if (_selected == 'SPECIFIC DAYS PER PERIOD') _buildPeriodDays(),

                      // 6. REPEAT
                      _buildRadio('REPEAT'),
                      if (_selected == 'REPEAT') _buildRepeat(),
                    ],
                  ),
                ),
              ),

              // Bottom nav: BACK • dots • NEXT
              const SizedBox(height: 16),
              Row(
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
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1))),
                      const SizedBox(width: 6),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.transparent, shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1))),
                    ],
                  ),
                  GestureDetector(
                    onTap: () async {
                      // Navigate to schedule screen — passing all data so far
                      final result = await Navigator.push<Map<String, String>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HabitScheduleScreen(
                            category: widget.category,
                            title: widget.title,
                            description: widget.description,
                            frequency: _selected,
                            initialStartDate: widget.startDate,
                          ),
                        ),
                      );
                      // Bubble result up if user saved
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                      // If user pressed BACK, stay on frequency screen
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
            ],
          ),
        ),
      ),
    );
  }
}

// ── HABIT DETAIL SCREEN ──
// Reached after user selects a category (any category except Create Category)
// User inputs: Habit Name (required) + Description (optional)
// BACK returns to category screen. NEXT adds the habit and returns to main screen.
class HabitDetailScreen extends StatefulWidget {
  final String category;
  final String startDate;

  const HabitDetailScreen({
    super.key,
    required this.category,
    required this.startDate,
  });

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── DEFINE YOUR HABIT title ──
              const Text(
                'DEFINE YOUR HABIT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 40),

              // ── HABIT name input (required) ──
              TextField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                decoration: const InputDecoration(
                  hintText: 'HABIT',
                  hintStyle: TextStyle(
                    color: Colors.white38,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24, width: 1),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── DESCRIPTION input (optional) ──
              TextField(
                controller: _descController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                decoration: const InputDecoration(
                  hintText: 'DESCRIPTION (OPTIONAL)',
                  hintStyle: TextStyle(
                    color: Colors.white38,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24, width: 1),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 1),
                  ),
                ),
              ),

              const Spacer(),

              // ── Bottom nav: BACK • pagination dots • NEXT ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // BACK — return to category screen
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

                  // Pagination dots — step 2 of flow
                  Row(
                    children: [
                      // Dot 1 — filled (current step)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Dot 2 — empty (next step)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Dot 3 — empty (next step)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 1),
                        ),
                      ),
                    ],
                  ),

                  // NEXT — confirm and return habit data
                  GestureDetector(
                    onTap: () async {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return; // require habit name
                      // Navigate to frequency screen — passing all collected data
                      final result = await Navigator.push<Map<String, String>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HabitFrequencyScreen(
                            category: widget.category,
                            startDate: widget.startDate,
                            title: name,
                            description: _descController.text.trim(),
                          ),
                        ),
                      );
                      // Bubble result up to CategorySelectionScreen → _showAddDialog
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                      // If user pressed BACK on frequency screen, stay on detail screen
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

            ],
          ),
        ),
      ),
    );
  }
}

// ── CATEGORY SELECTION SCREEN ──
// Full page — reached via Navigator.push from the habit name dialog
// User picks a category here — returns selection to previous screen
// BACK returns null — habit is NOT added if user goes back
class CategorySelectionScreen extends StatelessWidget {
  final String habitTitle;
  final String startDate; // passed from the caller — used when navigating to HabitDetailScreen

  const CategorySelectionScreen({
    super.key,
    required this.habitTitle,
    this.startDate = '',
  });

  static const List<String> categories = [
    'MEDITATION',
    'SPORT',
    'ENTERTAINMENT',
    'ART',
    'STUDY',
    'QUIT A BAD HABIT',
    'CREATE CATEGORY',
  ];

  static const String _createCategory = 'CREATE CATEGORY';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── DEFINE YOUR HABIT title — non-interactive ──
              const Text(
                'DEFINE YOUR HABIT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 32),

              // ── Category list — scrollable middle section ──
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isCreateCategory = category == _createCategory;

                    return GestureDetector(
                      onTap: () async {
                        if (isCreateCategory) {
                          // CREATE CATEGORY: keep existing behavior unchanged
                          Navigator.pop(context, category);
                        } else {
                          // Any other category: navigate to HabitDetailScreen
                          // Pass category name and startDate as parameters
                          final result = await Navigator.push<Map<String, String>>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HabitDetailScreen(
                                category: category,
                                startDate: startDate,
                              ),
                            ),
                          );
                          // If user completed the detail screen, bubble result up
                          if (result != null && context.mounted) {
                            Navigator.pop(context, result);
                          }
                          // If user pressed BACK on detail screen, stay on category screen
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── BACK button — fixed at bottom left ──
              // Returns null — habit NOT added
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
                child: const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'BACK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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

// ── START DATE MODAL ──
// Shown as an overlay on non-Today dates — stays on same page
// Background is dimmed, card appears centered in foreground
// Three options:
//   1. Selected date → navigate to category screen with selectedDate as startDate
//   2. TODAY         → navigate to category screen with today as startDate
//   3. CLOSE         → dismiss modal, no action
class StartDateModal extends StatelessWidget {
  final DateTime selectedDate;

  const StartDateModal({super.key, required this.selectedDate});

  String _formatDate(DateTime date) {
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  // Shared helper: navigate to category screen and return result to modal caller
  // Passes startDate so CategorySelectionScreen can forward it to HabitDetailScreen
  Future<void> _navigateToCategory(BuildContext context, DateTime startDate) async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => CategorySelectionScreen(
          habitTitle: '',
          startDate: startDate.toIso8601String(),
        ),
      ),
    );
    // result can be Map<String,String> from HabitDetailScreen or String from CREATE CATEGORY
    if (result != null && context.mounted) {
      if (result is Map<String, String>) {
        // Full habit data from HabitDetailScreen — bubble up to _showAddDialog
        Navigator.pop(context, result);
      } else if (result is String) {
        // CREATE CATEGORY selected — return minimal result
        Navigator.pop(context, {
          'category': result,
          'startDate': startDate.toIso8601String(),
        });
      }
    }
    // If user pressed BACK on category screen, modal stays open (do nothing)
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── START DATE label — header, not tappable ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 1),
                ),
              ),
              child: const Center(
                child: Text(
                  'START DATE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // ── Option 1: Selected date ──
            // Tapping navigates to category screen with selectedDate as startDate
            GestureDetector(
              onTap: () => _navigateToCategory(context, selectedDate),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.black, width: 1),
                  ),
                ),
                child: Center(
                  child: Text(
                    _formatDate(selectedDate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            // ── Option 2: TODAY ──
            // Tapping navigates to category screen with today's date as startDate
            GestureDetector(
              onTap: () => _navigateToCategory(context, DateTime.now()),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.black, width: 1),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            // ── Option 3: CLOSE ──
            // Dismisses modal only — no navigation, no state change
            // HitTestBehavior.opaque ensures entire row registers taps
            // including transparent/empty areas — consistent with other options
            GestureDetector(
              onTap: () => Navigator.pop(context, null),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: const Center(
                  child: Text(
                    'CLOSE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
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
    );
  }
}

class HabitHomePage extends StatefulWidget {
  const HabitHomePage({super.key});
  @override
  State<HabitHomePage> createState() => _HabitHomePageState();
}

class _HabitHomePageState extends State<HabitHomePage> {
  // ── SOURCE OF TRUTH ──
  // selectedDate: the single source of truth for selection
  DateTime _selectedDate = DateTime.now();

  // visibleWeekStart: the Monday of the currently visible 7-day strip
  // Independent of selectedDate — only changed by bottom arrows
  late DateTime _visibleWeekStart;

  final List<Habit> _habits = [];
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  @override
  void initState() {
    super.initState();
    // Initialize visible week to the Monday of the current week
    _visibleWeekStart = _getMondayOf(_selectedDate);
  }

  // ── HELPERS ──

  // Get Monday of the week containing [date]
  DateTime _getMondayOf(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  // Get the 7 days of the visible strip
  List<DateTime> get _visibleWeekDays {
    return List.generate(7, (i) => _visibleWeekStart.add(Duration(days: i)));
  }

  // Format selectedDate as full label: "Thursday, 20 Feb 2026"
  String get _selectedDateLabel {
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${weekdays[_selectedDate.weekday - 1]}, '
        '${_selectedDate.day} '
        '${months[_selectedDate.month - 1]} '
        '${_selectedDate.year}';
  }

  // Full month name from selectedDate — top large text
  String get _selectedMonthName {
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return months[_selectedDate.month - 1];
  }

  // ── TOP ARROWS: Change month of selectedDate, reset to day 1 ──
  void _previousMonth() {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month - 1,
        1,
      );
      // Move visible strip to show the week of the new selectedDate
      _visibleWeekStart = _getMondayOf(_selectedDate);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month + 1,
        1,
      );
      // Move visible strip to show the week of the new selectedDate
      _visibleWeekStart = _getMondayOf(_selectedDate);
    });
  }

  // ── BOTTOM ARROWS: Shift 7-day strip only — do NOT change selectedDate ──
  void _shiftWeekBack() {
    setState(() {
      _visibleWeekStart = _visibleWeekStart.subtract(const Duration(days: 7));
      // selectedDate is NOT changed
    });
  }

  void _shiftWeekForward() {
    setState(() {
      _visibleWeekStart = _visibleWeekStart.add(const Duration(days: 7));
      // selectedDate is NOT changed
    });
  }

  // ── USER TAPS A DATE: Only this updates selectedDate ──
  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      // Top month label auto-updates because it derives from selectedDate
      // Visible strip does NOT change — user stays in same viewport
    });
  }

  // ── HABITS ──
  void _toggleHabit(String id) {
    setState(() {
      final h = _habits.firstWhere((h) => h.id == id);
      h.isDone = !h.isDone;
    });
  }

  // ── Tap + → conditional navigation based on selected date context ──
  // TODAY context → go directly to CategorySelectionScreen (existing behavior)
  // NON-TODAY context → go to StartDateScreen first (new behavior)
  Future<void> _showAddDialog() async {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    if (isToday) {
      // ── TODAY: navigate to category screen with today's date as startDate ──
      final result = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
          builder: (_) => CategorySelectionScreen(
            habitTitle: '',
            startDate: now.toIso8601String(),
          ),
        ),
      );
      if (result != null && mounted) {
        if (result is Map<String, String>) {
          // Full result from HabitDetailScreen — use title from user input
          setState(() => _habits.add(Habit(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: result['title'] ?? result['category'] ?? '',
                category: result['category'] ?? '',
              )));
        } else if (result is String) {
          // CREATE CATEGORY returned a string
          setState(() => _habits.add(Habit(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: result,
                category: result,
              )));
        }
      }
    } else {
      // ── NON-TODAY: modal overlay on same screen — no navigation ──
      // Background dims. User stays on same page. Tap outside or CLOSE to dismiss.
      // TODAY row inside modal navigates to category screen then returns result.
      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        barrierDismissible: true,
        builder: (_) => StartDateModal(selectedDate: _selectedDate),
      );
      if (result != null && mounted) {
        setState(() => _habits.add(Habit(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: result['title'] ?? result['category'] ?? '',
              category: result['category'] ?? '',
            )));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final visibleDays = _visibleWeekDays;

    // Format today's date for sidebar: "WEDNESDAY" / "APRIL 15, 2026"
    final now = DateTime.now();
    final sidebarWeekdays = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY'
    ];
    final sidebarMonths = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    final sidebarDayName = sidebarWeekdays[now.weekday - 1];
    final sidebarDateLine =
        '${sidebarMonths[now.month - 1]} ${now.day}, ${now.year}';

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
                // Day name — e.g. WEDNESDAY
                Text(
                  sidebarDayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                // Date line — e.g. APRIL 15, 2026
                Text(
                  sidebarDateLine,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 32),
                // TODAY label
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // HABITS label
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'HABITS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
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

            // ── TOP BAR: selected date label (left) + icons (right) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top-left label — STATIC layout, visibility-only toggle for "TODAY"
                  // Layout never shifts. "TODAY" is always in the tree but opacity = 0 when not today.
                  // Burger icon added to the LEFT of the date text — same row, no layout shift.
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Burger menu icon — left of date text, purely visual
                        GestureDetector(
                          onTap: _openDrawer,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(
                              Icons.menu,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        // Date column — unchanged in every way
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "TODAY" label — always occupies space, only opacity changes
                            Opacity(
                              opacity: () {
                                final now = DateTime.now();
                                return (_selectedDate.year == now.year &&
                                        _selectedDate.month == now.month &&
                                        _selectedDate.day == now.day)
                                    ? 1.0
                                    : 0.0;
                              }(),
                              child: const Text(
                                'TODAY',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Formatted date — always visible, always same position
                            Text(
                              _selectedDateLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Right icons
                  Row(children: [
                    const Icon(Icons.search, color: Colors.white, size: 22),
                    const SizedBox(width: 18),
                    const Icon(Icons.calendar_month, color: Colors.white, size: 22),
                    const SizedBox(width: 18),
                    const Text(
                      '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ]),
                ],
              ),
            ),

            // ── HABITS TITLE ──
            const Center(
              child: Text(
                'HABITS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── TOP ARROWS + MONTH LABEL ──
            // Month text derives from selectedDate — always accurate
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top-left arrow → previous month
                  GestureDetector(
                    onTap: _previousMonth,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),

                  // Month label — strictly derived from selectedDate
                  Text(
                    _selectedMonthName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),

                  // Top-right arrow → next month
                  GestureDetector(
                    onTap: _nextMonth,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── BOTTOM ARROWS + 7-DAY STRIP ──
            // Bottom arrows shift the viewport only — selectedDate unchanged
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Bottom-left arrow → shift strip back 7 days
                  GestureDetector(
                    onTap: _shiftWeekBack,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.white54,
                        size: 22,
                      ),
                    ),
                  ),

                  // 7-day date strip
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (i) {
                        final day = visibleDays[i];

                        // isSelected: matches selectedDate exactly
                        final isSelected =
                            day.year == _selectedDate.year &&
                            day.month == _selectedDate.month &&
                            day.day == _selectedDate.day;

                        return GestureDetector(
                          // Tapping a date updates selectedDate
                          // Top month label auto-updates as it derives from selectedDate
                          onTap: () => _selectDate(day),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Day label
                              Text(
                                dayLabels[i],
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Date number with circle
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.white,
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Dot indicator — marks real system TODAY always
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: (day.year == DateTime.now().year &&
                                          day.month == DateTime.now().month &&
                                          day.day == DateTime.now().day)
                                      ? Colors.white
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),

                  // Bottom-right arrow → shift strip forward 7 days
                  GestureDetector(
                    onTap: _shiftWeekForward,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white54,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Container(height: 0.5, color: Colors.white12),

            // ── HABIT LIST ──
            Expanded(
              child: _habits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white24,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'NO HABITS YET',
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap + to add your first habit',
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: _habits.length,
                      itemBuilder: (context, index) {
                        final habit = _habits[index];
                        return Dismissible(
                          key: Key(habit.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => setState(() =>
                              _habits.removeWhere((h) => h.id == habit.id)),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red.withValues(alpha: 0.2),
                            child: const Text(
                              'DELETE',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          child: GestureDetector(
                            onTap: () => _toggleHabit(habit.id),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white10,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: habit.isDone
                                        ? Colors.white
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: habit.isDone
                                          ? Colors.white
                                          : Colors.white38,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: habit.isDone
                                      ? const Icon(Icons.check,
                                          color: Colors.black, size: 13)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    habit.title,
                                    style: TextStyle(
                                      color: habit.isDone
                                          ? Colors.white38
                                          : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      decoration: habit.isDone
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      decorationColor: Colors.white38,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // ── FLOATING + BUTTON ──
      floatingActionButton: GestureDetector(
        onTap: _showAddDialog,
        child: Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2C),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}