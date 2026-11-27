import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/expense_bloc.dart';
import '../data/csv.dart';
import '../data/expense.dart';

const _palette = [Color(0xFF0F766E), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF22C55E)];
Color catColor(String c) => _palette[c.toLowerCase().codeUnits.fold(0, (a, b) => a + b) % _palette.length];
IconData catIcon(String c) {
  switch (c.toLowerCase()) {
    case 'food': return Icons.restaurant;
    case 'transport': return Icons.directions_bus;
    case 'rent': return Icons.home;
    case 'fun': return Icons.movie;
    case 'salary': return Icons.payments;
    default: return Icons.sell;
  }
}

class ExpenseApp extends StatefulWidget {
  final ExpenseBloc bloc;
  const ExpenseApp({super.key, required this.bloc});
  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  ThemeMode mode = ThemeMode.light;
  ThemeData _theme(Brightness b) => ThemeData(colorSchemeSeed: const Color(0xFF0F766E), brightness: b, useMaterial3: true, cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: b == Brightness.light ? const Color(0xFFD9E2DF) : const Color(0xFF334155)))));
  @override
  Widget build(BuildContext context) => BlocProvider.value(
      value: widget.bloc,
      child: MaterialApp(title: 'Smart Expense Tracker', debugShowCheckedModeBanner: false, theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), themeMode: mode,
          home: HomePage(dark: mode == ThemeMode.dark, onTheme: () => setState(() => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark))));
}

class HomePage extends StatefulWidget {
  final bool dark;
  final VoidCallback onTheme;
  const HomePage({super.key, this.dark = false, required this.onTheme});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpenseBloc, ExpenseState>(
      listenWhen: (a, b) => a.message != b.message && b.message != null,
      listener: (c, s) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s.message!))),
      builder: (context, s) {
        final pages = [_Overview(s: s, onSeeAll: () => setState(() => tab = 1)), _Transactions(s: s), _Insights(s: s), _Budgets(s: s)];
        return Scaffold(
          appBar: AppBar(title: const Text('Smart Expense Tracker', style: TextStyle(fontWeight: FontWeight.w700)), actions: [
            IconButton(tooltip: 'Toggle dark mode', icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode), onPressed: widget.onTheme),
            IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.file_download),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: toCsv(s.items)));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
                }),
            IconButton(tooltip: 'Account', icon: const Icon(Icons.account_circle_outlined), onPressed: () => showAccountDialog(context)),
            IconButton(tooltip: 'Sync', icon: s.syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), onPressed: s.syncing ? null : () => context.read<ExpenseBloc>().add(SyncRequested())),
          ]),
          floatingActionButton: FloatingActionButton(tooltip: 'Add entry', onPressed: () => showEntrySheet(context), child: const Icon(Icons.add)),
          bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
            NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Budgets'),
          ]),
          body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: pages[tab])),
        );
      },
    );
  }
}

Future<void> showEntrySheet(BuildContext context, {Expense? edit}) async {
  final amount = TextEditingController(text: edit == null ? '' : fmtMoney(edit.cents)), cat = TextEditingController(text: edit?.category ?? 'food'), note = TextEditingController(text: edit?.note ?? '');
  var income = edit?.isIncome ?? false;
  final bloc = context.read<ExpenseBloc>();
  await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
          builder: (c, set) => Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(edit == null ? 'Add entry' : 'Edit entry', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Expense'), icon: Icon(Icons.arrow_upward)), ButtonSegment(value: true, label: Text('Income'), icon: Icon(Icons.arrow_downward))], selected: {income}, onSelectionChanged: (v) => set(() => income = v.first)),
                const SizedBox(height: 12),
                TextField(controller: amount, key: const Key('amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: cat, key: const Key('category'), decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder())),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [for (final k in ['food', 'transport', 'rent', 'fun', 'salary']) ActionChip(label: Text(k), onPressed: () => cat.text = k)]),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: FilledButton(
                    key: const Key('save'),
                    onPressed: () {
                      final v = double.tryParse(amount.text);
                      if (v == null || v <= 0) return;
                      final cents = (v * 100).round(), category = cat.text.trim().isEmpty ? 'other' : cat.text.trim();
                      if (edit == null) { bloc.add(ExpenseAdded(cents, category, note.text, isIncome: income)); } else { bloc.add(ExpenseEdited(edit.id, cents, category, note.text, isIncome: income)); }
                      Navigator.pop(c);
                    },
                    child: const Text('Save'))),
              ]))));
}

Widget _kpi(BuildContext c, String t, String v, {Color? color, IconData? icon}) => Expanded(
    child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [if (icon != null) Icon(icon, size: 14, color: color), if (icon != null) const SizedBox(width: 4), Text(t, style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant))]),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color))),
    ]))));

class _DemoCard extends StatelessWidget {
  const _DemoCard();
  @override
  Widget build(BuildContext context) => Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Icon(Icons.account_balance_wallet, size: 36),
        const SizedBox(height: 8),
        const Text('No entries yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const Text('Load sample entries (marked "sample") to look around.', textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton(key: const Key('load-sample'), onPressed: () => context.read<ExpenseBloc>().add(DemoRequested()), child: const Text('Load sample data')),
      ])));
}

class _Tile extends StatelessWidget {
  final Expense e;
  const _Tile(this.e);
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ExpenseBloc>();
    return Dismissible(
        key: ValueKey(e.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) {
          bloc.add(ExpenseDeleted(e.id));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${e.category}'), action: SnackBarAction(label: 'Undo', onPressed: () => bloc.add(ExpenseRestored(e)))));
        },
        background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
        child: ListTile(
            onTap: () => showEntrySheet(context, edit: e),
            leading: CircleAvatar(backgroundColor: catColor(e.category).withValues(alpha: .15), child: Icon(catIcon(e.category), color: catColor(e.category), size: 20)),
            title: Text(e.category),
            subtitle: Text('${fmtDate(e.date)}  ${e.note}'),
            trailing: Text('${e.isIncome ? '+' : '-'}${fmtMoney(e.cents)}', style: TextStyle(fontWeight: FontWeight.w700, color: e.isIncome ? Colors.green : Colors.red))));
  }
}

class _Overview extends StatelessWidget {
  final ExpenseState s;
  final VoidCallback onSeeAll;
  const _Overview({required this.s, required this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day).subtract(Duration(days: i))];
    final perDay = [for (final d in days) s.items.where((e) => !e.isIncome && fmtDate(e.date) == fmtDate(d)).fold<int>(0, (a, e) => a + e.cents) / 100];
    final maxY = perDay.fold<double>(1, (a, b) => b > a ? b : a);
    final cats = s.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [_kpi(context, 'Balance', fmtMoney(s.balance), icon: Icons.account_balance_wallet), _kpi(context, 'Spent', fmtMoney(s.spent), color: Colors.red, icon: Icons.arrow_upward)]),
      Row(children: [_kpi(context, 'Income', fmtMoney(s.income), color: Colors.green, icon: Icons.arrow_downward), _kpi(context, 'Not synced', '${s.pendingCount}', icon: Icons.cloud_off)]),
      if (s.items.isEmpty) const _DemoCard(),
      if (s.items.isNotEmpty) ...[
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Spending, last 7 days', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(height: 170, child: BarChart(BarChartData(
              maxY: maxY * 1.2, gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(show: true, leftTitles: const AxisTitles(), rightTitles: const AxisTitles(), topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => SideTitleWidget(meta: m, child: Text(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][days[v.toInt()].weekday - 1], style: const TextStyle(fontSize: 11)))))),
              barGroups: [for (final (i, v) in perDay.indexed) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: v, width: 18, color: const Color(0xFF0F766E), borderRadius: BorderRadius.circular(5))])]))),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Where it goes', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(height: 150, width: 150, child: PieChart(PieChartData(centerSpaceRadius: 38, sectionsSpace: 2, sections: [for (final e in cats) PieChartSectionData(value: e.value / 100, title: '', radius: 26, color: catColor(e.key))]))),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [for (final e in cats.take(5)) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Icon(Icons.circle, size: 10, color: catColor(e.key)), const SizedBox(width: 8), Expanded(child: Text(e.key)), Text(fmtMoney(e.value), style: const TextStyle(fontWeight: FontWeight.w600))]))])),
          ]),
        ]))),
        Card(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 6, 0), child: Row(children: [const Text('Recent', style: TextStyle(fontWeight: FontWeight.w700)), const Spacer(), TextButton(onPressed: onSeeAll, child: const Text('See all'))])),
          for (final e in s.items.take(4)) _Tile(e),
        ])),
      ],
      const SizedBox(height: 70),
    ]);
  }
}

class _Transactions extends StatefulWidget {
  final ExpenseState s;
  const _Transactions({required this.s});
  @override
  State<_Transactions> createState() => _TransactionsState();
}

class _TransactionsState extends State<_Transactions> {
  String q = '';
  String type = 'all';
  @override
  Widget build(BuildContext context) {
    final items = widget.s.items.where((e) => (type == 'all' || (type == 'income') == e.isIncome) && (q.isEmpty || '${e.category} ${e.note}'.toLowerCase().contains(q.toLowerCase()))).toList();
    final total = items.fold<int>(0, (a, e) => a + (e.isIncome ? e.cents : -e.cents));
    String? last;
    return ListView(padding: const EdgeInsets.all(14), children: [
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search category or note', border: OutlineInputBorder()), onChanged: (v) => setState(() => q = v)),
      const SizedBox(height: 8),
      Row(children: [for (final t in ['all', 'expense', 'income']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t), selected: type == t, onSelected: (_) => setState(() => type = t))), const Spacer(), Text('${items.length} entries, net ${fmtMoney(total)}', style: const TextStyle(fontSize: 12))]),
      const SizedBox(height: 8),
      if (items.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Nothing matches.'))),
      for (final e in items) ...[
        if (last != fmtDate(e.date)) Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 2), child: Text(last = fmtDate(e.date), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))),
        Card(margin: const EdgeInsets.symmetric(vertical: 2), child: _Tile(e)),
      ],
      const SizedBox(height: 70),
    ]);
  }
}

class _Insights extends StatelessWidget {
  final ExpenseState s;
  const _Insights({required this.s});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = s.items.where((e) => e.date.year == now.year && e.date.month == now.month).toList();
    final spent = month.where((e) => !e.isIncome).fold<int>(0, (a, e) => a + e.cents);
    final inc = month.where((e) => e.isIncome).fold<int>(0, (a, e) => a + e.cents);
    final avg = spent ~/ (now.day == 0 ? 1 : now.day);
    final rate = inc == 0 ? null : ((inc - spent) * 100 / inc).round();
    final byCat = <String, int>{};
    for (final e in month.where((e) => !e.isIncome)) { byCat[e.category] = (byCat[e.category] ?? 0) + e.cents; }
    final top = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final biggest = month.where((e) => !e.isIncome).fold<Expense?>(null, (a, e) => a == null || e.cents > a.cents ? e : a);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('This month', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Row(children: [_kpi(context, 'Spent', fmtMoney(spent), color: Colors.red), _kpi(context, 'Income', fmtMoney(inc), color: Colors.green)]),
      Row(children: [_kpi(context, 'Avg per day', fmtMoney(avg)), _kpi(context, 'Savings rate', rate == null ? 'n/a' : '$rate%')]),
      if (biggest != null) Card(child: ListTile(leading: const Icon(Icons.priority_high), title: const Text('Largest expense this month'), subtitle: Text('${biggest.category}  ${biggest.note}'), trailing: Text(fmtMoney(biggest.cents), style: const TextStyle(fontWeight: FontWeight.w700)))),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Spending by category', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (top.isEmpty) const Text('No expenses this month yet.'),
        for (final e in top) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(e.key)), Text('${fmtMoney(e.value)}  (${(e.value * 100 / spent).round()}%)')]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: e.value / spent, minHeight: 8, color: catColor(e.key))),
        ])),
      ]))),
      const SizedBox(height: 70),
    ]);
  }
}

class _Budgets extends StatelessWidget {
  final ExpenseState s;
  const _Budgets({required this.s});
  Future<void> _set(BuildContext context, String cat, int current) async {
    final bloc = context.read<ExpenseBloc>();
    final ctl = TextEditingController(text: current > 0 ? fmtMoney(current) : '');
    final catCtl = TextEditingController(text: cat);
    await showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Monthly budget'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: catCtl, decoration: const InputDecoration(labelText: 'Category')),
      TextField(controller: ctl, key: const Key('budget-amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount per month (empty removes)')),
    ]), actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      FilledButton(onPressed: () { final v = double.tryParse(ctl.text) ?? 0; if (catCtl.text.trim().isNotEmpty) bloc.add(BudgetSet(catCtl.text.trim(), (v * 100).round())); Navigator.pop(c); }, child: const Text('Save')),
    ]));
  }
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spentBy = <String, int>{};
    for (final e in s.items.where((e) => !e.isIncome && e.date.year == now.year && e.date.month == now.month)) { spentBy[e.category] = (spentBy[e.category] ?? 0) + e.cents; }
    final cats = {...s.budgets.keys}.toList()..sort();
    final suggestions = spentBy.keys.where((k) => !s.budgets.containsKey(k)).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [Text('Budgets', style: Theme.of(context).textTheme.titleLarge), const Spacer(), FilledButton.tonalIcon(onPressed: () => _set(context, '', 0), icon: const Icon(Icons.add), label: const Text('New budget'))]),
      const Text('Monthly limits per category, stored on this device.'),
      const SizedBox(height: 8),
      if (cats.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No budgets yet. Add one, or tap a category below.'))),
      for (final c in cats) Builder(builder: (context) {
        final limit = s.budgets[c]!, used = spentBy[c] ?? 0, over = used > limit, pct = used / limit;
        return Card(child: InkWell(onTap: () => _set(context, c, limit), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(catIcon(c), size: 18, color: catColor(c)), const SizedBox(width: 8), Expanded(child: Text(c, style: const TextStyle(fontWeight: FontWeight.w700))), Text('${fmtMoney(used)} / ${fmtMoney(limit)}')]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: pct.clamp(0, 1).toDouble(), minHeight: 10, color: over ? Colors.red : pct > .8 ? Colors.orange : Colors.green)),
          const SizedBox(height: 4),
          Text(over ? 'Over budget by ${fmtMoney(used - limit)}' : '${fmtMoney(limit - used)} left this month', style: TextStyle(fontSize: 12, color: over ? Colors.red : null)),
        ]))));
      }),
      if (suggestions.isNotEmpty) ...[const SizedBox(height: 8), const Text('Spending without a budget'), Wrap(spacing: 6, children: [for (final k in suggestions) ActionChip(label: Text('$k (${fmtMoney(spentBy[k]!)})'), onPressed: () => _set(context, k, 0))])],
      const SizedBox(height: 70),
    ]);
  }
}


/// Log in, create an account, or log out. Without an account the app still works as an anonymous device.
Future<void> showAccountDialog(BuildContext context) async {
  final sync = context.read<ExpenseBloc>().sync;
  if (sync == null) return;
  final mail = TextEditingController();
  final pass = TextEditingController();
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final signedIn = sync.token != null && sync.token!.isNotEmpty;
      Future<void> go(bool register) async {
        setState(() {
          busy = true;
          error = null;
        });
        final err = await sync.authenticate(mail.text, pass.text, register: register);
        if (err == null && ctx.mounted) {
          Navigator.pop(ctx);
          if (context.mounted) context.read<ExpenseBloc>().add(SyncRequested());
        } else {
          setState(() {
            busy = false;
            error = err;
          });
        }
      }

      return AlertDialog(
        title: Text(signedIn ? 'Account' : 'Log in or create an account'),
        content: signedIn
            ? Text('Signed in as ${sync.email}. Your entries sync to this account.')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(key: const Key('auth-email'), controller: mail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                TextField(key: const Key('auth-password'), controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)')),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const Key('auth-error'), style: const TextStyle(color: Colors.red))),
              ]),
        actions: signedIn
            ? [
                TextButton(key: const Key('logout'), onPressed: () async {
                  await sync.logout();
                  if (ctx.mounted) Navigator.pop(ctx);
                }, child: const Text('Log out')),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ]
            : [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Stay offline')),
                TextButton(key: const Key('signup'), onPressed: busy ? null : () => go(true), child: const Text('Create account')),
                FilledButton(key: const Key('login'), onPressed: busy ? null : () => go(false), child: const Text('Log in')),
              ],
      );
    }),
  );
}
