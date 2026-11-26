import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'dart:math';
import 'bloc/expense_bloc.dart';
import 'data/csv.dart';
import 'data/local_db.dart';
import 'data/sync_service.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On the web build SQLite runs as WebAssembly (sqflite_common_ffi_web); on Android it is native SQLite.
  final factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
  final db = await LocalDb.open(factory, kIsWeb ? 'expenses_web.db' : '${await getDatabasesPath()}/expenses.db');
  // Each install gets its own random id, so users never see each other's data.
  var uid = await db.meta('user_id');
  if (uid == null) {
    uid = 'u${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 30)}';
    await db.setMeta('user_id', uid);
  }
  final sync = SyncService(db: db, client: http.Client(), baseUrl: apiUrl, userId: uid);
  runApp(ExpenseApp(bloc: ExpenseBloc(db: db, sync: sync)..add(LoadRequested())));
}

class ExpenseApp extends StatelessWidget {
  final ExpenseBloc bloc;
  const ExpenseApp({super.key, required this.bloc});
  @override
  Widget build(BuildContext context) => BlocProvider.value(
      value: bloc, child: MaterialApp(title: 'Smart Expense Tracker', theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true), home: const HomePage()));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpenseBloc, ExpenseState>(
      listenWhen: (a, b) => a.message != b.message && b.message != null,
      listener: (c, s) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s.message!))),
      builder: (context, s) => Scaffold(
        appBar: AppBar(title: const Text('Smart Expense Tracker'), actions: [
          IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.file_download),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: toCsv(s.items)));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
              }),
          IconButton(tooltip: 'Sync', icon: s.syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), onPressed: s.syncing ? null : () => context.read<ExpenseBloc>().add(SyncRequested())),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: () => _add(context), child: const Icon(Icons.add)),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            _kpi('Balance', fmtMoney(s.balance)), _kpi('Spent', fmtMoney(s.spent)), _kpi('Not synced', '${s.pendingCount}'),
          ]),
          if (s.items.isEmpty)
            Card(
                color: Colors.amber.shade50,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      const Text('No entries yet. Load synthetic demo data (clearly marked "demo") to look around.'),
                      const SizedBox(height: 8),
                      FilledButton(key: const Key('try-demo'), onPressed: () => context.read<ExpenseBloc>().add(DemoRequested()), child: const Text('Try demo')),
                    ]))),
          if (s.byCategory.isNotEmpty)
            SizedBox(
                height: 180,
                child: PieChart(PieChartData(sections: [
                  for (final (i, e) in s.byCategory.entries.indexed)
                    PieChartSectionData(value: e.value / 100, title: e.key, radius: 60, color: Colors.primaries[(i * 3) % Colors.primaries.length], titleStyle: const TextStyle(fontSize: 11, color: Colors.white)),
                ]))),
          for (final e in s.items)
            Dismissible(
                key: ValueKey(e.id),
                onDismissed: (_) => context.read<ExpenseBloc>().add(ExpenseDeleted(e.id)),
                background: Container(color: Colors.red),
                child: ListTile(title: Text(e.category), subtitle: Text('${fmtDate(e.date)}  ${e.note}'), trailing: Text('${e.isIncome ? '+' : '-'}${fmtMoney(e.cents)}', style: TextStyle(color: e.isIncome ? Colors.green : Colors.red)))),
        ]),
      ),
    );
  }

  Widget _kpi(String t, String v) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 12)), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))));

  Future<void> _add(BuildContext context) async {
    final amount = TextEditingController(), cat = TextEditingController(text: 'food'), note = TextEditingController();
    var income = false;
    final bloc = context.read<ExpenseBloc>();
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(title: const Text('Add entry'), content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: amount, key: const Key('amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
                  TextField(controller: cat, key: const Key('category'), decoration: const InputDecoration(labelText: 'Category')),
                  TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
                  SwitchListTile(title: const Text('Income'), value: income, onChanged: (v) => set(() => income = v)),
                ]), actions: [
                  TextButton(
                      key: const Key('save'),
                      onPressed: () {
                        final v = double.tryParse(amount.text);
                        if (v == null || v <= 0) return;
                        bloc.add(ExpenseAdded((v * 100).round(), cat.text.trim().isEmpty ? 'other' : cat.text.trim(), note.text, isIncome: income));
                        Navigator.pop(c);
                      },
                      child: const Text('Save'))
                ])));
  }
}
