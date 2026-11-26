import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_expense/bloc/expense_bloc.dart';
import 'package:smart_expense/data/sync_service.dart';
import 'package:smart_expense/main.dart';
import 'helpers.dart';

void main() {
  test('login stores the token and later syncs use Bearer, logout goes back to the device id', () async {
    final db = await memDb();
    final seen = <String, Map<String, String>>{};
    final client = MockClient((req) async {
      seen[req.url.path] = req.headers;
      if (req.url.path == '/auth/login') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        return b['password'] == 'correct-horse' ? http.Response(jsonEncode({'access_token': 'tok123'}), 200) : http.Response(jsonEncode({'detail': 'Invalid email or password'}), 401);
      }
      return http.Response(jsonEncode({'changes': [], 'server_time': 5}), 200);
    });
    final s = SyncService(db: db, client: client, baseUrl: 'http://x', userId: 'dev1');

    expect(await s.authenticate('a@b.co', 'nope', register: false), 'Invalid email or password');
    expect(s.token, isNull);
    expect(await s.authenticate('a@b.co', 'correct-horse', register: false), isNull);
    expect(s.token, 'tok123');

    await s.sync();
    expect(seen['/sync']!['Authorization'], 'Bearer tok123');
    expect(seen['/sync']!.containsKey('X-User-Id'), isFalse);

    // The session survives an app restart.
    final s2 = SyncService(db: db, client: client, baseUrl: 'http://x', userId: 'dev1');
    await s2.restoreSession();
    expect(s2.token, 'tok123');

    await s.logout();
    await s.sync();
    expect(seen['/sync']!['X-User-Id'], 'dev1');
    expect(seen['/sync']!.containsKey('Authorization'), isFalse);
  });

  testWidgets('account dialog logs in and then offers log out', (tester) async {
    final db = await tester.runAsync(memDb);
    final client = MockClient((req) async => req.url.path == '/auth/login'
        ? http.Response(jsonEncode({'access_token': 't'}), 200)
        : http.Response(jsonEncode({'changes': [], 'server_time': 1}), 200));
    final sync = SyncService(db: db!, client: client, baseUrl: 'http://x', userId: 'd');
    final bloc = ExpenseBloc(db: db, sync: sync)..add(LoadRequested());
    await tester.pumpWidget(ExpenseApp(bloc: bloc));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-email')), 'me@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'correct-horse');
    await tester.tap(find.byKey(const Key('login')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('me@example.com'), findsOneWidget);
    expect(find.byKey(const Key('logout')), findsOneWidget);
  });
}
