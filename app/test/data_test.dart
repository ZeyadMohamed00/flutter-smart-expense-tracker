import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_expense/data/csv.dart';
import 'package:smart_expense/data/expense.dart';
import 'package:smart_expense/data/sync_service.dart';
import 'helpers.dart';

Expense ex(String id, int cents, {String cat = 'food', String note = '', int t = 1, bool inc = false, bool del = false}) =>
    Expense(id: id, cents: cents, category: cat, note: note, date: DateTime(2026, 11, 20), isIncome: inc, updatedAt: t, deleted: del);

void main() {
  test('csv escapes commas, quotes and newlines and formats cents', () {
    final out = toCsv([ex('1', 1234, note: 'lunch, "big"\nsecond line'), ex('2', 5, inc: true, cat: 'pay'), ex('3', 99, del: true)]);
    expect(out.split('\n').first, 'date,type,category,amount,note');
    expect(out, contains('2026-11-20,expense,food,12.34,"lunch, ""big""\nsecond line"'));
    expect(out, contains('2026-11-20,income,pay,0.05,'));
    expect(out, isNot(contains('0.99')));
  });

  test('sqlite round trip, pending flag and soft delete', () async {
    final db = await memDb();
    await db.upsert(ex('a', 100), synced: false);
    await db.upsert(ex('b', 200), synced: true);
    expect((await db.list()).length, 2);
    expect((await db.pending()).map((e) => e.id), ['a']);
    await db.upsert(ex('a', 100, del: true, t: 2), synced: false);
    expect((await db.list()).map((e) => e.id), ['b']);
  });

  test('applyRemote: newer remote wins, older remote is ignored', () async {
    final db = await memDb();
    await db.upsert(ex('a', 100, t: 10), synced: false);
    await db.applyRemote(ex('a', 999, t: 5));
    expect((await db.list()).first.cents, 100);
    await db.applyRemote(ex('a', 999, t: 20));
    expect((await db.list()).first.cents, 999);
    expect(await db.pending(), isEmpty);
  });

  test('sync pushes pending, pulls remote, remembers cursor', () async {
    final db = await memDb();
    await db.upsert(ex('local', 111, t: 5), synced: false);
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      expect(req.headers['X-User-Id'], 'u1');
      sent = jsonDecode(req.body);
      return http.Response(jsonEncode({'server_time': 777, 'changes': [ex('remote', 222, t: 6).toJson()]}), 200);
    });
    final r = await SyncService(db: db, client: client, baseUrl: 'http://x', userId: 'u1').sync();
    expect(r.ok, true);
    expect((sent['changes'] as List).single['id'], 'local');
    expect(sent['since'], 0);
    expect((await db.list()).map((e) => e.id).toSet(), {'local', 'remote'});
    expect(await db.pending(), isEmpty);
    expect(await db.meta('since'), '777');
  });

  test('offline: sync fails gracefully and keeps data pending', () async {
    final db = await memDb();
    await db.upsert(ex('local', 111), synced: false);
    final client = MockClient((_) async => throw http.ClientException('no network'));
    final r = await SyncService(db: db, client: client, baseUrl: 'http://x', userId: 'u1').sync();
    expect(r.ok, false);
    expect((await db.pending()).length, 1);
    final bad = MockClient((_) async => http.Response('oops', 500));
    expect((await SyncService(db: db, client: bad, baseUrl: 'http://x', userId: 'u1').sync()).ok, false);
    expect((await db.pending()).length, 1);
  });

  test('edit made during a sync is not marked synced', () async {
    final db = await memDb();
    await db.upsert(ex('a', 100, t: 1), synced: false);
    final client = MockClient((_) async {
      await db.upsert(ex('a', 150, t: 2), synced: false); // user edits mid-flight
      return http.Response(jsonEncode({'server_time': 1, 'changes': []}), 200);
    });
    await SyncService(db: db, client: client, baseUrl: 'http://x', userId: 'u').sync();
    expect((await db.pending()).single.cents, 150);
  });
}
