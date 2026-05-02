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

// ── CATEGORY SELECTION SCREEN ──
// Full page — reached via Navigator.push from the habit name dialog
// User picks a category here — returns selection to previous screen
// BACK returns null — habit is NOT added if user goes back
class CategorySelectionScreen extends StatelessWidget {
  final String habitTitle;

  const CategorySelectionScreen({super.key, required this.habitTitle});

  static const List<String> categories = [
    'MEDITATION',
    'SPORT',
    'ENTERTAINMENT',
    'ART',
    'STUDY',
    'QUIT A BAD HABIT',
    'CREATE CATEGORY',
  ];

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
              const SizedBox(height: 32),

              // ── Category list — scrollable middle section ──
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      // Tapping a category returns it to the dialog screen
                      // which then adds the habit and closes
                      onTap: () => Navigator.pop(context, categories[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          categories[index],
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

// ── START DATE SCREEN ──
// Shown when user taps + on a non-Today date
// Matches the reference image: dark card with START DATE, date, TODAY, CLOSE
class StartDateScreen extends StatelessWidget {
  final DateTime selectedDate;

  const StartDateScreen({super.key, required this.selectedDate});

  String _formatDate(DateTime date) {
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // START DATE label
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
              // Selected date
              Container(
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
              // TODAY option — navigate to category screen for today
              GestureDetector(
                onTap: () async {
                  // User picks TODAY as start date → go to category screen
                  final selectedCategory = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CategorySelectionScreen(
                        habitTitle: '',
                      ),
                    ),
                  );
                  if (selectedCategory != null && context.mounted) {
                    Navigator.pop(context, {
                      'category': selectedCategory,
                      'startDate': 'today',
                    });
                  }
                },
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
              // CLOSE — dismiss without adding
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
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
      // ── TODAY: existing behavior — direct to category screen ──
      final selectedCategory = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const CategorySelectionScreen(habitTitle: ''),
        ),
      );
      if (selectedCategory != null && mounted) {
        setState(() => _habits.add(Habit(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: selectedCategory,
              category: selectedCategory,
            )));
      }
    } else {
      // ── NON-TODAY: new behavior — show StartDateScreen first ──
      final result = await Navigator.push<Map<String, String>>(
        context,
        MaterialPageRoute(
          builder: (_) => StartDateScreen(selectedDate: _selectedDate),
        ),
      );
      if (result != null && mounted) {
        setState(() => _habits.add(Habit(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: result['category'] ?? '',
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