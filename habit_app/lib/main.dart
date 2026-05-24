import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
import 'dart:async';

void main() => runApp(const HabitApp());

class HabitApp extends StatelessWidget {
  const HabitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Habits',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Colors.black),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
        home: const HabitHomePage(),
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
  final String id, title, category, description;
  String frequency;
  int priority;
  List<ReminderEntry> reminders;
  DateTime startDate;
  DateTime? endDate;
  final Map<String, HabitState> dailyState = {};
  final Map<String, String> dailyNote = {};
  Map<String,bool> freqWeekDays;
  Set<int> freqMonthDays;
  List<DateTime> freqYearDays;
  int freqPeriodDays;
  String freqPeriodUnit;
  int freqRepeatEvery;

  Habit({required this.id, required this.title, this.category = '', this.description = '', this.priority = 1, List<ReminderEntry>? reminders, required this.startDate, this.endDate, this.frequency = 'EVERY DAY', Map<String,bool>? freqWeekDays, Set<int>? freqMonthDays, List<DateTime>? freqYearDays, this.freqPeriodDays = 1, this.freqPeriodUnit = 'WEEK', this.freqRepeatEvery = 1})
      : reminders = reminders ?? [],
        freqWeekDays = freqWeekDays ?? {'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false},
        freqMonthDays = freqMonthDays ?? {},
        freqYearDays = freqYearDays ?? [];

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) return false;
    if (endDate != null && d.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day))) return false;
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
  HabitScheduleResult({required this.title, required this.description, required this.category, required this.startDate, required this.frequency, required this.endDate, required this.priority, required this.reminders, Map<String,bool>? freqWeekDays, Set<int>? freqMonthDays, List<DateTime>? freqYearDays, this.freqPeriodDays=1, this.freqPeriodUnit='WEEK', this.freqRepeatEvery=1})
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
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialNote); }
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
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
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
            onTap: () { widget.onConfirm(_ctrl.text.trim()); Navigator.pop(context); },
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

class _CategorySelectDialog extends StatefulWidget {
  final void Function(String) onSelected;
  const _CategorySelectDialog({required this.onSelected});
  @override State<_CategorySelectDialog> createState() => _CategorySelectDialogState();
}
class _CategorySelectDialogState extends State<_CategorySelectDialog> {
  final _scrollCtrl = ScrollController();
  static const _categories = [
    'MEDITATION','SPORT','ENTERTAINMENT','ART','STUDY',
    'QUIT A BAD HABIT',
  ];
  static const _manageCategory = 'MANAGE CATEGORIES';
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
              onTap: () { widget.onSelected(_manageCategory); Navigator.pop(context); },
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


class _FrequencyEditResult {
  final String frequency;
  final Map<String,bool> weekDays;
  final Set<int> monthDays;
  final List<DateTime> yearDays;
  final int periodDays;
  final String periodUnit;
  final int repeatEvery;
  _FrequencyEditResult({required this.frequency,required this.weekDays,required this.monthDays,required this.yearDays,required this.periodDays,required this.periodUnit,required this.repeatEvery});
}


// ─── Edit Habit Screen ────────────────────────────────────────────────────────

class EditHabitScreen extends StatefulWidget {
  final Habit habit;
  final VoidCallback onDelete;
  const EditHabitScreen({super.key, required this.habit, required this.onDelete});
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
      initialDate: widget.habit.endDate ?? widget.habit.startDate.add(const Duration(days: 60)),
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
        onSelected: (cat) => setState(() => _category = cat),
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
          setState(() {
            _reminders = updated;
            widget.habit.reminders
              ..clear()
              ..addAll(updated);
          });
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
      });
    }
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
                            Navigator.pop(context);
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

                    // 11. ARCHIVE
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            'ARCHIVE HABIT',
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

                    // 12. RESTART HABIT PROGRESS
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
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
  final DateTime selectedDay;
  final void Function(HabitState) onStateChanged;
  final void Function(String) onNoteChanged;
  final VoidCallback onDelete;
  const _HabitBottomSheet({
    required this.habit,
    required this.selectedDay,
    required this.onStateChanged,
    required this.onNoteChanged,
    required this.onDelete,
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
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => EditHabitScreen(
          habit: widget.habit,
          onDelete: widget.onDelete,
        ),
      ),
    );
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
          Container(
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
                    ? Text(_note.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3))
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
              onTap: () { Navigator.pop(context); },
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
  const HabitFrequencyScreen({super.key,required this.category,required this.startDate,required this.title,required this.description,this.initialFrequency,this.editMode=false,this.initialWeekDays,this.initialMonthDays,this.initialYearDays,this.initialPeriodDays,this.initialPeriodUnit,this.initialRepeatEvery});
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
    return Padding(padding:const EdgeInsets.only(left:48,top:8,bottom:4),child:Row(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.center,children:[
      const Text('EVERY',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
      const SizedBox(width:12),
      SizedBox(width:44,child:TextField(keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.only(bottom:2),border:InputBorder.none),controller:TextEditingController(text:'$_repeatEvery')..selection=TextSelection.collapsed(offset:'$_repeatEvery'.length),onChanged: (v) {
  final n = int.tryParse(v);
  if (n != null && n > 0) setState(() => _repeatEvery = n);
},)),
      const SizedBox(width:12),
      const Text('DAYS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
    ]));
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
  @override void initState(){super.initState();final p=DateTime.tryParse(widget.initialStartDate)??DateTime.now();_start=p;final n=DateTime.now();_startIsToday=p.year==n.year&&p.month==n.month&&p.day==n.day;_end=_start.add(const Duration(days:60));}
  @override void dispose(){_dCtrl.dispose();super.dispose();}
  String _fmt(DateTime d)=>'${d.month}/${d.day}/${d.year%100}';
  String _lbl()=>_startIsToday?'TODAY':_fmt(_start);
  DateTime _compEnd(){final n=int.tryParse(_dCtrl.text)??60;return _start.add(Duration(days:n));}
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
      if(_endEnabled)...[Container(height:0.5,color:Colors.white12),Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[GestureDetector(onTap:_pickE,child:_pill(ed)),const SizedBox(width:16),SizedBox(width:80,child:TextField(controller:_dCtrl,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.symmetric(vertical:2),border:InputBorder.none),onChanged:(v){if(v.trim().isEmpty){setState(()=>_end=DateTime.now());return;}final n=int.tryParse(v);if(n!=null&&n>0)setState(()=>_end=_start.add(Duration(days:n)));})),const SizedBox(width:16),const Text('DAYS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5))]))],
      _row('TIME AND REMINDERS',GestureDetector(onTap:_showR,child:Container(width:32,height:32,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:Center(child:Text('${_reminders.length}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700))))),onRowTap:_showR),
      _row('PRIORITY',GestureDetector(onTap:_showP,child:_pill(_priority==1?'DEFAULT':'${_priority}🏳')),onRowTap:_showP),
      const Spacer(),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        GestureDetector(onTap:()=>Navigator.pop(context,null),child:const Text('BACK',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
        Row(children:[Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1)))]),
        GestureDetector(onTap:(){
          if(_endEnabled){final ee=_end??DateTime.now();final sd=DateTime(_start.year,_start.month,_start.day);final ed2=DateTime(ee.year,ee.month,ee.day);if(!ed2.isAfter(sd)){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:const Text('End date must be after start date',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));return;}}
          Navigator.pop(context,HabitScheduleResult(title:widget.title,description:widget.description,category:widget.category,startDate:_start.toIso8601String(),frequency:widget.frequency,endDate:_endEnabled&&_end!=null?_end!.toIso8601String():'',priority:_priority,reminders:List.from(_reminders)));
        },child:const Text('SAVE',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
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

class CategorySelectionScreen extends StatelessWidget {
  final String habitTitle,startDate;
  const CategorySelectionScreen({super.key,required this.habitTitle,this.startDate=''});
  static const _cats=['MEDITATION','SPORT','ENTERTAINMENT','ART','STUDY','QUIT A BAD HABIT','CREATE CATEGORY'];
  @override
  Widget build(BuildContext context){
    return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,32,24,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('DEFINE YOUR HABIT',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:1)),
      const SizedBox(height:32),
      Expanded(child:ListView.builder(padding:EdgeInsets.zero,itemCount:_cats.length,itemBuilder:(ctx,i){
        final c=_cats[i];
        return GestureDetector(onTap:()async{
          if(c=='CREATE CATEGORY'){Navigator.pop(context,c);return;}
          final res=await Navigator.push<HabitScheduleResult>(context,MaterialPageRoute(builder:(_)=>HabitDetailScreen(category:c,startDate:startDate)));
          if(res!=null&&context.mounted)Navigator.pop(context,res);
        },child:Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Text(c,style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))));
      })),
      GestureDetector(onTap:()=>Navigator.pop(context,null),child:const Padding(padding:EdgeInsets.only(top:16),child:Text('BACK',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5)))),
    ]))));
  }
}

// ─── Start Date Modal ─────────────────────────────────────────────────────────

class StartDateModal extends StatelessWidget {
  final DateTime selectedDate;
  const StartDateModal({super.key,required this.selectedDate});
  String _fmt(DateTime d){const m=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];return '${m[d.month-1]} ${d.day}, ${d.year}';}
  Future<void> _nav(BuildContext ctx,DateTime sd)async{
    final res=await Navigator.push<dynamic>(ctx,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:sd.toIso8601String())));
    if(res!=null&&ctx.mounted){
      if(res is HabitScheduleResult)Navigator.pop(ctx,res);
      else if(res is String)Navigator.pop(ctx,HabitScheduleResult(title:res,description:'',category:res,startDate:sd.toIso8601String(),frequency:'',endDate:'',priority:1,reminders:[]));
    }
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
  const _HabitAnimatedList({
    required this.habits,
    required this.selectedDay,
    required this.buildReminderIcon,
    required this.earliestReminderTime,
    required this.buildStatusIcon,
    required this.onTap,
    required this.onDismiss,
    required this.onLongPress,
  });
  @override State<_HabitAnimatedList> createState() => _HabitAnimatedListState();
}

class _HabitAnimatedListState extends State<_HabitAnimatedList> {
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
    return Dismissible(
      key:Key('d_${habit.id}'),
      direction:DismissDirection.endToStart,
      onDismissed:(_)=>widget.onDismiss(habit.id),
      background:Container(alignment:Alignment.centerRight,padding:const EdgeInsets.only(right:20),color:Colors.red.withValues(alpha:0.2),child:const Text('DELETE',style:TextStyle(color:Colors.red,fontSize:11,letterSpacing:2,fontWeight:FontWeight.w700))),
      child:GestureDetector(
        onTap:()=>widget.onTap(habit.id),
        onLongPress:()=>widget.onLongPress(habit.id),
        child:Container(padding:const EdgeInsets.symmetric(vertical:16),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.white10,width:0.5))),child:Row(children:[
          Text(habit.title.toUpperCase(),style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,letterSpacing:0.3)),
          if(habit.priority>1)...[const SizedBox(width:6),Text('${habit.priority}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),const SizedBox(width:2),const Icon(Icons.flag,color:Colors.white,size:14)],
          if(icon!=null)...[const SizedBox(width:6),icon,if(time!=null)...[const SizedBox(width:4),Text(time,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w600))]],
          if(icon==null&&time!=null)...[const SizedBox(width:6),Text(time,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w600))],
          const Spacer(),
          widget.buildStatusIcon(state, hasReminders),
        ])),
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

// ─── Habit Home Page ──────────────────────────────────────────────────────────

class HabitHomePage extends StatefulWidget {
  const HabitHomePage({super.key});
  @override State<HabitHomePage> createState() => _HabitHomePageState();
}

class _HabitHomePageState extends State<HabitHomePage> {
  DateTime _sel=DateTime.now();
  late DateTime _weekStart;
  final List<Habit> _all=[];
  final _ctrl=TextEditingController();
  final _scaffoldKey=GlobalKey<ScaffoldState>();

  @override void initState(){super.initState();_weekStart=_monday(_sel);}
  DateTime _monday(DateTime d)=>d.subtract(Duration(days:d.weekday-1));
  List<DateTime> get _week=>List.generate(7,(i)=>_weekStart.add(Duration(days:i)));

  String get _dateLabel{
    const wd=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const m=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wd[_sel.weekday-1]}, ${_sel.day} ${m[_sel.month-1]} ${_sel.year}';
  }
  String get _monthName{const m=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];return m[_sel.month-1];}

  void _prevMonth()=>setState((){_sel=DateTime(_sel.year,_sel.month-1,1);_weekStart=_monday(_sel);});
  void _nextMonth()=>setState((){_sel=DateTime(_sel.year,_sel.month+1,1);_weekStart=_monday(_sel);});
  void _back()=>setState(()=>_weekStart=_weekStart.subtract(const Duration(days:7)));
  void _fwd()=>setState(()=>_weekStart=_weekStart.add(const Duration(days:7)));
  void _pick(DateTime d)=>setState(()=>_sel=d);

  List<Habit> _forDay(DateTime d)=>_all.where((h)=>h.isActiveOn(d)).toList();

  double _progress(DateTime day){
    final h=_forDay(day);
    if(h.isEmpty)return 0;
    return h.where((x)=>x.stateOn(day)==HabitState.done).length/h.length;
  }

  List<Habit> get _sorted{
    final h=_forDay(_sel);
    final empty=h.where((x)=>x.stateOn(_sel)==HabitState.empty||x.stateOn(_sel)==HabitState.skipped).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    final done=h.where((x)=>x.stateOn(_sel)!=HabitState.empty&&x.stateOn(_sel)!=HabitState.skipped).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    return [...empty,...done];
  }

  void _cycle(String id){
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
        selectedDay: _sel,
        onStateChanged: (s) {
          setState(() => habit.setStateOn(_sel, s));
        },
        onNoteChanged: (n) {
          setState(() => habit.setNoteOn(_sel, n));
        },
        onDelete: () {
          setState(() => _all.removeWhere((h) => h.id == id));
        },
      ),
    );
  }

  Future<void> _add()async{
    final now=DateTime.now();
    final isToday=_sel.year==now.year&&_sel.month==now.month&&_sel.day==now.day;
    if(isToday){
      final res=await Navigator.push<dynamic>(context,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:now.toIso8601String())));
      if(res!=null&&mounted)_addFromResult(res);
    }else{
      final res=await showDialog<dynamic>(context:context,barrierColor:Colors.black.withValues(alpha:0.75),barrierDismissible:true,builder:(_)=>StartDateModal(selectedDate:_sel));
      if(res!=null&&mounted)_addFromResult(res);
    }
  }

  void _addFromResult(dynamic r){
    if(r is HabitScheduleResult){
      final sd=DateTime.tryParse(r.startDate)??DateTime.now();
      final ed=r.endDate.isNotEmpty?DateTime.tryParse(r.endDate):null;
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r.title.isNotEmpty?r.title:r.category,category:r.category,description:r.description,priority:r.priority,reminders:r.reminders,startDate:sd,endDate:ed,frequency:r.frequency,freqWeekDays:Map.from(r.freqWeekDays),freqMonthDays:Set.from(r.freqMonthDays),freqYearDays:List.from(r.freqYearDays),freqPeriodDays:r.freqPeriodDays,freqPeriodUnit:r.freqPeriodUnit,freqRepeatEvery:r.freqRepeatEvery)));
    }else if(r is String){
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r,category:r,description:'',startDate:DateTime.now())));
    }else if(r is Map){
      final sd=r['startDate']!=null?DateTime.tryParse(r['startDate'] as String)??DateTime.now():DateTime.now();
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:((r['title']??r['category'])as String?)??' ',category:(r['category']as String?)??' ',description:(r['description']as String?)??' ',startDate:sd)));
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
        GestureDetector(onTap:()=>Navigator.pop(context),child:const Text('HABITS',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:0.5))),
      ])))),
      body:SafeArea(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Expanded(child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
            GestureDetector(onTap:()=>_scaffoldKey.currentState?.openDrawer(),child:const Padding(padding:EdgeInsets.only(right:10),child:Icon(Icons.menu,color:Colors.white,size:22))),
            Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
              Opacity(opacity:(_sel.year==now.year&&_sel.month==now.month&&_sel.day==now.day)?1.0:0.0,child:const Text('TODAY',style:TextStyle(color:Colors.white38,fontSize:11,fontWeight:FontWeight.w600,letterSpacing:2))),
              const SizedBox(height:2),
              Text(_dateLabel,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w600,letterSpacing:0.3)),
            ]),
          ])),
          Row(children:[const Icon(Icons.search,color:Colors.white,size:22),const SizedBox(width:18),const Icon(Icons.calendar_month,color:Colors.white,size:22),const SizedBox(width:18),const Text('?',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w300))]),
        ])),
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
        Expanded(child:sorted.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Container(width:56,height:56,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white12)),child:const Icon(Icons.add,color:Colors.white24,size:28)),const SizedBox(height:16),const Text('NO HABITS YET',style:TextStyle(color:Colors.white24,fontSize:12,letterSpacing:3,fontWeight:FontWeight.w600)),const SizedBox(height:6),const Text('Tap + to add your first habit',style:TextStyle(color:Colors.white24,fontSize:12))]))
          :_HabitAnimatedList(
              habits:sorted,
              selectedDay:_sel,
              buildReminderIcon:_reminderIcon,
              earliestReminderTime:_earliestTime,
              buildStatusIcon:_statusIcon,
              onTap:_cycle,
              onDismiss:(id)=>setState(()=>_all.removeWhere((h)=>h.id==id)),
              onLongPress:_longPress,
            )),
      ])),
      floatingActionButton:GestureDetector(onTap:_add,child:Container(width:54,height:54,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:const Icon(Icons.add,color:Colors.white,size:26))),
    );
  }

  @override void dispose(){_ctrl.dispose();super.dispose();}
}