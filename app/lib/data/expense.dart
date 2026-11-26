import 'package:equatable/equatable.dart';

/// Amounts are integer minor units (cents) to avoid float drift.
class Expense extends Equatable {
  final String id;
  final int cents;
  final String category;
  final String note;
  final DateTime date;
  final bool isIncome;
  final int updatedAt; // ms since epoch, drives last-write-wins sync
  final bool deleted;

  const Expense({
    required this.id,
    required this.cents,
    required this.category,
    required this.note,
    required this.date,
    this.isIncome = false,
    required this.updatedAt,
    this.deleted = false,
  });

  Map<String, Object?> toRow({required bool synced}) => {
        'id': id,
        'cents': cents,
        'category': category,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'is_income': isIncome ? 1 : 0,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'synced': synced ? 1 : 0,
      };

  factory Expense.fromRow(Map<String, Object?> r) => Expense(
        id: r['id'] as String,
        cents: r['cents'] as int,
        category: r['category'] as String,
        note: r['note'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        isIncome: (r['is_income'] as int) == 1,
        updatedAt: r['updated_at'] as int,
        deleted: (r['deleted'] as int) == 1,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'cents': cents,
        'category': category,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'is_income': isIncome,
        'updated_at': updatedAt,
        'deleted': deleted,
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        cents: j['cents'] as int,
        category: j['category'] as String,
        note: j['note'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
        isIncome: j['is_income'] as bool,
        updatedAt: j['updated_at'] as int,
        deleted: j['deleted'] as bool,
      );

  Expense copyWith({bool? deleted, int? updatedAt}) => Expense(
        id: id, cents: cents, category: category, note: note, date: date, isIncome: isIncome,
        updatedAt: updatedAt ?? this.updatedAt, deleted: deleted ?? this.deleted);

  @override
  List<Object?> get props => [id, cents, category, note, date, isIncome, updatedAt, deleted];
}
