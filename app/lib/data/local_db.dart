import 'package:sqflite/sqflite.dart';
import 'expense.dart';

/// SQLite store. Offline-first: every write lands here first with synced=0.
class LocalDb {
  final Database db;
  LocalDb(this.db);

  static Future<LocalDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, singleInstance: singleInstance, onCreate: (d, _) async {
          await d.execute('''CREATE TABLE expenses(
            id TEXT PRIMARY KEY, cents INTEGER NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL,
            date INTEGER NOT NULL, is_income INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0, synced INTEGER NOT NULL DEFAULT 0)''');
          await d.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        }));
    return LocalDb(db);
  }

  Future<void> upsert(Expense e, {required bool synced}) =>
      db.insert('expenses', e.toRow(synced: synced), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Expense>> list() async =>
      (await db.query('expenses', where: 'deleted = 0', orderBy: 'date DESC, updated_at DESC')).map(Expense.fromRow).toList();

  Future<List<Expense>> pending() async =>
      (await db.query('expenses', where: 'synced = 0')).map(Expense.fromRow).toList();

  Future<void> markSynced(Iterable<String> ids) async {
    for (final id in ids) {
      await db.update('expenses', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// Apply a change that came from the server: newest updated_at wins; a local
  /// unsynced edit that is newer than the remote one is kept and pushed next time.
  Future<void> applyRemote(Expense remote) async {
    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [remote.id]);
    if (rows.isNotEmpty && (rows.first['updated_at'] as int) >= remote.updatedAt) return;
    await upsert(remote, synced: true);
  }

  Future<String?> meta(String k) async {
    final r = await db.query('meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  Future<void> setMeta(String k, String v) =>
      db.insert('meta', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
}
