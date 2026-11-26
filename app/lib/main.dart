import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'ui/app.dart';
export 'ui/app.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'dart:math';
import 'bloc/expense_bloc.dart';
import 'data/local_db.dart';
import 'data/sync_service.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On the web build SQLite runs as WebAssembly (sqflite_common_ffi_web); on Android it is native SQLite.
  final factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
  final db = await LocalDb.open(factory, kIsWeb ? 'expenses_web.db' : '${await getDatabasesPath()}/expenses.db');
  // Each install gets its own random id, so users never see each other's data.
  var uid = await db.meta('user_id');
  if (uid == null) {
    uid = 'u${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 30)}';
    await db.setMeta('user_id', uid);
  }
  final sync = SyncService(db: db, client: http.Client(), baseUrl: apiUrl, userId: uid);
  runApp(ExpenseApp(bloc: ExpenseBloc(db: db, sync: sync)..add(LoadRequested())));
}

