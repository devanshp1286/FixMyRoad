import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/models.dart';

class OfflineDraftService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'fixmyroad_drafts.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE drafts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            image_path  TEXT NOT NULL,
            latitude    REAL NOT NULL,
            longitude   REAL NOT NULL,
            address     TEXT,
            description TEXT,
            created_at  TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static Future<int> saveDraft(DraftReport draft) async {
    final db = await database;
    return db.insert('drafts', draft.toMap());
  }

  static Future<List<DraftReport>> getAllDrafts() async {
    final db = await database;
    final maps = await db.query('drafts', orderBy: 'created_at ASC');
    return maps.map((m) => DraftReport.fromMap(m)).toList();
  }

  static Future<void> deleteDraft(int localId) async {
    final db = await database;
    await db.delete('drafts', where: 'id = ?', whereArgs: [localId]);
  }

  static Future<int> getDraftCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM drafts');
    return result.first['count'] as int;
  }
}
