import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await NotificationService.instance.init();
  runApp(const TodoApp());
}

class Task {
  Task({required this.id, required this.title, required this.createdAt,
    required this.assignedDate, this.deadline, this.completedAt, this.deleted = false});
  final String id;
  String title;
  DateTime createdAt;
  DateTime assignedDate;
  DateTime? deadline;
  DateTime? completedAt;
  bool deleted;

  bool get isCompleted => completedAt != null;
  bool isLateAt(DateTime at) => deadline != null && completedAt != null && completedAt!.isAfter(deadline!);
  bool isOverdue(DateTime now) => !isCompleted && deadline != null && now.isAfter(deadline!);

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'createdAt': createdAt.toIso8601String(),
    'assignedDate': assignedDate.toIso8601String(), 'deadline': deadline?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(), 'deleted': deleted,
  };
  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'], title: j['title'], createdAt: DateTime.parse(j['createdAt']),
    assignedDate: DateTime.parse(j['assignedDate']),
    deadline: j['deadline'] == null ? null : DateTime.parse(j['deadline']),
    completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt']),
    deleted: j['deleted'] ?? false,
  );
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  Future<void> schedule(Task task, List<int> offsets) async {
    await cancel(task.id);
    if (task.deadline == null || task.isCompleted) return;
    for (var i = 0; i < offsets.length; i++) {
      final when = task.deadline!.subtract(Duration(minutes: offsets[i]));
      if (when.isAfter(DateTime.now())) {
        await plugin.zonedSchedule(
          _notificationId(task.id, i), 'Task reminder', task.title,
          tz.TZDateTime.from(when, tz.local),
          const NotificationDetails(android: AndroidNotificationDetails(
            'task_reminders', 'Task reminders', channelDescription: 'Reminders for your tasks',
            importance: Importance.defaultImportance, priority: Priority.defaultPriority)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: task.id,
        );
      }
    }
  }
  int _notificationId(String id, int i) => (id.hashCode & 0x0fffffff) + i;
  Future<void> cancel(String id) async {
    for (var i = 0; i < 10; i++) { await plugin.cancel(_notificationId(id, i)); }
  }
}

class TodoApp extends StatefulWidget {
  const TodoApp({super.key});
  @override State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  ThemeMode mode = ThemeMode.dark;
  int themeIndex = 0;
  @override Widget build(BuildContext context) {
    final seeds = [const Color(0xFF75866A), const Color(0xFF9A7558), const Color(0xFF54758B), const Color(0xFF9B6875), const Color(0xFF777777)];
    final seed = seeds[themeIndex % seeds.length];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'To-Do List',
      themeMode: mode,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF5F2EA)),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark, surface: const Color(0xFF252923)), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFF252923)),
      home: TodoHome(onTheme: (m, i) => setState(() { mode = m; themeIndex = i; })),
    );
  }
}

typedef ThemeChanged = void Function(ThemeMode mode, int index);

class TodoHome extends StatefulWidget {
  const TodoHome({super.key, required this.onTheme});
  final ThemeChanged onTheme;
  @override State<TodoHome> createState() => _TodoHomeState();
}

enum ViewKind { today, upcoming, all, history }

class _TodoHomeState extends State<TodoHome> {
  final List<Task> tasks = [];
  final TextEditingController quick = TextEditingController();
  final FocusNode quickFocus = FocusNode();
  ViewKind view = ViewKind.today;
  bool loading = true;
  bool showAddedTime = false;
  bool remindersEnabled = true;
  List<int> reminderOffsets = [1440, 360, 60];
  ThemeMode currentMode = ThemeMode.dark;
  int themeIndex = 0;
  Task? lastChanged;
  DateTime get now => DateTime.now();
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  bool sameDay(DateTime a, DateTime b) => day(a) == day(b);

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { quick.dispose(); quickFocus.dispose(); super.dispose(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('tasks_v1');
    if (raw != null) {
      try { tasks.addAll((jsonDecode(raw) as List).map((e) => Task.fromJson(e))); } catch (_) {}
    }
    remindersEnabled = p.getBool('reminders') ?? true;
    reminderOffsets = p.getStringList('offsets')?.map(int.parse).toList() ?? [1440, 360, 60];
    showAddedTime = p.getBool('added_time') ?? false;
    themeIndex = p.getInt('theme_index') ?? 0;
    currentMode = (p.getString('theme_mode') ?? 'dark') == 'light' ? ThemeMode.light : ThemeMode.dark;
    if (todayTasks.isEmpty) {
      view = upcomingTasks.isNotEmpty ? ViewKind.upcoming : ViewKind.all;
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tasks_v1', jsonEncode(tasks.map((e) => e.toJson()).toList()));
    await p.setBool('reminders', remindersEnabled);
    await p.setStringList('offsets', reminderOffsets.map((e) => '$e').toList());
    await p.setBool('added_time', showAddedTime);
    await p.setInt('theme_index', themeIndex);
    await p.setString('theme_mode', currentMode == ThemeMode.dark ? 'dark' : 'light');
  }
  List<Task> get active => tasks.where((t) => !t.deleted && !t.isCompleted).toList();
  List<Task> get completed => tasks.where((t) => !t.deleted && t.isCompleted).toList()..sort((a,b) => b.completedAt!.compareTo(a.completedAt!));
  List<Task> get todayTasks {
    final list = active.where((t) => t.deadline == null || sameDay(t.deadline!, now) || t.deadline!.isBefore(day(now))).toList();
    list.sort((a,b) => a.createdAt.compareTo(b.createdAt)); return list;
  }
  List<Task> get upcomingTasks {
    final list = active.where((t) => t.deadline != null && day(t.deadline!).isAfter(day(now))).toList();
    list.sort((a,b) => a.deadline!.compareTo(b.deadline!)); return list;
  }
  List<Task> get allTasks {
    final list = active.toList();
    list.sort((a,b) {
      if (a.deadline == null && b.deadline != null) return 1;
      if (b.deadline == null && a.deadline != null) return -1;
      if (a.deadline != null && b.deadline != null) return a.deadline!.compareTo(b.deadline!);
      return a.createdAt.compareTo(b.createdAt);
    }); return list;
  }
  Future<void> _addTask(String text, {DateTime? deadline}) async {
    final value = text.trim(); if (value.isEmpty) return;
    final task = Task(id: '${DateTime.now().microsecondsSinceEpoch}', title: value, createdAt: now, assignedDate: day(now), deadline: deadline);
    setState(() { tasks.add(task); }); await _save();
    if (remindersEnabled) await NotificationService.instance.schedule(task, reminderOffsets);
  }
  Future<void> _toggle(Task t) async {
    setState(() { t.completedAt = t.isCompleted ? null : now; lastChanged = t; });
    if (t.isCompleted) { await NotificationService.instance.cancel(t.id); } else if (remindersEnabled) { await NotificationService.instance.schedule(t, reminderOffsets); }
    await _save();
    if (t.isCompleted && view == ViewKind.today && todayTasks.isEmpty) {
      setState(() => view = upcomingTasks.isNotEmpty ? ViewKind.upcoming : ViewKind.all);
    }
    if (!t.isCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Task restored'), action: SnackBarAction(label: 'Undo', onPressed: () => _toggle(t))));
    }
  }
  Future<void> _delete(Task t) async {
    setState(() => t.deleted = true); await NotificationService.instance.cancel(t.id); await _save();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Task deleted'), action: SnackBarAction(label: 'Undo', onPressed: () async { setState(() => t.deleted = false); await _save(); })));
  }
  Future<void> _edit(Task t) async {
    final c = TextEditingController(text: t.title);
    DateTime? deadline = t.deadline;
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Edit task'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'What needs to be done?')), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: deadline ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 10)); if (d != null) { final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(deadline ?? now)); if (tm != null) refresh(() => deadline = DateTime(d.year,d.month,d.day,tm.hour,tm.minute)); } }, icon: const Icon(Icons.schedule), label: Text(deadline == null ? 'No deadline' : DateFormat('d MMM, h:mm a').format(deadline!))), if (deadline != null) TextButton(onPressed: () => refresh(() => deadline = null), child: const Text('Remove deadline'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]))));
    if (result == true && c.text.trim().isNotEmpty) { setState(() { t.title = c.text.trim(); t.deadline = deadline; }); await _save(); if (remindersEnabled) await NotificationService.instance.schedule(t, reminderOffsets); }
    c.dispose();
  }
  Future<DateTime?> _pickDeadline() async {
    final d = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 10));
    if (d == null) return null;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (tm == null) return null;
    return DateTime(d.year,d.month,d.day,tm.hour,tm.minute);
  }
  String _dateLabel(DateTime d) => sameDay(d, now) ? 'Today' : sameDay(d, now.add(const Duration(days: 1))) ? 'Tomorrow' : DateFormat('d MMM').format(d);
  String _completionLabel(Task t) {
    final c = t.completedAt!;
    final time = DateFormat('h:mm a').format(c);
    final multiDay = t.deadline != null && !sameDay(t.deadline!, t.assignedDate);
    final carried = t.deadline == null && day(c).isAfter(t.assignedDate);
    if (!multiDay && !carried && !t.isLateAt(c)) return time;
    return '${DateFormat('d MMM').format(c)}, $time';
  }
  bool _late(Task t) => t.isCompleted && (t.isLateAt(t.completedAt!) || (t.deadline == null && day(t.completedAt!).isAfter(t.assignedDate)));

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final items = switch(view) { ViewKind.today => todayTasks, ViewKind.upcoming => upcomingTasks, ViewKind.all => allTasks, ViewKind.history => completed };
    final title = switch(view) { ViewKind.today => 'Today', ViewKind.upcoming => 'Upcoming', ViewKind.all => 'All tasks', ViewKind.history => 'Completed' };
    final doneToday = completed.where((t) => sameDay(t.completedAt!, now)).length;
    final totalToday = todayTasks.length + doneToday;
    return Scaffold(
      appBar: AppBar(title: Text('To-Do List', style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.5)), actions: [IconButton(tooltip: 'Appearance', onPressed: _openAppearance, icon: const Icon(Icons.palette_outlined)), IconButton(tooltip: 'Settings', onPressed: _openSettings, icon: const Icon(Icons.tune))]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMMM').format(now).toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1.3, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8), Row(children: [Expanded(child: Text(view == ViewKind.today ? "Today's tasks" : title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1))), IconButton(tooltip: 'Switch view', onPressed: _cycleView, icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28))]),
          if (view == ViewKind.today && totalToday > 0) ...[const SizedBox(height: 8), Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: (doneToday / totalToday).clamp(0,1), minHeight: 5, backgroundColor: cs.surfaceContainerHighest))), const SizedBox(width: 10), Text('$doneToday/$totalToday', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))])]
        ])),
        Expanded(child: items.isEmpty ? _emptyState(cs) : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), itemCount: items.length, itemBuilder: (context, index) => _taskRow(items[index], cs))),
        if (view != ViewKind.history) _quickAdd(cs),
        _bottomNav(cs),
      ])),
    );
  }
  Widget _taskRow(Task t, ColorScheme cs) {
    final overdue = t.isOverdue(now);
    final late = _late(t);
    final done = t.isCompleted;
    final danger = overdue || late;
    final stamp = done ? _completionLabel(t) : (t.deadline == null ? (showAddedTime ? 'Added ${DateFormat('h:mm a').format(t.createdAt)}' : '') : '${_dateLabel(t.deadline!)} · ${DateFormat('h:mm a').format(t.deadline!)}');
    return Dismissible(key: ValueKey(t.id), direction: DismissDirection.endToStart, background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.delete_outline, color: cs.onErrorContainer)), onDismissed: (_) => _delete(t), child: InkWell(onTap: () => _edit(t), onLongPress: () => _delete(t), borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(onTap: () => _toggle(t), customBorder: const CircleBorder(), child: Padding(padding: const EdgeInsets.all(4), child: Icon(done ? Icons.check_circle : Icons.circle_outlined, size: 23, color: done ? cs.primary : (danger ? cs.error : cs.onSurfaceVariant)))),
      const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.title, style: TextStyle(fontSize: 15, height: 1.35, decoration: done ? TextDecoration.lineThrough : null, color: done ? cs.onSurfaceVariant : (overdue ? cs.error : cs.onSurface))), if (stamp.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(stamp, style: TextStyle(fontSize: 11, color: danger ? cs.error : cs.onSurfaceVariant))) ])),
      if (!done) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Set deadline', onPressed: () async { final d = await _pickDeadline(); if (d != null) { setState(() => t.deadline = d); await _save(); if (remindersEnabled) await NotificationService.instance.schedule(t, reminderOffsets); } }, icon: Icon(Icons.schedule, size: 18, color: cs.onSurfaceVariant)),
    ]))));
  }
  Widget _quickAdd(ColorScheme cs) => Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 12), child: Row(children: [Icon(Icons.add, color: cs.primary), const SizedBox(width: 8), Expanded(child: TextField(controller: quick, focusNode: quickFocus, textInputAction: TextInputAction.done, onSubmitted: (v) async { await _addTask(v); quick.clear(); quickFocus.requestFocus(); }, decoration: const InputDecoration(hintText: 'Add a task...', border: InputBorder.none, isDense: true))), IconButton(tooltip: 'Add task with deadline', onPressed: () async { final d = await _pickDeadline(); if (d != null && quick.text.trim().isNotEmpty) { await _addTask(quick.text, deadline: d); quick.clear(); } }, icon: const Icon(Icons.event_outlined))]));
  Widget _bottomNav(ColorScheme cs) => NavigationBar(height: 66, selectedIndex: view.index, onDestinationSelected: (i) => setState(() => view = ViewKind.values[i]), destinations: const [NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'), NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Upcoming'), NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'All'), NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'Done')]);
  Widget _emptyState(ColorScheme cs) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(view == ViewKind.today ? Icons.wb_sunny_outlined : Icons.check_circle_outline, size: 42, color: cs.primary.withOpacity(.75)), const SizedBox(height: 12), Text(view == ViewKind.today ? 'Nothing on your list yet' : view == ViewKind.upcoming ? 'No upcoming deadlines' : view == ViewKind.history ? 'Nothing completed yet' : 'All clear', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)), const SizedBox(height: 5), Text(view == ViewKind.today ? 'Add a task below and get started.' : 'Your tasks will appear here.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))])));
  void _cycleView() => setState(() => view = ViewKind.values[(view.index + 1) % ViewKind.values.length]);
  Future<void> _openAppearance() async {
    await showModalBottomSheet(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Appearance', style: Theme.of(ctx).textTheme.titleLarge), const SizedBox(height: 18), Wrap(spacing: 14, children: [0,1,2,3,4].map((i) { final colors = [const Color(0xFF75866A),const Color(0xFF9A7558),const Color(0xFF54758B),const Color(0xFF9B6875),const Color(0xFF777777)]; return GestureDetector(onTap: () async { setState(() => themeIndex = i); widget.onTheme(currentMode, i); await _save(); refresh(() {}); }, child: CircleAvatar(radius: 23, backgroundColor: colors[i], child: themeIndex == i ? const Icon(Icons.check, color: Colors.white) : null)); }).toList()), const SizedBox(height: 20), SegmentedButton<ThemeMode>(segments: const [ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)), ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined))], selected: {currentMode}, onSelectionChanged: (s) async { setState(() => currentMode = s.first); widget.onTheme(currentMode, themeIndex); await _save(); refresh(() {}); }), const SizedBox(height: 20)]))));
  }
  Future<void> _openSettings() async {
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => Padding(padding: EdgeInsets.fromLTRB(20,20,20,MediaQuery.of(ctx).viewInsets.bottom + 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Settings', style: Theme.of(ctx).textTheme.titleLarge), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Task reminders'), subtitle: const Text('Allow scheduled deadline reminders'), value: remindersEnabled, onChanged: (v) async { setState(() => remindersEnabled = v); if (!v) { for (final t in tasks) { await NotificationService.instance.cancel(t.id); } } else { for (final t in active) { await NotificationService.instance.schedule(t, reminderOffsets); } } await _save(); refresh(() {}); }), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show task creation time'), value: showAddedTime, onChanged: (v) async { setState(() => showAddedTime = v); await _save(); refresh(() {}); }), const SizedBox(height: 8), const Text('Reminder intervals before deadline', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8), Wrap(spacing: 8, children: [const [1440,'24 hours'],[360,'6 hours'],[60,'1 hour'],[30,'30 min'],[10,'10 min']].map((pair) { final mins = pair[0] as int; final label = pair[1] as String; return FilterChip(label: Text(label), selected: reminderOffsets.contains(mins), onSelected: (v) async { setState(() { v ? reminderOffsets.add(mins) : reminderOffsets.remove(mins); reminderOffsets.sort((a,b)=>b.compareTo(a)); }); await _save(); for (final t in active) { await NotificationService.instance.schedule(t, reminderOffsets); } refresh(() {}); }); }).toList()), const SizedBox(height: 12), Text('Notifications depend on Android permission and battery settings.', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12)), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async { final data = jsonEncode(tasks.map((t)=>t.toJson()).toList()); await showDialog(context: ctx, builder: (d) => AlertDialog(title: const Text('Backup data'), content: SelectableText(data), actions: [TextButton(onPressed: ()=>Navigator.pop(d), child: const Text('Close'))])); }, icon: const Icon(Icons.backup_outlined), label: const Text('View backup data'))]))));
  }
}
