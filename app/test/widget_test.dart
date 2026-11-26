import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense/bloc/expense_bloc.dart';
import 'package:smart_expense/main.dart';
import 'helpers.dart';

void main() {
  demoWidget();
  testWidgets('user adds an expense and sees it and the totals', (tester) async {
    final db = await tester.runAsync(memDb);
    final bloc = ExpenseBloc(db: db!)..add(LoadRequested());
    await tester.pumpWidget(ExpenseApp(bloc: bloc));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '12.50');
    await tester.enterText(find.byKey(const Key('category')), 'coffee');
    await tester.tap(find.byKey(const Key('save')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('coffee'), findsWidgets);
    expect(find.text('12.50'), findsOneWidget); // Spent KPI
    expect(find.text('-12.50'), findsNWidgets(2)); // Balance KPI + list row
    expect(find.text('Not synced'), findsOneWidget);
  });
}

void demoWidget() {
  testWidgets('Try demo button loads labeled demo entries', (tester) async {
    final db = await tester.runAsync(memDb);
    final bloc = ExpenseBloc(db: db!)..add(LoadRequested());
    await tester.pumpWidget(ExpenseApp(bloc: bloc));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('try-demo')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.textContaining('(demo)'), findsWidgets);
    expect(find.byKey(const Key('try-demo')), findsNothing);
  });
}
