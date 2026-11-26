import 'dart:convert';
import 'dart:math';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/expense.dart';
import '../data/local_db.dart';
import '../data/sync_service.dart';

abstract class ExpenseEvent extends Equatable {
  const ExpenseEvent();
  @override
  List<Object?> get props => [];
}

class LoadRequested extends ExpenseEvent {}

class ExpenseAdded extends ExpenseEvent {
  final int cents;
  final String category;
  final String note;
  final bool isIncome;
  final DateTime? date;
  const ExpenseAdded(this.cents, this.category, this.note, {this.isIncome = false, this.date});
  @override
  List<Object?> get props => [cents, category, note, isIncome, date];
}

class ExpenseDeleted extends ExpenseEvent {
  final String id;
  const ExpenseDeleted(this.id);
  @override
  List<Object?> get props => [id];
}

class ExpenseEdited extends ExpenseEvent {
  final String id;
  final int cents;
  final String category;
  final String note;
  final bool isIncome;
  const ExpenseEdited(this.id, this.cents, this.category, this.note, {this.isIncome = false});
  @override
  List<Object?> get props => [id, cents, category, note, isIncome];
}

class ExpenseRestored extends ExpenseEvent {
  final Expense expense;
  const ExpenseRestored(this.expense);
  @override
  List<Object?> get props => [expense];
}

class BudgetSet extends ExpenseEvent {
  final String category;
  final int cents; // 0 removes the budget
  const BudgetSet(this.category, this.cents);
  @override
  List<Object?> get props => [category, cents];
}

class SyncRequested extends ExpenseEvent {}

class DemoRequested extends ExpenseEvent {}

class ExpenseState extends Equatable {
  final List<Expense> items;
  final int pendingCount;
  final bool syncing;
  final String? message;
  final Map<String, int> budgets; // monthly budget per category, in cents
  const ExpenseState({this.items = const [], this.pendingCount = 0, this.syncing = false, this.message, this.budgets = const {}});

  int get income => items.where((e) => e.isIncome).fold(0, (a, e) => a + e.cents);
  int get spent => items.where((e) => !e.isIncome).fold(0, (a, e) => a + e.cents);
  int get balance => income - spent;
  Map<String, int> get byCategory {
    final m = <String, int>{};
    for (final e in items.where((e) => !e.isIncome)) {
      m[e.category] = (m[e.category] ?? 0) + e.cents;
    }
    return m;
  }

  ExpenseState copyWith({List<Expense>? items, int? pendingCount, bool? syncing, String? message, Map<String, int>? budgets}) => ExpenseState(
      items: items ?? this.items, pendingCount: pendingCount ?? this.pendingCount, syncing: syncing ?? this.syncing, message: message, budgets: budgets ?? this.budgets);

  @override
  List<Object?> get props => [items, pendingCount, syncing, message, budgets];
}

int _seq = 0;
String _randomId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}-${Random().nextInt(1 << 30)}';

class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  final LocalDb db;
  final SyncService? sync;
  final String Function() newId;
  final int Function() now;

  ExpenseBloc({required this.db, this.sync, String Function()? idGen, int Function()? clock})
      : newId = idGen ?? _randomId,
        now = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        super(const ExpenseState()) {
    on<LoadRequested>((e, emit) async => emit(await _snapshot(state)));
    on<ExpenseAdded>((e, emit) async {
      await db.upsert(
          Expense(id: newId(), cents: e.cents, category: e.category, note: e.note, date: e.date ?? DateTime.fromMillisecondsSinceEpoch(now()), isIncome: e.isIncome, updatedAt: now()),
          synced: false);
      emit(await _snapshot(state));
    });
    on<ExpenseDeleted>((e, emit) async {
      final rows = await db.db.query('expenses', where: 'id = ?', whereArgs: [e.id]);
      if (rows.isEmpty) return;
      // Soft delete so the deletion itself can sync to other devices.
      await db.upsert(Expense.fromRow(rows.first).copyWith(deleted: true, updatedAt: now()), synced: false);
      emit(await _snapshot(state));
    });
    on<ExpenseEdited>((e, emit) async {
      final rows = await db.db.query('expenses', where: 'id = ?', whereArgs: [e.id]);
      if (rows.isEmpty) return;
      final old = Expense.fromRow(rows.first);
      await db.upsert(Expense(id: old.id, cents: e.cents, category: e.category, note: e.note, date: old.date, isIncome: e.isIncome, updatedAt: now()), synced: false);
      emit(await _snapshot(state));
    });
    on<ExpenseRestored>((e, emit) async {
      await db.upsert(e.expense.copyWith(deleted: false, updatedAt: now()), synced: false);
      emit(await _snapshot(state));
    });
    on<BudgetSet>((e, emit) async {
      final b = Map<String, int>.from(state.budgets);
      if (e.cents <= 0) { b.remove(e.category); } else { b[e.category] = e.cents; }
      await db.setMeta('budgets', jsonEncode(b));
      emit(await _snapshot(state));
    });
    on<DemoRequested>((e, emit) async {
      const demo = [
        (4500, 'food', 'Groceries (demo)', false), (1200, 'transport', 'Metro card (demo)', false), (8000, 'rent', 'Share of rent (demo)', false),
        (2500, 'fun', 'Cinema (demo)', false), (650, 'food', 'Coffee (demo)', false), (30000, 'salary', 'Freelance payment (demo)', true), (1800, 'transport', 'Taxi (demo)', false),
      ];
      final base = now();
      for (final (i, d) in demo.indexed) {
        await db.upsert(Expense(id: newId(), cents: d.$1, category: d.$2, note: d.$3, date: DateTime.fromMillisecondsSinceEpoch(base - i * 86400000), isIncome: d.$4, updatedAt: base + i), synced: false);
      }
      emit(await _snapshot(state));
    });
    on<SyncRequested>((e, emit) async {
      if (sync == null) return emit(state.copyWith(message: 'Sync is not configured'));
      emit(state.copyWith(syncing: true));
      final r = await sync!.sync();
      final snap = await _snapshot(state);
      emit(snap.copyWith(syncing: false, message: r.ok ? 'Synced: sent ${r.pushed}, received ${r.pulled}' : r.error));
    });
  }

  Future<ExpenseState> _snapshot(ExpenseState s) async {
    final raw = await db.meta('budgets');
    final budgets = raw == null ? <String, int>{} : (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    return s.copyWith(items: await db.list(), pendingCount: (await db.pending()).length, budgets: budgets);
  }
}
