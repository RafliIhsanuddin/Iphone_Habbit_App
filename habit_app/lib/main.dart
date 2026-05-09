import 'package:flutter/material.dart';
import 'dart:math' as math;

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

// ── Models ──
class ReminderEntry {
  String time, type, schedule;
  Set<String> weekDays;
  int daysBefore;
  ReminderEntry({this.time = '12:00', this.type = 'notification', this.schedule = 'always', Set<String>? weekDays, this.daysBefore = 1}) : weekDays = weekDays ?? {};
}

enum HabitState { empty, done, failed }

class Habit {
  final String id, title, category, frequency;
  int priority;
  List<ReminderEntry> reminders;
  final DateTime startDate;
  final DateTime? endDate;
  // Per-day state: 'yyyy-MM-dd' → HabitState
  final Map<String, HabitState> dailyState = {};

  Habit({required this.id, required this.title, this.category = '', this.priority = 1, List<ReminderEntry>? reminders, required this.startDate, this.endDate, this.frequency = 'EVERY DAY'}) : reminders = reminders ?? [];

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) return false;
    if (endDate != null && d.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day))) return false;
    return true;
  }

  HabitState stateOn(DateTime day) => dailyState[_key(day)] ?? HabitState.empty;
  void setStateOn(DateTime day, HabitState s) => dailyState[_key(day)] = s;
}

class HabitScheduleResult {
  final String title, description, category, startDate, frequency, endDate;
  final int priority;
  final List<ReminderEntry> reminders;
  HabitScheduleResult({required this.title, required this.description, required this.category, required this.startDate, required this.frequency, required this.endDate, required this.priority, required this.reminders});
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
                Expanded(child: GestureDetector(onTap: () => setState(() { if (_val > 1) _val--; }), child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF888888), shape: BoxShape.circle), child: const Icon(Icons.remove, color: Colors.white, size: 20)))))),
                Container(width: 1.5, color: Colors.white24),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('$_val', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800))))),
                Container(width: 1.5, color: Colors.white24),
                Expanded(child: GestureDetector(onTap: () => setState(() => _val++), child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF888888), shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 20)))))),
              ])),
            ),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF888888), borderRadius: BorderRadius.circular(20)), child: const Text('DEFAULT = 1 🏳', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
          Container(height: 0.5, color: Colors.white24),
          GestureDetector(onTap: () { widget.onChanged(_val); Navigator.pop(context); }, child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('CLOSE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))))),
        ]),
      ),
    );
  }
}

// ── TIME PICKER DIALOG ──
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
        Container(height: 0.5, color: Colors.white24),
        IntrinsicHeight(child: Row(children: [
          Expanded(child: GestureDetector(onTap: ()=>Navigator.pop(context), child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: Text('CANCEL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
          Container(width: 0.5, color: Colors.white24),
          Expanded(child: GestureDetector(onTap: (){_finalH();_finalM();widget.onConfirm(_hour,_minute);Navigator.pop(context);}, child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: Text('OK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)))))),
        ])),
      ]),
    );
  }
}

// ── REMINDERS MODAL ──
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
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: const Text('TIME AND REMINDERS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)))),
        Container(height: 0.5, color: Colors.white24),
        Flexible(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(20,0,20,0), child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_list.isEmpty) ...[const SizedBox(height:20), const Icon(Icons.notifications_off, color: Colors.white, size: 48), const SizedBox(height:8), const Text('NO REMINDERS FOR THIS ACTIVITY', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)), const SizedBox(height:20)]
          else ...[
            ..._list.asMap().entries.map((e) {
              final i=e.key; final r=e.value;
              final icon = r.type=='none'?Icons.notifications_off:r.type=='alarm'?Icons.alarm:Icons.notifications;
              final sched = r.schedule=='always'?'ALWAYS ENABLED':r.schedule=='before'?'${r.daysBefore} DAYS BEFORE':r.weekDays.join(' . ');
              return Column(children: [
                SizedBox(height: 60, child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: ()=>_edit(i), child: Row(children: [
                    Container(width:36,height:36,decoration:const BoxDecoration(color:Color(0xFF444444),shape:BoxShape.circle),child:Icon(icon,color:Colors.white70,size:18)),
                    const SizedBox(width:12),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(r.time,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800)),Text(sched,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54,fontSize:11,letterSpacing:0.5))])),
                    const SizedBox(width:48),
                  ]))),
                  Positioned(right:0,top:0,bottom:0,child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: (){setState((){_list.removeAt(i);widget.onChanged(List.from(_list));});}, child: Center(child: Container(width:36,height:36,decoration:const BoxDecoration(color:Color(0xFF444444),shape:BoxShape.circle),child:const Icon(Icons.delete_outline,color:Colors.white70,size:18))))),
                ])),
                Container(height: 0.5, color: Colors.white12),
              ]);
            }),
            const SizedBox(height:4),
          ],
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: GestureDetector(onTap: _add, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_circle_outline,color:Colors.white,size:18),SizedBox(width:6),Text('NEW REMINDER',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700,letterSpacing:0.5))]))),
        ])))),
        Container(height: 0.5, color: Colors.white24),
        GestureDetector(onTap: (){widget.onChanged(_list);Navigator.pop(context);}, child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('CLOSE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5))))),
      ])),
    );
  }
}

// ── NEW/EDIT REMINDER MODAL ──
class _NewReminderModal extends StatefulWidget {
  final void Function(ReminderEntry) onConfirm;
  final List<String> existingTimes;
  final ReminderEntry? initialEntry;
  final String title;
  const _NewReminderModal({required this.onConfirm, this.existingTimes=const[], this.initialEntry, this.title='NEW REMINDERS'});
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
    _tCtrl=TextEditingController(text:init?.time??'12:00');
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
            await showDialog(context:context,builder:(_)=>_TimePickerDialog(initialHour:int.tryParse(p.isNotEmpty?p[0]:'12')??12,initialMinute:int.tryParse(p.length>1?p[1]:'00')??0,onConfirm:(h,m){setState(()=>_tCtrl.text='${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}');}));
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
          Expanded(child:GestureDetector(onTap:()=>Navigator.pop(context),child:const Padding(padding:EdgeInsets.symmetric(vertical:14),child:Center(child:Text('CANCEL',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
          Container(width:0.5,color:Colors.white24),
          Expanded(child:GestureDetector(onTap:(){
            final t=_tCtrl.text.trim();
            if(widget.existingTimes.contains(t)){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:const Text('Duplicate Reminder',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),content:const Text('A reminder already exists at that time',style:TextStyle(color:Colors.white70,fontSize:13)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));return;}
            widget.onConfirm(ReminderEntry(time:t,type:_type,schedule:_schedule,weekDays:Set.from(_weekDays),daysBefore:int.tryParse(_dbCtrl.text)??1));
            Navigator.pop(context);
          },child:const Padding(padding:EdgeInsets.symmetric(vertical:14),child:Center(child:Text('CONFIRM',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
        ])),
      ])),
    );
  }
}

// ── HABIT FREQUENCY SCREEN ──
class HabitFrequencyScreen extends StatefulWidget {
  final String category,startDate,title,description;
  const HabitFrequencyScreen({super.key,required this.category,required this.startDate,required this.title,required this.description});
  @override State<HabitFrequencyScreen> createState() => _HabitFrequencyScreenState();
}
class _HabitFrequencyScreenState extends State<HabitFrequencyScreen> {
  String _sel='EVERY DAY';
  final Map<String,bool> _wDays={'MONDAY':false,'TUESDAY':false,'WEDNESDAY':false,'THURSDAY':false,'FRIDAY':false,'SATURDAY':false,'SUNDAY':false};
  final Set<int> _mDays={};
  final List<DateTime> _yDays=[];
  bool _showYPicker=false;
  int _pMonth=DateTime.now().month,_pDay=DateTime.now().day,_periodDays=1,_repeatEvery=1;
  String _periodUnit='WEEK';
  bool _showPDrop=false;
  static const _mNames=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];

  Widget _radio(String opt){
    final sel=_sel==opt;
    return GestureDetector(onTap:()=>setState((){_sel=opt;_showYPicker=false;_showPDrop=false;}),child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
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
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ..._yDays.asMap().entries.map((e){final i=e.key;final d=e.value;return Padding(padding:const EdgeInsets.only(left:32,bottom:8),child:Row(children:[Text('${_mNames[d.month-1]} ${d.day}',style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.3)),const Spacer(),GestureDetector(onTap:()=>setState(()=>_yDays.removeAt(i)),child:const Icon(Icons.delete_outline,color:Colors.white,size:20)),const SizedBox(width:12),GestureDetector(onTap:()=>setState((){_pMonth=DateTime.now().month;_pDay=DateTime.now().day;_showYPicker=true;}),child:const Icon(Icons.add,color:Colors.white,size:20))]));},),
      if(_yDays.isEmpty)Padding(padding:const EdgeInsets.only(left:32,bottom:8),child:GestureDetector(onTap:()=>setState((){_pMonth=DateTime.now().month;_pDay=DateTime.now().day;_showYPicker=true;}),child:const Row(children:[Text('SELECT AT LEAST ONE DAY',style:TextStyle(color:Colors.white38,fontSize:14,fontWeight:FontWeight.w600,letterSpacing:0.5)),SizedBox(width:8),Icon(Icons.add,color:Colors.white,size:18)]))),
      if(_showYPicker)Container(margin:const EdgeInsets.only(left:32,top:4,bottom:8),decoration:BoxDecoration(color:const Color(0xFF2C2C2C),borderRadius:BorderRadius.circular(12)),padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Center(child:Text('SELECT A DATE',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700,letterSpacing:1))),
        const SizedBox(height:12),
        SizedBox(height:100,child:Row(children:[
          Expanded(flex:2,child:ListWheelScrollView.useDelegate(itemExtent:32,physics:const FixedExtentScrollPhysics(),onSelectedItemChanged:(i)=>setState(()=>_pMonth=i+1),childDelegate:ListWheelChildBuilderDelegate(builder:(c,i)=>Center(child:Text(_mNames[i],style:TextStyle(color:_pMonth==i+1?Colors.white:Colors.white38,fontSize:14,fontWeight:_pMonth==i+1?FontWeight.w700:FontWeight.w400))),childCount:12))),
          const SizedBox(width:8),
          Expanded(child:ListWheelScrollView.useDelegate(itemExtent:32,physics:const FixedExtentScrollPhysics(),onSelectedItemChanged:(i)=>setState(()=>_pDay=i+1),childDelegate:ListWheelChildBuilderDelegate(builder:(c,i)=>Center(child:Text('${i+1}',style:TextStyle(color:_pDay==i+1?Colors.white:Colors.white38,fontSize:14,fontWeight:_pDay==i+1?FontWeight.w700:FontWeight.w400))),childCount:31))),
        ])),
        const SizedBox(height:12),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[GestureDetector(onTap:()=>setState(()=>_showYPicker=false),child:const Text('CANCEL',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700))),GestureDetector(onTap:()=>setState((){_yDays.add(DateTime(2000,_pMonth,_pDay));_showYPicker=false;}),child:const Text('OK',style:TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))]),
      ])),
    ]);
  }

  Widget _periodUI(){
    return Padding(padding:const EdgeInsets.only(left:32,top:8,bottom:4),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        SizedBox(width:44,child:TextField(keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.only(bottom:2),border:InputBorder.none),controller:TextEditingController(text:'$_periodDays')..selection=TextSelection.collapsed(offset:'$_periodDays'.length),onChanged:(v){final n=int.tryParse(v);if(n!=null&&n>0)setState(()=>_periodDays=n);})),
        const SizedBox(width:12),
        const Text('DAYS PER',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
        const SizedBox(width:12),
        GestureDetector(onTap:()=>setState(()=>_showPDrop=!_showPDrop),child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[Text(_periodUnit,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),const SizedBox(width:6),const Icon(Icons.keyboard_arrow_down,color:Colors.white,size:22)])),
      ]),
      if(_showPDrop)Padding(padding:const EdgeInsets.only(top:8,left:120),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:['WEEK','MONTH','YEAR'].map((u)=>GestureDetector(onTap:()=>setState((){_periodUnit=u;_showPDrop=false;}),child:Padding(padding:const EdgeInsets.only(bottom:6),child:Text(u,style:TextStyle(color:_periodUnit==u?Colors.white:Colors.white54,fontSize:15,fontWeight:FontWeight.w700,letterSpacing:0.5))))).toList())),
    ]));
  }

  Widget _repeatUI(){
    return Padding(padding:const EdgeInsets.only(left:48,top:8,bottom:4),child:Row(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.center,children:[
      const Text('EVERY',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
      const SizedBox(width:12),
      SizedBox(width:44,child:TextField(keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.only(bottom:2),border:InputBorder.none),controller:TextEditingController(text:'$_repeatEvery')..selection=TextSelection.collapsed(offset:'$_repeatEvery'.length),onChanged:(v){final n=int.tryParse(v);if(n!=null&&n>0)setState(()=>_repeatEvery=n);})),
      const SizedBox(width:12),
      const Text('DAYS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5)),
    ]));
  }

  void _alert(String msg){showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF2C2C2C),title:Text(msg,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('OK',style:TextStyle(color:Colors.white)))]));}

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,32,24,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('PREFERRED FREQUENCY?',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5)),
      const SizedBox(height:20),
      Expanded(child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _radio('EVERY DAY'),
        _radio('SPECIFIC DAYS OF THE WEEK'),if(_sel=='SPECIFIC DAYS OF THE WEEK')_wDaysUI(),
        _radio('SPECIFIC DAYS OF THE MONTH'),if(_sel=='SPECIFIC DAYS OF THE MONTH')_mDaysUI(),
        _radio('SPECIFIC DAYS OF THE YEAR'),if(_sel=='SPECIFIC DAYS OF THE YEAR')_yDaysUI(),
        _radio('SOME DAYS PER PERIOD'),if(_sel=='SOME DAYS PER PERIOD')_periodUI(),
        _radio('REPEAT'),if(_sel=='REPEAT')_repeatUI(),
      ]))),
      const SizedBox(height:16),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        GestureDetector(onTap:()=>Navigator.pop(context,null),child:const Text('BACK',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
        Row(children:[Container(width:8,height:8,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle)),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1))),const SizedBox(width:6),Container(width:8,height:8,decoration:BoxDecoration(color:Colors.transparent,shape:BoxShape.circle,border:Border.all(color:Colors.white38,width:1)))]),
        GestureDetector(onTap:()async{
          if(_sel=='SPECIFIC DAYS OF THE WEEK'&&!_wDays.values.any((v)=>v)){_alert('Select at least one day');return;}
          if(_sel=='SPECIFIC DAYS OF THE MONTH'&&_mDays.isEmpty){_alert('Select at least one day');return;}
          if(_sel=='SPECIFIC DAYS OF THE YEAR'&&_yDays.isEmpty){_alert('Select at least one day');return;}
          final res=await Navigator.push<HabitScheduleResult>(context,MaterialPageRoute(builder:(_)=>_ScheduleScreen(category:widget.category,title:widget.title,description:widget.description,frequency:_sel,initialStartDate:widget.startDate)));
          if(res!=null&&context.mounted)Navigator.pop(context,res);
        },child:const Text('NEXT',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:0.5))),
      ]),
    ]))));
  }
}

// ── SCHEDULE SCREEN ──
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
  Widget _row(String l,Widget r)=>Column(children:[Container(height:0.5,color:Colors.white12),Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(l,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800,letterSpacing:0.3)),r]))]);
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
      _row('START DATE',GestureDetector(onTap:_pickS,child:_pill(_lbl()))),
      _row('END DATE',Switch(value:_endEnabled,onChanged:(v)=>setState((){_endEnabled=v;if(v)_end=_compEnd();}),activeColor:Colors.white,activeTrackColor:const Color(0xFF555555),inactiveThumbColor:Colors.white38,inactiveTrackColor:const Color(0xFF333333))),
      if(_endEnabled)...[Container(height:0.5,color:Colors.white12),Padding(padding:const EdgeInsets.symmetric(vertical:14),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[GestureDetector(onTap:_pickE,child:_pill(ed)),const SizedBox(width:16),SizedBox(width:80,child:TextField(controller:_dCtrl,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,decoration:TextDecoration.underline,decorationColor:Colors.white),decoration:const InputDecoration(isDense:true,contentPadding:EdgeInsets.symmetric(vertical:2),border:InputBorder.none),onChanged:(v){if(v.trim().isEmpty){setState(()=>_end=DateTime.now());return;}final n=int.tryParse(v);if(n!=null&&n>0)setState(()=>_end=_start.add(Duration(days:n)));})),const SizedBox(width:16),const Text('DAYS',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.5))]))],
      _row('TIME AND REMINDERS',GestureDetector(onTap:_showR,child:Container(width:32,height:32,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:Center(child:Text('${_reminders.length}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)))))),
      _row('PRIORITY',GestureDetector(onTap:_showP,child:_pill(_priority==1?'DEFAULT':'${_priority}🏳'))),
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

// ── HABIT DETAIL SCREEN ──
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
      TextField(controller:_n,autofocus:true,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),decoration:const InputDecoration(hintText:'HABIT',hintStyle:TextStyle(color:Colors.white38,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white24,width:1)),focusedBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white,width:1)))),
      const SizedBox(height:28),
      TextField(controller:_d,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),decoration:const InputDecoration(hintText:'DESCRIPTION (OPTIONAL)',hintStyle:TextStyle(color:Colors.white38,fontSize:16,fontWeight:FontWeight.w600,letterSpacing:0.5),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white24,width:1)),focusedBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white,width:1)))),
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

// ── CATEGORY SELECTION SCREEN ──
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

// ── START DATE MODAL ──
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

// ════════════════════════════════════════════════════════════
// ── CIRCULAR PROGRESS PAINTER ──
// ════════════════════════════════════════════════════════════
class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);
  @override
  void paint(Canvas c, Size s) {
    final center=Offset(s.width/2,s.height/2);
    final r=(s.width/2)-1.5;
    c.drawCircle(center,r,Paint()..color=Colors.white.withOpacity(0.14)..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
    if(progress<=0)return;
    c.drawArc(Rect.fromCircle(center:center,radius:r),-math.pi/2,2*math.pi*progress.clamp(0.0,1.0),false,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
  }
  @override bool shouldRepaint(_RingPainter o)=>o.progress!=progress;
}

// ════════════════════════════════════════════════════════════
// ── ANIMATED HABIT LIST ──
// Uses Flutter AnimatedList with a Myers-diff to animate
// each item sliding to its new position smoothly.
// ════════════════════════════════════════════════════════════
class _HabitAnimatedList extends StatefulWidget {
  final List<Habit> habits;
  final DateTime selectedDay;
  final Widget? Function(Habit) buildReminderIcon;
  final String? Function(Habit) earliestReminderTime;
  final Widget Function(HabitState) buildStatusIcon;
  final void Function(String) onTap;
  final void Function(String) onDismiss;
  const _HabitAnimatedList({required this.habits,required this.selectedDay,required this.buildReminderIcon,required this.earliestReminderTime,required this.buildStatusIcon,required this.onTap,required this.onDismiss});
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
    // Always update the habit references in _cur so stateOn() is fresh
    for(int i=0;i<_cur.length;i++){
      final idx=widget.habits.indexWhere((h)=>h.id==_cur[i].id);
      if(idx!=-1)_cur[i]=widget.habits[idx];
    }
    // Only animate if the order changed
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

    // Step 1: Remove items no longer in next (high-to-low to keep indices valid)
    for(int i=_cur.length-1;i>=0;i--){
      if(!newIds.contains(_cur[i].id)){
        final h=_cur.removeAt(i);
        _key.currentState?.removeItem(i,(ctx,anim)=>_animated(h,anim,leaving:true),duration:_dur);
      }
    }

    // Step 2: Insert brand-new items that do not exist in _cur yet
    for(int ni=0;ni<next.length;ni++){
      if(!_cur.any((h)=>h.id==next[ni].id)){
        final insertAt=ni.clamp(0,_cur.length);
        _cur.insert(insertAt,next[ni]);
        _key.currentState?.insertItem(insertAt,duration:_dur);
      }
    }

    // Step 3: Animate reordering — process each target position in order
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
    return Dismissible(
      key:Key('d_${habit.id}'),
      direction:DismissDirection.endToStart,
      onDismissed:(_)=>widget.onDismiss(habit.id),
      background:Container(alignment:Alignment.centerRight,padding:const EdgeInsets.only(right:20),color:Colors.red.withOpacity(0.2),child:const Text('DELETE',style:TextStyle(color:Colors.red,fontSize:11,letterSpacing:2,fontWeight:FontWeight.w700))),
      child:GestureDetector(onTap:()=>widget.onTap(habit.id),child:Container(padding:const EdgeInsets.symmetric(vertical:16),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Colors.white10,width:0.5))),child:Row(children:[
        Text(habit.title.toUpperCase(),style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,letterSpacing:0.3)),
        if(habit.priority>1)...[const SizedBox(width:6),Text('${habit.priority}',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),const SizedBox(width:2),const Icon(Icons.flag,color:Colors.white,size:14)],
        if(icon!=null)...[const SizedBox(width:6),icon,if(time!=null)...[const SizedBox(width:4),Text(time,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w600))]],
        const Spacer(),
        widget.buildStatusIcon(state),
      ]))),
    );
  }

  Widget _animated(Habit h,Animation<double> anim,{bool leaving=false,bool movingDown=false}){
    // When entering: slide in from below (positive y) for items moving down in list,
    // or from above (negative y) for items moving up.
    // When leaving: slide out in the opposite direction.
    final double beginY=leaving?(movingDown?-0.5:0.5):(movingDown?0.5:-0.5);
    final double endY=leaving?(movingDown?-0.5:0.5):0.0;
    final slide=Tween<Offset>(
      begin:Offset(0,beginY),
      end:Offset(0,endY),
    ).animate(CurvedAnimation(parent:anim,curve:leaving?Curves.easeIn:Curves.easeOut));
    return SizeTransition(
      sizeFactor:anim,
      axisAlignment:-1,
      child:FadeTransition(
        opacity:anim,
        child:SlideTransition(position:slide,child:_row(h)),
      ),
    );
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

// ════════════════════════════════════════════════════════════
// ── HABIT HOME PAGE ──
// ════════════════════════════════════════════════════════════
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

  // ── Per-day habit list ──
  List<Habit> _forDay(DateTime d)=>_all.where((h)=>h.isActiveOn(d)).toList();

  // ── Per-day progress (independent) ──
  double _progress(DateTime day){
    final h=_forDay(day);
    if(h.isEmpty)return 0;
    return h.where((x)=>x.stateOn(day)==HabitState.done).length/h.length;
  }

  // ── Sorted habits for selected day ──
  List<Habit> get _sorted{
    final h=_forDay(_sel);
    final empty=h.where((x)=>x.stateOn(_sel)==HabitState.empty).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    final done=h.where((x)=>x.stateOn(_sel)!=HabitState.empty).toList()..sort((a,b)=>b.priority.compareTo(a.priority));
    return [...empty,...done];
  }

  // ── Cycle per-day state ──
  void _cycle(String id){
    setState((){
      final h=_all.firstWhere((x)=>x.id==id);
      final cur=h.stateOn(_sel);
      h.setStateOn(_sel,cur==HabitState.empty?HabitState.done:cur==HabitState.done?HabitState.failed:HabitState.empty);
    });
  }

  // ── Reminder helpers ──
  int _toMins(String t){final p=t.split(':');return(int.tryParse(p[0])??0)*60+(p.length>1?(int.tryParse(p[1])??0):0);}
  ReminderEntry? _earliest(Habit h){final a=h.reminders.where((r)=>r.type!='none').toList();if(a.isEmpty)return null;a.sort((x,y)=>_toMins(x.time).compareTo(_toMins(y.time)));return a.first;}
  String? _earliestTime(Habit h)=>_earliest(h)?.time;
  Widget? _reminderIcon(Habit h){
    final a=h.reminders.where((r)=>r.type!='none').toList();if(a.isEmpty)return null;
    final e=_earliest(h)!;final icon=e.type=='alarm'?Icons.alarm:Icons.notifications;
    if(a.length==1)return Icon(icon,color:Colors.white,size:16);
    return SizedBox(width:20,height:18,child:Stack(children:[Positioned(left:3,top:2,child:Icon(icon,color:Colors.white.withOpacity(0.5),size:14)),Positioned(left:0,top:0,child:Icon(icon,color:Colors.white,size:16))]));
  }

  Widget _statusIcon(HabitState s){
    switch(s){
      case HabitState.empty:return Container(width:26,height:26,decoration:BoxDecoration(shape:BoxShape.circle,color:Colors.white,border:Border.all(color:Colors.white,width:1.5)),child:const Icon(Icons.circle,color:Colors.white,size:14));
      case HabitState.done:return Container(width:26,height:26,decoration:const BoxDecoration(shape:BoxShape.circle,color:Colors.white),child:const Icon(Icons.check,color:Colors.black,size:16));
      case HabitState.failed:return Container(width:26,height:26,decoration:const BoxDecoration(shape:BoxShape.circle,color:Colors.white),child:const Icon(Icons.close,color:Colors.black,size:16));
    }
  }

  Future<void> _add()async{
    final now=DateTime.now();
    final isToday=_sel.year==now.year&&_sel.month==now.month&&_sel.day==now.day;
    if(isToday){
      final res=await Navigator.push<dynamic>(context,MaterialPageRoute(builder:(_)=>CategorySelectionScreen(habitTitle:'',startDate:now.toIso8601String())));
      if(res!=null&&mounted)_addFromResult(res);
    }else{
      final res=await showDialog<dynamic>(context:context,barrierColor:Colors.black.withOpacity(0.75),barrierDismissible:true,builder:(_)=>StartDateModal(selectedDate:_sel));
      if(res!=null&&mounted)_addFromResult(res);
    }
  }

  void _addFromResult(dynamic r){
    if(r is HabitScheduleResult){
      final sd=DateTime.tryParse(r.startDate)??DateTime.now();
      final ed=r.endDate.isNotEmpty?DateTime.tryParse(r.endDate):null;
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r.title.isNotEmpty?r.title:r.category,category:r.category,priority:r.priority,reminders:r.reminders,startDate:sd,endDate:ed,frequency:r.frequency)));
    }else if(r is String){
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:r,category:r,startDate:DateTime.now())));
    }else if(r is Map){
      final sd=r['startDate']!=null?DateTime.tryParse(r['startDate'] as String)??DateTime.now():DateTime.now();
      setState(()=>_all.add(Habit(id:DateTime.now().millisecondsSinceEpoch.toString(),title:((r['title']??r['category'])as String?)??' ',category:(r['category']as String?)??' ',startDate:sd)));
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
        // TOP BAR
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
        // HABITS TITLE
        const Center(child:Text('HABITS',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800,letterSpacing:3))),
        const SizedBox(height:20),
        // MONTH ROW
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          GestureDetector(onTap:_prevMonth,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_left,color:Colors.white,size:28))),
          Text(_monthName,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w700,letterSpacing:2)),
          GestureDetector(onTap:_nextMonth,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_right,color:Colors.white,size:28))),
        ])),
        const SizedBox(height:16),
        // 7-DAY STRIP with per-day progress rings
        Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Row(children:[
          GestureDetector(onTap:_back,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.chevron_left,color:Colors.white54,size:22))),
          Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:List.generate(7,(i){
            final day=week[i];
            final isSel=day.year==_sel.year&&day.month==_sel.month&&day.day==_sel.day;
            // Per-day progress — fully independent
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
        // HABIT LIST
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
            )),
      ])),
      floatingActionButton:GestureDetector(onTap:_add,child:Container(width:54,height:54,decoration:const BoxDecoration(color:Color(0xFF2C2C2C),shape:BoxShape.circle),child:const Icon(Icons.add,color:Colors.white,size:26))),
    );
  }

  @override void dispose(){_ctrl.dispose();super.dispose();}
}