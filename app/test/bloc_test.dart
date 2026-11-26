import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense/bloc/expense_bloc.dart';
import 'helpers.dart';

void main() {
  demoTests();
  test('add, totals, category split, delete, all through SQLite', () async {
    final db = await memDb();
    var n = 0, t = 1000;
    final bloc = ExpenseBloc(db: db, idGen: () => 'id${n++}', clock: () => t++);
    bloc.add(ExpenseAdded(5000, 'food', 'groceries'));
    bloc.add(ExpenseAdded(2500, 'transport', 'bus'));
    bloc.add(ExpenseAdded(10000, 'salary', 'pay', isIncome: true));
    bloc.add(ExpenseAdded(1000, 'food', 'snack'));
    await bloc.stream.firstWhere((s) => s.items.length == 4);
    final s = bloc.state;
    expect(s.spent, 8500);
    expect(s.income, 10000);
    expect(s.balance, 1500);
    expect(s.byCategory, {'food': 6000, 'transport': 2500});
    expect(s.pendingCount, 4);
    bloc.add(const ExpenseDeleted('id1'));
    final after = await bloc.stream.firstWhere((s) => s.items.length == 3);
    expect(after.spent, 6000);
    expect(after.pendingCount, 4); // the deletion itself is pending sync
    await bloc.close();
  });

  test('sync without a service reports it instead of crashing', () async {
    final bloc = ExpenseBloc(db: await memDb());
    bloc.add(SyncRequested());
    final s = await bloc.stream.firstWhere((s) => s.message != null);
    expect(s.message, contains('not configured'));
    await bloc.close();
  });
}

void demoTests() {
  test('demo data is labeled and adds entries', () async {
    final bloc = ExpenseBloc(db: await memDb());
    bloc.add(DemoRequested());
    final s = await bloc.stream.firstWhere((s) => s.items.isNotEmpty);
    expect(s.items.length, 7);
    expect(s.items.every((e) => e.note.contains('(demo)')), true);
    await bloc.close();
  });
}
