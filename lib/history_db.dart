import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class HistoryDb {
  Database? _db;

  Future<Database> get _d async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'potfinder.db'),
        version: 1,
        onCreate: (d, v) => d.execute('CREATE TABLE potholes('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, conf REAL, '
            'l REAL, t REAL, r REAL, b REAL, fw INTEGER, fh INTEGER, '
            'severity TEXT, score REAL, image TEXT)'),
      );

  Future<void> insert(Map<String, Object?> row) async => (await _d).insert('potholes', row);

  Future<List<Map<String, Object?>>> all() async =>
      (await _d).query('potholes', orderBy: 'ts DESC');

  Future<void> delete(int id, String? image) async {
    await (await _d).delete('potholes', where: 'id = ?', whereArgs: [id]);
    if (image != null) {
      try {
        await File(image).delete();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final rows = await all();
    await (await _d).delete('potholes');
    for (final r in rows) {
      try {
        await File(r['image'] as String).delete();
      } catch (_) {}
    }
  }
}
