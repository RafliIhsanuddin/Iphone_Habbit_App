import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  int _selectedNav = 0;

  // Sample habit data: date -> list of (name, done)
  final Map<String, List<Map<String, dynamic>>> _habits = {
    _key(DateTime.now()): [
      {'name': 'Morning Meditation', 'done': true},
      {'name': 'Exercise 30 min', 'done': false},
      {'name': 'Read 20 pages', 'done': true},
      {'name': 'Cold Shower', 'done': false},
    ],
    _key(DateTime.now().subtract(const Duration(days: 1))): [
      {'name': 'Morning Meditation', 'done': true},
      {'name': 'Exercise 30 min', 'done': true},
      {'name': 'Read 20 pages', 'done': true},
      {'name': 'Cold Shower', 'done': true},
    ],
    _key(DateTime.now().subtract(const Duration(days: 2))): [
      {'name': 'Morning Meditation', 'done': false},
      {'name': 'Exercise 30 min', 'done': true},
      {'name': 'Read 20 pages', 'done': false},
      {'name': 'Cold Shower', 'done': true},
    ],
  };

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  List<Map<String, dynamic>> get _selectedHabits =>
      _habits[_key(_selectedDay)] ?? [];

  int get _completedCount =>
      _selectedHabits.where((h) => h['done'] == true).length;

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildCalendar(),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            _buildDaySummary(),
            Expanded(child: _buildHabitList()),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                months[_focusedMonth.month - 1],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                '${_focusedMonth.year}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _NavButton(icon: CupertinoIcons.chevron_left, onTap: _previousMonth),
              const SizedBox(width: 4),
              _NavButton(icon: CupertinoIcons.chevron_right, onTap: _nextMonth),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 0=Sun, 6=Sat

    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Weekday labels
          Row(
            children: weekdays.map((d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF999999),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox();
              final day = index - startWeekday + 1;
              final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
              return _DayCell(
                day: day,
                date: date,
                isSelected: _isSameDay(date, _selectedDay),
                isToday: _isSameDay(date, DateTime.now()),
                habitDots: _getHabitDots(date),
                onTap: () => setState(() => _selectedDay = date),
              );
            },
          ),
        ],
      ),
    );
  }

  List<bool> _getHabitDots(DateTime date) {
    final habits = _habits[_key(date)];
    if (habits == null) return [];
    return habits.map<bool>((h) => h['done'] == true).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDaySummary() {
    final weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final total = _selectedHabits.length;
    final done = _completedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weekdays[_selectedDay.weekday % 7],
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              Text(
                '${months[_selectedDay.month - 1]} ${_selectedDay.day}, ${_selectedDay.year}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF888888),
                ),
              ),
            ],
          ),
          if (total > 0)
            _ProgressRing(done: done, total: total),
        ],
      ),
    );
  }

  Widget _buildHabitList() {
    if (_selectedHabits.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.checkmark_circle, size: 40, color: Color(0xFFCCCCCC)),
            SizedBox(height: 10),
            Text(
              'No habits for this day',
              style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      itemCount: _selectedHabits.length,
      separatorBuilder: (_, a) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final habit = _selectedHabits[index];
        return _HabitRow(
          name: habit['name'] as String,
          done: habit['done'] as bool,
          onToggle: () {
            setState(() {
              _habits.putIfAbsent(_key(_selectedDay), () => _selectedHabits);
              _habits[_key(_selectedDay)]![index]['done'] =
                  !_habits[_key(_selectedDay)]![index]['done'];
            });
          },
        );
      },
    );
  }

  Widget _buildBottomNav() {
    final items = [
      (CupertinoIcons.calendar, 'Calendar'),
      (CupertinoIcons.chart_bar, 'Stats'),
      (CupertinoIcons.person, 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final selected = _selectedNav == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedNav = i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[i].$1,
                    size: 24,
                    color: selected ? Colors.black : const Color(0xFFBBBBBB),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.black : const Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: Colors.black),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final List<bool> habitDots;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.habitDots,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected ? Colors.white : Colors.black;
    final bgColor = isSelected
        ? Colors.black
        : isToday
            ? const Color(0xFFF0F0F0)
            : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : isToday
                          ? Colors.black
                          : Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          _buildDots(textColor),
        ],
      ),
    );
  }

  Widget _buildDots(Color selectedTextColor) {
    if (habitDots.isEmpty) return const SizedBox(height: 5);
    final dots = habitDots.take(4).toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: dots.map((done) {
        return Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? (isSelected ? Colors.white : Colors.black)
                : (isSelected ? Colors.white38 : const Color(0xFFCCCCCC)),
          ),
        );
      }).toList(),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final String name;
  final bool done;
  final VoidCallback onToggle;

  const _HabitRow({
    required this.name,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: done ? Colors.black : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              size: 22,
              color: done ? Colors.white : const Color(0xFFCCCCCC),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: done ? Colors.white : Colors.black,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final int done;
  final int total;
  const _ProgressRing({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 3.5,
            backgroundColor: const Color(0xFFE8E8E8),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
            strokeCap: StrokeCap.round,
          ),
        ),
        Text(
          '$done/$total',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}
