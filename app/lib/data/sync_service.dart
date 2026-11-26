import 'dart:convert';
import 'package:http/http.dart' as http;
import 'expense.dart';
import 'local_db.dart';

class SyncResult {
  final bool ok;
  final int pushed;
  final int pulled;
  final String? error;
  const SyncResult({required this.ok, this.pushed = 0, this.pulled = 0, this.error});
}

/// One round trip: push local pending changes, receive everything newer than `since`.
/// Offline or server errors never lose data: rows stay synced=0 and go out next time.
class SyncService {
  final LocalDb db;
  final http.Client client;
  final String baseUrl;
  final String userId;
  SyncService({required this.db, required this.client, required this.baseUrl, required this.userId});

  Future<SyncResult> sync() async {
    try {
      final pending = await db.pending();
      final since = int.parse(await db.meta('since') ?? '0');
      final res = await client
          .post(Uri.parse('$baseUrl/sync'),
              headers: {'Content-Type': 'application/json', 'X-User-Id': userId},
              body: jsonEncode({'since': since, 'changes': pending.map((e) => e.toJson()).toList()}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return SyncResult(ok: false, error: 'Server returned ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // Mark pushed rows synced only if they are unchanged since we read them.
      final stillPending = {for (final e in await db.pending()) e.id: e.updatedAt};
      await db.markSynced(pending.where((e) => stillPending[e.id] == e.updatedAt).map((e) => e.id));
      var pulled = 0;
      for (final j in (body['changes'] as List)) {
        await db.applyRemote(Expense.fromJson(j as Map<String, dynamic>));
        pulled++;
      }
      await db.setMeta('since', '${body['server_time']}');
      return SyncResult(ok: true, pushed: pending.length, pulled: pulled);
    } catch (e) {
      return SyncResult(ok: false, error: 'Offline or unreachable: changes are saved on this device');
    }
  }
}
