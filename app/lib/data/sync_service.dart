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

  /// Account session. Without a token the app syncs as an anonymous device (X-User-Id); with one, as the signed-in user.
  String? token;
  String? email;

  Future<void> restoreSession() async {
    token = await db.meta('token');
    email = await db.meta('email');
  }

  /// Returns null on success, or an error message. `register` true creates the account first.
  Future<String?> authenticate(String mail, String password, {required bool register}) async {
    try {
      final res = await client
          .post(Uri.parse('$baseUrl/auth/${register ? 'register' : 'login'}'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': mail.trim(), 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 201) {
        try {
          final d = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
          if (d is String) return d;
        } catch (_) {}
        return register ? 'Could not create the account (check the email and an 8+ character password)' : 'Wrong email or password';
      }
      token = (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
      email = mail.trim();
      await db.setMeta('token', token!);
      await db.setMeta('email', email!);
      // A different account must not inherit another account's sync cursor.
      await db.setMeta('since', '0');
      return null;
    } catch (_) {
      return 'Cannot reach the server';
    }
  }

  Future<void> logout() async {
    token = null;
    email = null;
    await db.setMeta('token', '');
    await db.setMeta('email', '');
    await db.setMeta('since', '0');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token' else 'X-User-Id': userId,
      };

  Future<SyncResult> sync() async {
    try {
      final pending = await db.pending();
      final since = int.parse(await db.meta('since') ?? '0');
      final res = await client
          .post(Uri.parse('$baseUrl/sync'),
              headers: _headers,
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
