import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
const teal = Color(0xFF087F8C);
const paleTeal = Color(0xFFE8F6F6);
const ink = Color(0xFF17343A);
const muted = Color(0xFF71858A);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.instance.database;
  runApp(const MediBoxApp());
}

class MediBoxApp extends StatelessWidget {
  const MediBoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MediBox',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      scaffoldBackgroundColor: const Color(0xFFF5F9FA),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white),
    ),
    home: const HomePage(),
  );
}

String day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String showDate(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? s : '${d.day}/${d.month}/${d.year}';
}

String showTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

class DB {
  DB._();
  static final DB instance = DB._();
  Database? _db;

  
Future<Database> get database async {
  if (_db != null) return _db!;

  late final String dbPath;

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    dbPath = 'medibox_web.db';
  } else {
    final root = await getDatabasesPath();
    dbPath = p.join(root, 'medibox.db');
  }

  _db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE medicines(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          dosage TEXT NOT NULL,
          frequency TEXT NOT NULL,
          reminder TEXT NOT NULL,
          startDate TEXT NOT NULL,
          endDate TEXT NOT NULL,
          food TEXT NOT NULL,
          notes TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE doses(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          medicineId INTEGER NOT NULL,
          medicineName TEXT NOT NULL,
          date TEXT NOT NULL,
          reminder TEXT NOT NULL,
          taken INTEGER NOT NULL DEFAULT 0,
          takenAt TEXT,
          UNIQUE(medicineId, date)
        )
      ''');
    },
  );

  return _db!;
}


  Future<List<Map<String, Object?>>> medicines() async =>
      (await database).query('medicines', orderBy: 'name COLLATE NOCASE');

  Future<void> saveMedicine(Map<String, Object?> m) async {
    final db = await database;
    if (m['id'] == null) {
      await db.insert('medicines', m);
    } else {
      await db.update('medicines', m,
          where: 'id = ?', whereArgs: [m['id']]);
    }
  }

  Future<void> deleteMedicine(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('doses', where: 'medicineId = ?', whereArgs: [id]);
      await txn.delete('medicines', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> todayDoses(
      List<Map<String, Object?>> meds) async {
    final db = await database;
    final today = day(DateTime.now());
    for (final m in meds) {
      if ((m['startDate'] as String).compareTo(today) <= 0 &&
          (m['endDate'] as String).compareTo(today) >= 0) {
        await db.insert(
          'doses',
          {
            'medicineId': m['id'],
            'medicineName': m['name'],
            'date': today,
            'reminder': m['reminder'],
            'taken': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    return db.query(
      'doses',
      where: 'date = ?',
      whereArgs: [today],
      orderBy: 'reminder',
    );
  }

  Future<List<Map<String, Object?>>> history() async =>
      (await database).query('doses', orderBy: 'date DESC, reminder ASC');

  Future<void> toggleDose(Map<String, Object?> dose) async {
    final taken = (dose['taken'] as int) == 1;
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    await (await database).update(
      'doses',
      {
        'taken': taken ? 0 : 1,
        'takenAt': taken ? null : stamp,
      },
      where: 'id = ?',
      whereArgs: [dose['id']],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  List<Map<String, Object?>> meds = [];
  List<Map<String, Object?>> doses = [];
  List<Map<String, Object?>> history = [];
  String search = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final m = await DB.instance.medicines();
    final d = await DB.instance.todayDoses(m);
    final h = await DB.instance.history();
    if (!mounted) return;
    setState(() {
      meds = m;
      doses = d;
      history = h;
      loading = false;
    });
  }

  Future<void> edit([Map<String, Object?>? medicine]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MedicineForm(medicine: medicine),
    );
    if (result != null) {
      await DB.instance.saveMedicine(result);
      await refresh();
    }
  }

  Future<void> delete(Map<String, Object?> m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text('Delete ${m['name']} and its dose history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) {
      await DB.instance.deleteMedicine(m['id'] as int);
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.medication_rounded, color: teal, size: 30),
          SizedBox(width: 9),
          Text('MediBox',
              style: TextStyle(fontWeight: FontWeight.w900, color: ink)),
        ]),
        actions: [
          IconButton(
              onPressed: () => edit(),
              icon: const Icon(Icons.add_circle, color: teal, size: 30),
              tooltip: 'Add medicine'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
        index: tab,
        children: [
          dashboard(),
          medicinePage(),
          historyPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.medication_outlined), label: 'Medicines'),
          NavigationDestination(
              icon: Icon(Icons.history), label: 'History'),
        ],
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
        onPressed: () => edit(),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      )
          : null,
    );
  }

  Widget dashboard() {
    final active = meds.where((m) {
      final today = day(DateTime.now());
      return (m['startDate'] as String).compareTo(today) <= 0 &&
          (m['endDate'] as String).compareTo(today) >= 0;
    }).length;
    final taken = doses.where((d) => d['taken'] == 1).length;
    final pending = doses.length - taken;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Good ${DateTime.now().hour < 12 ? 'morning' : 'day'} 👋',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 8),
        const Text('Your health,\none dose at a time.',
            style: TextStyle(
                fontSize: 29,
                height: 1.2,
                fontWeight: FontWeight.w900,
                color: ink)),
        const SizedBox(height: 8),
        Text(day(DateTime.now()), style: const TextStyle(color: muted)),
        const SizedBox(height: 20),
        Row(children: [
          stat('Active', '$active', Icons.medication_outlined),
          const SizedBox(width: 9),
          stat('Taken', '$taken', Icons.check_circle_outline),
          const SizedBox(width: 9),
          stat('Pending', '$pending', Icons.schedule),
        ]),
        const SizedBox(height: 24),
        const Text('Today’s schedule',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 12),
        if (doses.isEmpty)
          empty('Nothing scheduled today',
              'Add a medicine with dates that include today.')
        else
          ...doses.map((d) => Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                  backgroundColor: paleTeal,
                  child: Icon(Icons.medication, color: teal)),
              title: Text('${d['medicineName']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: ink)),
              subtitle: Text(
                  '${d['reminder']}${d['takenAt'] == null ? '' : ' • Taken at ${d['takenAt']}'}'),
              trailing: (d['taken'] as int) == 1
                  ? const Chip(label: Text('Taken'))
                  : TextButton(
                  onPressed: () async {
                    await DB.instance.toggleDose(d);
                    await refresh();
                  },
                  child: const Text('Mark taken')),
            ),
          )),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily progress  ${doses.isEmpty ? 0 : (taken / doses.length * 100).round()}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: doses.isEmpty ? 0 : taken / doses.length,
                    color: teal,
                    backgroundColor: paleTeal,
                    minHeight: 9,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ]),
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'MediBox is a tracking tool, not a replacement for professional medical advice.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget stat(String label, String value, IconData icon) => Expanded(
    child: Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        child: Column(children: [
          Icon(icon, color: teal),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: ink)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: muted)),
        ]),
      ),
    ),
  );

  Widget medicinePage() {
    final filtered = meds.where((m) =>
    (m['name'] as String).toLowerCase().contains(search.toLowerCase()) ||
        (m['type'] as String).toLowerCase().contains(search.toLowerCase()));

    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('My medicines',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, color: ink)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search name or type',
            filled: true,
          ),
        ),
      ),
      Expanded(
        child: filtered.isEmpty
            ? empty('No medicines found', 'Add a medicine to get started.')
            : ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
          children: filtered.map((m) {
            return Card(
              color: Colors.white,
              elevation: 0,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: paleTeal,
                  child: Icon(Icons.medication, color: teal),
                ),
                title: Text('${m['name']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: ink)),
                subtitle: Text(
                    '${m['type']} • ${m['dosage']}\n${m['frequency']} • ${m['reminder']}\n${showDate(m['startDate'] as String)} – ${showDate(m['endDate'] as String)}'),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') edit(m);
                    if (v == 'delete') delete(m);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget historyPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Dose history',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: ink)),
        const SizedBox(height: 12),
        if (history.isEmpty)
          empty('No dose history yet', 'Scheduled doses will appear here.')
        else
          ...history.map((d) => Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: Icon(
                d['taken'] == 1 ? Icons.check_circle : Icons.schedule,
                color: teal,
              ),
              title: Text('${d['medicineName']}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${showDate(d['date'] as String)} • ${d['reminder']}${d['takenAt'] == null ? '' : ' • Taken at ${d['takenAt']}'}'),
              trailing: Text(d['taken'] == 1 ? 'Taken' : 'Pending'),
            ),
          )),
      ],
    );
  }

  Widget empty(String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.medication_outlined, size: 52, color: teal),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted)),
      ]),
    ),
  );
}

class MedicineForm extends StatefulWidget {
  final Map<String, Object?>? medicine;
  const MedicineForm({super.key, this.medicine});
  @override
  State<MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<MedicineForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name, dosage, notes;
  late String type, frequency, food, startDate, endDate;
  late TimeOfDay time;

  final types = ['Tablet', 'Capsule', 'Syrup', 'Drops', 'Other'];
  final frequencies = [
    'Once daily',
    'Twice daily',
    'Three times daily',
    'As needed'
  ];
  final foods = ['Before food', 'After food', 'With food', 'No instruction'];

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    name = TextEditingController(text: m?['name'] as String? ?? '');
    dosage = TextEditingController(text: m?['dosage'] as String? ?? '');
    notes = TextEditingController(text: m?['notes'] as String? ?? '');
    type = m?['type'] as String? ?? types.first;
    frequency = m?['frequency'] as String? ?? frequencies.first;
    food = m?['food'] as String? ?? foods[1];
    startDate = m?['startDate'] as String? ?? day(DateTime.now());
    endDate = m?['endDate'] as String? ??
        day(DateTime.now().add(const Duration(days: 7)));
    time = _parseTime(m?['reminder'] as String?);
  }

  TimeOfDay _parseTime(String? raw) {
    if (raw == null) return const TimeOfDay(hour: 8, minute: 0);
    try {
      final parts = raw.split(' ');
      final hm = parts[0].split(':');
      var h = int.parse(hm[0]);
      final min = int.parse(hm[1]);
      if (parts.length > 1 && parts[1] == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1] == 'AM' && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: min);
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  @override
  void dispose() {
    name.dispose();
    dosage.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pickDate(bool isStart) async {
    final initial = DateTime.tryParse(isStart ? startDate : endDate) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = day(picked);
          if (endDate.compareTo(startDate) < 0) endDate = startDate;
        } else {
          endDate = day(picked);
        }
      });
    }
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked != null) setState(() => time = picked);
  }

  void save() {
    if (!formKey.currentState!.validate()) return;
    if (endDate.compareTo(startDate) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End date must be on or after start date.')));
      return;
    }
    Navigator.pop(context, <String, Object?>{
      if (widget.medicine?['id'] != null) 'id': widget.medicine!['id'],
      'name': name.text.trim(),
      'type': type,
      'dosage': dosage.text.trim(),
      'frequency': frequency,
      'reminder': showTime(time),
      'startDate': startDate,
      'endDate': endDate,
      'food': food,
      'notes': notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.medicine == null ? 'Add medicine' : 'Edit medicine'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Medicine name'),
              validator: (v) =>
              v == null || v.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Medicine type'),
              items: types
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: dosage,
              decoration: const InputDecoration(labelText: 'Dosage'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter dosage instructions'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: frequencies
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => frequency = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: pickTime,
              icon: const Icon(Icons.schedule),
              label: Text('Reminder: ${showTime(time)}'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => pickDate(true),
                  child: Text('Start: ${showDate(startDate)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => pickDate(false),
                  child: Text('End: ${showDate(endDate)}'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: food,
              decoration:
              const InputDecoration(labelText: 'Food instructions'),
              items: foods
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => food = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              maxLines: 2,
              decoration:
              const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
          onPressed: save,
          child: Text(widget.medicine == null ? 'Save' : 'Save changes')),
    ],
  );
}