import 'expense.dart';

String _q(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String fmtMoney(int cents) => '${cents < 0 ? '-' : ''}${(cents.abs() ~/ 100)}.${two(cents.abs() % 100)}';

String toCsv(List<Expense> items) {
  final b = StringBuffer('date,type,category,amount,note\n');
  for (final e in items.where((e) => !e.deleted)) {
    b.write('${fmtDate(e.date)},${e.isIncome ? 'income' : 'expense'},${_q(e.category)},${fmtMoney(e.cents)},${_q(e.note)}\n');
  }
  return b.toString();
}
