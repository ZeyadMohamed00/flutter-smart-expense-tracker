import 'package:smart_expense/data/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalDb> memDb() async {
  sqfliteFfiInit();
  return LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
}
