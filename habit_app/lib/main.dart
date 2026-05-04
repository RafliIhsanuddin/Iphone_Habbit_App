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

  static const List<String> _options = [
    'EVERY DAY',
    'SPECIFIC DAYS OF THE WEEK',
    'SPECIFIC DAYS OF THE MONTH',
    'SPECIFIC DAYS OF THE YEAR',
    'SPECIFIC DAYS PER PERIOD',
    'REPEAT',
  ];

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
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: selected ? Colors.white : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.circle, size: 10, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              option,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: 0.3,
                decoration: selected ? TextDecoration.underline : TextDecoration.none,
                decorationColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Specific Days of the Week sub-UI ──
  Widget _buildWeekDays() {
    final days = _weekDays.keys.toList();
    final rows = <Widget>[];
    for (int i = 0; i < days.length; i += 3) {
      final rowDays = days.sublist(i, i + 3 > days.length ? days.length : i + 3);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 32),
        child: Row(
          children: rowDays.map((day) {
            final checked = _weekDays[day]!;
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () => setState(() => _weekDays[day] = !checked),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.5),
                        color: checked ? Colors.white : Colors.transparent,
                      ),
                      child: checked
                          ? const Icon(Icons.check, size: 12, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      day.substring(0, 3 > day.length ? day.length : 3) == day.substring(0,
                          day.length > 3 ? 3 : day.length)
                          ? day
                          : day,
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
  Widget _buildMonthDays() {
    final List<Widget> rows = [];
    final allDays = [...List.generate(31, (i) => i + 1)];
    for (int i = 0; i < allDays.length; i += 7) {
      final rowItems = allDays.sublist(i, i + 7 > allDays.length ? allDays.length : i + 7);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: rowItems.map((d) {
            final selected = _monthDays.contains(d);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) _monthDays.remove(d); else _monthDays.add(d);
              }),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                  color: Colors.transparent,
                ),
                child: Center(
                  child: Text(
                    '$d',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
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
    // Add LAST button row
    rows.add(Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() {
              if (_monthDays.contains(0)) _monthDays.remove(0); else _monthDays.add(0);
            }),
            child: Container(
              width: 60,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _monthDays.contains(0) ? Colors.white : Colors.transparent, width: 2),
              ),
              child: Center(
                child: Text(
                  'Last',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: _monthDays.contains(0) ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ));
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
                  Icon(Icons.add, color: Colors.white38, size: 18),
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
  Widget _buildPeriodDays() {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                child: TextField(
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
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
              const SizedBox(width: 8),
              const Text(
                'DAYS PER',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _showPeriodDropdown = !_showPeriodDropdown),
                child: Row(
                  children: [
                    Text(
                      _periodUnit,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ],
          ),
          if (_showPeriodDropdown)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: ['WEEK', 'MONTH', 'YEAR'].map((unit) {
                return GestureDetector(
                  onTap: () => setState(() {
                    _periodUnit = unit;
                    _showPeriodDropdown = false;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 24),
                    child: Text(
                      unit,
                      style: TextStyle(
                        color: _periodUnit == unit ? Colors.white : Colors.white54,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── Repeat sub-UI ──
  Widget _buildRepeat() {
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
      child: Row(
        children: [
          const Text(
            'EVERY',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            child: TextField(
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
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
          const SizedBox(width: 8),
          const Text(
            'DAYS',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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
                    onTap: () {
                      // Return all habit data including frequency
                      Navigator.pop(context, {
                        'title': widget.title,
                        'description': widget.description,
                        'category': widget.category,
                        'startDate': widget.startDate,
                        'frequency': _selected,
                      });
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